;;;; claude-bridge.lisp - Claude API integration
;;;;
;;;; Bridge for communicating with Claude.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; Claude Client
;;; ===================================================================

(defclass claude-client ()
  ((api-key :initarg :api-key
            :accessor client-api-key
            :documentation "Anthropic API key")
   (model :initarg :model
          :accessor client-model
          :initform "claude-sonnet-4-20250514"
          :documentation "Model to use")
   (base-url :initarg :base-url
             :accessor client-base-url
             :initform "https://api.anthropic.com/v1"
             :documentation "API base URL")
   (max-tokens :initarg :max-tokens
               :accessor client-max-tokens
               :initform 4096
               :documentation "Default max tokens")
   (api-version :initarg :api-version
                :accessor client-api-version
                :initform "2023-06-01"
                :documentation "Anthropic API version"))
  (:documentation "Client for Claude API"))

(defun make-claude-client (&key api-key model max-tokens base-url)
  "Create a new Claude client."
  (make-instance 'claude-client
                 :api-key (or api-key (uiop:getenv "ANTHROPIC_API_KEY"))
                 :model (or model "claude-sonnet-4-20250514")
                 :max-tokens (or max-tokens 4096)
                 :base-url (or base-url "https://api.anthropic.com/v1")))

;;; ===================================================================
;;; HTTP Communication
;;; ===================================================================

(defun build-request-body (client messages &key system tools)
  "Build the JSON request body for Claude API."
  (let ((body `(("model" . ,(client-model client))
                ("max_tokens" . ,(client-max-tokens client))
                ("messages" . ,messages))))
    (when system
      (push (cons "system" system) body))
    (when tools
      (push (cons "tools" tools) body))
    body))

(defun make-api-headers (client)
  "Create headers for Claude API request."
  `(("x-api-key" . ,(client-api-key client))
    ("anthropic-version" . ,(client-api-version client))
    ("content-type" . "application/json")))

;;; --- LLM Protocol Implementation ---

(defmethod llm-auth-headers ((client claude-client))
  "Return Claude API authentication headers."
  `(("x-api-key" . ,(client-api-key client))
    ("anthropic-version" . ,(client-api-version client))))

(defmethod llm-complete ((client claude-client) messages &key tools system)
  "Send completion to Claude API via unified protocol."
  (unless (client-api-key client)
    (error 'autopoiesis.core:autopoiesis-error
           :message "No API key configured. Set ANTHROPIC_API_KEY or provide :api-key"))
  (let ((body (build-request-body client messages :system system :tools tools)))
    (llm-http-post client
                   (format nil "~a/messages" (client-base-url client))
                   body)))

(defun send-api-request (client endpoint body)
  "Send a request to the Claude API and return the parsed response.
   Delegates to llm-http-post for shared HTTP transport."
  (unless (client-api-key client)
    (error 'autopoiesis.core:autopoiesis-error
           :message "No API key configured. Set ANTHROPIC_API_KEY or provide :api-key"))
  (llm-http-post client
                 (format nil "~a~a" (client-base-url client) endpoint)
                 body))

;;; ===================================================================
;;; API Operations
;;; ===================================================================

(defun claude-complete (client messages &key system tools)
  "Send a completion request to Claude.
   Thin wrapper around llm-complete for backward compatibility."
  (llm-complete client messages :system system :tools tools))

(defun claude-stream (client messages callback &key system tools)
  "Stream a completion from Claude, calling CALLBACK for each chunk.

   Currently not implemented - returns an error."
  (declare (ignore client messages callback system tools))
  ;; Streaming requires SSE parsing which is more complex
  (error 'autopoiesis.core:autopoiesis-error
         :message "Claude streaming not yet implemented"))

(defun claude-tool-use (client messages tools)
  "Send a request expecting tool use response.

   This is a convenience wrapper around claude-complete that
   includes tools and handles the tool_use stop reason."
  (claude-complete client messages :tools tools))

;;; ===================================================================
;;; Response Helpers
;;; ===================================================================

(defun response-text (response)
  "Extract the text content from a Claude response."
  (let ((content (cdr (assoc :content response))))
    (when content
      (loop for block in content
            when (string= "text" (cdr (assoc :type block)))
            collect (cdr (assoc :text block)) into texts
            finally (return (format nil "~{~a~}" texts))))))

(defun response-tool-calls (response)
  "Extract tool use blocks from a Claude response."
  (let ((content (cdr (assoc :content response))))
    (when content
      (loop for block in content
            when (string= "tool_use" (cdr (assoc :type block)))
            collect `(:id ,(cdr (assoc :id block))
                      :name ,(cdr (assoc :name block))
                      :input ,(cdr (assoc :input block)))))))

