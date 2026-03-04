;;;; persistent-supervisor-bridge.lisp - Bridge supervisor checkpoints to persistent agents
;;;;
;;;; Provides wrapper functions that call checkpoint-agent/revert-to-stable
;;;; and also sync the dual-agent persistent root.

(in-package #:autopoiesis.supervisor)

;;; ═══════════════════════════════════════════════════════════════════
;;; Persistent Checkpoint Bridge
;;; ═══════════════════════════════════════════════════════════════════

(defun checkpoint-dual-agent (agent &key operation)
  "Checkpoint a dual-agent: creates supervisor checkpoint AND syncs persistent root.
   For plain agents, falls back to regular checkpoint-agent."
  (let ((snap (checkpoint-agent agent :operation operation)))
    ;; If this is a dual-agent, also sync persistent root
    (when (typep agent 'autopoiesis.agent:dual-agent)
      (let ((new-root (autopoiesis.agent:sync-agent-to-persistent agent)))
        (setf (autopoiesis.agent:dual-agent-root agent) new-root)
        (autopoiesis.agent:record-agent-transition new-root :operation :checkpoint)))
    snap))

(defun revert-dual-agent (agent &key target)
  "Revert a dual-agent: reverts supervisor state AND syncs persistent root.
   For plain agents, falls back to regular revert-to-stable."
  (let ((result (revert-to-stable agent :target target)))
    (when (typep agent 'autopoiesis.agent:dual-agent)
      (let ((new-root (autopoiesis.agent:sync-agent-to-persistent agent)))
        (setf (autopoiesis.agent:dual-agent-root agent) new-root)
        (autopoiesis.agent:record-agent-transition new-root :operation :revert)))
    result))
