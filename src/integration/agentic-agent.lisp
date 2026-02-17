;;;; agentic-agent.lisp - Agent with direct LLM API agentic loop
;;;;
;;;; Unlike provider-backed-agent which delegates to CLI tools,
;;;; agentic-agent runs the tool loop itself in CL, giving full
;;;; observability and control over each turn.

(in-package #:autopoiesis.integration)

;;; ===================================================================
;;; Agentic Agent Class
;;; ===================================================================

(defclass agentic-agent (autopoiesis.agent:agent)
  ((client :initarg :client
           :accessor agent-client
           :initform nil
           :documentation "API client instance (claude-client or openai-client)")
   (inference-provider :initarg :inference-provider
                       :accessor agent-inference-provider
                       :initform nil
                       :documentation "Inference provider (when set, takes precedence over client)")
   (system-prompt :initarg :system-prompt
                  :accessor agent-system-prompt
                  :initform nil
                  :documentation "System prompt for all invocations")
   (max-turns :initarg :max-turns
              :accessor agent-max-turns
              :initform 25
              :documentation "Maximum agentic turns per cognitive cycle")
   (conversation-history :initarg :conversation-history
                         :accessor agent-conversation-history
                         :initform nil
                         :documentation "Accumulated messages across cycles")
   (conversation-context :initarg :conversation-context
                         :accessor agent-conversation-context
                         :initform nil
                         :documentation "Substrate context entity ID for persistent turn recording")
   (tool-capabilities :initarg :tool-capabilities
                      :accessor agent-tool-capabilities
                      :initform nil
                      :documentation "List of capability instances available as tools"))
  (:documentation "Agent that runs agentic loops via direct API calls.

Unlike provider-backed-agent which delegates to external CLI tools,
agentic-agent runs the multi-turn tool loop itself. Each turn is
recorded as a thought, enabling full observability, snapshotting,
and time-travel through the conversation.

Supports any LLM backend via inference-provider (Anthropic, OpenAI,
Ollama, etc.). For backward compatibility, can also accept a raw
claude-client directly."))

(defun make-agentic-agent (&key api-key model name system-prompt capabilities max-turns
                               provider)
  "Create an agent that runs agentic loops via direct API calls.

   API-KEY - API key (default: from environment based on provider)
   MODEL - Model to use (default: depends on provider)
   NAME - Agent name
   SYSTEM-PROMPT - System prompt string
   CAPABILITIES - List of capability names (keywords) to expose as tools
   MAX-TURNS - Max agentic turns per cycle (default: 25)
   PROVIDER - An inference-provider instance (takes precedence over api-key/model).
              When nil, a Claude provider is created from api-key/model for
              backward compatibility."
  (let ((cap-instances (loop for cap-name in capabilities
                             for cap = (autopoiesis.agent:find-capability cap-name)
                             when cap collect cap
                             else do (warn "Capability ~a not found in registry" cap-name))))
    (if provider
        ;; Provider-based construction
        (make-instance 'agentic-agent
                       :name (or name "agentic-agent")
                       :client (provider-api-client provider)
                       :inference-provider provider
                       :system-prompt (or system-prompt (provider-system-prompt provider))
                       :capabilities capabilities
                       :tool-capabilities cap-instances
                       :max-turns (or max-turns (provider-max-turns provider) 25))
        ;; Legacy: create a Claude client directly (backward compatible)
        (let ((client (make-claude-client :api-key api-key :model model)))
          (make-instance 'agentic-agent
                         :name (or name "agentic-agent")
                         :client client
                         :system-prompt system-prompt
                         :capabilities capabilities
                         :tool-capabilities cap-instances
                         :max-turns (or max-turns 25))))))

;;; ===================================================================
;;; Cognitive Loop Specializations
;;; ===================================================================

(defmethod autopoiesis.agent:perceive ((agent agentic-agent) environment)
  "Coerce environment to a list of messages for the API.
   When a conversation-context is set and a substrate store is active,
   records each user message as a turn in the substrate."
  (let ((messages (etypecase environment
                    (string (list `(("role" . "user") ("content" . ,environment))))
                    (list (if (and (consp (first environment))
                               (assoc "role" (first environment) :test #'string=))
                            environment
                            (list `(("role" . "user")
                                    ("content" . ,(or (getf environment :prompt)
                                                      (format nil "~{~a~^ ~}" environment)))))))
                    (null nil))))
    (when messages
      (autopoiesis.core:stream-append
       (autopoiesis.agent:agent-thought-stream agent)
       (autopoiesis.core:make-observation
        (let ((text (cdr (assoc "content" (first messages) :test #'string=))))
          (if (> (length text) 100)
              (format nil "Received prompt: ~a..." (subseq text 0 100))
              (format nil "Received prompt: ~a" text)))
        :source "user-input"))
      ;; Record user turn in substrate when context is available
      (record-turn-if-context agent :user
                              (cdr (assoc "content" (first messages) :test #'string=))))
    messages))

(defmethod autopoiesis.agent:reason ((agent agentic-agent) observations)
  "Build the full message list and gather tool capabilities."
  (let ((messages (append (agent-conversation-history agent) observations)))
    (list :messages messages
          :capabilities (agent-tool-capabilities agent)
          :system-prompt (agent-system-prompt agent))))

(defmethod autopoiesis.agent:decide ((agent agentic-agent) understanding)
  "Record decision to run the agentic loop and pass understanding through."
  (autopoiesis.core:stream-append
   (autopoiesis.agent:agent-thought-stream agent)
   (autopoiesis.core:make-decision
    `((:agentic-loop . 1.0) (:skip . 0.0))
    :agentic-loop
    :rationale (format nil "Running agentic loop with ~a tool~:p, max ~a turns"
                       (length (getf understanding :capabilities))
                       (agent-max-turns agent))
    :confidence 1.0))
  understanding)

(defmethod autopoiesis.agent:act ((agent agentic-agent) decision)
  "Run the agentic loop and record each turn as a thought."
  (let* ((messages (getf decision :messages))
         (capabilities (getf decision :capabilities))
         (system (getf decision :system-prompt))
         (provider (agent-inference-provider agent))
         (api-source (if provider
                         (format nil "~a-api" (provider-name provider))
                         "claude-api"))
         (thought-stream (autopoiesis.agent:agent-thought-stream agent))
         (on-thought (lambda (type data)
                       (autopoiesis.core:stream-append
                        thought-stream
                        (case type
                          (:llm-response
                           (autopoiesis.core:make-observation
                            (or data "")
                            :source api-source))
                          (:tool-execution
                           (autopoiesis.core:make-action
                            "tool-execution" :tools data))
                          (:tool-result
                           (autopoiesis.core:make-observation
                            (format nil "~a" data)
                            :source "tool-result"))
                          (:error
                           (autopoiesis.core:make-observation
                            (format nil "Error: ~a" data)
                            :source "error"))
                          (otherwise
                           (autopoiesis.core:make-observation
                            (format nil "~a: ~a" type data)
                            :source "agentic-loop")))))))
    ;; When using an inference-provider, bind the complete function
    ;; so the agentic loop uses the right API backend
    (let* ((ctx (agent-conversation-context agent))
           (model-kw (when provider (intern (string-upcase (provider-name provider)) :keyword)))
           (wrapped-on-thought
             (lambda (type data)
               ;; Record turns in substrate when context available
               (when ctx
                 (case type
                   (:llm-response
                    (when (and data (stringp data) (> (length data) 0))
                      (record-turn-if-context agent :assistant data :model model-kw)))
                   (:tool-result
                    (record-turn-if-context agent :tool (format nil "~a" data)))))
               ;; Delegate to the original on-thought callback
               (funcall on-thought type data))))
      (let ((*claude-complete-function*
              (or *claude-complete-function*
                  (when provider
                    (or (provider-complete-function provider)
                        (ecase (provider-api-format provider)
                          (:anthropic nil)  ; use default claude-complete
                          (:openai #'openai-complete)))))))
        (multiple-value-bind (final-response all-messages turn-count)
            (agentic-loop (agent-client agent) messages capabilities
                          :system system
                          :max-turns (agent-max-turns agent)
                          :on-thought wrapped-on-thought)
          (declare (ignore turn-count))
          ;; Update conversation history with the full exchange
          (setf (agent-conversation-history agent) all-messages)
          ;; Return the final response text
          (if (consp final-response)
              (response-text final-response)
              final-response))))))

(defmethod autopoiesis.agent:reflect ((agent agentic-agent) action-result)
  "Record a reflection on the agentic loop outcome."
  (let ((success (and action-result (stringp action-result) (> (length action-result) 0))))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-reflection
      "agentic-loop"
      (if success
          (format nil "Agentic loop completed: ~a chars of response"
                  (length action-result))
          "Agentic loop produced no response")
      :modification (unless success :retry-suggested)))))

;;; ===================================================================
;;; Substrate Conversation Integration (Phase 7)
;;; ===================================================================

(defun record-turn-if-context (agent role content &key model tokens tool-use)
  "Record a turn in the substrate if agent has a conversation-context
   and a substrate store is active. Silently skips otherwise."
  (let ((ctx (agent-conversation-context agent)))
    (when (and ctx
               autopoiesis.substrate:*store*
               content
               (stringp content)
               (> (length content) 0))
      (handler-case
          (autopoiesis.conversation:append-turn ctx role content
                                                 :model model
                                                 :tokens tokens
                                                 :tool-use tool-use)
        (error (e)
          (warn "Failed to record turn in substrate: ~a" e))))))

(defun init-conversation-context (agent &key name)
  "Initialize a conversation context for an agentic agent.
   Requires an active substrate store. Returns the context entity ID."
  (when autopoiesis.substrate:*store*
    (let* ((agent-name (autopoiesis.agent:agent-name agent))
           (ctx-name (or name (format nil "conv-~a" agent-name)))
           (ctx (autopoiesis.conversation:make-context ctx-name)))
      (setf (agent-conversation-context agent) ctx)
      ctx)))

(defun fork-agent-context (agent &key name)
  "Fork the agent's conversation context. Returns the new context entity ID.
   The agent continues using the original context; the fork is returned
   for use by another agent or branch."
  (let ((ctx (agent-conversation-context agent)))
    (when (and ctx autopoiesis.substrate:*store*)
      (autopoiesis.conversation:fork-context ctx :name name))))

;;; ===================================================================
;;; Convenience API
;;; ===================================================================

(defun agentic-agent-prompt (agent prompt-string)
  "Run one cognitive cycle with PROMPT-STRING. Returns the response text."
  (autopoiesis.agent:start-agent agent)
  (autopoiesis.agent:cognitive-cycle agent prompt-string))

;;; ===================================================================
;;; Serialization
;;; ===================================================================

(defun agentic-agent-to-sexpr (agent)
  "Serialize an agentic-agent's configuration (not conversation state)."
  (let ((provider (agent-inference-provider agent)))
    (if provider
        `(:agentic-agent
          :name ,(autopoiesis.agent:agent-name agent)
          :provider ,(provider-to-sexpr provider)
          :system-prompt ,(agent-system-prompt agent)
          :capabilities ,(autopoiesis.agent:agent-capabilities agent)
          :max-turns ,(agent-max-turns agent))
        `(:agentic-agent
          :name ,(autopoiesis.agent:agent-name agent)
          :model ,(client-model (agent-client agent))
          :system-prompt ,(agent-system-prompt agent)
          :capabilities ,(autopoiesis.agent:agent-capabilities agent)
          :max-turns ,(agent-max-turns agent)))))
