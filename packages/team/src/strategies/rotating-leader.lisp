;;;; rotating-leader.lisp - Rotating leader coordination strategy
;;;;
;;;; Leadership rotates through team members for each task or phase.
;;;; Each member gets opportunity to lead, promoting skill development
;;;; and preventing single points of failure.

(in-package #:autopoiesis.team)

(defclass rotating-leader-strategy ()
  ((rotation-method :initarg :rotation-method
                    :accessor rl-rotation-method
                    :initform :round-robin
                    :type (member :round-robin :performance-based :random)
                    :documentation "How to select the next leader")
   (current-leader-index :initarg :current-leader-index
                         :accessor rl-current-leader-index
                         :initform 0
                         :documentation "Index of current leader in members list")
   (performance-scores :initarg :performance-scores
                       :accessor rl-performance-scores
                       :initform nil
                       :documentation "Performance scores for each member: alist of (agent-id . score)")
   (tasks-completed :initarg :tasks-completed
                    :accessor rl-tasks-completed
                    :initform 0
                    :documentation "Number of tasks completed under current leadership"))
  (:documentation "Leadership rotates through team members to distribute responsibility."))

(defmethod strategy-initialize ((strategy rotating-leader-strategy) team)
  "Initialize rotation state and select first leader."
  (let ((members (team-members team)))
    (unless members
      (error "Rotating leader strategy requires at least one team member"))
    ;; Start with first member as initial leader
    (setf (rl-current-leader-index strategy) 0)
    (setf (team-leader team) (first members))
    (setf (rl-performance-scores strategy)
          (mapcar (lambda (member) (cons member 1.0)) members))
    (setf (rl-tasks-completed strategy) 0))
  (values))

(defmethod strategy-assign-work ((strategy rotating-leader-strategy) team task)
  "Assign task to current rotating leader, who then coordinates the team."
  (let* ((leader-id (team-leader team))
         (send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when send-fn
      (funcall send-fn "team-system" leader-id
               (list :type :leader-coordination
                     :task task
                     :team-id (team-id team)
                     :rotation-context (list :method (rl-rotation-method strategy)
                                           :tasks-completed (rl-tasks-completed strategy)))))
    (format nil "Task assigned to rotating leader ~A" leader-id)))

(defmethod strategy-collect-results ((strategy rotating-leader-strategy) team)
  "Collect results coordinated by current leader."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (funcall list-fn ws-id :status :complete))))))

(defmethod strategy-complete-p ((strategy rotating-leader-strategy) team)
  "Complete when leader signals task completion."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (let ((completed (funcall list-fn ws-id :status :complete)))
            (> (length completed) 0)))))))

(defmethod strategy-handle-failure ((strategy rotating-leader-strategy) team agent-id condition)
  "Handle failure and potentially rotate leadership if current leader fails."
  (call-next-method)
  (when (equal agent-id (team-leader team))
    ;; Current leader failed - rotate immediately
    (rotate-leadership strategy team :reason :failure)
    (format *error-output* "Leader ~A failed, rotated to ~A~%"
            agent-id (team-leader team))))

(defun rotate-leadership (strategy team &key reason)
  "Rotate to the next leader based on rotation method."
  (let* ((members (team-members team))
         (current-idx (rl-current-leader-index strategy))
         (next-idx (select-next-leader strategy members reason)))
    (setf (rl-current-leader-index strategy) next-idx)
    (setf (team-leader team) (nth next-idx members))
    (setf (rl-tasks-completed strategy) 0)
    next-idx))

(defun select-next-leader (strategy members reason)
  "Select next leader index based on rotation method."
  (let ((current-idx (rl-current-leader-index strategy)))
    (ecase (rl-rotation-method strategy)
      (:round-robin
       (mod (1+ current-idx) (length members)))
      (:performance-based
       (select-highest-performance-leader strategy members))
      (:random
       (let ((available (remove current-idx (loop for i from 0 below (length members) collect i))))
         (nth (random (length available)) available))))))

(defun select-highest-performance-leader (strategy members)
  "Select leader with highest performance score."
  (let* ((scores (rl-performance-scores strategy))
         (best-member (first (sort (copy-list members)
                                  (lambda (a b)
                                    (> (or (cdr (assoc a scores :test #'equal)) 0)
                                       (or (cdr (assoc b scores :test #'equal)) 0)))))))
    (position best-member members :test #'equal)))

(defun record-leader-performance (strategy leader-id success-p)
  "Update performance score for LEADER-ID based on task outcome."
  (let* ((scores (rl-performance-scores strategy))
         (current-score (or (cdr (assoc leader-id scores :test #'equal)) 1.0))
         (adjustment (if success-p 0.1 -0.2))
         (new-score (max 0.1 (+ current-score adjustment))))
    (setf (cdr (assoc leader-id scores :test #'equal)) new-score)))

(defun complete-leader-task (strategy)
  "Mark current task as completed and prepare for potential rotation."
  (incf (rl-tasks-completed strategy)))