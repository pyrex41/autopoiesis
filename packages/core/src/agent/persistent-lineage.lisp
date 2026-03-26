;;;; persistent-lineage.lisp - Agent forking, merging, and ancestry
;;;;
;;;; O(1) forking via structural sharing of persistent data.
;;;; Lineage tracking through parent-root chains.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Forking
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-fork (agent &key name)
  "O(1) fork of AGENT. Creates a child sharing all persistent data.
   Returns (values child updated-parent) where:
   - CHILD has a new id, parent-root set to agent's id, empty children, version 0
   - UPDATED-PARENT has child's id added to its children list."
  (let* ((child-id (make-uuid))
         (child (%make-persistent-agent
                 :id          child-id
                 :name        (or name
                                  (format nil "~a/fork" (persistent-agent-name agent)))
                 :version     0
                 :timestamp   (get-precise-time)
                 :membrane    (persistent-agent-membrane agent)
                 :genome      (persistent-agent-genome agent)
                 :thoughts    (persistent-agent-thoughts agent)
                 :capabilities (persistent-agent-capabilities agent)
                 :heuristics  (persistent-agent-heuristics agent)
                 :children    nil
                 :parent-root (persistent-agent-id agent)
                 :metadata    (persistent-agent-metadata agent)))
         (updated-parent
           (copy-persistent-agent agent
             :children (cons child-id (persistent-agent-children agent)))))
    (values child updated-parent)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Diffing
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-agent-diff (agent1 agent2)
  "Compute a structural diff between two persistent agents.
   Delegates to sexpr-diff on their serialized forms."
  (sexpr-diff (persistent-agent-to-sexpr agent1)
              (persistent-agent-to-sexpr agent2)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Merging
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-agent-merge (agent1 agent2)
  "Append-only merge of two agents.
   - Thoughts: concatenated (agent1 then agent2)
   - Capabilities: set union
   - Genome: latest-wins (by timestamp)
   - Membrane: latest-wins (by timestamp)
   - Heuristics: append deduplicated
   - Metadata: merged (latest-wins by timestamp)
   Returns a new agent."
  (let* ((later (if (>= (persistent-agent-timestamp agent1)
                        (persistent-agent-timestamp agent2))
                    agent1 agent2))
         (earlier (if (eq later agent1) agent2 agent1)))
    (%make-persistent-agent
     :id           (persistent-agent-id later)
     :name         (persistent-agent-name later)
     :version      (1+ (max (persistent-agent-version agent1)
                             (persistent-agent-version agent2)))
     :timestamp    (get-precise-time)
     :membrane     (pmap-merge (persistent-agent-membrane earlier)
                               (persistent-agent-membrane later))
     :genome       (persistent-agent-genome later)
     :thoughts     (pvec-concat (persistent-agent-thoughts agent1)
                                (persistent-agent-thoughts agent2))
     :capabilities (pset-union (persistent-agent-capabilities agent1)
                               (persistent-agent-capabilities agent2))
     :heuristics   (remove-duplicates
                    (append (persistent-agent-heuristics agent1)
                            (persistent-agent-heuristics agent2))
                    :test #'equal)
     :children     (union (persistent-agent-children agent1)
                          (persistent-agent-children agent2)
                          :test #'equal)
     :parent-root  (persistent-agent-parent-root later)
     :metadata     (pmap-merge (persistent-agent-metadata earlier)
                               (persistent-agent-metadata later)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Ancestry
;;; ═══════════════════════════════════════════════════════════════════

(defun persistent-ancestors (agent registry)
  "Walk the parent-root chain using REGISTRY (hash-table id->agent).
   Returns list of ancestors oldest-first (root ancestor is first)."
  (let ((ancestors nil)
        (current agent))
    (loop
      (let ((parent-id (persistent-agent-parent-root current)))
        (when (null parent-id)
          (return (nreverse ancestors)))
        (let ((parent (gethash parent-id registry)))
          (unless parent
            (return (nreverse ancestors)))
          (push parent ancestors)
          (setf current parent))))))

(defun persistent-common-ancestor (agent1 agent2 registry)
  "Find the first shared ancestor of AGENT1 and AGENT2.
   Returns the common ancestor agent, or NIL if none found."
  (let ((ancestors1 (persistent-ancestors agent1 registry))
        (ancestors2-ids (make-hash-table :test 'equal)))
    ;; Index agent2's ancestry
    (setf (gethash (persistent-agent-id agent2) ancestors2-ids) t)
    (dolist (a (persistent-ancestors agent2 registry))
      (setf (gethash (persistent-agent-id a) ancestors2-ids) t))
    ;; Walk agent1's ancestry from newest to oldest
    (dolist (a (reverse ancestors1))
      (when (gethash (persistent-agent-id a) ancestors2-ids)
        (return-from persistent-common-ancestor a)))
    ;; Check if agent2 itself is an ancestor of agent1
    (when (gethash (persistent-agent-id agent1) ancestors2-ids)
      agent1)
    nil))

(defun persistent-generation (agent registry)
  "Count parent-root hops from AGENT to root (agent with nil parent-root).
   Returns 0 for a root agent."
  (let ((count 0)
        (current agent))
    (loop
      (let ((parent-id (persistent-agent-parent-root current)))
        (when (null parent-id)
          (return count))
        (let ((parent (gethash parent-id registry)))
          (unless parent
            (return count))
          (incf count)
          (setf current parent))))))
