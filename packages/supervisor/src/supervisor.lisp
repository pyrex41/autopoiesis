;;;; supervisor.lisp - with-checkpoint macro for automatic checkpoint-and-revert
;;;;
;;;; Wraps high-risk operations with automatic checkpointing. On success,
;;;; the checkpoint is promoted. On failure, the agent is reverted.

(in-package #:autopoiesis.supervisor)

;;; ═══════════════════════════════════════════════════════════════════
;;; Checkpoint-and-Revert Macro
;;; ═══════════════════════════════════════════════════════════════════

(defmacro with-checkpoint ((agent &key operation on-revert) &body body)
  "Execute BODY with automatic checkpoint-and-revert on failure.

   On success: promotes the checkpoint to stable-root and returns the result.
   On error: reverts agent to checkpoint, calls ON-REVERT if provided,
   then re-signals the error.

   AGENT      - Agent instance to checkpoint
   OPERATION  - Optional name for this operation (for status/logging)
   ON-REVERT  - Optional function to call on revert, receives the error condition"
  (let ((agent-var (gensym "AGENT"))
        (snap-var (gensym "SNAP"))
        (result-var (gensym "RESULT")))
    `(let* ((,agent-var ,agent)
            (,snap-var (checkpoint-agent ,agent-var :operation ,operation)))
       (handler-case
           (let ((,result-var (progn ,@body)))
             (promote-checkpoint)
             ,result-var)
         (error (e)
           (revert-to-stable ,agent-var
                             :target (autopoiesis.snapshot:snapshot-id ,snap-var))
           ,(when on-revert
              `(funcall ,on-revert e))
           (error e))))))
