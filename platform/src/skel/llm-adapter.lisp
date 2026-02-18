;;;; llm-adapter.lisp - Thin bridge between SKEL and autopoiesis.integration LLM clients
;;;; Adapts SKEL's LLM expectations to the existing llm-complete protocol

(in-package #:autopoiesis.skel)

;;; ============================================================================
;;; LLM Error Conditions
;;; ============================================================================

(define-condition skel-llm-rate-limit-error (skel-error)
  ((retry-after :initarg :retry-after :reader skel-llm-retry-after
                :initform nil
                :documentation "Seconds to wait before retrying"))
  (:report (lambda (c s)
             (format s "SKEL LLM rate limit error: ~A" (skel-error-message c))))
  (:documentation "Signaled on 429 Too Many Requests."))

(define-condition skel-llm-server-error (skel-error)
  ()
  (:report (lambda (c s)
             (format s "SKEL LLM server error: ~A" (skel-error-message c))))
  (:documentation "Signaled on 5xx server errors."))

(define-condition skel-llm-connection-error (skel-error)
  ()
  (:report (lambda (c s)
             (format s "SKEL LLM connection error: ~A" (skel-error-message c))))
  (:documentation "Signaled on network/timeout errors."))

;;; ============================================================================
;;; Client Protocol - Generic Functions
;;; ============================================================================

(defgeneric skel-client-api-key (client)
  (:documentation "Return the API key for a SKEL-compatible LLM client."))

(defgeneric skel-client-model (client)
  (:documentation "Return the model name for a SKEL-compatible LLM client."))

(defgeneric skel-client-max-tokens (client)
  (:documentation "Return the max tokens setting for a SKEL-compatible LLM client."))

(defgeneric skel-client-temperature (client)
  (:documentation "Return the temperature setting for a SKEL-compatible LLM client."))

(defgeneric skel-client-timeout (client)
  (:documentation "Return the timeout setting for a SKEL-compatible LLM client."))

;;; ============================================================================
;;; Default Client Wrapper
;;; ============================================================================

(defclass skel-llm-client ()
  ((api-key
    :initarg :api-key
    :initform nil
    :accessor skel-llm-client-api-key
    :documentation "API key for the provider")
   (model
    :initarg :model
    :initform "claude-sonnet-4-20250514"
    :accessor skel-llm-client-model
    :documentation "Model identifier")
   (max-tokens
    :initarg :max-tokens
    :initform 4096
    :accessor skel-llm-client-max-tokens
    :documentation "Maximum response tokens")
   (temperature
    :initarg :temperature
    :initform nil
    :accessor skel-llm-client-temperature
    :documentation "Sampling temperature")
   (timeout
    :initarg :timeout
    :initform 60
    :accessor skel-llm-client-timeout
    :documentation "Request timeout in seconds"))
  (:documentation "Default SKEL LLM client wrapping autopoiesis.integration clients."))

(defmethod skel-client-api-key ((client skel-llm-client))
  (skel-llm-client-api-key client))

(defmethod skel-client-model ((client skel-llm-client))
  (skel-llm-client-model client))

(defmethod skel-client-max-tokens ((client skel-llm-client))
  (skel-llm-client-max-tokens client))

(defmethod skel-client-temperature ((client skel-llm-client))
  (skel-llm-client-temperature client))

(defmethod skel-client-timeout ((client skel-llm-client))
  (skel-llm-client-timeout client))

;;; ============================================================================
;;; Constructor
;;; ============================================================================

(defun make-skel-llm-client (&key api-key model max-tokens temperature timeout)
  "Create a new SKEL LLM client."
  (make-instance 'skel-llm-client
    :api-key (or api-key (uiop:getenv "ANTHROPIC_API_KEY"))
    :model (or model "claude-sonnet-4-20250514")
    :max-tokens (or max-tokens 4096)
    :temperature temperature
    :timeout (or timeout 60)))

;;; ============================================================================
;;; Send Message - Synchronous
;;; ============================================================================

(defgeneric skel-send-message (client prompt &key system)
  (:documentation "Send a message to the LLM and return (values text input-tokens output-tokens)."))

(defmethod skel-send-message ((client skel-llm-client) prompt &key system)
  "Send a message via autopoiesis.integration:llm-complete.
Returns (values text input-tokens output-tokens)."
  (let* ((messages (list `((:role . "user") (:content . ,prompt))))
         (response (handler-case
                       (autopoiesis.integration:llm-complete
                        (autopoiesis.integration:make-claude-client
                         :api-key (skel-client-api-key client)
                         :model (skel-client-model client)
                         :max-tokens (skel-client-max-tokens client))
                        messages
                        :system system)
                     (error (e)
                       (error 'skel-llm-connection-error
                              :message (format nil "LLM call failed: ~A" e))))))
    ;; Extract text from Claude-format response
    (let* ((content (cdr (assoc :content response)))
           (text (if (listp content)
                     ;; Content blocks format
                     (let ((text-block (find-if (lambda (block)
                                                  (string= (cdr (assoc :type block)) "text"))
                                                content)))
                       (when text-block
                         (cdr (assoc :text text-block))))
                     ;; Simple string format
                     content))
           (usage (cdr (assoc :usage response)))
           (input-tokens (or (cdr (assoc :input--tokens usage)) 0))
           (output-tokens (or (cdr (assoc :output--tokens usage)) 0)))
      (values (or text "")
              input-tokens
              output-tokens))))

;;; ============================================================================
;;; Stream Message - Synchronous Fallback
;;; ============================================================================

(defgeneric skel-stream-message (client prompt &key system on-chunk on-complete on-error)
  (:documentation "Stream a message from the LLM with callbacks.
Default implementation: synchronous call delivered as single chunk."))

(defmethod skel-stream-message ((client skel-llm-client) prompt
                                &key system on-chunk on-complete on-error)
  "Default streaming: synchronous call delivered as single chunk."
  (handler-case
      (multiple-value-bind (text input-tokens output-tokens)
          (skel-send-message client prompt :system system)
        (declare (ignore input-tokens output-tokens))
        (when on-chunk
          (funcall on-chunk text))
        (when on-complete
          (funcall on-complete text))
        ;; Return a simple stream handle
        :completed)
    (error (e)
      (if on-error
          (funcall on-error e)
          (error e))
      :error)))

(defgeneric skel-stream-cancel-llm (stream)
  (:documentation "Cancel an in-progress LLM stream."))

(defmethod skel-stream-cancel-llm ((stream t))
  "Default no-op for stream cancellation."
  nil)
