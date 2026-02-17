;;;; llm-client.lisp - Unified LLM client protocol
;;;;
;;;; Generic functions and shared HTTP transport for Claude and
;;;; OpenAI-compatible API clients. Both bridges implement these
;;;; generics, allowing the agentic loop to dispatch via CLOS
;;;; instead of the *claude-complete-function* hack.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; LLM Client Protocol
;;; ===================================================================

(defgeneric llm-complete (client messages &key tools system)
  (:documentation "Send a completion request to an LLM provider.
   Returns a normalized response alist (Claude format) regardless of
   the underlying API. This enables the agentic loop to work with
   any LLM backend through a single interface.

   CLIENT - A client instance (claude-client, openai-client, etc.)
   MESSAGES - List of message alists in Claude format
   SYSTEM - Optional system prompt string
   TOOLS - Optional list of tool definitions in Claude format"))

(defgeneric llm-auth-headers (client)
  (:documentation "Return authentication headers for this LLM provider.
   Does not include content-type (added by shared transport)."))

;;; ===================================================================
;;; Shared HTTP Transport
;;; ===================================================================

(defun llm-http-post (client url body)
  "Send HTTP POST with provider-specific auth headers.
   Returns the parsed JSON response as an alist."
  (let* ((headers (append (llm-auth-headers client)
                          '(("content-type" . "application/json"))))
         (json-body (cl-json:encode-json-to-string body)))
    (handler-case
        (multiple-value-bind (response-body status-code)
            (dex:post url :headers headers :content json-body)
          (let ((parsed (cl-json:decode-json-from-string
                         (if (stringp response-body)
                             response-body
                             (babel:octets-to-string response-body
                                                     :encoding :utf-8)))))
            (if (and (>= status-code 200) (< status-code 300))
                parsed
                (error 'autopoiesis.core:autopoiesis-error
                       :message (format nil "LLM API error (~a): ~a"
                                        status-code
                                        (or (cdr (assoc :message
                                                        (cdr (assoc :error parsed))))
                                            (format nil "~a" parsed)))))))
      (dex:http-request-failed (e)
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "HTTP request failed: ~a" e)))
      (autopoiesis.core:autopoiesis-error (e)
        (error e))
      (error (e)
        (error 'autopoiesis.core:autopoiesis-error
               :message (format nil "Error communicating with LLM API: ~a" e))))))

;;; ===================================================================
;;; LLM Response Struct
;;; ===================================================================

(defstruct llm-response
  "Structured wrapper for LLM responses. Optional convenience layer
   over the normalized response alist used by the agentic loop."
  (content nil :type (or null string))
  (tool-calls nil :type list)
  (stop-reason nil :type (or null keyword))
  (usage nil :type list)
  (raw nil))

(defun response-to-llm-response (response)
  "Convert a normalized response alist to an llm-response struct."
  (make-llm-response
   :content (response-text response)
   :tool-calls (response-tool-calls response)
   :stop-reason (let ((sr (response-stop-reason response)))
                  (when sr (intern (string-upcase (string sr)) :keyword)))
   :usage (response-usage response)
   :raw response))
