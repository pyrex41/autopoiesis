;;;; cognitive-loop.lisp - Agent cognitive cycle
;;;;
;;;; Implements the perceive-reason-decide-act-reflect loop.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Cognitive Cycle Phases
;;; ═══════════════════════════════════════════════════════════════════

(defgeneric perceive (agent environment)
  (:documentation "Gather observations from the environment.")
  (:method ((agent agent) environment)
    (declare (ignore environment))
    ;; Default: no perception
    nil))

(defgeneric reason (agent observations)
  (:documentation "Process observations into understanding.")
  (:method ((agent agent) observations)
    (declare (ignore observations))
    ;; Default: pass through
    nil))

(defgeneric decide (agent understanding)
  (:documentation "Choose an action based on understanding.")
  (:method ((agent agent) understanding)
    (declare (ignore understanding))
    ;; Default: no action
    nil))

(defgeneric act (agent decision)
  (:documentation "Execute the decided action.")
  (:method ((agent agent) decision)
    (declare (ignore decision))
    ;; Default: no-op
    nil))

(defgeneric reflect (agent action-result)
  (:documentation "Reflect on the action's outcome.")
  (:method ((agent agent) action-result)
    (declare (ignore action-result))
    ;; Default: no reflection
    nil))

;;; ═══════════════════════════════════════════════════════════════════
;;; Main Cognitive Loop
;;; ═══════════════════════════════════════════════════════════════════

(defun cognitive-cycle (agent environment)
  "Execute one iteration of the cognitive loop.
   Reflect is always called, even when act signals an error, so the learning
   system can record failures."
  (when (agent-running-p agent)
    (let* ((observations (perceive agent environment))
           (understanding (reason agent observations))
           (decision (decide agent understanding))
           (result nil)
           (errored nil))
      (handler-case
          (setf result (act agent decision))
        (error (e)
          (setf errored t)
          ;; Re-signal after reflect so callers still see the error
          (reflect agent nil)
          (error e)))
      (unless errored
        (reflect agent result))
      result)))
