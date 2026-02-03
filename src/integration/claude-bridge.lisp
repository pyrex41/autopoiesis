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

(defun send-api-request (client endpoint body)
  "Send a request to the Claude API and return the parsed response."
  (unless (client-api-key client)
    (error 'autopoiesis.core:autopoiesis-error
           :message "No API key configured. Set ANTHROPIC_API_KEY or provide :api-key"))
  (let* ((url (format nil "~a~a" (client-base-url client) endpoint))
         (json-body (cl-json:encode-json-to-string body))
         (headers (make-api-headers client)))
    (handler-case
        (multiple-value-bind (response-body status-code response-headers)
            (dex:post url
                      :headers headers
                      :content json-body)
          (declare (ignore response-headers))
          (let ((parsed (cl-json:decode-json-from-string
                         (if (stringp response-body)
                             response-body
                             (babel:octets-to-string response-body :encoding :utf-8)))))
            (if (and (>= status-code 200) (< status-code 300))
                parsed
                (error 'autopoiesis.core:autopoiesis-error
                       :message (format nil "Claude API error (~a): ~a"
                                        status-code
                                        (cdr (assoc :message (cdr (assoc :error parsed)))))))))
      (dex:http-request-failed (e)
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "HTTP request failed: ~a" e)))
      (error (e)
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "Error communicating with Claude API: ~a" e))))))

;;; ===================================================================
;;; API Operations
;;; ===================================================================

(defun claude-complete (client messages &key system tools)
  "Send a completion request to Claude.

   CLIENT - A claude-client instance
   MESSAGES - List of message alists with 'role' and 'content' keys
   SYSTEM - Optional system prompt string
   TOOLS - Optional list of tool definitions in Claude format

   Returns the parsed API response as an alist."
  (let ((body (build-request-body client messages :system system :tools tools)))
    (send-api-request client "/messages" body)))

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
