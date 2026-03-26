;;;; leader-parallel.lisp - Leader-parallel hybrid coordination strategy
;;;;
;;;; Leader decomposes task into subtasks, then assigns each subtask
;;;; to a worker (or group) for parallel execution. Combines decomposition
;;;; planning with parallel execution efficiency.

(in-package #:autopoiesis.team)

(defclass leader-parallel-strategy ()
  ((decomposition-method :initarg :decomposition-method
                         :accessor lp-decomposition-method
                         :initform :equal-parts
                         :type (member :equal-parts :expertise-based :load-balanced)
                         :documentation "How to decompose the main task")
   (subtasks :initarg :subtasks
             :accessor lp-subtasks
             :initform nil
             :documentation "List of decomposed subtasks")
   (assignment-map :initarg :assignment-map
                   :accessor lp-assignment-map
                   :initform nil
                   :documentation "Mapping of subtasks to assigned agents: alist of (subtask . agent-id)")
   (results-collected :initarg :results-collected
                      :accessor lp-results-collected
                      :initform nil
                      :documentation "Collected results from subtasks: alist of (subtask . result)"))
  (:documentation "Leader decomposes task, then parallel execution of subtasks."))

(defmethod strategy-initialize ((strategy leader-parallel-strategy) team)
  "Validate team has a leader and initialize state."
  (unless (team-leader team)
    (when (team-members team)
      (setf (team-leader team) (first (team-members team)))))
  (setf (lp-subtasks strategy) nil)
  (setf (lp-assignment-map strategy) nil)
  (setf (lp-results-collected strategy) nil)
  (values))

(defmethod strategy-assign-work ((strategy leader-parallel-strategy) team task)
  "Leader decomposes task, then assigns subtasks to workers in parallel."
  (cond
    ((null (lp-subtasks strategy))
     ;; First phase: assign to leader for decomposition
     (let ((send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
       (when send-fn
         (funcall send-fn "team-system" (team-leader team)
                  (list :type :task-decomposition
                        :method (lp-decomposition-method strategy)
                        :task task
                        :team-id (team-id team)))))
     (format nil "Task assigned to leader ~A for decomposition" (team-leader team)))
    (t
     ;; Second phase: assign decomposed subtasks to workers in parallel
     (assign-subtasks-in-parallel strategy team))))

(defmethod strategy-collect-results ((strategy leader-parallel-strategy) team)
  "Collect and combine results from all parallel subtasks."
  (declare (ignore team))
  (let ((collected (lp-results-collected strategy)))
    (when (= (length collected) (length (lp-subtasks strategy)))
      ;; All subtasks complete - synthesize final result
      (synthesize-parallel-results collected))))

(defmethod strategy-complete-p ((strategy leader-parallel-strategy) team)
  "Complete when all subtasks have been completed."
  (declare (ignore team))
  (let ((subtasks (lp-subtasks strategy))
        (collected (lp-results-collected strategy)))
    (and subtasks
         (= (length collected) (length subtasks)))))

(defun assign-subtasks-in-parallel (strategy team)
  "Assign each subtask to a worker agent."
  (let ((subtasks (lp-subtasks strategy))
        (members (remove (team-leader team) (team-members team) :test #'equal))
        (send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when (and subtasks send-fn)
      (loop for subtask in subtasks
            for i from 0
            for worker = (nth (mod i (length members)) members)
            do (funcall send-fn "team-system" worker
                       (list :type :subtask-execution
                             :subtask subtask
                             :team-id (team-id team)))
               (push (cons subtask worker) (lp-assignment-map strategy))))
    (format nil "Assigned ~A subtasks to ~A workers in parallel"
            (length subtasks) (length members))))

(defun record-task-decomposition (strategy subtasks)
  "Record that the main task was decomposed into SUBTASKS."
  (setf (lp-subtasks strategy) subtasks))

(defun record-subtask-result (strategy subtask result)
  "Record RESULT for completed SUBTASK."
  (push (cons subtask result) (lp-results-collected strategy)))

(defun synthesize-parallel-results (results)
  "Combine results from parallel subtasks into final output."
  ;; Simple concatenation - could be made more sophisticated
  (format nil "Combined results: ~{~A~^, ~}"
          (mapcar #'cdr results)))