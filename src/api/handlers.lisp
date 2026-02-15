;;;; handlers.lisp - WebSocket message handlers
;;;;
;;;; Maps incoming JSON message types to autopoiesis operations.
;;;; Each handler receives a decoded message plist and connection,
;;;; and returns a response plist (or nil for no response).

(in-package #:autopoiesis.api)

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Encoding/Decoding
;;; ═══════════════════════════════════════════════════════════════════

(defun decode-message (json-string)
  "Decode a JSON message string to a hash table."
  (handler-case
      (com.inuoe.jzon:parse json-string)
    (error (e)
      (log:warn "Failed to decode message: ~a" e)
      nil)))

(defun encode-message (plist)
  "Encode a plist as a JSON string."
  (com.inuoe.jzon:stringify plist))

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
                                          (format nil "~a" e)
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
  (let* ((agent-id (gethash "agentId" msg))
         (agent (find-agent agent-id)))
    (if agent
        (ok-response "agent" "agent" (agent-to-json-plist agent))
        (error-response "not_found"
                        (format nil "Agent not found: ~a" agent-id)))))

(define-handler handle-create-agent "create_agent" (msg conn)
  (declare (ignore conn))
  (let* ((name (or (gethash "name" msg) "unnamed"))
         (capabilities (mapcar (lambda (c)
                                 (intern (string-upcase c) :keyword))
                               (or (gethash "capabilities" msg) nil)))
         (agent (make-agent :name name :capabilities capabilities)))
    (register-agent agent)
    ;; Broadcast to all connections subscribed to agent updates
    (let ((notification (encode-message
                         (ok-response "agent_created"
                                      "agent" (agent-to-json-plist agent)))))
      (broadcast-message notification :subscription-type "agents"))
    (ok-response "agent_created"
                 "agent" (agent-to-json-plist agent))))

(define-handler handle-agent-action "agent_action" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (action (gethash "action" msg))
         (agent (find-agent agent-id)))
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
      ;; Broadcast state change
      (let ((notification (encode-message
                           (ok-response "agent_state_changed"
                                        "agentId" agent-id
                                        "state" (string-downcase
                                                 (symbol-name (agent-state agent)))))))
        (broadcast-message notification :subscription-type "agents"))
      (ok-response "agent_state_changed"
                   "agentId" agent-id
                   "state" (string-downcase
                            (symbol-name (agent-state agent)))))))

(define-handler handle-step-agent "step_agent" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (agent (find-agent agent-id)))
    (unless agent
      (return-from handle-step-agent
        (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
    ;; Execute one cognitive cycle
    (let ((env (or (gethash "environment" msg) nil)))
      (cognitive-cycle agent env)
      (ok-response "step_complete"
                   "agentId" agent-id
                   "thoughtCount" (stream-length (agent-thought-stream agent))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Thought Handlers
;;; ═══════════════════════════════════════════════════════════════════

(define-handler handle-get-thoughts "get_thoughts" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (limit (or (gethash "limit" msg) 50))
         (agent (find-agent agent-id)))
    (unless agent
      (return-from handle-get-thoughts
        (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
    (let ((thoughts (stream-last (agent-thought-stream agent) limit)))
      (ok-response "thoughts"
                   "agentId" agent-id
                   "thoughts" (mapcar #'thought-to-json-plist thoughts)
                   "total" (stream-length (agent-thought-stream agent))))))

(define-handler handle-inject-thought "inject_thought" (msg conn)
  (declare (ignore conn))
  (let* ((agent-id (gethash "agentId" msg))
         (content (gethash "content" msg))
         (thought-type (or (gethash "thoughtType" msg) "observation"))
         (agent (find-agent agent-id)))
    (unless agent
      (return-from handle-inject-thought
        (error-response "not_found" (format nil "Agent not found: ~a" agent-id))))
    (let* ((thought (cond
                      ((equal thought-type "observation")
                       (make-observation content :source :api))
                      ((equal thought-type "reflection")
                       (make-reflection nil content))
                      (t
                       (make-thought content
                                     :type (intern (string-upcase thought-type) :keyword)))))
           (_ (stream-append (agent-thought-stream agent) thought))
           (thought-json (thought-to-json-plist thought)))
      (declare (ignore _))
      ;; Push to thought subscribers
      (let ((notification (encode-message
                           (ok-response "thought_added"
                                        "agentId" agent-id
                                        "thought" thought-json))))
        (broadcast-to-agent-subscribers agent-id notification))
      (ok-response "thought_added"
                   "agentId" agent-id
                   "thought" thought-json))))

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
         (label (gethash "label" msg))
         (agent (find-agent agent-id)))
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
                   "snapshot" (snapshot-to-json-plist snapshot)))))

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
         (from-snapshot (gethash "fromSnapshot" msg))
         (branch (create-branch name :from-snapshot from-snapshot)))
    (ok-response "branch_created"
                 "branch" (branch-to-json-plist branch))))

(define-handler handle-switch-branch "switch_branch" (msg conn)
  (declare (ignore conn))
  (let* ((name (gethash "name" msg))
         (branch (switch-branch name)))
    (ok-response "branch_switched"
                 "branch" (branch-to-json-plist branch))))

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
  (let* ((request-id (gethash "requestId" msg))
         (response (gethash "response" msg)))
    (multiple-value-bind (ok request)
        (respond-to-request request-id response)
      (if ok
          (ok-response "blocking_responded"
                       "requestId" request-id
                       "status" "responded")
          (error-response "not_found"
                          (format nil "Blocking request not found: ~a" request-id))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Subscription Handlers
;;; ═══════════════════════════════════════════════════════════════════

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
  (let* ((limit (or (gethash "limit" msg) 50))
         (event-type (when (gethash "eventType" msg)
                       (intern (string-upcase (gethash "eventType" msg)) :keyword)))
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
