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
  (declare (ignore conn))
  (let* ((name (or (gethash "name" msg) "unnamed"))
         (capabilities (mapcar (lambda (c)
                                 (or (find-symbol (string-upcase c) :keyword)
                                     (return-from handle-create-agent
                                       (error-response "invalid_capability"
                                                        (format nil "Unknown capability: ~a" c)))))
                               (or (gethash "capabilities" msg) nil)))
         (agent (make-agent :name name :capabilities capabilities)))
    (register-agent agent)
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
                      ((equal action "start") (start-agent agent))
                      ((equal action "stop") (stop-agent agent))
                      ((equal action "pause") (pause-agent agent))
                      ((equal action "resume") (resume-agent agent))
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
        (stream-append (agent-thought-stream agent) thought)
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
             (metadata (when label (list :label label)))
             (snapshot (make-snapshot state :metadata metadata)))
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
