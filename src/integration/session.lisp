;;;; session.lisp - Claude session management
;;;;
;;;; Manages conversation sessions between agents and Claude,
;;;; tracking message history, tools, and system prompts.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; Session Registry
;;; ===================================================================

(defvar *claude-session-registry* (make-hash-table :test 'equal)
  "Registry of active Claude sessions by session ID.")

(defvar *agent-claude-session-map* (make-hash-table :test 'equal)
  "Map from agent ID to Claude session ID for quick lookup.")

;;; ===================================================================
;;; Claude Session Class
;;; ===================================================================

(defclass claude-session ()
  ((id :initarg :id
       :accessor claude-session-id
       :initform (autopoiesis.core:make-uuid)
       :documentation "Unique session identifier")
   (agent-id :initarg :agent-id
             :accessor claude-session-agent-id
             :initform nil
             :documentation "ID of the agent this session belongs to")
   (messages :initarg :messages
             :accessor claude-session-messages
             :initform nil
             :documentation "List of conversation messages in Claude API format")
   (system-prompt :initarg :system-prompt
                  :accessor claude-session-system-prompt
                  :initform nil
                  :documentation "System prompt for this session")
   (tools :initarg :tools
          :accessor claude-session-tools
          :initform nil
          :documentation "Tool definitions available in this session")
   (created-at :initarg :created-at
               :accessor claude-session-created-at
               :initform (get-universal-time)
               :documentation "When the session was created")
   (updated-at :initarg :updated-at
               :accessor claude-session-updated-at
               :initform (get-universal-time)
               :documentation "When the session was last updated")
   (metadata :initarg :metadata
             :accessor claude-session-metadata
             :initform (make-hash-table :test 'equal)
             :documentation "Additional session metadata"))
  (:documentation "A conversation session with Claude for an agent."))

;;; ===================================================================
;;; Session Creation
;;; ===================================================================

(defun make-claude-session (&key id agent-id messages system-prompt tools metadata)
  "Create a new Claude session instance.

   ID - Optional session ID (auto-generated if not provided)
   AGENT-ID - ID of the owning agent
   MESSAGES - Initial messages list
   SYSTEM-PROMPT - System prompt string
   TOOLS - Tool definitions for Claude
   METADATA - Additional key-value metadata

   Returns a new claude-session instance."
  (let ((session (make-instance 'claude-session
                                :agent-id agent-id
                                :messages (or messages nil)
                                :system-prompt system-prompt
                                :tools tools)))
    (when id
      (setf (claude-session-id session) id))
    (when metadata
      (maphash (lambda (k v)
                 (setf (gethash k (claude-session-metadata session)) v))
               metadata))
    session))

(defun create-claude-session-for-agent (agent &key system-prompt tools)
  "Create a new Claude session for an agent and register it.

   AGENT - The agent to create a session for
   SYSTEM-PROMPT - Optional system prompt (auto-generated if not provided)
   TOOLS - Optional tools list (derived from agent capabilities if not provided)

   Returns the new session, registered in the global registry."
  (let* ((agent-id (autopoiesis.agent:agent-id agent))
         (prompt (or system-prompt (generate-system-prompt agent)))
         (tool-defs (or tools (agent-capabilities-to-claude-tools agent)))
         (session (make-claude-session :agent-id agent-id
                                       :system-prompt prompt
                                       :tools tool-defs)))
    ;; Register the session
    (setf (gethash (claude-session-id session) *claude-session-registry*) session)
    (setf (gethash agent-id *agent-claude-session-map*) (claude-session-id session))
    session))

;;; ===================================================================
;;; System Prompt Generation
;;; ===================================================================

(defun generate-system-prompt (agent)
  "Generate a system prompt for an agent based on its configuration.

   AGENT - The agent to generate a prompt for.

   Returns a string suitable for Claude's system parameter."
  (let* ((name (autopoiesis.agent:agent-name agent))
         (caps-registry (autopoiesis.agent:agent-capabilities agent))
         (capabilities (when (hash-table-p caps-registry)
                         (autopoiesis.agent:list-capabilities
                          :registry caps-registry))))
    (format nil "You are an AI agent named ~a operating within the Autopoiesis platform.

Your capabilities include: ~{~a~^, ~}

You operate as part of a larger agent system where:
- All your thoughts and actions are recorded in an immutable event log
- Humans can review, branch, and navigate your cognitive history
- You may be paused for human input at critical decision points

Guidelines:
- Be concise and focused in your responses
- Explain your reasoning before taking actions
- If uncertain about a decision with significant consequences, request human input
- Use tools when they help accomplish the task more effectively"
            (or name "Agent")
            (if capabilities
                (mapcar #'autopoiesis.agent:capability-name capabilities)
                '("none currently registered")))))

;;; ===================================================================
;;; Session Lookup
;;; ===================================================================

(defun find-claude-session (session-id)
  "Find a Claude session by its ID.

   SESSION-ID - The session ID to look up.

   Returns the session or NIL if not found."
  (gethash session-id *claude-session-registry*))

(defun find-claude-session-for-agent (agent-id)
  "Find the active Claude session for an agent.

   AGENT-ID - The agent ID to look up.

   Returns the session or NIL if no session exists for this agent."
  (let ((session-id (gethash agent-id *agent-claude-session-map*)))
    (when session-id
      (find-claude-session session-id))))

(defun list-claude-sessions ()
  "List all active Claude sessions.

   Returns a list of all session objects in the registry."
  (loop for session being the hash-values of *claude-session-registry*
        collect session))

;;; ===================================================================
;;; Session Deletion
;;; ===================================================================

(defun delete-claude-session (session-id)
  "Delete a Claude session from the registry.

   SESSION-ID - The ID of the session to delete.

   Returns T if the session was deleted, NIL if it didn't exist."
  (let ((session (find-claude-session session-id)))
    (when session
      ;; Remove from agent map if present
      (when (claude-session-agent-id session)
        (remhash (claude-session-agent-id session) *agent-claude-session-map*))
      ;; Remove from main registry
      (remhash session-id *claude-session-registry*)
      t)))

;;; ===================================================================
;;; Message Management
;;; ===================================================================

(defun claude-session-add-message (session role content)
  "Add a message to the Claude session.

   SESSION - The session to add to
   ROLE - Message role (\"user\" or \"assistant\")
   CONTENT - Message content (string or content blocks)

   Returns the updated session."
  (let ((message (format-message role content)))
    (setf (claude-session-messages session)
          (append (claude-session-messages session) (list message)))
    (setf (claude-session-updated-at session) (get-universal-time))
    session))

(defun claude-session-add-assistant-response (session response)
  "Add an assistant response from Claude API to the session.

   SESSION - The session to add to
   RESPONSE - The parsed Claude API response

   Returns the updated session."
  (let ((content (cdr (assoc :content response))))
    (when content
      (let ((message `(("role" . "assistant")
                       ("content" . ,content))))
        (setf (claude-session-messages session)
              (append (claude-session-messages session) (list message)))
        (setf (claude-session-updated-at session) (get-universal-time)))))
  session)

(defun claude-session-add-tool-results (session results)
  "Add tool results to the Claude session as a user message.

   SESSION - The session to add to
   RESULTS - List of tool result plists from execute-tool-call

   Returns the updated session."
  (let ((message (format-tool-results results)))
    (setf (claude-session-messages session)
          (append (claude-session-messages session) (list message)))
    (setf (claude-session-updated-at session) (get-universal-time))
    session))

(defun claude-session-clear-messages (session)
  "Clear all messages from the Claude session.

   SESSION - The session to clear

   Returns the updated session."
  (setf (claude-session-messages session) nil)
  (setf (claude-session-updated-at session) (get-universal-time))
  session)

;;; ===================================================================
;;; Tool Synchronization
;;; ===================================================================

(defun sync-claude-session-tools (session agent)
  "Synchronize Claude session tools with current agent capabilities.

   SESSION - The session to update
   AGENT - The agent to sync with

   Returns the updated session."
  (setf (claude-session-tools session)
        (agent-capabilities-to-claude-tools agent))
  (setf (claude-session-updated-at session) (get-universal-time))
  session)

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defun claude-session-to-sexpr (session)
  "Convert a Claude session to an S-expression for persistence.

   SESSION - The session to serialize.

   Returns a serializable S-expression."
  `(:claude-session
    :id ,(claude-session-id session)
    :agent-id ,(claude-session-agent-id session)
    :messages ,(claude-session-messages session)
    :system-prompt ,(claude-session-system-prompt session)
    :tools ,(claude-session-tools session)
    :created-at ,(claude-session-created-at session)
    :updated-at ,(claude-session-updated-at session)
    :metadata ,(hash-table-alist (claude-session-metadata session))))

(defun sexpr-to-claude-session (sexpr)
  "Restore a Claude session from an S-expression.

   SEXPR - The S-expression to deserialize.

   Returns a claude-session instance."
  (unless (and (consp sexpr) (eq (first sexpr) :claude-session))
    (error 'autopoiesis.core:autopoiesis-error
           :message "Invalid Claude session S-expression"))
  (let ((plist (rest sexpr)))
    (let ((session (make-instance 'claude-session
                                  :id (getf plist :id)
                                  :agent-id (getf plist :agent-id)
                                  :messages (getf plist :messages)
                                  :system-prompt (getf plist :system-prompt)
                                  :tools (getf plist :tools)
                                  :created-at (getf plist :created-at)
                                  :updated-at (getf plist :updated-at))))
      ;; Restore metadata
      (dolist (pair (getf plist :metadata))
        (setf (gethash (car pair) (claude-session-metadata session)) (cdr pair)))
      session)))
