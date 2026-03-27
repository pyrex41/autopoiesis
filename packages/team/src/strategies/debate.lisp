;;;; debate.lisp - Debate coordination strategy
;;;;
;;;; N rounds of argumentation: agents produce arguments in parallel,
;;;; then receive opponents' arguments as rebuttals. A judge agent
;;;; evaluates and selects the winner.

(in-package #:autopoiesis.team)

(defclass debate-strategy ()
  ((max-rounds :initarg :max-rounds
               :accessor debate-max-rounds
               :initform 3
               :documentation "Maximum number of debate rounds")
   (current-round :initarg :current-round
                  :accessor debate-current-round
                  :initform 0
                  :documentation "Current round counter")
   (judge :initarg :judge
          :accessor debate-judge
          :initform nil
          :documentation "Agent ID of the judge (defaults to team leader)")
   (arguments :initarg :arguments
              :accessor debate-arguments
              :initform nil
              :documentation "Collected arguments per round: list of (round . alist)"))
  (:documentation "Structured debate between agents with a judge."))

(defmethod strategy-initialize ((strategy debate-strategy) team)
  (setf (debate-current-round strategy) 0)
  (setf (debate-arguments strategy) nil)
  (unless (debate-judge strategy)
    (setf (debate-judge strategy) (team-leader team)))
  (values))

(defmethod strategy-assign-work ((strategy debate-strategy) team task)
  "Dispatch debate round: all non-judge members argue the TASK.
   In subsequent rounds, include opponents' previous arguments."
  (let* ((round (debate-current-round strategy))
         (judge-id (debate-judge strategy))
         (debaters (remove judge-id (team-members team) :test #'equal))
         (send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent))
         (prev-args (when (> round 0)
                      (cdr (assoc (1- round) (debate-arguments strategy))))))
    (when send-fn
      (dolist (agent-id debaters)
        (funcall send-fn "team-system" agent-id
                 (list :type :debate-round
                       :round round
                       :task task
                       :team-id (team-id team)
                       :previous-arguments
                       (remove agent-id prev-args :key #'car :test #'equal)))))
    (format nil "Debate round ~A dispatched to ~A debaters"
            round (length debaters))))

(defmethod strategy-collect-results ((strategy debate-strategy) team)
  "Return all arguments across all rounds."
  (declare (ignore team))
  (debate-arguments strategy))

(defmethod strategy-complete-p ((strategy debate-strategy) team)
  "Complete when max rounds reached."
  (declare (ignore team))
  (>= (debate-current-round strategy) (debate-max-rounds strategy)))

(defun record-debate-argument (strategy agent-id argument)
  "Record AGENT-ID's ARGUMENT for the current round."
  (let* ((round (debate-current-round strategy))
         (entry (assoc round (debate-arguments strategy))))
    (if entry
        (push (cons agent-id argument) (cdr entry))
        (push (cons round (list (cons agent-id argument)))
              (debate-arguments strategy)))))

(defun advance-debate (strategy)
  "Advance to the next debate round."
  (incf (debate-current-round strategy)))
