;;;; parallel.lisp - Parallel execution strategy
;;;;
;;;; All agents receive the same task and work independently.
;;;; Results are collected and the best is selected (or all returned).

(in-package #:autopoiesis.team)

(defclass parallel-strategy ()
  ((selection-method :initarg :selection-method
                     :accessor parallel-selection-method
                     :initform :all
                     :type (member :all :first :best)
                     :documentation "How to select from parallel results"))
  (:documentation "All agents work the same task in parallel."))

(defmethod strategy-initialize ((strategy parallel-strategy) team)
  (declare (ignore strategy team))
  (values))

(defmethod strategy-assign-work ((strategy parallel-strategy) team task)
  "Send TASK to all team members via their mailboxes."
  (let ((send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when send-fn
      (dolist (member-id (team-members team))
        (funcall send-fn "team-system" member-id
                 (list :type :task-assignment
                       :task task
                       :team-id (team-id team))))))
  (format nil "Task assigned to ~A members in parallel"
          (length (team-members team))))

(defmethod strategy-collect-results ((strategy parallel-strategy) team)
  "Collect results from all members."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (let ((completed (funcall list-fn ws-id :status :complete)))
            (ecase (parallel-selection-method strategy)
              (:all completed)
              (:first (list (first completed)))
              (:best completed))))))))

(defmethod strategy-complete-p ((strategy parallel-strategy) team)
  "Complete when all members have submitted results."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (let ((completed (funcall list-fn ws-id :status :complete)))
            (>= (length completed) (length (team-members team)))))))))
