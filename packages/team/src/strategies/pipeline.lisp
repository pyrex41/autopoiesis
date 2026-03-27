;;;; pipeline.lisp - Pipeline (sequential) coordination strategy
;;;;
;;;; Agents process the task in sequence: each stage's output becomes
;;;; the next stage's input. Members list defines the order.

(in-package #:autopoiesis.team)

(defclass pipeline-strategy ()
  ((current-stage :initarg :current-stage
                  :accessor pipeline-current-stage
                  :initform 0
                  :documentation "Index of the currently executing stage")
   (stage-results :initarg :stage-results
                  :accessor pipeline-stage-results
                  :initform nil
                  :documentation "Accumulated results from completed stages"))
  (:documentation "Sequential pipeline where each agent processes in order."))

(defmethod strategy-initialize ((strategy pipeline-strategy) team)
  (setf (pipeline-current-stage strategy) 0)
  (setf (pipeline-stage-results strategy) nil)
  (values))

(defmethod strategy-assign-work ((strategy pipeline-strategy) team task)
  "Assign TASK to the current pipeline stage's agent.
   Includes previous stage results as context."
  (let* ((stage (pipeline-current-stage strategy))
         (members (team-members team))
         (agent-id (when (< stage (length members))
                     (nth stage members))))
    (when agent-id
      (let ((send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent))
            (input (if (pipeline-stage-results strategy)
                       (list :type :pipeline-stage
                             :stage stage
                             :task task
                             :previous-output (car (last (pipeline-stage-results strategy)))
                             :team-id (team-id team))
                       (list :type :pipeline-stage
                             :stage stage
                             :task task
                             :team-id (team-id team)))))
        (when send-fn
          (funcall send-fn "team-system" agent-id input))
        (format nil "Task assigned to stage ~A agent ~A" stage agent-id)))))

(defmethod strategy-collect-results ((strategy pipeline-strategy) team)
  "Return accumulated pipeline results."
  (declare (ignore team))
  (pipeline-stage-results strategy))

(defmethod strategy-complete-p ((strategy pipeline-strategy) team)
  "Complete when all stages have produced output."
  (>= (pipeline-current-stage strategy) (length (team-members team))))

(defun advance-pipeline (strategy result)
  "Record RESULT for the current stage and advance to the next."
  (push result (pipeline-stage-results strategy))
  (incf (pipeline-current-stage strategy)))
