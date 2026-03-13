;;;; integration.lisp - Supervisor integration with recovery and extension systems
;;;;
;;;; Registers a recovery strategy for state-inconsistency-error and
;;;; provides the checkpoint hook for extension invocation.

(in-package #:autopoiesis.supervisor)

;;; ═══════════════════════════════════════════════════════════════════
;;; Recovery Strategy
;;; ═══════════════════════════════════════════════════════════════════

(autopoiesis.core:define-recovery-strategy revert-on-inconsistency
    state-inconsistency-error
    (:priority 200
     :description "Revert to last checkpoint on state inconsistency"
     :applicable-when (not (null autopoiesis.supervisor:*checkpoint-stack*)))
  ;; We cannot easily get the agent here, so signal availability
  (format *error-output*
          "~&Supervisor: State inconsistency detected, checkpoint available for revert~%")
  :revert-available)

;;; ═══════════════════════════════════════════════════════════════════
;;; Extension Invocation Hook
;;; ═══════════════════════════════════════════════════════════════════

(defvar *current-agent-for-checkpoint* nil
  "When bound to an agent, extension invocations via *checkpoint-on-invoke*
   will automatically checkpoint before and promote/revert after execution.")

;; Set the checkpoint hook on the extension compiler so that
;; invoke-extension wraps execution with checkpoint when available.
(when (boundp 'autopoiesis.core::*checkpoint-on-invoke*)
  (setf autopoiesis.core::*checkpoint-on-invoke*
        (lambda (thunk)
          (if *current-agent-for-checkpoint*
              ;; Agent is bound — wrap with checkpoint/revert
              (let ((agent *current-agent-for-checkpoint*))
                (checkpoint-agent agent :operation :extension-invoke)
                (handler-case
                    (let ((result (funcall thunk)))
                      (ignore-errors (promote-checkpoint))
                      result)
                  (error (e)
                    (ignore-errors
                      (pop *checkpoint-stack*)
                      (revert-to-stable agent))
                    (error e))))
              ;; No agent bound — direct invocation
              (funcall thunk)))))
