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
           :documentation "Claude API client instance")
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
   (tool-capabilities :initarg :tool-capabilities
                      :accessor agent-tool-capabilities
                      :initform nil
                      :documentation "List of capability instances available as tools"))
  (:documentation "Agent that runs agentic loops via direct Claude API calls.

Unlike provider-backed-agent which delegates to external CLI tools,
agentic-agent runs the multi-turn tool loop itself. Each turn is
recorded as a thought, enabling full observability, snapshotting,
and time-travel through the conversation."))

(defun make-agentic-agent (&key api-key model name system-prompt capabilities max-turns)
  "Create an agent that runs agentic loops via direct API calls.

   API-KEY - Anthropic API key (default: ANTHROPIC_API_KEY env var)
   MODEL - Model to use (default: claude-sonnet-4-20250514)
   NAME - Agent name
   SYSTEM-PROMPT - System prompt string
   CAPABILITIES - List of capability names (keywords) to expose as tools
   MAX-TURNS - Max agentic turns per cycle (default: 25)"
  (let ((client (make-claude-client :api-key api-key :model model))
        (cap-instances (loop for cap-name in capabilities
                             for cap = (autopoiesis.agent:find-capability cap-name)
                             when cap collect cap
                             else do (warn "Capability ~a not found in registry" cap-name))))
    (make-instance 'agentic-agent
                   :name (or name "agentic-agent")
                   :client client
                   :system-prompt system-prompt
                   :capabilities capabilities
                   :tool-capabilities cap-instances
                   :max-turns (or max-turns 25))))

;;; ===================================================================
;;; Cognitive Loop Specializations
;;; ===================================================================

(defmethod autopoiesis.agent:perceive ((agent agentic-agent) environment)
  "Coerce environment to a list of messages for the API."
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
        :source "user-input")))
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
         (thought-stream (autopoiesis.agent:agent-thought-stream agent))
         (on-thought (lambda (type data)
                       (autopoiesis.core:stream-append
                        thought-stream
                        (case type
                          (:llm-response
                           (autopoiesis.core:make-observation
                            (or data "")
                            :source "claude-api"))
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
    (multiple-value-bind (final-response all-messages turn-count)
        (agentic-loop (agent-client agent) messages capabilities
                      :system system
                      :max-turns (agent-max-turns agent)
                      :on-thought on-thought)
      (declare (ignore turn-count))
      ;; Update conversation history with the full exchange
      (setf (agent-conversation-history agent) all-messages)
      ;; Return the final response text
      (if (consp final-response)
          (response-text final-response)
          final-response))))

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
  `(:agentic-agent
    :name ,(autopoiesis.agent:agent-name agent)
    :model ,(client-model (agent-client agent))
    :system-prompt ,(agent-system-prompt agent)
    :capabilities ,(autopoiesis.agent:agent-capabilities agent)
    :max-turns ,(agent-max-turns agent)))
