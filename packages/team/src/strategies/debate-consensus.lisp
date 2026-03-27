;;;; debate-consensus.lisp - Debate-consensus hybrid coordination strategy
;;;;
;;;; Combines structured debate rounds with consensus convergence.
;;;; Agents first debate to generate diverse perspectives, then work
;;;; toward consensus through iterative review and voting.

(in-package #:autopoiesis.team)

(defclass debate-consensus-strategy ()
  ((debate-rounds :initarg :debate-rounds
                  :accessor dc-debate-rounds
                  :initform 2
                  :documentation "Number of debate rounds before consensus")
   (consensus-iterations :initarg :consensus-iterations
                        :accessor dc-consensus-iterations
                        :initform 3
                        :documentation "Maximum consensus iterations")
   (current-phase :initarg :current-phase
                  :accessor dc-current-phase
                  :initform :debate
                  :type (member :debate :consensus :complete)
                  :documentation "Current coordination phase")
   (debate-arguments :initarg :debate-arguments
                     :accessor dc-debate-arguments
                     :initform nil
                     :documentation "Arguments collected during debate phase")
   (consensus-votes :initarg :consensus-votes
                    :accessor dc-consensus-votes
                    :initform nil
                    :documentation "Votes collected during consensus phase")
   (current-draft :initarg :current-draft
                  :accessor dc-current-draft
                  :initform nil
                  :documentation "Current consensus draft"))
  (:documentation "Debate rounds followed by consensus convergence."))

(defmethod strategy-initialize ((strategy debate-consensus-strategy) team)
  "Initialize debate-consensus state."
  (setf (dc-current-phase strategy) :debate)
  (setf (dc-debate-arguments strategy) nil)
  (setf (dc-consensus-votes strategy) nil)
  (setf (dc-current-draft strategy) nil)
  (values))

(defmethod strategy-assign-work ((strategy debate-consensus-strategy) team task)
  "Dispatch work based on current phase: debate or consensus."
  (ecase (dc-current-phase strategy)
    (:debate
     (assign-debate-round strategy team task))
    (:consensus
     (assign-consensus-round strategy team task))))

(defmethod strategy-collect-results ((strategy debate-consensus-strategy) team)
  "Return combined debate arguments and consensus results."
  (declare (ignore team))
  (list :debate-arguments (dc-debate-arguments strategy)
        :consensus-votes (dc-consensus-votes strategy)
        :final-draft (dc-current-draft strategy)))

(defmethod strategy-complete-p ((strategy debate-consensus-strategy) team)
  "Complete when consensus is reached or max iterations exceeded."
  (or (eq (dc-current-phase strategy) :complete)
      (and (eq (dc-current-phase strategy) :consensus)
           (consensus-reached-p strategy team))))

(defun assign-debate-round (strategy team task)
  "Assign debate round to all team members."
  (let ((send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when send-fn
      (dolist (agent-id (team-members team))
        (funcall send-fn "team-system" agent-id
                 (list :type :debate-argument
                       :task task
                       :round (length (dc-debate-arguments strategy))
                       :team-id (team-id team)
                       :previous-arguments (dc-debate-arguments strategy)))))
    (format nil "Debate round assigned to ~A team members"
            (length (team-members team)))))

(defun assign-consensus-round (strategy team task)
  "Assign consensus review/voting round."
  (let ((send-fn (find-symbol "SEND-MESSAGE" :autopoiesis.agent)))
    (when send-fn
      (dolist (agent-id (team-members team))
        (funcall send-fn "team-system" agent-id
                 (list :type :consensus-review
                       :task task
                       :iteration (length (dc-consensus-votes strategy))
                       :team-id (team-id team)
                       :current-draft (dc-current-draft strategy)))))
    (format nil "Consensus round ~A assigned to ~A team members"
            (length (dc-consensus-votes strategy)) (length (team-members team)))))

(defun record-debate-argument (strategy agent-id argument)
  "Record debate argument from AGENT-ID."
  (push (cons agent-id argument) (dc-debate-arguments strategy)))

(defun record-consensus-vote (strategy agent-id vote &optional feedback)
  "Record consensus vote from AGENT-ID."
  (let ((current-votes (dc-consensus-votes strategy)))
    (if current-votes
        (push (cons agent-id (list vote feedback)) (first current-votes))
        (push (list (cons agent-id (list vote feedback)))
              (dc-consensus-votes strategy)))))

(defun transition-to-consensus (strategy)
  "Transition from debate phase to consensus phase."
  (when (eq (dc-current-phase strategy) :debate)
    ;; Generate initial draft from debate arguments
    (let ((arguments (dc-debate-arguments strategy)))
      (setf (dc-current-draft strategy)
            (synthesize-debate-draft arguments)))
    (setf (dc-current-phase strategy) :consensus)))

(defun consensus-reached-p (strategy team)
  "Check if consensus threshold is met."
  (let* ((latest-votes (first (dc-consensus-votes strategy)))
         (total-members (length (team-members team)))
         (approvals (count :approve latest-votes :key #'cdr)))
    ;; Require 80% approval for consensus
    (and latest-votes
         (>= (/ approvals (max total-members 1)) 0.8))))

(defun synthesize-debate-draft (arguments)
  "Create initial consensus draft from debate arguments."
  ;; Simple synthesis - could be more sophisticated
  (format nil "Synthesized draft from ~A debate arguments: ~{~A~^; ~}"
          (length arguments)
          (mapcar #'cdr arguments)))

(defun update-consensus-draft (strategy new-draft)
  "Update the current consensus draft."
  (setf (dc-current-draft strategy) new-draft))

(defun finalize-consensus (strategy)
  "Mark consensus phase as complete."
  (setf (dc-current-phase strategy) :complete))