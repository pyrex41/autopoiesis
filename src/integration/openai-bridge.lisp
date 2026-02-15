;;;; openai-bridge.lisp - OpenAI-compatible API client
;;;;
;;;; Minimal HTTP client for OpenAI-format APIs. Covers OpenAI, Groq,
;;;; Together, Fireworks, Ollama, vLLM, and any other OpenAI-compatible
;;;; endpoint. Differs from Claude API in message format (system is a
;;;; message, not a parameter) and tool call format.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; OpenAI Client
;;; ===================================================================

(defclass openai-client ()
  ((api-key :initarg :api-key
            :accessor openai-client-api-key
            :initform nil
            :documentation "API key (nil for local endpoints like Ollama)")
   (model :initarg :model
          :accessor openai-client-model
          :initform "gpt-4o"
          :documentation "Model to use")
   (base-url :initarg :base-url
             :accessor openai-client-base-url
             :initform "https://api.openai.com/v1"
             :documentation "API base URL")
   (max-tokens :initarg :max-tokens
               :accessor openai-client-max-tokens
               :initform 4096
               :documentation "Default max tokens"))
  (:documentation "Client for OpenAI-compatible APIs."))

(defun make-openai-client (&key api-key model max-tokens base-url)
  "Create a new OpenAI-compatible client."
  (make-instance 'openai-client
                 :api-key (or api-key (uiop:getenv "OPENAI_API_KEY"))
                 :model (or model "gpt-4o")
                 :max-tokens (or max-tokens 4096)
                 :base-url (or base-url "https://api.openai.com/v1")))

;;; ===================================================================
;;; Message Format Conversion
;;; ===================================================================

(defun aget (key alist)
  "Get value from alist with flexible key matching.
   Handles both string keys (\"type\") and keyword keys (:type/:TYPE).
   This is needed because cl-json produces keyword keys but manual
   construction may use string keys."
  (let ((key-str (string key)))
    (cdr (or (assoc key-str alist :test #'string=)
             (assoc key alist)
             (assoc (intern (string-upcase key-str) :keyword) alist)))))

(defun claude-messages-to-openai (messages &key system)
  "Convert Claude-format messages to OpenAI format.

   Key differences:
   - OpenAI puts system prompt as a message with role 'system'
   - OpenAI tool results use role 'tool' not 'user' with tool_result content
   - OpenAI tool calls are in a 'tool_calls' field, not inline content blocks

   Handles both string-keyed alists (manual construction) and keyword-keyed
   alists (from cl-json parsing)."
  (let ((result nil))
    ;; System prompt becomes first message
    (when system
      (push `(("role" . "system") ("content" . ,system)) result))
    ;; Convert each message
    (dolist (msg messages)
      (let ((role (aget "role" msg))
            (content (aget "content" msg)))
        (cond
          ;; User message with tool_result blocks -> tool role messages
          ((and (string= role "user")
                (listp content)
                (consp (first content))
                (let ((type (aget "type" (first content))))
                  (and type (string= "tool_result" type))))
           (dolist (block content)
             (push `(("role" . "tool")
                     ("tool_call_id" . ,(aget "tool_use_id" block))
                     ("content" . ,(aget "content" block)))
                   result)))
          ;; Assistant message with tool_use content blocks -> tool_calls field
          ((and (string= role "assistant")
                (listp content)
                (some (lambda (b)
                        (and (listp b)
                             (let ((type (aget "type" b)))
                               (and type (string= "tool_use" type)))))
                      content))
           (let ((text-parts nil)
                 (tool-calls nil))
             (dolist (block content)
               (let ((type (aget "type" block)))
                 (cond
                   ((and type (string= type "text"))
                    (let ((text (aget "text" block)))
                      (when (and text (> (length text) 0))
                        (push text text-parts))))
                   ((and type (string= type "tool_use"))
                    (push `(("id" . ,(aget "id" block))
                            ("type" . "function")
                            ("function" . (("name" . ,(aget "name" block))
                                           ("arguments" . ,(cl-json:encode-json-to-string
                                                            (aget "input" block))))))
                          tool-calls)))))
             (let ((msg `(("role" . "assistant"))))
               (when text-parts
                 (push (cons "content" (format nil "~{~a~}" (nreverse text-parts))) msg))
               (when tool-calls
                 (push (cons "tool_calls" (nreverse tool-calls)) msg))
               (push (nreverse msg) result))))
          ;; Regular message - pass through
          (t (push msg result)))))
    (nreverse result)))

