;;;; registry.lisp - Agent registry
;;;;
;;;; Global tracking of active agents.

(in-package #:autopoiesis.agent)

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *agent-registry* (make-hash-table :test 'equal)
  "Global registry of all agents by ID.")

(defun register-agent (agent &key (registry *agent-registry*))
  "Register an agent in the global registry."
  (setf (gethash (agent-id agent) registry) agent))

(defun unregister-agent (agent &key (registry *agent-registry*))
  "Remove an agent from the registry."
  (remhash (agent-id agent) registry))

(defun find-agent (id &key (registry *agent-registry*))
  "Find an agent by ID."
  (gethash id registry))

(defun list-agents (&key (registry *agent-registry*))
  "List all registered agents."
  (loop for agent being the hash-values of registry
        collect agent))

(defun running-agents (&key (registry *agent-registry*))
  "List all currently running agents."
  (remove-if-not #'agent-running-p (list-agents :registry registry)))
