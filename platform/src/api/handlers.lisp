;;;; handlers.lisp - WebSocket message handlers
;;;;
;;;; Maps incoming JSON message types to autopoiesis operations.
;;;; Each handler receives a decoded message hash-table and connection,
;;;; and returns a response hash-table (or nil for no response).
;;;;
;;;; Client requests always arrive as JSON text frames.
;;;; Direct responses always go back as JSON text frames.
;;;; Push notifications (events, thought updates, state changes) go
;;;; as binary (MessagePack) or JSON depending on connection preference.

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Encoding/Decoding (for request/response - always JSON)
;;; ═══════════════════════════════════════════════════════════════════

(defun decode-message (json-string)
  "Decode a JSON message string to a hash table."
  (decode-json json-string))

(defun encode-message (data)
  "Encode data as a JSON string (for control responses)."
  (encode-control data))

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Dispatch
;;; ═══════════════════════════════════════════════════════════════════

(defun handle-message (connection json-string)
  "Dispatch an incoming WebSocket message to the appropriate handler.

   Returns the response JSON string to send back, or NIL."
  (let ((msg (decode-message json-string)))
    (unless msg
      (return-from handle-message
        (encode-message (error-response "invalid_json" "Failed to parse message"))))
    (let* ((msg-type (gethash "type" msg))
           (request-id (gethash "requestId" msg)))
      (unless msg-type
        (return-from handle-message
          (encode-message (error-response "missing_type" "Message must have a 'type' field"
                                          :request-id request-id))))
      (log:debug "API message: ~a from ~a" msg-type (connection-id connection))
      (handler-case
          (let ((result (dispatch-message msg-type msg connection)))
            (when result
              ;; Attach requestId for client-side correlation
              (when request-id
                (setf (gethash "requestId" result) request-id))
              (encode-message result)))
        (autopoiesis.core:autopoiesis-error (e)
          (encode-message (error-response "autopoiesis_error"
                                          (format nil "~a" e)
                                          :request-id request-id)))
        (error (e)
          (log:error "Handler error for ~a: ~a" msg-type e)
          (encode-message (error-response "internal_error"
                                          "An internal error occurred"
                                          :request-id request-id)))))))

(defun dispatch-message (msg-type msg connection)
  "Route a message to the correct handler based on type."
  (let ((handler (gethash msg-type *message-handlers*)))
    (if handler
        (funcall handler msg connection)
        (error-response "unknown_type"
                        (format nil "Unknown message type: ~a" msg-type)))))