(defun claude-tools-to-openai (tools)
  "Convert Claude tool format to OpenAI function calling format.

   Claude: {name, description, input_schema: {type, properties, required}}
   OpenAI: {type: 'function', function: {name, description, parameters: {type, properties, required}}}"
  (mapcar (lambda (tool)
            `(("type" . "function")
              ("function" . (("name" . ,(cdr (assoc "name" tool :test #'string=)))
                             ("description" . ,(or (cdr (assoc "description" tool :test #'string=)) ""))
                             ("parameters" . ,(or (cdr (assoc "input_schema" tool :test #'string=))
                                                  '(("type" . "object")
                                                    ("properties"))))))))
          tools))

;;; ===================================================================
;;; HTTP Communication
;;; ===================================================================

(defun openai-build-request-body (client messages &key tools)
  "Build the JSON request body for OpenAI API."
  (let ((body `(("model" . ,(openai-client-model client))
                ("max_tokens" . ,(openai-client-max-tokens client))
                ("messages" . ,messages))))
    (when tools
      (push (cons "tools" tools) body))
    body))

(defun openai-make-headers (client)
  "Create headers for OpenAI API request."
  (let ((headers '(("content-type" . "application/json"))))
    (when (openai-client-api-key client)
      (push (cons "authorization"
                   (format nil "Bearer ~a" (openai-client-api-key client)))
            headers))
    headers))

(defun openai-send-request (client endpoint body)
  "Send a request to the OpenAI API and return the parsed response."
  (let* ((url (format nil "~a~a" (openai-client-base-url client) endpoint))
         (json-body (cl-json:encode-json-to-string body))
         (headers (openai-make-headers client)))
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
                       :message (format nil "OpenAI API error (~a): ~a"
                                        status-code
                                        (cdr (assoc :message (cdr (assoc :error parsed)))))))))
      (dex:http-request-failed (e)
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "HTTP request failed: ~a" e)))
      (error (e)
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "Error communicating with OpenAI API: ~a" e))))))

;;; ===================================================================
;;; API Operations
;;; ===================================================================

(defun openai-complete (client messages &key system tools)
  "Send a completion request to an OpenAI-compatible API.

   CLIENT - An openai-client instance
   MESSAGES - List of message alists in Claude format (auto-converted)
   SYSTEM - Optional system prompt string
   TOOLS - Optional list of tool definitions in Claude format (auto-converted)

   Returns the parsed API response, normalized to Claude-like format for
   consumption by the agentic loop."
  (let* ((openai-messages (claude-messages-to-openai messages :system system))
         (openai-tools (when tools (claude-tools-to-openai tools)))
         (body (openai-build-request-body client openai-messages :tools openai-tools))
         (raw-response (openai-send-request client "/chat/completions" body)))
    ;; Normalize OpenAI response to Claude-like format
    (openai-response-to-claude-format raw-response)))

;;; ===================================================================
;;; Response Format Normalization
;;; ===================================================================

(defun openai-response-to-claude-format (response)
  "Convert an OpenAI API response to Claude-like format.

   This allows the agentic loop to work with both APIs through a common
   response format."
  (let* ((choices (cdr (assoc :choices response)))
         (choice (first choices))
         (message (cdr (assoc :message choice)))
         (finish-reason (cdr (assoc :finish--reason choice)))
         (content-text (cdr (assoc :content message)))
         (tool-calls (cdr (assoc :tool--calls message)))
         (usage (cdr (assoc :usage response)))
         (content-blocks nil))
    ;; Build content blocks in Claude format
    (when (and content-text (> (length content-text) 0))
      (push `((:type . "text") (:text . ,content-text)) content-blocks))
    (dolist (tc tool-calls)
      (let* ((func (cdr (assoc :function tc)))
             (args-string (cdr (assoc :arguments func)))
             (args (handler-case (cl-json:decode-json-from-string args-string)
                     (error () nil))))
        (push `((:type . "tool_use")
                (:id . ,(cdr (assoc :id tc)))
                (:name . ,(cdr (assoc :name func)))
                (:input . ,args))
              content-blocks)))
    ;; Map finish_reason to Claude's stop_reason
    (let ((stop-reason (cond
                         ((string= finish-reason "tool_calls") "tool_use")
                         ((string= finish-reason "stop") "end_turn")
                         ((string= finish-reason "length") "max_tokens")
                         (t finish-reason))))
      `((:id . ,(or (cdr (assoc :id response)) "msg_openai"))
        (:type . "message")
        (:role . "assistant")
        (:content . ,(nreverse content-blocks))
        (:model . ,(or (cdr (assoc :model response)) "unknown"))
        (:stop--reason . ,stop-reason)
        (:usage . ,usage)))))
