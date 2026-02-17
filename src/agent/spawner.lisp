;;;; spawner.lisp - Agent spawning
;;;;
;;;; Creating new agents, including from snapshots.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Spawning
;;; ═══════════════════════════════════════════════════════════════════

(defun spawn-agent (parent &key name capabilities)
  "Spawn a new child agent from PARENT."
  (let ((child (make-agent :name name
                           :capabilities (or capabilities
                                              (agent-capabilities parent))
                           :parent (agent-id parent))))
    ;; Register child with parent
    (push (agent-id child) (agent-children parent))
    child))

(defun spawn-with-snapshot (snapshot &key name)
  "Create a new agent from a snapshot state."
  ;; Placeholder - requires snapshot layer
  (declare (ignore snapshot))
  (make-agent :name name))

(defun agent-lineage (agent)
  "Return the list of ancestor agent IDs."
  (let ((lineage nil)
        (current (agent-parent agent)))
    (loop while current
          do (push current lineage)
             ;; Would need agent registry to continue traversal
             (setf current nil))
    (nreverse lineage)))
