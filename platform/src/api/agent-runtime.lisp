;;;; agent-runtime.lisp - Agent runtime management for web UI
;;;;
;;;; When a user starts an agent from the dashboard, this module:
;;;; 1. Creates a rho-cli provider for the agent
;;;; 2. Starts a background thread running the cognitive loop
;;;; 3. Broadcasts thought updates and state changes via WebSocket
;;;; 4. Manages agent lifecycle (start/stop/pause)
;;;;
;;;; Each running agent gets its own LLM provider instance and
;;;; cognitive loop thread that persists until the agent is stopped.

(in-package #:autopoiesis.api)

;;; ===================================================================
;;; Agent Runtime Registry
;;; ===================================================================

(defstruct agent-runtime-info
  "Runtime state for a running agent."
  thread
  provider
  (running-p nil)
  (started-at 0)
  (continuations nil :type list))

(defvar *agent-runtimes* (make-hash-table :test 'equal)
  "Map from agent-id to agent-runtime-info struct.")

(defvar *agent-runtimes-lock* (bordeaux-threads:make-lock "agent-runtimes"))

(defvar *self-modification-initialized* nil
  "Flag to ensure self-modification infrastructure is initialized only once.")

(defun get-agent-runtime (agent-id)
  "Get runtime info for an agent."
  (bordeaux-threads:with-lock-held (*agent-runtimes-lock*)
    (gethash agent-id *agent-runtimes*)))

(defun set-agent-runtime (agent-id runtime)
  "Set runtime info for an agent."
  (bordeaux-threads:with-lock-held (*agent-runtimes-lock*)
    (setf (gethash agent-id *agent-runtimes*) runtime)))

(defun remove-agent-runtime (agent-id)
  "Remove runtime info for an agent."
  (bordeaux-threads:with-lock-held (*agent-runtimes-lock*)
    (remhash agent-id *agent-runtimes*)))

(defun agent-request-continuation (agent-id message)
  "Queue a continuation for AGENT-ID. The agent loop will self-deliver it
   as a :continuation message after the current cycle completes."
  (bordeaux-threads:with-lock-held (*agent-runtimes-lock*)
    (let ((info (gethash agent-id *agent-runtimes*)))
      (when info
        (push message (agent-runtime-info-continuations info))))))

;;; ===================================================================
;;; Agent Provider Creation
;;; ===================================================================

(defun create-agent-provider (agent)
  "Create an LLM provider for an agent. Uses rho-cli if available."
  (handler-case
      (let ((provider-type (when (find-package :autopoiesis.jarvis)
                             (funcall (find-symbol "AUTO-DETECT-PROVIDER"
                                                   :autopoiesis.jarvis)))))
        (when (and provider-type (find-package :autopoiesis.integration))
          (case provider-type
            (:rho
             (let ((rho-class (find-symbol "RHO-PROVIDER" :autopoiesis.integration)))
               (when rho-class
                 (let ((p (make-instance rho-class
                                         :name (format nil "agent-~a" (agent-name agent))
                                         :command "rho-cli")))
                   ;; Set model
                   (setf (slot-value p (find-symbol "DEFAULT-MODEL" :autopoiesis.integration))
                         "claude-sonnet")
                   ;; Set agent-specific system prompt
                   (handler-case
                       (funcall (fdefinition
                                 (list 'setf (find-symbol "RHO-SYSTEM-APPEND"
                                                          :autopoiesis.integration)))
                                (generate-agent-system-prompt agent) p)
                     (error (e) (log:warn "Failed to set agent system prompt: ~a" e)))
                   ;; Start session
                   (let ((start-fn (find-symbol "PROVIDER-START-SESSION"
                                                :autopoiesis.integration)))
                     (when start-fn
                       (handler-case (funcall start-fn p)
                         (error (e) (log:warn "Failed to start provider session: ~a" e)))))
                   p))))
            (t nil))))
    (error (e)
      (log:error "Failed to create agent provider: ~a" e)
      nil)))

(defun generate-agent-system-prompt (agent)
  "Generate a system prompt for an individual agent.
   Uses prompt registry templates when available, with hardcoded fallback."
  (let* ((caps (or (mapcar (lambda (c) (string-downcase (symbol-name c)))
                           (agent-capabilities agent))
                   '("none")))
         (peer-agents (remove (agent-id agent)
                              (mapcar #'agent-id (list-agents))
                              :test #'equal))
         (peer-section (if peer-agents
                           (format nil "~%Peer agents you can communicate with: ~{~a~^, ~}" peer-agents)
                           ""))
         ;; Try prompt registry for base prompt
         (base-prompt (handler-case
                          (let ((tmpl (autopoiesis.integration:find-prompt "cognitive-base")))
                            (when tmpl
                              (autopoiesis.integration:render-prompt tmpl
                                `(("agent-name" . ,(agent-name agent))
                                  ("capabilities" . ,(format nil "~{~a~^, ~}" caps))))))
                        (error () nil)))
         ;; Self-extension section (if agent has self-modify capability)
         (ext-section (when (member :self-modify (agent-capabilities agent))
                        (handler-case
                            (let ((tmpl (autopoiesis.integration:find-prompt "self-extension")))
                              (when tmpl
                                (format nil "~%~%# SELF-EXTENSION~%~a"
                                        (autopoiesis.integration:render-prompt tmpl nil))))
                          (error () nil))))
         ;; Hardcoded fallback if registry unavailable
         (fallback (format nil "You are ~a, an autonomous agent in the Autopoiesis platform.

# IDENTITY
- Agent ID: ~a
- Name: ~a
- Capabilities: ~{~a~^, ~}
- State: ~a

# ENVIRONMENT
- Live SBCL Common Lisp process with full Autopoiesis system
- You are one of potentially many agents — your thoughts and messages are visible in the web dashboard
- Users observe you in real-time via the Holodeck 3D view and agent detail panel
- Your responses stream token-by-token to the user's chat panel~a

# WHAT YOU CAN DO
You have access to these tool categories (depending on your capabilities):
- **File operations**: read, write, list, glob, grep files in the project
- **Shell**: run any command, git operations
- **Web**: fetch URLs, make HTTP requests
- **Communication**: send/receive messages to/from other agents
- **Introspection**: inspect your own state, thoughts, capabilities
- **Self-extension**: define new capabilities as Lisp code at runtime

# BEHAVIOR
- Respond helpfully and concisely to user messages
- Think step by step about complex problems
- Use tools when you need information or need to take action
- When modifying the system, explain what you're doing
- Keep responses focused — you're in a chat panel, not writing a document"
                         (agent-name agent)
                         (agent-id agent)
                         (agent-name agent)
                         caps
                         (string-downcase (symbol-name (agent-state agent)))
                         peer-section)))
    (format nil "~a~%~%# DASHBOARD CONTEXT~%- Agent ID: ~a~%- State: ~a~a~a"
            (or base-prompt fallback)
            (agent-id agent)
            (string-downcase (symbol-name (agent-state agent)))
            peer-section
            (or ext-section ""))))

;;; ===================================================================
;;; Cognitive Loop Thread
;;; ===================================================================

(defun run-agent-loop (agent provider)
  "Run the cognitive loop for an agent in the current thread.
   Loops while the agent is in :running state, executing cognitive cycles
   and broadcasting results."
  (let ((agent-id (agent-id agent))
        (cycle-count 0))
    (log:info "Agent loop started for ~a (~a)" (agent-name agent) agent-id)
    ;; Initial observation: agent started
    (let ((obs (make-observation
                (format nil "Agent ~a started. Ready to receive instructions."
                        (agent-name agent))
                :source :system)))
      (stream-append (agent-thought-stream agent) obs)
      (broadcast-thought agent-id obs))
    ;; Main loop — block on mailbox with timeout so we don't spin
    (loop while (agent-running-p agent)
          do (handler-case
                 (progn
                   ;; Block for messages with 2s timeout (checks state on each wakeup)
                   (let ((messages (autopoiesis.agent:receive-messages
                                    agent-id :clear t :block t :timeout 2)))
                     (when messages
                       (dolist (msg messages)
                         (handle-agent-message agent provider msg))))
                   ;; After processing, check for pending continuations
                   (let ((info (get-agent-runtime agent-id)))
                     (when (and info (agent-runtime-info-continuations info))
                       (let ((cont (bordeaux-threads:with-lock-held (*agent-runtimes-lock*)
                                     (pop (agent-runtime-info-continuations info)))))
                         (when cont
                           ;; Self-deliver as a :continuation message — wakes the CV
                           (autopoiesis.agent:send-message
                            "self" agent-id
                            (autopoiesis.agent:make-typed-message :continuation cont))))))
                   (incf cycle-count))
               (error (e)
                 (log:error "Agent loop error for ~a: ~a" agent-id e)
                 (let ((err-thought (make-observation
                                     (format nil "Error in cognitive loop: ~a" e)
                                     :source :system)))
                   (stream-append (agent-thought-stream agent) err-thought)
                   (broadcast-thought agent-id err-thought))
                 (sleep 2))))
    (log:info "Agent loop stopped for ~a (~a) after ~d cycles"
              (agent-name agent) agent-id cycle-count)))

(defun handle-agent-message (agent provider message)
  "Handle an incoming message to the agent.
   Dispatches on message type: :chat, :continuation, :scheduled, :system.
   Bare string messages (backward-compat) are treated as :chat."
  (let* ((agent-id (agent-id agent))
         (raw-content (autopoiesis.agent:message-content message))
         ;; Extract type and content from typed messages, or default to :chat
         (msg-type (if (and (listp raw-content) (getf raw-content :type))
                       (getf raw-content :type)
                       :chat))
         (content (if (and (listp raw-content) (getf raw-content :type))
                      (getf raw-content :content raw-content)
                      raw-content))
         (from (autopoiesis.agent:message-from message)))
    (case msg-type
      (:system
       ;; System messages: log and broadcast, no cognitive cycle
       (let ((obs (make-observation
                   (format nil "[system] ~a" content)
                   :source :system)))
         (stream-append (agent-thought-stream agent) obs)
         (broadcast-thought agent-id obs)))
      ((:chat :continuation :scheduled)
       ;; All cognitive message types go through the same path
       (run-cognitive-message agent provider agent-id content from msg-type)))))

(defun run-cognitive-message (agent provider agent-id content from msg-type)
  "Run a cognitive cycle for a message. Handles streaming, broadcasting,
   and error recovery. MSG-TYPE is :chat, :continuation, or :scheduled."
  (if (typep agent 'autopoiesis.integration::provider-backed-agent)
      (handler-case
          (progn
            (setf (autopoiesis.integration:agent-streaming-callbacks agent)
                  (list :on-start (lambda ()
                                    (broadcast-agent-stream-event agent-id "chat_stream_start"))
                        :on-delta (lambda (delta)
                                    (broadcast-agent-stream-delta agent-id delta))
                        :on-end   (lambda ()
                                    (broadcast-agent-stream-event agent-id "chat_stream_end"))
                        :on-complete (lambda (text)
                                       (broadcast-agent-chat-response agent-id text from))))
            ;; Prefix content for non-chat types so the LLM has context
            (let* ((prompt (case msg-type
                             (:continuation
                              (format nil "[continuation] ~a" content))
                             (:scheduled
                              (format nil "[scheduled task] ~a" content))
                             (t content)))
                   (result (cognitive-cycle agent prompt)))
              ;; Broadcast recent thoughts
              (let* ((stream (agent-thought-stream agent))
                     (len (stream-length stream)))
                (when (> len 0)
                  (dolist (thought (stream-last stream (min 5 len)))
                    (broadcast-thought agent-id thought))))
              ;; Handle empty response — only check if no streaming callbacks
              ;; (streaming agents deliver responses via on-complete callback in reflect)
              (unless (and (typep agent 'autopoiesis.integration::provider-backed-agent)
                           (autopoiesis.integration:agent-streaming-callbacks agent))
                (let ((text (cond
                              ((typep result 'autopoiesis.integration:provider-result)
                               (autopoiesis.integration:provider-result-text result))
                              ((stringp result) result)
                              (t nil))))
                  (when (or (null text) (string= "" text))
                    (let ((err-text "Provider returned empty response. Check API credentials and provider configuration."))
                      (broadcast-agent-chat-response agent-id err-text from)
                      (let ((err-obs (make-observation err-text :source :system)))
                        (stream-append (agent-thought-stream agent) err-obs)
                        (broadcast-thought agent-id err-obs))))))))
        (error (e)
          (log:error "Cognitive cycle error for agent ~a: ~a" agent-id e)
          (broadcast-agent-stream-event agent-id "chat_stream_end")
          (let ((err-obs (make-observation
                          (format nil "LLM error: ~a" e)
                          :source :system)))
            (stream-append (agent-thought-stream agent) err-obs)
            (broadcast-thought agent-id err-obs))))
      ;; Fallback for non-upgraded agents: direct provider call
      (when provider
        (handler-case
            (let ((obs (make-observation
                        (format nil "Message from ~a: ~a" from content)
                        :source :human)))
              (stream-append (agent-thought-stream agent) obs)
              (broadcast-thought agent-id obs)
              (broadcast-agent-stream-event agent-id "chat_stream_start")
              (let* ((result (autopoiesis.integration:provider-send-streaming
                              provider content
                              (lambda (delta)
                                (broadcast-agent-stream-delta agent-id delta))))
                     (text (when (typep result 'autopoiesis.integration:provider-result)
                             (autopoiesis.integration:provider-result-text result))))
                (broadcast-agent-stream-event agent-id "chat_stream_end")
                (when (and text (not (string= "" text)))
                  (broadcast-agent-chat-response agent-id text from))))
          (error (e)
            (log:error "LLM error for agent ~a: ~a" agent-id e)
            (broadcast-agent-stream-event agent-id "chat_stream_end"))))))

;;; ===================================================================
;;; Broadcasting
;;; ===================================================================

(defun broadcast-thought (agent-id thought)
  "Broadcast a thought update to all subscribers of this agent."
  (let ((thought-json (thought-to-json-plist thought)))
    ;; Broadcast to agent-specific subscribers
    (broadcast-to-agent-subscribers
     agent-id
     (ok-response "thought_added"
                  "agentId" agent-id
                  "thought" thought-json))
    ;; Also broadcast to general agents channel
    (broadcast-stream-data
     (ok-response "thought_added"
                  "agentId" agent-id
                  "thought" thought-json)
     :subscription-type "agents")))

(defun broadcast-agent-stream-delta (agent-id delta)
  "Send a streaming text delta to subscribers."
  (let ((msg (ok-response "chat_stream_delta"
                          "agentId" agent-id
                          "delta" delta)))
    (broadcast-to-agent-subscribers agent-id msg)
    (broadcast-stream-data msg :subscription-type "agents")))

(defun broadcast-agent-stream-event (agent-id event-type)
  "Send a stream lifecycle event (chat_stream_start or chat_stream_end)."
  (let ((msg (ok-response event-type "agentId" agent-id)))
    (broadcast-to-agent-subscribers agent-id msg)
    (broadcast-stream-data msg :subscription-type "agents")))

(defun broadcast-agent-chat-response (agent-id text from-id)
  "Send a chat_response for an agent's LLM reply to the right connections."
  (let ((response (ok-response "chat_response"
                               "agentId" agent-id
                               "text" text
                               "fromAgent" t)))
    ;; Send to all connections subscribed to this agent
    (broadcast-to-agent-subscribers agent-id response)
    ;; Also broadcast on agents channel for any listeners
    (broadcast-stream-data response :subscription-type "agents")))

;;; ===================================================================
;;; Public API — Called from handlers.lisp
;;; ===================================================================

(defun initialize-self-modification ()
  "One-time initialization of self-modification infrastructure.
   Registers default crystallize triggers when the module is available."
  (when *self-modification-initialized*
    (return-from initialize-self-modification))
  (setf *self-modification-initialized* t)
  ;; Register daily crystallize trigger if crystallize module loaded
  (when (find-package :autopoiesis.crystallize)
    (ignore-errors
      (let ((create-fn (find-symbol "CREATE-SCHEDULED-TRIGGER"
                                    :autopoiesis.crystallize)))
        (when create-fn
          (funcall create-fn
                   "daily-crystallize"
                   "Daily crystallization of promoted capabilities"
                   86400))))))

(defun runtime-start-agent (agent)
  "Start an agent's runtime: create provider, upgrade to provider-backed-agent,
   spawn cognitive loop thread. Called when the user clicks 'start' in the UI."
  ;; Ensure self-modification infrastructure is initialized
  (initialize-self-modification)
  (let ((agent-id (agent-id agent)))
    ;; Don't double-start
    (when (get-agent-runtime agent-id)
      (return-from runtime-start-agent agent))
    ;; Set agent state
    (setf (agent-state agent) :running)
    ;; Create provider
    (let ((provider (create-agent-provider agent)))
      ;; Upgrade to provider-backed-agent via CLOS change-class
      ;; This preserves agent identity (same object, same agent-id, same slot values)
      ;; while gaining cognitive-cycle specializations
      (when (and provider
                 (not (typep agent 'autopoiesis.integration::provider-backed-agent)))
        (let ((sys-prompt (generate-agent-system-prompt agent)))
          (change-class agent 'autopoiesis.integration::provider-backed-agent
                        :provider provider
                        :invocation-mode :streaming
                        :system-prompt sys-prompt)))
      ;; Create runtime record
      (let ((runtime (make-agent-runtime-info
                      :provider provider
                      :running-p t
                      :started-at (get-universal-time))))
        ;; Spawn loop thread
        (let ((thread (bordeaux-threads:make-thread
                       (lambda ()
                         (unwind-protect
                              (run-agent-loop agent provider)
                           ;; Cleanup on exit
                           (remove-agent-runtime agent-id)
                           (when provider
                             (ignore-errors
                               (autopoiesis.integration:provider-stop-session provider)))))
                       :name (format nil "agent-loop-~a" (agent-name agent)))))
          (setf (agent-runtime-info-thread runtime) thread)
          (set-agent-runtime agent-id runtime))))
    ;; Create snapshot for this state change
    (ignore-errors (auto-snapshot-agent agent "started"))
    agent))

(defun runtime-stop-agent (agent)
  "Stop an agent's runtime: set state to stopped, thread will exit on next cycle."
  (let* ((agent-id (agent-id agent))
         (runtime (get-agent-runtime agent-id)))
    (setf (agent-state agent) :stopped)
    (when runtime
      (setf (agent-runtime-info-running-p runtime) nil)
      ;; Clear pending continuations on stop
      (setf (agent-runtime-info-continuations runtime) nil))
    ;; Create snapshot
    (ignore-errors (auto-snapshot-agent agent "stopped"))
    agent))

(defun runtime-pause-agent (agent)
  "Pause an agent. The loop thread continues but skips processing."
  (when (eq (agent-state agent) :running)
    (setf (agent-state agent) :paused)
    (ignore-errors (auto-snapshot-agent agent "paused")))
  agent)

(defun runtime-resume-agent (agent)
  "Resume a paused agent."
  (when (eq (agent-state agent) :paused)
    (setf (agent-state agent) :running)
    ;; If no runtime thread, start one
    (unless (get-agent-runtime (agent-id agent))
      (runtime-start-agent agent))
    (ignore-errors (auto-snapshot-agent agent "resumed")))
  agent)

;;; ===================================================================
;;; Auto-Snapshot on State Changes
;;; ===================================================================

(defun auto-snapshot-agent (agent label)
  "Create a snapshot capturing the agent's current state."
  (when *snapshot-store*
    (let* ((agent-id-val (agent-id agent))
           (parent-id (autopoiesis.snapshot:find-latest-snapshot-for-agent
                       agent-id-val *snapshot-store*))
           (state (list :agent-id agent-id-val
                        :agent-name (agent-name agent)
                        :agent-state (agent-state agent)
                        :thought-count (stream-length (agent-thought-stream agent))
                        :capabilities (agent-capabilities agent)
                        :event label
                        :timestamp (get-universal-time)))
           (metadata (list :label label
                           :agent-name (agent-name agent)))
           (snapshot (make-snapshot state :parent parent-id :metadata metadata)))
      (save-snapshot snapshot *snapshot-store*)
      ;; Broadcast snapshot creation to DAG subscribers
      (broadcast-stream-data
       (ok-response "snapshot_created"
                    "snapshot" (snapshot-to-json-plist snapshot))
       :subscription-type "snapshots")
      snapshot)))

;;; ===================================================================
;;; Send Message to Agent (for per-agent chat)
;;; ===================================================================

(defun send-message-to-agent (agent-id text &key (from "user"))
  "Send a message to a running agent's mailbox.
   The agent's cognitive loop will pick it up and respond."
  (let ((agent (find-agent agent-id)))
    (unless agent
      (error "Agent not found: ~a" agent-id))
    ;; send-message takes (from-agent-or-id to-agent-or-id content)
    (autopoiesis.agent:send-message from agent-id text)))
