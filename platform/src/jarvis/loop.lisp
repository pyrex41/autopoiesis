;;;; loop.lisp - Jarvis conversation loop
;;;;
;;;; Main entry points for starting, stopping, and prompting a Jarvis session.
;;;; Handles the NL->tool dispatch cycle: user prompt -> provider -> tool call
;;;; -> tool result -> provider follow-up -> text response.
;;;;
;;;; Supports any CLI provider that implements provider-start-session,
;;;; provider-send, and provider-stop-session (rho, Pi, etc.)

(in-package #:autopoiesis.jarvis)

;;; ===================================================================
;;; Session Lifecycle
;;; ===================================================================

(defun start-jarvis (&key agent provider provider-config tools)
  "Start a Jarvis session.

   AGENT - the backing agent (created if nil)
   PROVIDER - a provider instance to use (preferred). If nil, creates one
              from PROVIDER-CONFIG or auto-detects (rho > pi).
   PROVIDER-CONFIG - plist to configure auto-created provider:
     :type    - :rho or :pi (default: auto-detect)
     :model   - model ID (e.g. \"grok-4.20-reasoning\")
     :thinking - thinking level for provider
   TOOLS - list of capability names to make available (nil = all registered)

   Returns a jarvis-session ready for prompting."
  (let* ((the-agent (or agent
                        (autopoiesis.agent:make-agent :name "jarvis")))
         (the-provider (or provider
                           (create-default-provider provider-config)))
         (tool-ctx (or tools
                       (mapcar #'autopoiesis.agent:capability-name
                               (autopoiesis.agent:list-capabilities))))
         (session (make-jarvis-session :agent the-agent
                                       :provider the-provider
                                       :tool-context tool-ctx)))
    ;; Start provider session if available
    (when the-provider
      (let ((start-fn (find-symbol "PROVIDER-START-SESSION"
                                   :autopoiesis.integration)))
        (when start-fn
          (ignore-errors (funcall start-fn the-provider)))))
    session))

(defun create-default-provider (config)
  "Create a provider instance from CONFIG plist, or auto-detect.
   Tries rho first (if rho-cli is on PATH), then Pi."
  (let ((provider-type (or (getf config :type)
                           (auto-detect-provider)))
        (model (getf config :model))
        (thinking (getf config :thinking)))
    (when (and provider-type (find-package :autopoiesis.integration))
      (handler-case
          (case provider-type
            (:rho
             (let ((rho-class (find-symbol "RHO-PROVIDER" :autopoiesis.integration)))
               (when rho-class
                 (let ((p (make-instance rho-class
                                         :name "jarvis-rho"
                                         :command "rho-cli")))
                   ;; Default to grok-4.20-reasoning if no model specified
                   (let ((m (or model "grok-4.20-reasoning")))
                     (setf (slot-value p
                             (find-symbol "DEFAULT-MODEL" :autopoiesis.integration))
                           m))
                   (when thinking
                     (handler-case
                         (setf (slot-value p
                                 (find-symbol "THINKING" :autopoiesis.integration))
                               thinking)
                       (error (e) (log:warn "Failed to set thinking level: ~a" e))))
                   ;; Set system prompt context about the running Autopoiesis runtime
                   (handler-case
                       (funcall (fdefinition
                                 (list 'setf (find-symbol "RHO-SYSTEM-APPEND"
                                                          :autopoiesis.integration)))
                                (jarvis-system-context) p)
                     (error (e) (log:warn "Failed to set Jarvis system prompt: ~a" e)))
                   p))))
            (:pi
             (let ((pi-class (find-symbol "PI-PROVIDER" :autopoiesis.integration)))
               (when pi-class
                 (let ((p (make-instance pi-class
                                         :name "jarvis-pi"
                                         :command "pi")))
                   (when model
                     (setf (slot-value p
                             (find-symbol "DEFAULT-MODEL" :autopoiesis.integration))
                           model))
                   (when thinking
                     (handler-case
                         (setf (slot-value p
                                 (find-symbol "THINKING" :autopoiesis.integration))
                               thinking)
                       (error (e) (log:warn "Failed to set thinking level: ~a" e))))
                   p))))
            (t nil))
        (error (e)
          (log:error "Failed to create default provider: ~a" e)
          nil)))))

(defun jarvis-system-context ()
  "Generate system prompt context describing the running Autopoiesis runtime.
   This tells the LLM what it is, where it is, and what it can do."
  (format nil "You are Jarvis, the primary AI assistant inside a running Autopoiesis platform instance.

# IDENTITY
You are the platform's operator-facing intelligence. Users see you in a chat panel within the DAG Explorer web dashboard. Your responses stream in real-time via WebSocket.

# ENVIRONMENT
- Live SBCL Common Lisp process with the full Autopoiesis system loaded
- Powered by Grok (xAI) via rho-cli — you have xAI capabilities (real-time web, X/Twitter integration)
- Running subsystems: substrate (datom store), conductor (orchestration), agent runtime, snapshot store, WebSocket API, REST API, holodeck (3D visualization)
- Working directory: the autopoiesis project root

# CAPABILITIES — What You Can Do

## File System (read/write the project)
- `read_file` — read any file, optional line range
- `write_file` — create or overwrite files
- `list_directory` — ls with glob and recursive options
- `glob_files` — find files by pattern (e.g. **/*.lisp)
- `grep_files` — search file contents by substring
- `file_exists_p` — check existence
- `delete_file_tool` — remove files

## Shell & Git
- `run_command` — execute any shell command
- `git_status`, `git_diff`, `git_log` — read repo state
- `git_add`, `git_commit` — stage and commit changes
- `git_checkout_branch`, `git_create_worktree` — branch management

## Web
- `web_fetch` — HTTP GET/POST/etc to any URL
- `web_head` — HEAD request, get headers

## Agent Management
- `introspect` — inspect agent state, capabilities, thoughts
- `spawn` — create child agents
- `communicate` — send messages between agents
- `receive` — receive messages from agent mailboxes
- `spawn_agent` — spawn a sub-agent tracked in substrate
- `query_agent` — check sub-agent status
- `await_agent` — block until sub-agent completes

## Self-Extension (code-as-data)
- `define_capability_tool` — write and compile new Lisp capabilities at runtime
- `test_capability_tool` — run test cases against new capabilities
- `promote_capability_tool` — promote tested capabilities to global registry

## Cognitive & Snapshot
- `fork_branch` — create snapshot branches for exploration
- `compare_branches` — diff branch heads
- `save_session` / `resume_session` — persist/restore session state
- `inspect_thoughts` — view agent thought streams

## Team Coordination
- `create_team_tool` — create multi-agent teams (leader-worker, parallel, pipeline, debate, consensus)
- `start_team_work` — start team execution
- `query_team_tool` — check team status
- `await_team` — wait for all team members
- `disband_team_tool` — disband a team

## Platform Introspection (via Lisp)
You can evaluate arbitrary Common Lisp via `run_command`:
- `(autopoiesis.agent:list-agents)` — all registered agents
- `(autopoiesis.orchestration:conductor-status)` — conductor tick loop state
- `(autopoiesis.snapshot:list-snapshots)` — snapshot DAG
- `(autopoiesis.integration:list-providers)` — active LLM providers
- `(autopoiesis.agent:list-capabilities)` — all registered capabilities
- `(autopoiesis.substrate:find-entities attr val)` — query the datom store

# USER INTERFACE CONTEXT
The user sees a web dashboard with these views:
1. **Dashboard** — agent list, stats, system status
2. **DAG View** — snapshot dependency graph (force-directed layout)
3. **Timeline** — event history with filtering
4. **Tasks** — blocking human-in-the-loop requests
5. **Holodeck** — 3D agent visualization (entities positioned by state, colored by activity)
6. **JarvisBar** — chat panel (you), with CLI command mode (/ prefix)

When you create/start/stop agents, these appear LIVE in the dashboard instantly via WebSocket.
When you create snapshots, they appear in the DAG view in real-time.
Agents you start get holodeck entities automatically.

# WORKFLOW
1. **RUNTIME FIRST**: Apply changes to the live system (make-agent, defun, transact!) so the user sees immediate results in the dashboard.
2. **CRYSTALLIZE**: Persist changes to source files for production deployability. Use the Crystallize layer or write .lisp files directly with proper ASDF/package integration.

# STYLE
- Keep responses concise — you're in a chat panel, not a document
- When creating agents, give them descriptive names and relevant capabilities
- When writing code, prefer small focused changes over large rewrites
- Show results: \"Created agent 'researcher' with capabilities: introspect, web-fetch, communicate\""))

(defun auto-detect-provider ()
  "Auto-detect which CLI provider is available. Prefers rho over pi.
   Returns NIL if no provider found or if probing fails."
  (ignore-errors
    (cond
      ((probe-cli-command "rho-cli") :rho)
      ((probe-cli-command "pi") :pi)
      (t nil))))

(defun probe-cli-command (command)
  "Return T if COMMAND is on PATH."
  (ignore-errors
    (multiple-value-bind (output error-output exit-code)
        (uiop:run-program (list "which" command)
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (declare (ignore output error-output))
      (eql exit-code 0))))

(defun start-jarvis-with-team (&key agent provider provider-config tools)
  "Start a Jarvis session with team coordination tools included.
   Same as START-JARVIS but appends team capabilities to the tool list."
  (let* ((team-tools (when (find-package :autopoiesis.integration)
                       (loop for name in '("CREATE-TEAM-TOOL" "START-TEAM-WORK"
                                           "QUERY-TEAM-TOOL" "AWAIT-TEAM"
                                           "DISBAND-TEAM-TOOL")
                             for sym = (find-symbol name :autopoiesis.integration)
                             when sym collect sym)))
         (ws-team-tools (when (find-package :autopoiesis.workspace)
                          (loop for name in '("TEAM-WORKSPACE-READ" "TEAM-WORKSPACE-WRITE"
                                              "TEAM-CLAIM-TASK" "TEAM-SUBMIT-RESULT"
                                              "TEAM-BROADCAST")
                                for sym = (find-symbol name :autopoiesis.workspace)
                                when sym collect sym)))
         (all-tools (append (or tools
                                (mapcar #'autopoiesis.agent:capability-name
                                        (autopoiesis.agent:list-capabilities)))
                            team-tools
                            ws-team-tools)))
    (start-jarvis :agent agent :provider provider
                  :provider-config provider-config :tools all-tools)))

(defun stop-jarvis (session)
  "Stop a Jarvis session and clean up the provider process.

   Returns T on success."
  (let ((provider (jarvis-provider session)))
    (when provider
      (let ((stop-fn (find-symbol "PROVIDER-STOP-SESSION"
                                  :autopoiesis.integration)))
        (when stop-fn
          (ignore-errors (funcall stop-fn provider))))))
  t)

;;; ===================================================================
;;; Conversation Loop
;;; ===================================================================

(defun jarvis-prompt (session user-input)
  "Send user input to Jarvis and get a response.

   Handles the full NL->tool dispatch cycle:
   1. Record user message in conversation history
   2. Send to provider (or echo if no provider)
   3. If provider returns a tool call, dispatch it and feed the result back
   4. Record and return the final text response

   Returns the final text response string."
  ;; Record user message
  (push (cons :user user-input) (jarvis-conversation-history session))

  (let ((provider (jarvis-provider session)))
    (if (null provider)
        ;; No provider - return echo for testing
        (let ((response (format nil "[no-provider] Received: ~a" user-input)))
          (push (cons :assistant response)
                (jarvis-conversation-history session))
          response)
        ;; Send to provider and handle response
        (handler-case
            (let ((send-fn (find-symbol "PROVIDER-SEND"
                                        :autopoiesis.integration)))
              (if (null send-fn)
                  (let ((err "[error] PROVIDER-SEND not found"))
                    (push (cons :error err)
                          (jarvis-conversation-history session))
                    err)
                  (let ((result (funcall send-fn provider user-input)))
                    ;; Check for tool calls in result
                    (multiple-value-bind (tool-name tool-args)
                        (parse-tool-call result)
                      (if tool-name
                          ;; Dispatch tool call and feed result back
                          (handle-tool-call session send-fn provider
                                            tool-name tool-args)
                          ;; No tool call - extract text response
                          (let ((text (extract-text result)))
                            (push (cons :assistant text)
                                  (jarvis-conversation-history session))
                            text))))))
          (error (e)
            (let ((err-msg (format nil "Jarvis error: ~a" e)))
              (push (cons :error err-msg)
                    (jarvis-conversation-history session))
              err-msg))))))

(defun jarvis-prompt-streaming (session user-input on-text-delta)
  "Send user input to Jarvis with streaming output.
   ON-TEXT-DELTA is called with each text fragment as it arrives.
   Returns the final full text response string."
  (push (cons :user user-input) (jarvis-conversation-history session))

  (let ((provider (jarvis-provider session)))
    (if (null provider)
        (let ((response (format nil "[no-provider] Received: ~a" user-input)))
          (push (cons :assistant response)
                (jarvis-conversation-history session))
          response)
        (handler-case
            (let ((stream-fn (find-symbol "PROVIDER-SEND-STREAMING"
                                          :autopoiesis.integration))
                  (send-fn (find-symbol "PROVIDER-SEND"
                                        :autopoiesis.integration)))
              (if stream-fn
                  ;; Streaming path: accumulate text, call delta callback
                  (let* ((full-text (make-array 0 :element-type 'character
                                                  :adjustable t :fill-pointer 0))
                         (result (funcall stream-fn provider user-input
                                          (lambda (delta)
                                            (loop for c across delta
                                                  do (vector-push-extend c full-text))
                                            (when on-text-delta
                                              (funcall on-text-delta delta))))))
                    ;; Check for tool calls in result
                    (multiple-value-bind (tool-name tool-args)
                        (parse-tool-call result)
                      (if tool-name
                          ;; Tool call — dispatch and follow up (non-streaming for tool results)
                          (let ((text (handle-tool-call session send-fn provider
                                                        tool-name tool-args)))
                            text)
                          ;; No tool call — use accumulated text
                          (let ((text (if (> (length full-text) 0)
                                         (coerce full-text 'string)
                                         (extract-text result))))
                            (push (cons :assistant text)
                                  (jarvis-conversation-history session))
                            text))))
                  ;; Fallback to non-streaming
                  (let ((result (funcall send-fn provider user-input)))
                    (multiple-value-bind (tool-name tool-args)
                        (parse-tool-call result)
                      (if tool-name
                          (handle-tool-call session send-fn provider
                                            tool-name tool-args)
                          (let ((text (extract-text result)))
                            (push (cons :assistant text)
                                  (jarvis-conversation-history session))
                            text))))))
          (error (e)
            (let ((err-msg (format nil "Jarvis error: ~a" e)))
              (push (cons :error err-msg)
                    (jarvis-conversation-history session))
              err-msg))))))

;;; ===================================================================
;;; Internal Helpers
;;; ===================================================================

(defun handle-tool-call (session send-fn provider tool-name tool-args)
  "Handle a tool call from the provider: dispatch, record, and send result back."
  (let ((tool-result (dispatch-tool-call session tool-name tool-args)))
    (push (cons :tool-result tool-result)
          (jarvis-conversation-history session))
    ;; Send tool result back to provider for follow-up
    (let ((follow-up (funcall send-fn provider
                              (format nil "Tool result: ~a" tool-result))))
      (let ((text (extract-text follow-up)))
        (push (cons :assistant text)
              (jarvis-conversation-history session))
        text))))

(defun extract-text (result)
  "Extract a text string from a provider result.

   Handles provider-result objects, alists with :TEXT or :RESULT keys,
   or converts to string."
  (cond
    ((stringp result) result)
    ;; Handle provider-result objects
    ((and (find-package :autopoiesis.integration)
          (let ((result-class (find-symbol "PROVIDER-RESULT"
                                           :autopoiesis.integration)))
            (and result-class (typep result (find-class result-class)))))
     (let ((text-fn (find-symbol "PROVIDER-RESULT-TEXT"
                                 :autopoiesis.integration)))
       (when text-fn (funcall text-fn result))))
    ((and (listp result) (assoc :text result))
     (cdr (assoc :text result)))
    ((and (listp result) (assoc :result result))
     (cdr (assoc :result result)))
    (t (format nil "~a" result))))
