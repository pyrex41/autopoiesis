;;;; agent-home.lisp - Persistent per-agent home directories
;;;;
;;;; Each agent gets a home directory under *agent-data-root*:
;;;;
;;;;   /data/agents/{agent-name}/
;;;;     config.sexp      - Agent configuration (system prompt, capabilities, etc.)
;;;;     history/          - Past conversation context references
;;;;     learning/         - Learned capabilities, patterns
;;;;     workspaces/       - Ephemeral task workspaces live here
;;;;
;;;; Homes persist across sessions. Workspaces within them are ephemeral.

(in-package #:autopoiesis.workspace)

;;; ── Configuration ───────────────────────────────────────────────

(defvar *agent-data-root* "/data/agents/"
  "Root directory for agent home directories.
   Each agent gets a subdirectory named after its agent-id or agent-name.")

;;; ── Agent Home ──────────────────────────────────────────────────

(defclass agent-home ()
  ((id :initarg :id
       :accessor agent-home-id
       :documentation "Agent identifier (name or uuid)")
   (root :initarg :root
         :accessor agent-home-root
         :documentation "Absolute path to agent home directory"))
  (:documentation "Persistent home directory for an agent."))

(defun agent-home-config-path (home)
  "Path to agent configuration file."
  (format nil "~Aconfig.sexp" (agent-home-root home)))

(defun agent-home-history-path (home)
  "Path to agent conversation history directory."
  (format nil "~Ahistory/" (agent-home-root home)))

(defun agent-home-learning-path (home)
  "Path to agent learning artifacts directory."
  (format nil "~Alearning/" (agent-home-root home)))

(defun agent-home-workspaces-path (home)
  "Path to agent workspaces directory."
  (format nil "~Aworkspaces/" (agent-home-root home)))

;;; ── Home Management ─────────────────────────────────────────────

(defun normalize-agent-id (agent-id)
  "Normalize an agent ID for use as a directory name.
   Lowercases and replaces non-alphanumeric chars with hyphens."
  (let ((id (string-downcase (princ-to-string agent-id))))
    (substitute-if #\- (lambda (c)
                          (not (or (alphanumericp c) (char= c #\-) (char= c #\_))))
                   id)))

(defun ensure-agent-home (agent-id &key (root *agent-data-root*))
  "Ensure a persistent home directory exists for the agent.
   Creates the directory structure if it doesn't exist.
   Returns an agent-home object.

   AGENT-ID can be a string, symbol, or agent object (uses agent-name)."
  (let* ((id (etypecase agent-id
               (string agent-id)
               (symbol (string-downcase (symbol-name agent-id)))
               (autopoiesis.agent:agent
                (autopoiesis.agent:agent-name agent-id))))
         (normalized (normalize-agent-id id))
         (home-path (format nil "~A~A/" root normalized)))
    ;; Create directory structure
    (ensure-directories-exist (format nil "~Aconfig.sexp" home-path))
    (ensure-directories-exist (format nil "~Ahistory/.keep" home-path))
    (ensure-directories-exist (format nil "~Alearning/.keep" home-path))
    (ensure-directories-exist (format nil "~Aworkspaces/.keep" home-path))
    ;; Track in substrate if available
    (when autopoiesis.substrate:*store*
      (let ((eid (autopoiesis.substrate:intern-id
                  (format nil "agent-home:~A" normalized))))
        (autopoiesis.substrate:transact!
         (list (autopoiesis.substrate:make-datom eid :agent-home/id normalized)
               (autopoiesis.substrate:make-datom eid :agent-home/root home-path)
               (autopoiesis.substrate:make-datom eid :agent-home/created-at
                                                  (get-universal-time))))))
    (make-instance 'agent-home :id normalized :root home-path)))
