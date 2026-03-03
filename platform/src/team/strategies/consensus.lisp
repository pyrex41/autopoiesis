;;;; consensus.lisp - Consensus coordination strategy
;;;;
;;;; Iterative convergence: draft → review → vote → converge or repeat.
;;;; All members must approve for consensus to be reached.

(in-package #:autopoiesis.team)

(defclass consensus-strategy ()
  ((max-iterations :initarg :max-iterations
                   :accessor consensus-max-iterations
                   :initform 5
                   :documentation "Maximum convergence iterations")
   (current-iteration :initarg :current-iteration
                      :accessor consensus-current-iteration
                      :initform 0
                      :documentation "Current iteration counter")
   (threshold :initarg :threshold
              :accessor consensus-threshold
              :initform 1.0
              :documentation "Fraction of members that must approve (0.0-1.0)")
   (votes :initarg :votes
          :accessor consensus-votes
          :initform nil
          :documentation "Votes per iteration: list of (iteration . alist)")
   (current-draft :initarg :current-draft
                  :accessor consensus-current-draft
                  :initform nil
                  :documentation "The current draft being reviewed"))
  (:documentation "Iterative consensus-building among all team members."))

(defmethod strategy-initialize ((strategy consensus-strategy) team)
  (declare (ignore team))
  (setf (consensus-current-iteration strategy) 0)
  (setf (consensus-votes strategy) nil)
  (setf (consensus-current-draft strategy) nil)
  (values))

(defmethod strategy-assign-work ((strategy consensus-strategy) team task)
  "Dispatch consensus iteration: all members review and vote on current draft.
   First iteration sends the original task for drafting."
  (let ((iteration (consensus-current-iteration strategy))
        (send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when send-fn
      (dolist (agent-id (team-members team))
        (funcall send-fn "team-system" agent-id
                 (list :type :consensus-round
                       :iteration iteration
                       :task task
                       :team-id (team-id team)
                       :current-draft (consensus-current-draft strategy)))))
    (format nil "Consensus iteration ~A dispatched to ~A members"
            iteration (length (team-members team)))))

(defmethod strategy-collect-results ((strategy consensus-strategy) team)
  "Return voting results."
  (declare (ignore team))
  (consensus-votes strategy))

(defmethod strategy-complete-p ((strategy consensus-strategy) team)
  "Complete when consensus threshold is met or max iterations reached."
  (or (>= (consensus-current-iteration strategy)
           (consensus-max-iterations strategy))
      (let* ((iteration (1- (consensus-current-iteration strategy)))
             (votes (cdr (assoc iteration (consensus-votes strategy))))
             (total (length (team-members team)))
             (approvals (count :approve votes :key #'cdr)))
        (and votes (>= (/ approvals (max total 1))
                       (consensus-threshold strategy))))))

(defun record-consensus-vote (strategy agent-id vote &optional feedback)
  "Record AGENT-ID's VOTE (:approve or :reject) for the current iteration.
   FEEDBACK is optional text explaining the vote."
  (let* ((iteration (consensus-current-iteration strategy))
         (entry (assoc iteration (consensus-votes strategy))))
    (if entry
        (push (cons agent-id (list vote feedback)) (cdr entry))
        (push (cons iteration (list (cons agent-id (list vote feedback))))
              (consensus-votes strategy)))))

(defun advance-consensus (strategy &optional new-draft)
  "Advance to the next consensus iteration, optionally updating the draft."
  (when new-draft
    (setf (consensus-current-draft strategy) new-draft))
  (incf (consensus-current-iteration strategy)))
