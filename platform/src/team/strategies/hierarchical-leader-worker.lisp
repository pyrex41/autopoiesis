;;;; hierarchical-leader-worker.lisp - Hierarchical leader/worker coordination strategy
;;;;
;;;; Multi-level hierarchy: top leader decomposes main task into subtasks,
;;;; sub-leaders further decompose their assigned subtasks, workers execute
;;;; leaf tasks. Results bubble up through the hierarchy.

(in-package #:autopoiesis.team)

(defclass hierarchical-leader-worker-strategy ()
  ((hierarchy-levels :initarg :hierarchy-levels
                     :accessor hlw-hierarchy-levels
                     :initform 2
                     :documentation "Number of hierarchy levels (minimum 2)")
   (current-level :initarg :current-level
                  :accessor hlw-current-level
                  :initform 0
                  :documentation "Current decomposition level")
   (subtask-mappings :initarg :subtask-mappings
                     :accessor hlw-subtask-mappings
                     :initform nil
                     :documentation "Mapping of tasks to subtasks: alist of (task-id . subtask-list)")
   (leader-assignments :initarg :leader-assignments
                       :accessor hlw-leader-assignments
                       :initform nil
                       :documentation "Assignment of leaders to subtasks: alist of (subtask-id . leader-id)"))
  (:documentation "Multi-level hierarchical decomposition and execution."))

(defmethod strategy-initialize ((strategy hierarchical-leader-worker-strategy) team)
  "Validate hierarchy levels and assign leaders at each level."
  (let ((members (team-members team))
        (levels (hlw-hierarchy-levels strategy)))
    (unless (>= (length members) levels)
      (error "Team needs at least ~A members for ~A-level hierarchy" levels levels))
    (unless (team-leader team)
      ;; Auto-assign top leader
      (setf (team-leader team) (first members)))
    ;; Initialize hierarchy state
    (setf (hlw-current-level strategy) 0)
    (setf (hlw-subtask-mappings strategy) nil)
    (setf (hlw-leader-assignments strategy) nil))
  (values))

(defmethod strategy-assign-work ((strategy hierarchical-leader-worker-strategy) team task)
  "Assign task to appropriate leader based on current hierarchy level."
  (let ((level (hlw-current-level strategy))
        (levels (hlw-hierarchy-levels strategy)))
    (cond
      ((= level 0)
       ;; Top level: assign to team leader for initial decomposition
       (let ((send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
         (when send-fn
           (funcall send-fn "team-system" (team-leader team)
                    (list :type :hierarchical-decomposition
                          :level level
                          :task task
                          :team-id (team-id team)))))
       (format nil "Task assigned to top leader ~A for level ~A decomposition"
               (team-leader team) level))
      ((< level levels)
       ;; Intermediate level: assign subtasks to sub-leaders
       (assign-subtasks-to-leaders strategy team task))
      (t
       ;; Bottom level: assign to worker agents
       (assign-to-workers strategy team task)))))

(defmethod strategy-collect-results ((strategy hierarchical-leader-worker-strategy) team)
  "Collect results from all hierarchy levels."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (funcall list-fn ws-id :status :complete))))))

(defmethod strategy-complete-p ((strategy hierarchical-leader-worker-strategy) team)
  "Complete when all levels have produced results."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((list-fn (find-symbol "WORKSPACE-LIST-TASKS" :autopoiesis.workspace)))
        (when list-fn
          (let ((completed (funcall list-fn ws-id :status :complete))
                (total-expected (calculate-expected-tasks strategy team)))
            (>= (length completed) total-expected)))))))

(defun assign-subtasks-to-leaders (strategy team parent-task)
  "Assign decomposed subtasks to sub-leaders."
  (let* ((mappings (hlw-subtask-mappings strategy))
         (subtasks (cdr (assoc parent-task mappings :test #'equal)))
         (members (team-members team))
         (send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when (and subtasks send-fn)
      (loop for subtask in subtasks
            for i from 1
            for leader = (nth (mod i (length members)) members)
            do (funcall send-fn "team-system" leader
                       (list :type :hierarchical-decomposition
                             :level (hlw-current-level strategy)
                             :task subtask
                             :parent-task parent-task
                             :team-id (team-id team)))
               (push (cons subtask leader) (hlw-leader-assignments strategy))))
    (format nil "Assigned ~A subtasks to sub-leaders at level ~A"
            (length subtasks) (hlw-current-level strategy))))

(defun assign-to-workers (strategy team task)
  "Assign leaf tasks to worker agents."
  (let ((ws-id (team-workspace-id team)))
    (when ws-id
      (let ((push-fn (find-symbol "WORKSPACE-PUSH-TASK" :autopoiesis.workspace)))
        (when push-fn
          (funcall push-fn ws-id task)
          (format nil "Leaf task queued in workspace ~A for worker claim" ws-id))))))

(defun calculate-expected-tasks (strategy team)
  "Calculate total expected tasks across all hierarchy levels."
  ;; This is a simplified calculation - in practice would track actual decomposition
  (let ((members (team-members team))
        (levels (hlw-hierarchy-levels strategy)))
    ;; Estimate: each level multiplies tasks by branching factor
    (max 1 (* (length members) levels))))

(defun record-hierarchical-decomposition (strategy parent-task subtasks)
  "Record that PARENT-TASK was decomposed into SUBTASKS."
  (push (cons parent-task subtasks) (hlw-subtask-mappings strategy)))

(defun advance-hierarchy-level (strategy)
  "Advance to the next hierarchy level."
  (incf (hlw-current-level strategy)))