(defun response-stop-reason (response)
  "Get the stop reason from a Claude response."
  (cdr (assoc :stop--reason response)))

(defun response-usage (response)
  "Get the usage statistics from a Claude response."
  (cdr (assoc :usage response)))

;;; ===================================================================
;;; Session Management
;;; ===================================================================

(defmacro with-claude-session ((client &key api-key model) &body body)
  "Execute BODY with a Claude client bound."
  `(let ((,client (make-claude-client :api-key ,api-key :model ,model)))
     ,@body))

;;; ===================================================================
;;; Agentic Loop
;;; ===================================================================

(defvar *claude-complete-function* nil
  "When non-nil, agentic-loop calls this instead of llm-complete.
   Signature: (funcall fn client messages :system system :tools tools)
   Used for testing without real API calls.")

(defun agentic-loop (client messages capabilities &key system (max-turns 25) on-thought)
  "Run a multi-turn agentic loop with Claude.

   Calls Claude, checks if stop_reason is tool_use, executes tools,
   sends results back, repeats until end_turn or max-turns reached.

   CLIENT - A claude-client instance
   MESSAGES - Initial message list (will be extended in-place via nconc)
   CAPABILITIES - List of capability instances for tool execution
   SYSTEM - Optional system prompt string
   MAX-TURNS - Maximum loop iterations (default 25)
   ON-THOUGHT - Optional callback called as (funcall on-thought type content)
               where type is one of :llm-response, :tool-execution, :tool-result, :complete, :error

   Returns (values final-response all-messages turn-count)."
  (let ((tools (capabilities-to-claude-tools capabilities))
        (turn-count 0)
        (response nil)
        (complete-fn (or *claude-complete-function* #'llm-complete)))
    (handler-case
        (loop
          (let ((resp (funcall complete-fn client messages :system system :tools tools)))
            (setf response resp)
            (incf turn-count)
            (when on-thought
              (funcall on-thought :llm-response (response-text resp)))
            ;; Append assistant message to conversation
            (let ((content-blocks (cdr (assoc :content resp))))
              (nconc messages
                     (list `(("role" . "assistant")
                             ("content" . ,content-blocks)))))
            ;; Check stop reason
            (let ((stop-reason (response-stop-reason resp)))
              (when (or (not (string= stop-reason "tool_use"))
                        (>= turn-count max-turns))
                (when on-thought
                  (funcall on-thought :complete (response-text resp)))
                (return (values response messages turn-count)))
              ;; Execute tools and continue
              (when on-thought
                (funcall on-thought :tool-execution
                         (mapcar (lambda (tc) (getf tc :name))
                                 (response-tool-calls resp))))
              (let* ((results (execute-all-tool-calls resp capabilities))
                     (tool-message (format-tool-results results)))
                (when on-thought
                  (funcall on-thought :tool-result results))
                (nconc messages (list tool-message))))))
      (error (e)
        (when on-thought
          (funcall on-thought :error (format nil "~a" e)))
        (error e)))))

(defun agentic-complete (client prompt capabilities &key system (max-turns 25) on-thought)
  "Convenience wrapper: run an agentic loop starting from a single user prompt.
   Returns (values final-text final-response all-messages turn-count)."
  (let ((messages (list `(("role" . "user") ("content" . ,prompt)))))
    (multiple-value-bind (response all-messages turn-count)
        (agentic-loop client messages capabilities
                      :system system
                      :max-turns max-turns
                      :on-thought on-thought)
      (values (response-text response) response all-messages turn-count))))
