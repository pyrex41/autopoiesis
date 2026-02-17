;;;; provider-inference.lisp - Inference provider for direct API calls
;;;;
;;;; A provider that makes direct HTTP API calls instead of spawning CLI
;;;; subprocesses. Supports Anthropic (Claude), OpenAI-compatible, and
;;;; local model endpoints (Ollama, vLLM).

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; API Format Protocol
;;; ===================================================================

(deftype api-format () '(member :anthropic :openai))

;;; ===================================================================
;;; Inference Provider Class
;;; ===================================================================

(defclass inference-provider (provider)
  ((api-client :initarg :api-client
               :accessor provider-api-client
               :documentation "The API client instance (claude-client or openai-client)")
   (api-format :initarg :api-format
               :accessor provider-api-format
               :initform :anthropic
               :type api-format
               :documentation "API format: :anthropic or :openai")
   (complete-function :initarg :complete-function
                      :accessor provider-complete-function
                      :initform nil
                      :documentation "Override complete function (for testing)")
   (capabilities :initarg :capabilities
                 :accessor provider-capabilities
                 :initform nil
                 :documentation "List of capability instances for tool execution")
   (system-prompt :initarg :system-prompt
                  :accessor provider-system-prompt
                  :initform nil
                  :documentation "Default system prompt"))
  (:documentation "Provider that calls LLM APIs directly instead of CLI subprocesses.

Supports Anthropic Claude API and OpenAI-compatible APIs through a unified
interface. Uses the agentic loop for multi-turn tool use."))

(defun make-inference-provider (&key name api-key model base-url max-tokens
                                     (api-format :anthropic)
                                     system-prompt capabilities max-turns)
  "Create a new inference provider.

   NAME - Provider name (default: derived from api-format)
   API-KEY - API key (default: from environment)
   MODEL - Model name (default: depends on api-format)
   BASE-URL - API base URL (default: depends on api-format)
   MAX-TOKENS - Max tokens per response (default: 4096)
   API-FORMAT - :anthropic or :openai (default: :anthropic)
   SYSTEM-PROMPT - Default system prompt
   CAPABILITIES - List of capability instances for tools
   MAX-TURNS - Max agentic turns (default: 25)"
  (let* ((default-name (ecase api-format
                         (:anthropic "anthropic")
                         (:openai "openai")))
         (client (ecase api-format
                   (:anthropic
                    (make-claude-client
                     :api-key api-key
                     :model (or model "claude-sonnet-4-20250514")
                     :max-tokens (or max-tokens 4096)
                     :base-url (when base-url base-url)))
                   (:openai
                    (make-openai-client
                     :api-key api-key
                     :model (or model "gpt-4o")
                     :max-tokens (or max-tokens 4096)
                     :base-url (when base-url base-url))))))
    (make-instance 'inference-provider
                   :name (or name default-name)
                   :command "direct-api"
                   :api-client client
                   :api-format api-format
                   :system-prompt system-prompt
                   :capabilities capabilities
                   :max-turns (or max-turns 25)
                   :default-model (ecase api-format
                                    (:anthropic (client-model client))
                                    (:openai (openai-client-model client))))))

;;; ===================================================================
;;; Convenience Constructors
;;; ===================================================================

(defun make-anthropic-provider (&key api-key model system-prompt capabilities max-turns name)
  "Create an inference provider for the Anthropic Claude API."
  (make-inference-provider
   :name (or name "anthropic")
   :api-key api-key
   :model model
   :api-format :anthropic
   :system-prompt system-prompt
   :capabilities capabilities
   :max-turns max-turns))

(defun make-openai-provider (&key api-key model base-url system-prompt capabilities max-turns name)
  "Create an inference provider for OpenAI-compatible APIs."
  (make-inference-provider
   :name (or name "openai")
   :api-key api-key
   :model model
   :base-url base-url
   :api-format :openai
   :system-prompt system-prompt
   :capabilities capabilities
   :max-turns max-turns))

(defun make-ollama-provider (&key model (port 11434) system-prompt capabilities max-turns name)
  "Create an inference provider for a local Ollama instance."
  (make-inference-provider
   :name (or name "ollama")
   :api-key nil
   :model (or model "llama3.1")
   :base-url (format nil "http://localhost:~a/v1" port)
   :api-format :openai
   :system-prompt system-prompt
   :capabilities capabilities
   :max-turns max-turns))

;;; ===================================================================
;;; Provider Protocol Implementation
;;; ===================================================================

(defmethod provider-supported-modes ((provider inference-provider))
  '(:one-shot :agentic))

(defmethod provider-invoke ((provider inference-provider) prompt &key tools mode agent-id)
  "Invoke the inference provider by running the agentic loop.

   Converts capabilities to tool format, runs agentic-loop, and returns
   a provider-result."
  (declare (ignore tools mode))
  (emit-integration-event :provider-request
                          (intern (string-upcase (provider-name provider)) :keyword)
                          (list :prompt (truncate-string (format nil "~a" prompt) 200)
                                :api-format (provider-api-format provider))
                          :agent-id agent-id)
  (let* ((messages (list `(("role" . "user") ("content" . ,prompt))))
         (capabilities (provider-capabilities provider))
         (system (provider-system-prompt provider))
         (start-time (get-internal-real-time)))
    (handler-case
        ;; Only override if provider has a test mock; llm-complete dispatches via CLOS
        (let ((*claude-complete-function* (provider-complete-function provider)))
          (multiple-value-bind (final-response all-messages turn-count)
              (agentic-loop (provider-api-client provider) messages capabilities
                            :system system
                            :max-turns (provider-max-turns provider))
            (declare (ignore all-messages))
            (let* ((duration (/ (- (get-internal-real-time) start-time)
                                internal-time-units-per-second))
                   (text (response-text final-response))
                   (result (make-instance 'provider-result
                                          :provider-name (provider-name provider)
                                          :text text
                                          :turns turn-count
                                          :duration duration
                                          :exit-code 0
                                          :raw-output (format nil "~s" final-response))))
              (emit-integration-event :provider-response
                                      (intern (string-upcase (provider-name provider)) :keyword)
                                      (list :turns turn-count
                                            :duration duration
                                            :text-length (length (or text "")))
                                      :agent-id agent-id)
              result)))
      (error (e)
        (let ((duration (/ (- (get-internal-real-time) start-time)
                            internal-time-units-per-second)))
          (make-instance 'provider-result
                         :provider-name (provider-name provider)
                         :text (format nil "Error: ~a" e)
                         :duration duration
                         :exit-code 1
                         :error-output (format nil "~a" e)))))))

(defmethod provider-build-command ((provider inference-provider) prompt &key tools)
  "Not applicable for direct API providers — no subprocess."
  (declare (ignore prompt tools))
  (values "direct-api" nil))

(defmethod provider-parse-output ((provider inference-provider) raw-output)
  "Not applicable for direct API providers."
  (make-instance 'provider-result
                 :text raw-output
                 :provider-name (provider-name provider)))

(defmethod provider-format-tools ((provider inference-provider) tools)
  "Format tools for this provider's API format."
  (ecase (provider-api-format provider)
    (:anthropic tools)
    (:openai (claude-tools-to-openai tools))))

(defmethod provider-alive-p ((provider inference-provider))
  "Inference providers are always 'alive' — no subprocess to check."
  t)

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defmethod provider-to-sexpr ((provider inference-provider))
  "Serialize inference provider configuration."
  (let ((client (provider-api-client provider)))
    `(:provider
      :type inference-provider
      :name ,(provider-name provider)
      :api-format ,(provider-api-format provider)
      :model ,(ecase (provider-api-format provider)
                (:anthropic (client-model client))
                (:openai (openai-client-model client)))
      :base-url ,(ecase (provider-api-format provider)
                   (:anthropic (client-base-url client))
                   (:openai (openai-client-base-url client)))
      :max-turns ,(provider-max-turns provider)
      :system-prompt ,(provider-system-prompt provider))))

(defun sexpr-to-inference-provider (sexpr)
  "Deserialize an inference provider from S-expression.

   SEXPR is a plist like (:provider :type inference-provider :name ... )"
  (let ((plist (if (eq (first sexpr) :provider) (rest sexpr) sexpr)))
    (make-inference-provider
     :name (getf plist :name)
     :api-format (getf plist :api-format :anthropic)
     :model (getf plist :model)
     :base-url (getf plist :base-url)
     :max-turns (getf plist :max-turns 25)
     :system-prompt (getf plist :system-prompt))))
