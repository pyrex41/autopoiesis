;;;; agentic-agent.lisp - Agent with direct LLM API agentic loop
;;;;
;;;; Unlike provider-backed-agent which delegates to CLI tools,
;;;; agentic-agent runs the tool loop itself in CL, giving full
;;;; observability and control over each turn.
;;;;
;;;; NOTE: For new agents, prefer provider-backed-agent with rho-cli.
;;;; agentic-agent is retained for direct API use cases where in-process
;;;; tool loop control is needed. Dashboard agents now use
;;;; provider-backed-agent via cognitive-cycle.

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
                      :documentation "List of capability instances available as tools")
   (cycle-actions :initarg :cycle-actions
                  :accessor agent-cycle-actions
                  :initform nil
                  :documentation "Tool actions collected during the current cognitive cycle")
   (cycle-count :initarg :cycle-count
                :accessor agent-cycle-count
                :initform 0
                :documentation "Number of cognitive cycles completed (for learning schedule)"))
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
                       :system-prompt (or system-prompt
                                          (provider-system-prompt provider)
                                          (let ((p (find-prompt "cognitive-base")))
                                            (when p (render-prompt p nil))))
                       :capabilities capabilities
                       :tool-capabilities cap-instances
                       :max-turns (or max-turns (provider-max-turns provider) 25))
        ;; Legacy: create a Claude client directly (backward compatible)
        (let ((client (make-claude-client :api-key api-key :model model)))
          (make-instance 'agentic-agent
                         :name (or name "agentic-agent")
                         :client client
                         :system-prompt (or system-prompt
                                            (let ((p (find-prompt "cognitive-base")))
                                              (when p (render-prompt p nil))))
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
  "Build the full message list, gather tool capabilities, and inject learned heuristics."
  (let* ((messages (append (agent-conversation-history agent) observations))
         (base-prompt (agent-system-prompt agent))
         (heuristic-section (format-learned-heuristics agent))
         (system-prompt (if heuristic-section
                            (format nil "~a~%~%~a" base-prompt heuristic-section)
                            base-prompt)))
    (list :messages messages
          :capabilities (agent-tool-capabilities agent)
          :system-prompt system-prompt)))

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
  ;; Reset cycle actions for this cycle
  (setf (agent-cycle-actions agent) nil)
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
               ;; Collect tool actions for learning system
               (when (eq type :tool-execution)
                 (let ((tool-name (cond
                                    ((stringp data) (intern (string-upcase data) :keyword))
                                    ((and (listp data) (evenp (length data)) (getf data :name))
                                     (intern (string-upcase (getf data :name)) :keyword))
                                    ((and (listp data) (first data))
                                     (if (keywordp (first data)) (first data)
                                         (intern (string-upcase (format nil "~a" (first data))) :keyword)))
                                    (t :unknown-tool))))
                   (push tool-name (agent-cycle-actions agent))))
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
      ;; Only override if provider has a test mock; llm-complete dispatches via CLOS
      (let ((*claude-complete-function*
              (or *claude-complete-function*
                  (when provider (provider-complete-function provider)))))
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
  "Record a reflection on the agentic loop outcome and run learning pipeline."
  (let* ((success (and action-result (stringp action-result) (> (length action-result) 0)))
         (actions (nreverse (agent-cycle-actions agent))))
    (autopoiesis.core:stream-append
     (autopoiesis.agent:agent-thought-stream agent)
     (autopoiesis.core:make-reflection
      "agentic-loop"
      (if success
          (format nil "Agentic loop completed: ~a chars, ~a tool call~:p"
                  (length action-result) (length actions))
          "Agentic loop produced no response")
      :modification (unless success :retry-suggested)))
    ;; Record experience with actual tool actions and richer context
    (ignore-errors
      (autopoiesis.agent:store-experience
       (autopoiesis.agent:make-experience
        :task-type :cognitive-cycle
        :context (list :agent-name (autopoiesis.agent:agent-name agent)
                       :capabilities (autopoiesis.agent:agent-capabilities agent)
                       :tool-count (length actions))
        :actions actions
        :outcome (if success :success :failure)
        :agent-id (autopoiesis.agent:agent-id agent))))
    ;; Run learning pipeline periodically (every 5 cycles)
    (incf (agent-cycle-count agent))
    (when (zerop (mod (agent-cycle-count agent) 5))
      (run-learning-pipeline agent))
    ;; Check crystallize triggers
    (when (find-package :autopoiesis.crystallize)
      (ignore-errors
        (let ((check-fn (find-symbol "AUTO-CRYSTALLIZE-IF-TRIGGERED"
                                     :autopoiesis.crystallize)))
          (when check-fn (funcall check-fn agent)))))))

;;; ===================================================================
;;; Learning Pipeline Integration
;;; ===================================================================

(defun run-learning-pipeline (agent)
  "Extract patterns from recent experiences and generate heuristics.
   Called periodically from reflect (every 5 cycles)."
  (ignore-errors
    (let* ((agent-id (autopoiesis.agent:agent-id agent))
           (experiences (autopoiesis.agent:list-experiences :agent-id agent-id))
           (recent (subseq experiences 0 (min 50 (length experiences)))))
      (when (>= (length recent) 3)
        (let ((patterns (autopoiesis.agent:extract-patterns recent :min-frequency 0.2)))
          (when patterns
            (let ((new-heuristics (autopoiesis.agent:generate-heuristics-from-patterns
                                   patterns :min-frequency 0.25)))
              (dolist (h new-heuristics)
                (autopoiesis.agent:store-heuristic h)))))))))

(defun format-learned-heuristics (agent)
  "Format applicable heuristics as a system prompt section, or NIL if none."
  (ignore-errors
    (let ((heuristics (autopoiesis.agent:list-heuristics :min-confidence 0.3)))
      (when heuristics
        (let ((lines (loop for h in (subseq heuristics 0 (min 10 (length heuristics)))
                           for rec = (autopoiesis.agent:heuristic-recommendation h)
                           for name = (autopoiesis.agent:heuristic-name h)
                           for conf = (autopoiesis.agent:heuristic-confidence h)
                           collect (format nil "- ~a (confidence: ~,1f): ~a"
                                           (or name "unnamed") conf
                                           (cond
                                             ((and (listp rec) (eq (first rec) :prefer-actions))
                                              (format nil "prefer ~{~a~^, ~}" (second rec)))
                                             ((and (listp rec) (eq (first rec) :avoid-actions))
                                              (format nil "avoid ~{~a~^, ~}" (second rec)))
                                             (t (format nil "~a" rec)))))))
          (when lines
            (format nil "# LEARNED PATTERNS~%Based on past experience:~%~{~a~%~}" lines)))))))

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
