;;;; persistent-substrate.lisp - Substrate event integration for persistent agents
;;;;
;;;; Records persistent agent state transitions as datoms in the substrate,
;;;; enabling querying agent evolution history through the datom store.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Transition Recording
;;; ═══════════════════════════════════════════════════════════════════

(defun record-agent-transition (agent &key operation)
  "Record a persistent agent version transition in the substrate.
   Emits datoms for :agent/version, :agent/thought-count, :agent/capability-count,
   and :agent/timestamp. Silently skips if no substrate store is active."
  (when (and (boundp 'autopoiesis.substrate:*store*)
             autopoiesis.substrate:*store*)
    (handler-case
        (let* ((agent-id (persistent-agent-id agent))
               (eid (autopoiesis.substrate:intern-id
                     (format nil "pa:~a" agent-id))))
          (autopoiesis.substrate:transact!
           (list
            (list eid :agent/id agent-id)
            (list eid :agent/name (persistent-agent-name agent))
            (list eid :agent/version (persistent-agent-version agent))
            (list eid :agent/thought-count (pvec-length (persistent-agent-thoughts agent)))
            (list eid :agent/capability-count (pset-count (persistent-agent-capabilities agent)))
            (list eid :agent/genome-size (length (persistent-agent-genome agent)))
            (list eid :agent/timestamp (persistent-agent-timestamp agent))
            (list eid :agent/hash (persistent-agent-hash agent))))
          (when operation
            (autopoiesis.substrate:transact!
             (list (list eid :agent/last-operation (princ-to-string operation))))))
      (error (e)
        (warn "Failed to record agent transition: ~a" e)))))

(defun query-agent-versions (agent-id)
  "Query all recorded versions of a persistent agent from the substrate.
   Returns a list of plists with version data."
  (when (and (boundp 'autopoiesis.substrate:*store*)
             autopoiesis.substrate:*store*)
    (let ((eid (autopoiesis.substrate:intern-id
                (format nil "pa:~a" agent-id))))
      (autopoiesis.substrate:entity-state eid))))

(defun record-fork-event (parent child)
  "Record a fork event in the substrate linking parent and child agents."
  (when (and (boundp 'autopoiesis.substrate:*store*)
             autopoiesis.substrate:*store*)
    (handler-case
        (let* ((parent-eid (autopoiesis.substrate:intern-id
                            (format nil "pa:~a" (persistent-agent-id parent))))
               (child-eid (autopoiesis.substrate:intern-id
                           (format nil "pa:~a" (persistent-agent-id child)))))
          (autopoiesis.substrate:transact!
           (list
            (list parent-eid :agent/child (persistent-agent-id child))
            (list child-eid :agent/parent (persistent-agent-id parent))
            (list child-eid :agent/fork-time (get-precise-time)))))
      (error (e)
        (warn "Failed to record fork event: ~a" e)))))