(defun error-response (code message &key request-id)
  "Create a standard error response."
  (let ((resp (make-hash-table :test 'equal)))
    (setf (gethash "type" resp) "error"
          (gethash "code" resp) code
          (gethash "message" resp) message)
    (when request-id
      (setf (gethash "requestId" resp) request-id))
    resp))

(defun ok-response (type &rest pairs)
  "Create a standard success response hash table.
   TYPE is the response type string.
   PAIRS are alternating key-value pairs to include."
  (let ((resp (make-hash-table :test 'equal)))
    (setf (gethash "type" resp) type)
    (loop for (key val) on pairs by #'cddr
          do (setf (gethash key resp) val))
    resp))

;;; ═══════════════════════════════════════════════════════════════════
;;; Handler Registry
;;; ═══════════════════════════════════════════════════════════════════

(defvar *message-handlers* (make-hash-table :test 'equal)
  "Map from message type string to handler function.")

(defmacro define-handler (name msg-type (msg-var conn-var) &body body)
  "Define a message handler for MSG-TYPE."
  `(progn
     (defun ,name (,msg-var ,conn-var)
       ,@body)
     (setf (gethash ,msg-type *message-handlers*) #',name)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-list-agents "list_agents" (msg conn)
  (declare (ignore msg conn))
  (let ((agents (list-agents)))
    (ok-response "agents"
                 "agents" (mapcar #'agent-to-json-plist agents))))

(define-handler handle-get-agent "get_agent" (msg conn)
  (declare (ignore conn))
  (let ((agent-id (gethash "agentId" msg)))
    (unless agent-id
      (return-from handle-get-agent
        (error-response "missing_field" "get_agent requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (if agent
          (ok-response "agent" "agent" (agent-to-json-plist agent))
          (error-response "not_found"
                          (format nil "Agent not found: ~a" agent-id))))))

(define-handler handle-create-agent "create_agent" (msg conn)
  (let* ((name (or (gethash "name" msg) "unnamed"))
         (task (gethash "task" msg))
         (raw-caps (gethash "capabilities" msg))
         (caps-list (etypecase raw-caps
                      (null nil)
                      (list raw-caps)
                      (vector (coerce raw-caps 'list))))
         (capabilities (mapcar (lambda (c)
                                 (intern (string-upcase c) :keyword))
                               caps-list))
         (agent (make-agent :name name :capabilities capabilities)))
    (register-agent agent)
    ;; Auto-snapshot agent creation
    (ignore-errors (auto-snapshot-agent agent "created"))
    ;; If task provided, auto-start the agent and send the task
    (when (and task (stringp task) (> (length task) 0))
      (runtime-start-agent agent)
      ;; Subscribe the creating connection to this agent's updates
      (subscribe-connection conn (format nil "agent:~a" (agent-id agent)))
      ;; Send task to agent's mailbox after a brief delay for runtime init
      (let ((agent-id (agent-id agent)))
        (bordeaux-threads:make-thread
         (lambda ()
           (sleep 0.5)  ; Allow runtime thread to start
           (ignore-errors (send-message-to-agent agent-id task :from "user")))
         :name (format nil "task-sender-~a" name))))
    ;; Broadcast to agent subscribers (binary stream)
    (broadcast-stream-data (ok-response "agent_created"
                                   "agent" (agent-to-json-plist agent))
                      :subscription-type "agents")
    (ok-response "agent_created"
                 "agent" (agent-to-json-plist agent))))

(define-handler handle-agent-action "agent_action" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (action (gethash "action" msg)))
    (unless agent-id
      (return-from handle-agent-action
        (error-response "missing_field" "agent_action requires 'agentId'")))
    (unless action
      (return-from handle-agent-action
        (error-response "missing_field" "agent_action requires 'action'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-agent-action
          (error-response "not_found"
                          (format nil "Agent not found: ~a" agent-id))))
      (let ((result (cond
                      ((equal action "start") (runtime-start-agent agent))
                      ((equal action "stop") (runtime-stop-agent agent))
                      ((equal action "pause") (runtime-pause-agent agent))
                      ((equal action "resume") (runtime-resume-agent agent))
                      (t (return-from handle-agent-action
                           (error-response "invalid_action"
                                           (format nil "Unknown action: ~a" action)))))))
        (declare (ignore result))
        ;; Broadcast state change (binary stream)
        (broadcast-stream-data (ok-response "agent_state_changed"
                                       "agentId" agent-id
                                       "state" (string-downcase
                                                (symbol-name (agent-state agent))))
                          :subscription-type "agents")
        (ok-response "agent_state_changed"
                     "agentId" agent-id
                     "state" (string-downcase
                              (symbol-name (agent-state agent))))))))

(define-handler handle-step-agent "step_agent" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg)))
    (unless agent-id
      (return-from handle-step-agent
        (error-response "missing_field" "step_agent requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-step-agent
          (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
      ;; Execute one cognitive cycle
      (let ((env (or (gethash "environment" msg) nil)))
        (cognitive-cycle agent env)
        (ok-response "step_complete"
                     "agentId" agent-id
                     "thoughtCount" (stream-length (agent-thought-stream agent)))))))

(define-handler handle-fork-agent "fork_agent" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (name (gethash "name" msg)))
    (unless agent-id
      (return-from handle-fork-agent
        (error-response "missing_field" "fork_agent requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-fork-agent
          (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
      ;; Check if it's a dual agent with persistent root
      (unless (and (typep agent 'autopoiesis.agent:dual-agent)
                   (autopoiesis.agent:dual-agent-root agent))
        (return-from handle-fork-agent
          (error-response "not_supported" "Agent must be upgraded to dual-agent first")))
      (multiple-value-bind (child updated-parent)
          (autopoiesis.agent:persistent-fork (autopoiesis.agent:dual-agent-root agent)
                                           :name name)
        ;; Update the agent's persistent root
        (setf (autopoiesis.agent:dual-agent-root agent) updated-parent)
        ;; Register the child as a new dual-agent
        (let ((child-agent (autopoiesis.agent:make-agent
                            :name (autopoiesis.agent:persistent-agent-name child))))
          (autopoiesis.agent:upgrade-to-dual child-agent)
          (setf (autopoiesis.agent:dual-agent-root child-agent) child)
          (autopoiesis.agent:register-agent child-agent))
        (ok-response "agent_forked"
                     "parentId" agent-id
                     "childId" (autopoiesis.agent:persistent-agent-id child))))))

(define-handler handle-upgrade-to-dual "upgrade_to_dual" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg)))
    (unless agent-id
      (return-from handle-upgrade-to-dual
        (error-response "missing_field" "upgrade_to_dual requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-upgrade-to-dual
          (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
      (if (typep agent 'autopoiesis.agent:dual-agent)
          (ok-response "already_dual"
                       "agentId" agent-id
                       "message" "Agent is already a dual-agent")
          (let ((dual-agent (autopoiesis.agent:upgrade-to-dual agent)))
            ;; Replace the agent in the registry
            (autopoiesis.agent:unregister-agent agent)
            (autopoiesis.agent:register-agent dual-agent)
            (ok-response "agent_upgraded"
                         "agentId" agent-id
                         "type" "dual-agent"))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Agent Scheduling Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-schedule-agent-task "schedule_agent_task" (msg conn)
  "Schedule a one-shot or recurring task for an agent.
   msg: { agentId, message, delaySeconds, recurring, intervalSeconds }"
  (declare (ignore conn))
  (let ((agent-id (gethash "agentId" msg))
        (message (gethash "message" msg))
        (delay (or (gethash "delaySeconds" msg) 0))
        (recurring (gethash "recurring" msg))
        (interval (gethash "intervalSeconds" msg)))
    (unless agent-id
      (return-from handle-schedule-agent-task
        (error-response "missing_field" "schedule_agent_task requires 'agentId'")))
    (unless message
      (return-from handle-schedule-agent-task
        (error-response "missing_field" "schedule_agent_task requires 'message'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-schedule-agent-task
          (error-response "not_found"
                          (format nil "Agent not found: ~a" agent-id)))))
    (let ((conductor autopoiesis.orchestration:*conductor*))
      (unless conductor
        (return-from handle-schedule-agent-task
          (error-response "conductor_unavailable" "Conductor is not running")))
      (autopoiesis.orchestration:schedule-action conductor delay
        (list :action-type :agent-wakeup
              :agent-id agent-id
              :message message
              :recurring (and recurring (not (eq recurring :false)))
              :interval (when (and recurring (not (eq recurring :false)))
                          (or interval 30))))
      (ok-response "task_scheduled"
                   "agentId" agent-id
                   "message" message
                   "delaySeconds" delay
                   "recurring" (if (and recurring (not (eq recurring :false))) t :false)
                   "intervalSeconds" (when (and recurring (not (eq recurring :false)))
                                      (or interval 30))))))

(define-handler handle-agent-continuation "agent_request_continuation" (msg conn)
  "Request a continuation for an agent (agent does another cycle)."
  (declare (ignore conn))
  (let ((agent-id (gethash "agentId" msg))
        (message (or (gethash "message" msg) "Continue working")))
    (unless agent-id
      (return-from handle-agent-continuation
        (error-response "missing_field" "agent_request_continuation requires 'agentId'")))
    (agent-request-continuation agent-id message)
    (ok-response "continuation_queued" "agentId" agent-id)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-get-thoughts "get_thoughts" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (limit (min (or (gethash "limit" msg) 50) 1000)))
    (unless agent-id
      (return-from handle-get-thoughts
        (error-response "missing_field" "get_thoughts requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-get-thoughts
          (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
      (let ((thoughts (stream-last (agent-thought-stream agent) limit)))
        (ok-response "thoughts"
                     "agentId" agent-id
                     "thoughts" (mapcar #'thought-to-json-plist thoughts)
                     "total" (stream-length (agent-thought-stream agent)))))))

(define-handler handle-inject-thought "inject_thought" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (content (gethash "content" msg))
         (thought-type (or (gethash "thoughtType" msg) "observation")))
    (unless agent-id
      (return-from handle-inject-thought
        (error-response "missing_field" "inject_thought requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-inject-thought
          (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
      (unless content
        (return-from handle-inject-thought
          (error-response "missing_field" "inject_thought requires 'content'")))
      (let ((thought (cond
                       ((equal thought-type "observation")
                        (make-observation content :source :api))
                       ((equal thought-type "reflection")
                        (make-reflection nil content))
                       ((member thought-type '("decision" "action") :test #'equal)
                        (make-thought content
                                      :type (find-symbol (string-upcase thought-type) :keyword)))
                       (t
                        (return-from handle-inject-thought
                          (error-response "invalid_type"
                                          (format nil "Unknown thought type: ~a. Valid: observation, reflection, decision, action" thought-type)))))))
        (let ((recorded-thought (stream-append (agent-thought-stream agent) thought)))
          ;; Emit integration event for SSE broadcasting
          (autopoiesis.integration:emit-integration-event
           :thought-recorded :api
           `((:agent-id . ,agent-id)
             (:thought . ,(autopoiesis.core:thought-to-sexpr recorded-thought)))
           :agent-id agent-id))
        (let ((thought-json (thought-to-json-plist thought)))
          ;; Push to thought subscribers (binary stream)
          (broadcast-to-agent-subscribers
           agent-id
           (ok-response "thought_added"
                        "agentId" agent-id
                        "thought" thought-json))
          (ok-response "thought_added"
                       "agentId" agent-id
                       "thought" thought-json))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Snapshot Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-list-snapshots "list_snapshots" (msg conn)
  (declare (ignore conn))
  (let* ((limit (or (gethash "limit" msg) 50))
         (parent-id (gethash "parentId" msg))
         (snapshots (if *snapshot-store*
                        (list-snapshots :parent-id parent-id
                                        :store *snapshot-store*)
                        nil)))
    (ok-response "snapshots"
                 "snapshots" (mapcar #'snapshot-to-json-plist
                                     (if (> (length snapshots) limit)
                                         (subseq snapshots 0 limit)
                                         snapshots))
                 "total" (length snapshots))))

(define-handler handle-get-snapshot "get_snapshot" (msg conn)
  (declare (ignore conn))
  (let* ((snapshot-id (gethash "snapshotId" msg))
         (snapshot (when *snapshot-store*
                     (load-snapshot snapshot-id *snapshot-store*))))
    (if snapshot
        (ok-response "snapshot"
                     "snapshot" (snapshot-to-json-plist snapshot)
                     "agentState" (format nil "~S" (snapshot-agent-state snapshot)))
        (error-response "not_found"
                        (format nil "Snapshot not found: ~a" snapshot-id)))))

(define-handler handle-create-snapshot "create_snapshot" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (label (gethash "label" msg)))
    (unless agent-id
      (return-from handle-create-snapshot
        (error-response "missing_field" "create_snapshot requires 'agentId'")))
    (let ((agent (find-agent agent-id)))
      (unless agent
        (return-from handle-create-snapshot
          (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
      ;; Serialize agent state and create snapshot
      (let* ((state (list :agent-id (agent-id agent)
                          :agent-name (agent-name agent)
                          :agent-state (agent-state agent)
                          :thought-count (stream-length (agent-thought-stream agent))
                          :capabilities (agent-capabilities agent)))
             (parent-id (when *snapshot-store*
                          (autopoiesis.snapshot:find-latest-snapshot-for-agent
                           agent-id *snapshot-store*)))
             (metadata (when label (list :label label)))
             (snapshot (make-snapshot state :parent parent-id :metadata metadata)))
        (when *snapshot-store*
          (save-snapshot snapshot *snapshot-store*))
        (ok-response "snapshot_created"
                     "snapshot" (snapshot-to-json-plist snapshot))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Branch Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-list-branches "list_branches" (msg conn)
  (declare (ignore msg conn))
  (ok-response "branches"
               "branches" (mapcar #'branch-to-json-plist (list-branches))
               "current" (when (current-branch)
                           (branch-name (current-branch)))))

(define-handler handle-create-branch "create_branch" (msg conn)
  (declare (ignore conn))
  (let* ((name (gethash "name" msg))
         (from-snapshot (gethash "fromSnapshot" msg)))
    (unless name
      (return-from handle-create-branch
        (error-response "missing_field" "create_branch requires 'name'")))
    (let ((branch (create-branch name :from-snapshot from-snapshot)))
      (ok-response "branch_created"
                   "branch" (branch-to-json-plist branch)))))

(define-handler handle-switch-branch "switch_branch" (msg conn)
  (declare (ignore conn))
  (let* ((name (gethash "name" msg)))
    (unless name
      (return-from handle-switch-branch
        (error-response "missing_field" "switch_branch requires 'name'")))
    (let ((branch (switch-branch name)))
      (ok-response "branch_switched"
                   "branch" (branch-to-json-plist branch)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Blocking Request Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-list-blocking "list_blocking_requests" (msg conn)
  (declare (ignore msg conn))
  (let ((requests (list-pending-blocking-requests)))
    (ok-response "blocking_requests"
                 "requests" (mapcar #'blocking-request-to-json-plist requests))))

(define-handler handle-respond-blocking "respond_blocking" (msg conn)
  (declare (ignore conn))
  ;; Use "blockingRequestId" to avoid collision with the protocol-level "requestId"
  (let* ((blocking-id (or (gethash "blockingRequestId" msg)
                          (gethash "requestId" msg)))  ; fallback for backwards compat
         (response (gethash "response" msg)))
    (unless blocking-id
      (return-from handle-respond-blocking
        (error-response "missing_field" "respond_blocking requires 'blockingRequestId'")))
    (multiple-value-bind (ok request)
        (respond-to-request blocking-id response)
      (declare (ignore request))
      (if ok
          (ok-response "blocking_responded"
                       "blockingRequestId" blocking-id
                       "status" "responded")
          (error-response "not_found"
                          (format nil "Blocking request not found: ~a" blocking-id))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Subscription Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-set-stream-format "set_stream_format" (msg conn)
  "Let a client switch between :msgpack (compact) and :json (debug-friendly)
for data stream messages. Control messages are always JSON."
  (let ((format (gethash "format" msg)))
    (cond
      ((equal format "msgpack")
       (setf (connection-stream-format conn) :msgpack)
       (ok-response "stream_format_set" "format" "msgpack"))
      ((equal format "json")
       (setf (connection-stream-format conn) :json)
       (ok-response "stream_format_set" "format" "json"))
      (t
       (error-response "invalid_format"
                       "format must be \"msgpack\" or \"json\"")))))

(define-handler handle-subscribe "subscribe" (msg conn)
  (let ((channel (gethash "channel" msg)))
    (unless channel
      (return-from handle-subscribe
        (error-response "missing_field" "subscribe requires 'channel'")))
    (subscribe-connection conn channel)
    (ok-response "subscribed" "channel" channel)))

(define-handler handle-unsubscribe "unsubscribe" (msg conn)
  (let ((channel (gethash "channel" msg)))
    (unless channel
      (return-from handle-unsubscribe
        (error-response "missing_field" "unsubscribe requires 'channel'")))
    (unsubscribe-connection conn channel)
    (ok-response "unsubscribed" "channel" channel)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Event History Handler
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-get-events "get_events" (msg conn)
  (declare (ignore conn))
  (let* ((limit (min (or (gethash "limit" msg) 50) 1000))
         (event-type (when (gethash "eventType" msg)
                       (let ((sym (find-symbol (string-upcase (gethash "eventType" msg)) :keyword)))
                         (unless sym
                           (return-from handle-get-events
                             (error-response "invalid_type"
                                             (format nil "Unknown event type: ~a" (gethash "eventType" msg)))))
                         sym)))
         (agent-id (gethash "agentId" msg))
         (events (get-event-history :limit limit
                                    :type event-type
                                    :agent-id agent-id)))
    (ok-response "events"
                 "events" (mapcar #'event-to-json-plist events)
                 "count" (length events))))

;;; ═══════════════════════════════════════════════════════════════════
;;; System Handlers
;;; ═══════════════════════════════════════════════════════════════════

;;; ═══════════════════════════════════════════════════════════════════
;;; Activity & Cost Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-get-activities "get_activities" (msg conn)
  "Return current activity data for all agents."
  (declare (ignore msg conn))
  (let ((activities (mapcar (lambda (agent)
                              (let* ((id (agent-id agent))
                                     (name (agent-name agent))
                                     (ht (make-hash-table :test 'equal)))
                                (setf (gethash "agentId" ht) id
                                      (gethash "agentName" ht) name
                                      (gethash "state" ht) (string-downcase
                                                             (symbol-name (agent-state agent))))
                                ;; Merge activity data
                                (let ((plist (activity-to-json-plist id)))
                                  (loop for (k v) on plist by #'cddr
                                        do (setf (gethash k ht) v)))
                                ht))
                            (list-agents))))
    (ok-response "activities" "activities" activities)))

;;; ═══════════════════════════════════════════════════════════════════
;;; System Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-ping "ping" (msg conn)
  (declare (ignore msg conn))
  (ok-response "pong"))

(define-handler handle-system-info "system_info" (msg conn)
  (declare (ignore msg conn))
  (let ((health (autopoiesis:health-check)))
    (ok-response "system_info"
                 "version" (autopoiesis:version)
                 "health" (getf health :status)
                 "agentCount" (length (list-agents))
                 "connectionCount" (connection-count))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Conductor Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-conductor-status "conductor_status" (msg conn)
  (declare (ignore msg conn))
  (let ((status (autopoiesis.orchestration:conductor-status)))
    (ok-response "conductor_status"
                 "running" (if (getf status :running) t :false)
                 "tickCount" (or (getf status :tick-count) 0)
                 "eventsProcessed" (or (getf status :events-processed) 0)
                 "eventsFailed" (or (getf status :events-failed) 0)
                 "timerErrors" (or (getf status :timer-errors) 0)
                 "tickErrors" (or (getf status :tick-errors) 0)
                 "taskRetries" (or (getf status :task-retries) 0)
                 "pendingTimers" (or (getf status :pending-timers) 0)
                 "activeWorkers" (or (getf status :active-workers) 0)
                 "triggersChecked" (getf status :triggers-checked)
                 "crystallizations" (getf status :crystallizations-performed))))

(define-handler handle-conductor-start "conductor_start" (msg conn)
  (declare (ignore msg conn))
  (handler-case
      (progn
        (autopoiesis.orchestration:start-conductor)
        (ok-response "conductor_started" "running" t))
    (error (e)
      (error-response "conductor_error" (format nil "~a" e)))))

(define-handler handle-conductor-stop "conductor_stop" (msg conn)
  (declare (ignore msg conn))
  (handler-case
      (progn
        (autopoiesis.orchestration:stop-conductor)
        (ok-response "conductor_stopped" "running" :false))
    (error (e)
      (error-response "conductor_error" (format nil "~a" e)))))

(define-handler handle-subscribe-conductor "subscribe_conductor" (msg conn)
  (declare (ignore msg))
  (subscribe-connection conn "conductor")
  (ok-response "subscribed" "channel" "conductor"))

(define-handler handle-subscribe-snapshots "subscribe_snapshots" (msg conn)
  "Subscribe to snapshot creation events for DAG updates."
  (declare (ignore msg))
  (subscribe-connection conn "snapshots")
  (ok-response "subscribed" "channel" "snapshots"))

;;; ═══════════════════════════════════════════════════════════════════
;;; Holodeck Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-holodeck-subscribe "holodeck_subscribe" (msg conn)
  "Subscribe connection to holodeck frame stream."
  (declare (ignore msg))
  (subscribe-connection conn "holodeck")
  (ok-response "subscribed" "channel" "holodeck"))

(define-handler handle-holodeck-unsubscribe "holodeck_unsubscribe" (msg conn)
  "Unsubscribe connection from holodeck frame stream."
  (declare (ignore msg))
  (unsubscribe-connection conn "holodeck")
  (ok-response "unsubscribed" "channel" "holodeck"))

(define-handler handle-holodeck-input "holodeck_input" (msg conn)
  "Forward keyboard/mouse input events to holodeck."
  (declare (ignore conn))
  (unless (holodeck-available-p)
    (return-from handle-holodeck-input
      (error-response "holodeck_unavailable" "Holodeck is not loaded or running")))
  (let ((action-name (gethash "action" msg))
        (key (gethash "key" msg)))
    (cond
      (action-name
       (let ((action-kw (find-symbol (string-upcase action-name) :keyword)))
         (unless action-kw
           (return-from handle-holodeck-input
             (error-response "invalid_action"
                             (format nil "Unknown action: ~a" action-name))))
         (if (holodeck-execute-action action-kw)
             (ok-response "holodeck_input_accepted" "action" action-name)
             (error-response "action_failed"
                             (format nil "Action handler not found: ~a" action-name)))))
      (key
       (let ((press-fn (find-symbol "HANDLE-KEY-PRESS" :autopoiesis.holodeck))
             (holodeck-val (holodeck-available-p)))
         (if (and press-fn (fboundp press-fn) holodeck-val)
             (let ((handler-fn (find-symbol "HOLODECK-KEYBOARD-HANDLER"
                                            :autopoiesis.holodeck)))
               (if (and handler-fn (fboundp handler-fn))
                   (let ((input-handler (funcall handler-fn holodeck-val)))
                     (when input-handler
                       (let ((key-sym (find-symbol (string-upcase key) :keyword)))
                         (when key-sym
                           (funcall press-fn input-handler key-sym))))
                     (ok-response "holodeck_input_accepted" "key" key))
                   (error-response "holodeck_error" "Input handler not available")))
             (error-response "holodeck_error" "Key press handler not available"))))
      (t
       (error-response "missing_field"
                       "holodeck_input requires 'action' or 'key'")))))

(define-handler handle-holodeck-camera "holodeck_camera" (msg conn)
  "Handle camera commands: orbit-left, orbit-right, zoom-in, zoom-out, reset-view."
  (declare (ignore conn))
  (unless (holodeck-available-p)
    (return-from handle-holodeck-camera
      (error-response "holodeck_unavailable" "Holodeck is not loaded or running")))
  (let ((command (gethash "command" msg)))
    (unless command
      (return-from handle-holodeck-camera
        (error-response "missing_field" "holodeck_camera requires 'command'")))
    (let ((action-kw (find-symbol (string-upcase command) :keyword)))
      (unless action-kw
        (return-from handle-holodeck-camera
          (error-response "invalid_command"
                          (format nil "Unknown camera command: ~a" command))))
      (if (holodeck-execute-action action-kw)
          (ok-response "holodeck_camera_done" "command" command)
          (error-response "command_failed"
                          (format nil "Camera command handler not found: ~a" command))))))

(define-handler handle-holodeck-select "holodeck_select" (msg conn)
  "Select an entity in the holodeck by ID."
  (declare (ignore conn))
  (unless (holodeck-available-p)
    (return-from handle-holodeck-select
      (error-response "holodeck_unavailable" "Holodeck is not loaded or running")))
  (let ((entity-id (gethash "entityId" msg)))
    (unless entity-id
      (return-from handle-holodeck-select
        (error-response "missing_field" "holodeck_select requires 'entityId'")))
    (let ((select-fn (find-symbol "SELECT-ENTITY" :autopoiesis.holodeck)))
      (if (and select-fn (fboundp select-fn))
          (handler-case
              (progn
                (funcall select-fn entity-id)
                (ok-response "holodeck_selected" "entityId" entity-id))
            (error (e)
              (error-response "select_failed"
                              (format nil "Failed to select entity: ~a" e))))
          (error-response "holodeck_error" "Entity selection not available")))))

(define-handler handle-holodeck-action "holodeck_action" (msg conn)
  "Perform agent operations on a selected entity in the holodeck."
  (declare (ignore conn))
  (unless (holodeck-available-p)
    (return-from handle-holodeck-action
      (error-response "holodeck_unavailable" "Holodeck is not loaded or running")))
  (let ((action (gethash "action" msg))
        (entity-id (gethash "entityId" msg)))
    (unless action
      (return-from handle-holodeck-action
        (error-response "missing_field" "holodeck_action requires 'action'")))
    (let ((action-kw (find-symbol (string-upcase action) :keyword)))
      (unless action-kw
        (return-from handle-holodeck-action
          (error-response "invalid_action"
                          (format nil "Unknown holodeck action: ~a" action))))
      (let ((entity-action-fn (find-symbol "ENTITY-ACTION" :autopoiesis.holodeck)))
        (if (and entity-action-fn (fboundp entity-action-fn))
            (handler-case
                (progn
                  (funcall entity-action-fn entity-id action-kw)
                  (ok-response "holodeck_action_done"
                               "action" action
                               "entityId" entity-id))
              (error (e)
                (error-response "action_failed"
                                (format nil "Holodeck action failed: ~a" e))))
            (if (holodeck-execute-action action-kw)
                (ok-response "holodeck_action_done"
                             "action" action
                             "entityId" entity-id)
                (error-response "action_failed"
                                (format nil "No handler for action: ~a" action))))))))

(define-handler handle-holodeck-set-view "holodeck_set_view" (msg conn)
  "Switch holodeck view mode."
  (declare (ignore conn))
  (unless (holodeck-available-p)
    (return-from handle-holodeck-set-view
      (error-response "holodeck_unavailable" "Holodeck is not loaded or running")))
  (let ((view-mode (gethash "mode" msg)))
    (unless view-mode
      (return-from handle-holodeck-set-view
        (error-response "missing_field" "holodeck_set_view requires 'mode'")))
    (let ((set-view-fn (find-symbol "SET-VIEW-MODE" :autopoiesis.holodeck)))
      (if (and set-view-fn (fboundp set-view-fn))
          (handler-case
              (let ((mode-kw (find-symbol (string-upcase view-mode) :keyword)))
                (unless mode-kw
                  (return-from handle-holodeck-set-view
                    (error-response "invalid_mode"
                                    (format nil "Unknown view mode: ~a" view-mode))))
                (funcall set-view-fn mode-kw)
                (ok-response "holodeck_view_set" "mode" view-mode))
            (error (e)
              (error-response "view_failed"
                              (format nil "Failed to set view mode: ~a" e))))
          (error-response "holodeck_error" "View mode switching not available")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Command Center Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-list-departments "list_departments" (msg conn)
  (declare (ignore msg conn))
  (let ((result (autopoiesis.substrate:find-entities :entity/type :department)))
    (ok-response "departments"
                 "departments" (mapcar #'department-to-json-plist result))))

(define-handler handle-create-department "create_department" (msg conn)
  (declare (ignore conn))
  (let ((name (gethash "name" msg)))
    (unless name
      (return-from handle-create-department
        (error-response "missing_field" "create_department requires 'name'")))
    (let ((eid (autopoiesis.substrate:intern-id
                (format nil "dept-~A" (make-uuid)))))
      (autopoiesis.substrate:transact!
       (list (list eid :entity/type :department)
             (list eid :department/name name)
             (list eid :department/parent (gethash "parent" msg))
             (list eid :department/description (gethash "description" msg))
             (list eid :department/budget-limit (gethash "budgetLimit" msg))
             (list eid :department/currency (or (gethash "currency" msg) "USD"))
             (list eid :department/created-at (get-universal-time))))
      (let ((dept-plist (department-to-json-plist eid)))
        (broadcast-stream-data (ok-response "department_created"
                                            "department" dept-plist)
                               :subscription-type "departments")
        (ok-response "department_created" "department" dept-plist)))))

(define-handler handle-update-department "update_department" (msg conn)
  (declare (ignore conn))
  (let ((eid (gethash "id" msg)))
    (unless eid
      (return-from handle-update-department
        (error-response "missing_field" "update_department requires 'id'")))
    (let ((datoms '()))
      (when (gethash "name" msg)
        (push (list eid :department/name (gethash "name" msg)) datoms))
      (when (gethash "description" msg)
        (push (list eid :department/description (gethash "description" msg)) datoms))
      (when (gethash "budgetLimit" msg)
        (push (list eid :department/budget-limit (gethash "budgetLimit" msg)) datoms))
      (when datoms
        (autopoiesis.substrate:transact! datoms))
      (ok-response "department_updated" "department" (department-to-json-plist eid)))))

(define-handler handle-list-goals "list_goals" (msg conn)
  (declare (ignore msg conn))
  (let ((result (autopoiesis.substrate:find-entities :entity/type :goal)))
    (ok-response "goals" "goals" (mapcar #'goal-to-json-plist result))))

(define-handler handle-create-goal "create_goal" (msg conn)
  (declare (ignore conn))
  (let ((title (gethash "title" msg)))
    (unless title
      (return-from handle-create-goal
        (error-response "missing_field" "create_goal requires 'title'")))
    (let ((eid (autopoiesis.substrate:intern-id
                (format nil "goal-~A" (make-uuid)))))
      (autopoiesis.substrate:transact!
       (list (list eid :entity/type :goal)
             (list eid :goal/title title)
             (list eid :goal/description (gethash "description" msg))
             (list eid :goal/department (gethash "department" msg))
             (list eid :goal/agent (gethash "agent" msg))
             (list eid :goal/status (intern (string-upcase (or (gethash "status" msg) "active")) :keyword))
             (list eid :goal/parent (gethash "parent" msg))
             (list eid :goal/created-at (get-universal-time))))
      (ok-response "goal_created" "goal" (goal-to-json-plist eid)))))

(define-handler handle-update-goal "update_goal" (msg conn)
  (declare (ignore conn))
  (let ((eid (gethash "id" msg)))
    (unless eid
      (return-from handle-update-goal
        (error-response "missing_field" "update_goal requires 'id'")))
    (let ((datoms '()))
      (when (gethash "title" msg)
        (push (list eid :goal/title (gethash "title" msg)) datoms))
      (when (gethash "status" msg)
        (push (list eid :goal/status (intern (string-upcase (gethash "status" msg)) :keyword)) datoms))
      (when (gethash "agent" msg)
        (push (list eid :goal/agent (gethash "agent" msg)) datoms))
      (when datoms
        (autopoiesis.substrate:transact! datoms))
      (ok-response "goal_updated" "goal" (goal-to-json-plist eid)))))

(define-handler handle-list-budgets "list_budgets" (msg conn)
  (declare (ignore msg conn))
  (let ((result (autopoiesis.substrate:find-entities :entity/type :budget)))
    (ok-response "budgets" "budgets" (mapcar #'budget-to-json-plist result))))

(define-handler handle-update-budget "update_budget" (msg conn)
  (declare (ignore conn))
  (let ((entity-id (gethash "entityId" msg))
        (limit (gethash "limit" msg)))
    (unless entity-id
      (return-from handle-update-budget
        (error-response "missing_field" "update_budget requires 'entityId'")))
    ;; Find or create budget entity
    (let ((budget-eid nil))
      (dolist (eid (autopoiesis.substrate:find-entities :entity/type :budget))
        (when (equal entity-id (autopoiesis.substrate:entity-attr eid :budget/target-id))
          (setf budget-eid eid)
          (return)))
      (unless budget-eid
        (setf budget-eid (autopoiesis.substrate:intern-id
                          (format nil "budget-~A" (make-uuid))))
        (autopoiesis.substrate:transact!
         (list (list budget-eid :entity/type :budget)
               (list budget-eid :budget/target-id entity-id)
               (list budget-eid :budget/target-type :agent)
               (list budget-eid :budget/spent 0)
               (list budget-eid :budget/currency "USD")
               (list budget-eid :budget/updated-at (get-universal-time)))))
      (autopoiesis.substrate:transact!
       (list (list budget-eid :budget/limit limit)
             (list budget-eid :budget/updated-at (get-universal-time))))
      (ok-response "budget_updated" "budget" (budget-to-json-plist budget-eid)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Evolution Handlers
;;; ═══════════════════════════════════════════════════════════════════

(defvar *evolution-thread* nil "Background evolution thread.")
(defvar *evolution-running* nil "Whether evolution is currently running.")
(defvar *evolution-generation* 0 "Current evolution generation.")

(define-handler handle-start-evolution "start_evolution" (msg conn)
  (declare (ignore conn))
  (when *evolution-running*
    (return-from handle-start-evolution
      (error-response "already_running" "Evolution is already running")))
  (let ((generations (or (gethash "generations" msg) 10))
        (mutation-rate (or (gethash "mutationRate" msg) 0.1))
        (population-size (or (gethash "populationSize" msg) 10)))
    (setf *evolution-running* t
          *evolution-generation* 0)
    (setf *evolution-thread*
          (bt:make-thread
           (lambda ()
             (unwind-protect
                  (handler-case
                      (let ((agents (loop repeat population-size
                                         collect (autopoiesis.agent:make-persistent-agent
                                                  :name (format nil "evo-~a" (gensym))
                                                  :capabilities '(:observe :decide :act))))
                            (evaluator (autopoiesis.agent:make-standard-pa-evaluator)))
                        (declare (ignore agents evaluator))
                        (dotimes (gen generations)
                          (unless *evolution-running* (return))
                          (setf *evolution-generation* (1+ gen))
                          ;; Broadcast progress
                          (broadcast-stream-data
                           (ok-response "evolution_progress"
                                        "generation" (1+ gen)
                                        "totalGenerations" generations
                                        "populationSize" population-size)
                           :subscription-type "evolution"))
                        (broadcast-stream-data
                         (ok-response "evolution_complete"
                                      "generations" generations)
                         :subscription-type "evolution"))
                    (error (e)
                      (broadcast-stream-data
                       (ok-response "evolution_error"
                                    "error" (format nil "~a" e))
                       :subscription-type "evolution")))
               (setf *evolution-running* nil)))
           :name "evolution-worker"))
    (ok-response "evolution_started"
                 "generations" generations
                 "mutationRate" mutation-rate
                 "populationSize" population-size)))

(define-handler handle-stop-evolution "stop_evolution" (msg conn)
  (declare (ignore msg conn))
  (if *evolution-running*
      (progn
        (setf *evolution-running* nil)
        (ok-response "evolution_stopped" "generation" *evolution-generation*))
      (error-response "not_running" "No evolution is running")))

(define-handler handle-evolution-status "evolution_status" (msg conn)
  (declare (ignore msg conn))
  (ok-response "evolution_status"
               "running" (if *evolution-running* t :false)
               "generation" *evolution-generation*))
