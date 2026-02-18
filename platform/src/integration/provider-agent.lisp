;;;; provider-agent.lisp - Provider-backed agent with cognitive loop
;;;;
;;;; Extends the agent class to use a CLI provider as its inference engine.
;;;; The provider drives the agentic loop; Autopoiesis wraps the exchange
;;;; as thoughts in the agent's thought stream.

(in-package #:autopoiesis.integration)

;;; ═══════════════════════════════════════════════════════════════════
;;; Provider-Backed Agent Class
;;; ═══════════════════════════════════════════════════════════════════

(defclass provider-backed-agent (autopoiesis.agent:agent)
  ((provider :initarg :provider
             :accessor agent-provider
             :documentation "The provider instance to use for inference")
   (system-prompt :initarg :system-prompt
                  :accessor agent-system-prompt
                  :initform nil
                  :documentation "System prompt prepended to all invocations")
   (invocation-mode :initarg :invocation-mode
                    :accessor agent-invocation-mode
                    :initform :one-shot
                    :documentation "How to invoke the provider (:one-shot or :streaming)"))
  (:documentation "An agent that delegates cognition to an external CLI provider.

The provider (Claude Code, Codex, etc.) runs its own agentic loop.
Autopoiesis records the exchange as thoughts for introspection and
time-travel debugging."))

(defun make-provider-backed-agent (provider &key name system-prompt capabilities mode)
  "Create an agent backed by PROVIDER.

   PROVIDER - A provider instance or name string (looked up in registry)
   NAME - Agent name
   SYSTEM-PROMPT - System prompt for all invocations
   CAPABILITIES - List of capabilities to expose as tools
   MODE - :one-shot (default) or :streaming"
  (let ((provider-instance (etypecase provider
                             (provider provider)
                             (string (or (find-provider provider)
                                         (error 'autopoiesis.core:autopoiesis-error
                                                :message (format nil "Provider ~a not found in registry"
                                                                 provider)))))))
    (make-instance 'provider-backed-agent
                   :name (or name (format nil "~a-agent" (provider-name provider-instance)))
                   :provider provider-instance
                   :system-prompt (or system-prompt
                                      (let ((p (find-prompt "provider-bridge")))
                                        (when p (render-prompt p nil))))
                   :capabilities capabilities
                   :invocation-mode (or mode :one-shot))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Cognitive Loop Specializations
;;; ═══════════════════════════════════════════════════════════════════

(defmethod autopoiesis.agent:perceive ((agent provider-backed-agent) environment)
  "Coerce environment to a prompt string."
  (etypecase environment
    (string environment)
    (list (or (getf environment :prompt)
              (format nil "~{~a~^ ~}" environment)))
    (null "")))

(defmethod autopoiesis.agent:reason ((agent provider-backed-agent) observations)
  "Build the full prompt with system prompt, and gather tool specs."
  (let* ((prompt (if (agent-system-prompt agent)
                     (format nil "~a~%~%~a" (agent-system-prompt agent) observations)
                     observations))
         (tools (when (autopoiesis.agent:agent-capabilities agent)
                  (loop for cap-name in (autopoiesis.agent:agent-capabilities agent)
                        for cap = (autopoiesis.agent:find-capability cap-name)
                        when cap
                          collect (capability-to-claude-tool cap)))))
    (list :prompt prompt :tools tools)))

(defmethod autopoiesis.agent:decide ((agent provider-backed-agent) understanding)
  "Record delegation decision and pass understanding through."
  (let ((prompt (getf understanding :prompt))
        (tools (getf understanding :tools)))
    ;; Record the decision to delegate to provider
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-decision
      `((:delegate . 1.0) (:self-process . 0.0))
      :delegate
      :rationale (format nil "Delegating to provider ~a"
                         (provider-name (agent-provider agent)))
      :confidence 1.0))
    ;; Pass through as-is for act phase
    (list :prompt prompt :tools tools)))

(defmethod autopoiesis.agent:act ((agent provider-backed-agent) decision)
  "Invoke the provider and record the exchange."
  (let* ((provider (agent-provider agent))
         (prompt (getf decision :prompt))
         (tools (getf decision :tools))
         (result (bt:with-lock-held ((provider-lock provider))
                   (provider-invoke provider prompt
                                    :tools tools
                                    :mode (agent-invocation-mode agent)
                                    :agent-id (autopoiesis.agent:agent-id agent)))))
    ;; Record the exchange in the thought stream
    (record-provider-exchange
     (autopoiesis.agent:agent-thought-stream agent)
     (provider-name provider)
     prompt
     result)
    result))

(defmethod autopoiesis.agent:reflect ((agent provider-backed-agent) action-result)
  "Record success/failure reflection."
  (when action-result
    (let ((success (result-success-p action-result)))
      (autopoiesis.core:stream-append
       (autopoiesis.agent:agent-thought-stream agent)
       (autopoiesis.core:make-reflection
        (provider-name (agent-provider agent))
        (if success
            "Provider invocation completed successfully"
            (format nil "Provider invocation failed: ~a"
                    (or (provider-result-error-output action-result) "unknown error")))
        :modification (unless success :retry-suggested))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Convenience API
;;; ═══════════════════════════════════════════════════════════════════

(defun provider-agent-prompt (agent prompt-string)
  "Convenience wrapper: start the agent, run one cognitive cycle with PROMPT-STRING.

   Returns the provider-result from the invocation."
  (autopoiesis.agent:start-agent agent)
  (prog1
      (autopoiesis.agent:cognitive-cycle agent prompt-string)
    ;; Don't stop the agent - leave it running for potential follow-ups
    ))

;;; ═══════════════════════════════════════════════════════════════════
;;; Serialization
;;; ═══════════════════════════════════════════════════════════════════

(defun provider-backed-agent-to-sexpr (agent)
  "Serialize a provider-backed agent configuration to S-expression."
  `(:provider-backed-agent
    :name ,(autopoiesis.agent:agent-name agent)
    :provider ,(provider-to-sexpr (agent-provider agent))
    :system-prompt ,(agent-system-prompt agent)
    :capabilities ,(autopoiesis.agent:agent-capabilities agent)
    :invocation-mode ,(agent-invocation-mode agent)))
