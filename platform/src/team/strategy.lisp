;;;; strategy.lisp - Strategy protocol for team coordination
;;;;
;;;; Defines the generic function protocol that all coordination
;;;; strategies must implement.

(in-package #:autopoiesis.team)

;;; ═══════════════════════════════════════════════════════════════════
;;; Strategy Protocol (Generic Functions)
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric strategy-initialize (strategy team)
  (:documentation "Initialize the strategy for TEAM. Called when team starts.")
  (:method (strategy team)
    (declare (ignore strategy team))
    nil))

(defgeneric strategy-assign-work (strategy team task)
  (:documentation "Assign TASK to team members according to the strategy.
   Returns a description of the assignment plan.")
  (:method (strategy team task)
    (declare (ignore strategy team task))
    nil))

(defgeneric strategy-collect-results (strategy team)
  (:documentation "Collect and synthesize results from team members.
   Returns the aggregated result.")
  (:method (strategy team)
    (declare (ignore strategy team))
    nil))

(defgeneric strategy-handle-failure (strategy team agent-id condition)
  (:documentation "Handle failure of AGENT-ID in TEAM.
   Default: log and continue.")
  (:method (strategy team agent-id condition)
    (declare (ignore strategy condition))
    (format *error-output* "Team ~A: agent ~A failed~%" (team-id team) agent-id)
    :continue))

(defgeneric strategy-complete-p (strategy team)
  (:documentation "Return T if the team's work is complete according to the strategy.")
  (:method (strategy team)
    (declare (ignore strategy team))
    nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Strategy Factory
;;; ═══════════════════════════════════════════════════════════════════

(defun make-strategy (keyword &optional config)
  "Create a strategy object from KEYWORD and optional CONFIG plist."
  (ecase keyword
    (:leader-worker (apply #'make-instance 'leader-worker-strategy
                           (or config nil)))
    (:parallel      (apply #'make-instance 'parallel-strategy
                           (or config nil)))
    (:pipeline      (apply #'make-instance 'pipeline-strategy
                           (or config nil)))
    (:debate        (apply #'make-instance 'debate-strategy
                           (or config nil)))
    (:consensus     (apply #'make-instance 'consensus-strategy
                           (or config nil)))))
