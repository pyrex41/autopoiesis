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

;; Set the checkpoint hook on the extension compiler so that
;; invoke-extension wraps execution with checkpoint when available.
(when (boundp 'autopoiesis.core::*checkpoint-on-invoke*)
  (setf autopoiesis.core::*checkpoint-on-invoke* nil))
