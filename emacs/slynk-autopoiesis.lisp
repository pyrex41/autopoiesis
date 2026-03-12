;;;; slynk-autopoiesis.lisp — CL-side Slynk contrib for Autopoiesis
;;;;
;;;; Loaded by SLY connected-hook. Provides in-image RPC for the full
;;;; Autopoiesis platform: agents, chat, orchestration, teams, swarm,
;;;; agentic loops, and events — with zero HTTP overhead via Slynk wire protocol.

(defpackage #:slynk-autopoiesis
  (:use #:cl)
  (:export ;; System lifecycle
           #:system-status
           #:start-platform
           #:stop-platform
           ;; Providers
           #:list-providers
           ;; Agents
           #:list-agents
           #:get-agent
           #:create-agent
           #:set-agent-state
           #:agent-thoughts
           ;; Capabilities
           #:list-capabilities
           #:invoke-capability
           ;; Chat (Jarvis)
           #:start-chat
           #:chat-prompt
           #:stop-chat
           ;; Conductor / Orchestration
           #:conductor-info
           #:start-conductor-rpc
           #:stop-conductor-rpc
           #:schedule-action-rpc
           ;; Agentic loops
           #:create-agentic-agent-rpc
           #:agentic-prompt
           #:list-agentic-agents
           ;; Teams
           #:list-teams
           #:create-team-rpc
           #:start-team-rpc
           #:query-team
           #:disband-team-rpc
           ;; Swarm
           #:start-evolution
           ;; Snapshots
           #:list-snapshots
           #:list-branches
           ;; Events
           #:recent-events
           #:event-stats))

(in-package #:slynk-autopoiesis)

;;; ═══════════════════════════════════════════════════════════════════
;;; Internal helpers
;;; ═══════════════════════════════════════════════════════════════════

(defvar *sly-chat-sessions* (make-hash-table :test 'equal)
  "Map from session-name to jarvis-session.")

(defvar *sly-agentic-agents* (make-hash-table :test 'equal)
  "Map from agent-id to agentic-agent instances created from SLY.")

(defun resolve (pkg-name sym-name)
  "Find symbol SYM-NAME in package PKG-NAME, or NIL if not available."
  (let ((pkg (find-package pkg-name)))
    (when pkg (find-symbol (string sym-name) pkg))))

(defun call-if-available (pkg-name sym-name &rest args)
  "Call PKG-NAME:SYM-NAME with ARGS if the package is loaded, else signal error."
  (let ((fn (resolve pkg-name sym-name)))
    (unless (and fn (fboundp fn))
      (error "~a:~a is not available. Load the ~a system first."
             pkg-name sym-name pkg-name))
    (apply fn args)))

(defun try-call (pkg-name sym-name &rest args)
  "Like CALL-IF-AVAILABLE but returns NIL instead of signaling."
  (let ((fn (resolve pkg-name sym-name)))
    (when (and fn (fboundp fn))
      (ignore-errors (apply fn args)))))

(defun safe-slot (obj accessor-name &optional (pkg :autopoiesis.agent))
  "Read a slot via an accessor, returning NIL if the accessor isn't bound."
  (let ((fn (resolve pkg accessor-name)))
    (when (and fn (fboundp fn))
      (funcall fn obj))))

(defun thought-to-alist (thought)
  "Convert a thought object to a simple alist for Emacs."
  (list (cons :id (or (safe-slot thought "THOUGHT-ID" :autopoiesis.core) ""))
        (cons :type (let ((ty (safe-slot thought "THOUGHT-TYPE" :autopoiesis.core)))
                      (if ty (string-downcase (symbol-name ty)) "unknown")))
        (cons :content (or (safe-slot thought "THOUGHT-CONTENT" :autopoiesis.core) ""))
        (cons :timestamp (let ((ts (safe-slot thought "THOUGHT-TIMESTAMP" :autopoiesis.core)))
                           (if ts (princ-to-string ts) "")))))

(defun sym-downcase (sym)
  "Downcase a symbol name, or return the string as-is."
  (if (symbolp sym) (string-downcase (symbol-name sym)) (princ-to-string sym)))

(defun conductor-var ()
  "Return the current *conductor* value, or NIL."
  (let ((sym (resolve :autopoiesis.orchestration "*CONDUCTOR*")))
    (when (and sym (boundp sym))
      (symbol-value sym))))

;;; ═══════════════════════════════════════════════════════════════════
;;; System Lifecycle
;;; ═══════════════════════════════════════════════════════════════════

(defun system-status ()
  "Return system status as a plist."
  (let ((health (try-call :autopoiesis "HEALTH-CHECK"))
        (version (try-call :autopoiesis "VERSION"))
        (agents (ignore-errors (call-if-available :autopoiesis.agent "LIST-AGENTS")))
        (conductor (conductor-var)))
    (list :version version
          :health-status (getf health :status)
          :agent-count (if agents (length agents) 0)
          :conductor-running (and conductor
                                  (try-call :autopoiesis.orchestration
                                            "CONDUCTOR-RUNNING-P" conductor))
          :checks (getf health :checks)
          :active-sessions (hash-table-count *sly-chat-sessions*)
          :agentic-agents (hash-table-count *sly-agentic-agents*))))

(defun start-platform (&optional monitoring-port)
  "Start the full platform (substrate, conductor, monitoring).
Returns system status plist."
  (apply #'call-if-available :autopoiesis.orchestration "START-SYSTEM"
         (when monitoring-port (list :monitoring-port monitoring-port)))
  (system-status))

(defun stop-platform ()
  "Stop the full platform."
  (call-if-available :autopoiesis.orchestration "STOP-SYSTEM")
  ;; Clean up chat sessions
  (maphash (lambda (k session)
             (declare (ignore k))
             (ignore-errors
               (call-if-available :autopoiesis.jarvis "STOP-JARVIS" session)))
           *sly-chat-sessions*)
  (clrhash *sly-chat-sessions*)
  t)

;;; ═══════════════════════════════════════════════════════════════════
;;; Providers
;;; ═══════════════════════════════════════════════════════════════════

(defun list-providers ()
  "Return list of (name command alive-p) for registered providers."
  (let ((providers (try-call :autopoiesis.integration "LIST-PROVIDERS")))
    (mapcar (lambda (p)
              (list (or (safe-slot p "PROVIDER-NAME" :autopoiesis.integration) "unknown")
                    (or (safe-slot p "PROVIDER-COMMAND" :autopoiesis.integration) "")
                    (let ((fn (resolve :autopoiesis.integration "PROVIDER-ALIVE-P")))
                      (when (and fn (fboundp fn))
                        (ignore-errors (funcall fn p))))))
            (or providers nil))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent CRUD
;;; ═══════════════════════════════════════════════════════════════════

(defun list-agents ()
  "Return list of (id name state cap-count thought-count) for all agents."
  (let ((agents (call-if-available :autopoiesis.agent "LIST-AGENTS")))
    (mapcar (lambda (agent)
              (list (safe-slot agent "AGENT-ID")
                    (safe-slot agent "AGENT-NAME")
                    (let ((st (safe-slot agent "AGENT-STATE")))
                      (if st (sym-downcase st) "unknown"))
                    (length (or (safe-slot agent "AGENT-CAPABILITIES") nil))
                    (let ((stream (safe-slot agent "AGENT-THOUGHT-STREAM")))
                      (if stream
                          (or (try-call :autopoiesis.core "STREAM-LENGTH" stream) 0)
                          0))))
            agents)))

(defun get-agent (id-string)
  "Return full agent plist for agent ID-STRING."
  (let ((agent (call-if-available :autopoiesis.agent "FIND-AGENT" id-string)))
    (unless agent
      (error "No agent found with id ~a" id-string))
    (list :id (safe-slot agent "AGENT-ID")
          :name (safe-slot agent "AGENT-NAME")
          :state (let ((st (safe-slot agent "AGENT-STATE")))
                   (if st (sym-downcase st) "unknown"))
          :capabilities (mapcar #'sym-downcase
                                (or (safe-slot agent "AGENT-CAPABILITIES") nil))
          :parent (safe-slot agent "AGENT-PARENT")
          :children (safe-slot agent "AGENT-CHILDREN")
          :thought-count (let ((stream (safe-slot agent "AGENT-THOUGHT-STREAM")))
                           (if stream
                               (or (try-call :autopoiesis.core "STREAM-LENGTH" stream) 0)
                               0)))))

(defun create-agent (name &optional capabilities-list)
  "Create and register a new agent with NAME.
CAPABILITIES-LIST is a list of capability name strings.
Returns the new agent's ID."
  (let* ((cap-keywords (mapcar (lambda (s) (intern (string-upcase s) :keyword))
                               (or capabilities-list nil)))
         (agent (call-if-available :autopoiesis.agent "MAKE-AGENT"
                                   :name name :capabilities cap-keywords)))
    (call-if-available :autopoiesis.agent "REGISTER-AGENT" agent)
    (safe-slot agent "AGENT-ID")))

(defun set-agent-state (id-string state-string)
  "Set agent state. STATE-STRING: running, paused, or stopped."
  (let ((agent (call-if-available :autopoiesis.agent "FIND-AGENT" id-string)))
    (unless agent (error "No agent found with id ~a" id-string))
    (let ((fn-name (cond
                     ((string-equal state-string "running") "START-AGENT")
                     ((string-equal state-string "paused") "PAUSE-AGENT")
                     ((string-equal state-string "stopped") "STOP-AGENT")
                     (t (error "Invalid state: ~a. Use running, paused, or stopped." state-string)))))
      (call-if-available :autopoiesis.agent fn-name agent)
      t)))

(defun agent-thoughts (id-string &optional (limit 20))
  "Return last LIMIT thoughts for agent ID-STRING as alists."
  (let ((agent (call-if-available :autopoiesis.agent "FIND-AGENT" id-string)))
    (unless agent (error "No agent found with id ~a" id-string))
    (let ((stream (safe-slot agent "AGENT-THOUGHT-STREAM")))
      (when stream
        (let ((thoughts (call-if-available :autopoiesis.core "STREAM-LAST" stream limit)))
          (mapcar #'thought-to-alist thoughts))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Capabilities
;;; ═══════════════════════════════════════════════════════════════════

(defun list-capabilities ()
  "Return list of (name description) for registered capabilities."
  (let ((caps (call-if-available :autopoiesis.agent "LIST-CAPABILITIES")))
    (mapcar (lambda (c)
              (list (let ((name (safe-slot c "CAPABILITY-NAME")))
                      (if name (sym-downcase name) (princ-to-string c)))
                    (or (safe-slot c "CAPABILITY-DESCRIPTION") "")))
            caps)))

(defun invoke-capability (name-string &rest args)
  "Invoke capability NAME-STRING with ARGS. Returns result as string."
  (let ((kw (intern (string-upcase name-string) :keyword)))
    (princ-to-string (apply #'call-if-available :autopoiesis.agent
                            "INVOKE-CAPABILITY" kw args))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Chat (Jarvis bridge — provider-aware)
;;; ═══════════════════════════════════════════════════════════════════

(defun start-chat (session-name &optional provider-type model)
  "Start a Jarvis chat session named SESSION-NAME.
PROVIDER-TYPE is an optional string: rho, pi, claude-code, or a registered provider name.
MODEL is an optional model string.
Returns the session name on success."
  (when (gethash session-name *sly-chat-sessions*)
    (return-from start-chat session-name))
  (let ((session
          (cond
            ;; No provider — auto-detect
            ((null provider-type)
             (call-if-available :autopoiesis.jarvis "START-JARVIS"))
            ;; rho or pi — use provider-config plist
            ((member (string-downcase provider-type) '("rho" "pi") :test #'string=)
             (call-if-available :autopoiesis.jarvis "START-JARVIS"
                                :provider-config
                                (append (list :type (intern (string-upcase provider-type) :keyword))
                                        (when model (list :model model)))))
            ;; Other — look up in provider registry
            (t
             (let ((provider (try-call :autopoiesis.integration "FIND-PROVIDER" provider-type)))
               (if provider
                   (progn
                     (when model
                       (let ((fn (resolve :autopoiesis.integration "DEFAULT-MODEL")))
                         (when (and fn (fboundp `(setf ,fn)))
                           (ignore-errors (funcall (fdefinition `(setf ,fn)) model provider)))))
                     (call-if-available :autopoiesis.jarvis "START-JARVIS" :provider provider))
                   ;; Fall back to provider-config with the type
                   (call-if-available :autopoiesis.jarvis "START-JARVIS"
                                      :provider-config
                                      (append (list :type (intern (string-upcase provider-type) :keyword))
                                              (when model (list :model model))))))))))
    (setf (gethash session-name *sly-chat-sessions*) session)
    session-name))

(defun chat-prompt (session-name text)
  "Send TEXT to the Jarvis session named SESSION-NAME.
Returns the response text string."
  (let ((session (gethash session-name *sly-chat-sessions*)))
    (unless session
      (error "No chat session ~a. Call start-chat first." session-name))
    (call-if-available :autopoiesis.jarvis "JARVIS-PROMPT" session text)))

(defun stop-chat (session-name)
  "Stop the Jarvis chat session named SESSION-NAME."
  (let ((session (gethash session-name *sly-chat-sessions*)))
    (when session
      (ignore-errors
        (call-if-available :autopoiesis.jarvis "STOP-JARVIS" session))
      (remhash session-name *sly-chat-sessions*)))
  t)

;;; ═══════════════════════════════════════════════════════════════════
;;; Conductor / Orchestration
;;; ═══════════════════════════════════════════════════════════════════

(defun conductor-info ()
  "Return conductor status as a plist, or NIL if not running."
  (let ((c (conductor-var)))
    (when c
      (call-if-available :autopoiesis.orchestration "CONDUCTOR-STATUS" :conductor c))))

(defun start-conductor-rpc ()
  "Start the conductor tick loop. Returns T on success."
  (call-if-available :autopoiesis.orchestration "START-CONDUCTOR")
  t)

(defun stop-conductor-rpc ()
  "Stop the conductor tick loop. Returns T on success."
  (let ((c (conductor-var)))
    (when c
      (call-if-available :autopoiesis.orchestration "STOP-CONDUCTOR" :conductor c)))
  t)

(defun schedule-action-rpc (delay-seconds action-type &optional data-plist)
  "Schedule an action after DELAY-SECONDS.
ACTION-TYPE is a string like tick, claude.
DATA-PLIST is optional additional action data.
Returns the fire-time."
  (let ((c (conductor-var)))
    (unless c (error "Conductor is not running"))
    (let ((action (append (list :action-type (intern (string-upcase action-type) :keyword))
                          data-plist)))
      (call-if-available :autopoiesis.orchestration "SCHEDULE-ACTION"
                         c delay-seconds action))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agentic Loops
;;; ═══════════════════════════════════════════════════════════════════

(defun create-agentic-agent-rpc (name &key provider model system-prompt capabilities)
  "Create an agentic agent backed by a provider.
PROVIDER is a registered provider name string or NIL for default.
CAPABILITIES is a list of capability name strings.
Returns the new agent's ID."
  (let* ((cap-keywords (mapcar (lambda (s) (intern (string-upcase s) :keyword))
                               (or capabilities nil)))
         (provider-obj (when provider
                         (try-call :autopoiesis.integration "FIND-PROVIDER" provider)))
         (agent (call-if-available :autopoiesis.integration "MAKE-AGENTIC-AGENT"
                                   :name name
                                   :provider provider-obj
                                   :model model
                                   :system-prompt system-prompt
                                   :capabilities cap-keywords)))
    (call-if-available :autopoiesis.agent "REGISTER-AGENT" agent)
    (let ((id (safe-slot agent "AGENT-ID")))
      (setf (gethash id *sly-agentic-agents*) agent)
      id)))

(defun agentic-prompt (agent-id prompt-text)
  "Send PROMPT-TEXT to agentic agent AGENT-ID. Returns response string."
  (let ((agent (or (gethash agent-id *sly-agentic-agents*)
                   (call-if-available :autopoiesis.agent "FIND-AGENT" agent-id))))
    (unless agent (error "No agentic agent with id ~a" agent-id))
    (call-if-available :autopoiesis.integration "AGENTIC-AGENT-PROMPT"
                       agent prompt-text)))

(defun list-agentic-agents ()
  "Return list of (id name) for tracked agentic agents."
  (let (result)
    (maphash (lambda (id agent)
               (push (list id (or (safe-slot agent "AGENT-NAME") "unnamed")) result))
             *sly-agentic-agents*)
    (nreverse result)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Teams
;;; ═══════════════════════════════════════════════════════════════════

(defun list-teams ()
  "Return list of (id status strategy member-count task) for all teams."
  (let ((teams (try-call :autopoiesis.team "LIST-TEAMS")))
    (mapcar (lambda (team)
              (list (safe-slot team "TEAM-ID" :autopoiesis.team)
                    (let ((st (safe-slot team "TEAM-STATUS" :autopoiesis.team)))
                      (if st (sym-downcase st) "unknown"))
                    (let ((strat (safe-slot team "TEAM-STRATEGY" :autopoiesis.team)))
                      (if strat (sym-downcase (type-of strat)) "none"))
                    (length (or (safe-slot team "TEAM-MEMBERS" :autopoiesis.team) nil))
                    (or (safe-slot team "TEAM-TASK" :autopoiesis.team) "")))
            (or teams nil))))

(defun create-team-rpc (name strategy-type &key task members leader)
  "Create a team with NAME using STRATEGY-TYPE.
STRATEGY-TYPE: leader-worker, parallel, pipeline, debate, consensus,
  hierarchical-leader-worker, leader-parallel, rotating-leader, debate-consensus.
MEMBERS is a list of agent ID strings.
Returns the team ID."
  (let* ((strat-kw (intern (string-upcase strategy-type) :keyword))
         (team (call-if-available :autopoiesis.team "CREATE-TEAM" name
                                  :strategy strat-kw
                                  :task task
                                  :members members
                                  :leader leader)))
    (safe-slot team "TEAM-ID" :autopoiesis.team)))

(defun start-team-rpc (team-id)
  "Start the team TEAM-ID. Returns T."
  (let ((team (call-if-available :autopoiesis.team "FIND-TEAM" team-id)))
    (unless team (error "No team with id ~a" team-id))
    (call-if-available :autopoiesis.team "START-TEAM" team)
    t))

(defun query-team (team-id)
  "Return team status plist for TEAM-ID."
  (let ((team (call-if-available :autopoiesis.team "FIND-TEAM" team-id)))
    (unless team (error "No team with id ~a" team-id))
    (call-if-available :autopoiesis.team "QUERY-TEAM-STATUS" team)))

(defun disband-team-rpc (team-id)
  "Disband the team TEAM-ID. Returns T."
  (let ((team (call-if-available :autopoiesis.team "FIND-TEAM" team-id)))
    (unless team (error "No team with id ~a" team-id))
    (call-if-available :autopoiesis.team "DISBAND-TEAM" team)
    t))

;;; ═══════════════════════════════════════════════════════════════════
;;; Swarm Evolution
;;; ═══════════════════════════════════════════════════════════════════

(defun start-evolution (agent-ids &key (generations 10) (mutation-rate 0.1)
                                       (elite-count 2) (tournament-size 3))
  "Evolve agents by AGENT-IDS (list of ID strings).
Returns list of (name fitness cap-count) for the evolved population."
  (let* ((agents (mapcar (lambda (id)
                           (or (call-if-available :autopoiesis.agent "FIND-AGENT" id)
                               (error "No agent with id ~a" id)))
                         agent-ids))
         ;; Convert mutable agents to persistent agents
         (persistent (mapcar (lambda (a)
                               (let ((fn (resolve :autopoiesis.agent "AGENT-TO-PERSISTENT")))
                                 (if (and fn (fboundp fn))
                                     (funcall fn a)
                                     (call-if-available :autopoiesis.agent "MAKE-PERSISTENT-AGENT"
                                                        :name (safe-slot a "AGENT-NAME")
                                                        :capabilities (safe-slot a "AGENT-CAPABILITIES")))))
                             agents))
         (evaluator (call-if-available :autopoiesis.swarm "MAKE-STANDARD-PA-EVALUATOR"))
         (evolved (call-if-available :autopoiesis.swarm "EVOLVE-PERSISTENT-AGENTS"
                                     persistent evaluator nil
                                     :generations generations
                                     :mutation-rate mutation-rate
                                     :elite-count elite-count
                                     :tournament-size tournament-size)))
    (mapcar (lambda (pa)
              (let* ((name (safe-slot pa "PERSISTENT-AGENT-NAME" :autopoiesis.agent))
                     (caps (safe-slot pa "PERSISTENT-AGENT-CAPABILITIES" :autopoiesis.agent))
                     (cap-count (let ((fn (resolve :autopoiesis.core "PSET-COUNT")))
                                  (if (and fn (fboundp fn) caps)
                                      (ignore-errors (funcall fn caps))
                                      0)))
                     (genome-fn (resolve :autopoiesis.swarm "PERSISTENT-AGENT-TO-GENOME"))
                     (fitness (when (and genome-fn (fboundp genome-fn))
                                (let ((g (ignore-errors (funcall genome-fn pa))))
                                  (when g
                                    (safe-slot g "GENOME-FITNESS" :autopoiesis.swarm))))))
                (list (or name "evolved")
                      (or fitness 0.0)
                      (or cap-count 0))))
            evolved)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshots
;;; ═══════════════════════════════════════════════════════════════════

(defun list-snapshots (&optional (limit 20))
  "Return up to LIMIT snapshot ID strings."
  (let ((ids (call-if-available :autopoiesis.snapshot "LIST-SNAPSHOTS")))
    (if (> (length ids) limit)
        (subseq ids 0 limit)
        ids)))

(defun list-branches ()
  "Return list of (name head-id) for all branches."
  (let ((branches (call-if-available :autopoiesis.snapshot "LIST-BRANCHES")))
    (mapcar (lambda (b)
              (list (safe-slot b "BRANCH-NAME" :autopoiesis.snapshot)
                    (safe-slot b "BRANCH-HEAD" :autopoiesis.snapshot)))
            branches)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Events
;;; ═══════════════════════════════════════════════════════════════════

(defun recent-events (&optional (limit 50))
  "Return last LIMIT integration events as alists."
  (let ((events (try-call :autopoiesis.integration "GET-EVENT-HISTORY" :limit limit)))
    (mapcar (lambda (ev)
              (list (cons :type (let ((ty (safe-slot ev "INTEGRATION-EVENT-KIND"
                                                    :autopoiesis.integration)))
                                  (if ty (sym-downcase ty) "unknown")))
                    (cons :source (or (safe-slot ev "INTEGRATION-EVENT-SOURCE"
                                                :autopoiesis.integration) ""))
                    (cons :agent-id (or (safe-slot ev "INTEGRATION-EVENT-AGENT-ID"
                                                  :autopoiesis.integration) ""))
                    (cons :timestamp (let ((ts (safe-slot ev "INTEGRATION-EVENT-TIMESTAMP"
                                                         :autopoiesis.integration)))
                                      (if ts (princ-to-string ts) "")))))
            (or events nil))))

(defun event-stats ()
  "Return event count statistics as a plist."
  (list :total (or (try-call :autopoiesis.integration "COUNT-EVENTS") 0)
        :tool-calls (or (try-call :autopoiesis.integration "COUNT-EVENTS"
                                  :type :tool-called) 0)
        :claude-requests (or (try-call :autopoiesis.integration "COUNT-EVENTS"
                                       :type :claude-request) 0)
        :provider-requests (or (try-call :autopoiesis.integration "COUNT-EVENTS"
                                         :type :provider-request) 0)))

(provide :slynk-autopoiesis)
