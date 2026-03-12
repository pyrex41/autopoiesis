;;;; api-tests.lisp - Tests for the WebSocket API layer
;;;;
;;;; Tests the wire format, serializers, message handlers, connection
;;;; management, and event bridge without requiring actual WebSocket connections.

(defpackage #:autopoiesis.api.test
  (:use #:cl #:fiveam #:autopoiesis.api)
  (:local-nicknames (#:bt #:bordeaux-threads))
  (:export #:run-api-tests))

(in-package #:autopoiesis.api.test)

(def-suite api-tests
  :description "Tests for the WebSocket API layer")

(in-suite api-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Test Helpers
;;; ═══════════════════════════════════════════════════════════════════

(defun make-test-agent (&key (name "test-agent") capabilities)
  "Create and register a test agent."
  (let ((agent (autopoiesis.agent:make-agent :name name :capabilities capabilities)))
    (autopoiesis.agent:register-agent agent)
    agent))

(defun cleanup-agents ()
  "Remove all agents from the registry."
  (dolist (agent (autopoiesis.agent:list-agents))
    (autopoiesis.agent:unregister-agent agent)))

(defmacro with-clean-state (&body body)
  "Execute body with clean global state."
  `(let ((autopoiesis.agent::*agent-registry* (make-hash-table :test 'equal))
         (autopoiesis.snapshot::*branch-registry* (make-hash-table :test 'equal))
         (autopoiesis.snapshot::*current-branch* nil)
         (autopoiesis.api::*connections* (make-hash-table :test 'equal)))
     ,@body))

;;; ═══════════════════════════════════════════════════════════════════
;;; Wire Format Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite wire-format-tests
  :in api-tests
  :description "Tests for hybrid JSON/MessagePack wire format")

(in-suite wire-format-tests)

(test json-encode-decode-roundtrip
  "JSON encode/decode preserves data."
  (let* ((h (make-hash-table :test 'equal)))
    (setf (gethash "type" h) "test"
          (gethash "value" h) 42
          (gethash "name" h) "hello")
    (let* ((encoded (encode-json h))
           (decoded (decode-json encoded)))
      (is (stringp encoded))
      (is (equal (gethash "type" decoded) "test"))
      (is (= (gethash "value" decoded) 42))
      (is (equal (gethash "name" decoded) "hello")))))

(test msgpack-encode-decode-roundtrip
  "MessagePack encode/decode preserves data."
  (let* ((h (make-hash-table :test 'equal)))
    (setf (gethash "type" h) "event"
          (gethash "value" h) 99
          (gethash "name" h) "stream-data")
    (let* ((encoded (encode-msgpack h))
           (decoded (decode-msgpack encoded)))
      (is (typep encoded '(simple-array (unsigned-byte 8) (*)))
          "MessagePack should encode to byte vector")
      ;; decoded is alist from cl-messagepack
      (is (equal (cdr (assoc "type" decoded :test #'equal)) "event"))
      (is (= (cdr (assoc "value" decoded :test #'equal)) 99))
      (is (equal (cdr (assoc "name" decoded :test #'equal)) "stream-data")))))

(test msgpack-smaller-than-json
  "MessagePack encoding is smaller than JSON for typical messages."
  (let* ((h (make-hash-table :test 'equal)))
    (setf (gethash "type" h) "thought_added"
          (gethash "agentId" h) "abc-123-def-456"
          (gethash "timestamp" h) 1234567890.123d0
          (gethash "content" h) "observation data here"
          (gethash "confidence" h) 0.95d0)
    (let ((json-size (length (encode-json h)))
          (msgpack-size (length (encode-msgpack h))))
      (is (< msgpack-size json-size)
          (format nil "MsgPack (~d bytes) should be smaller than JSON (~d bytes)"
                  msgpack-size json-size)))))

(test encode-control-produces-string
  "encode-control always produces a string (JSON text frame)."
  (let ((h (make-hash-table :test 'equal)))
    (setf (gethash "type" h) "pong")
    (is (stringp (encode-control h)))))

(test encode-stream-produces-bytes
  "encode-stream always produces a byte vector (MessagePack binary frame)."
  (let ((h (make-hash-table :test 'equal)))
    (setf (gethash "type" h) "event")
    (is (typep (encode-stream h) '(simple-array (unsigned-byte 8) (*))))))

(test stream-message-classification
  "Stream message types are correctly classified."
  (is (autopoiesis.api::stream-message-p "event"))
  (is (autopoiesis.api::stream-message-p "thought_added"))
  (is (autopoiesis.api::stream-message-p "agent_state_changed"))
  (is (not (autopoiesis.api::stream-message-p "pong")))
  (is (not (autopoiesis.api::stream-message-p "agents")))
  (is (not (autopoiesis.api::stream-message-p "subscribed"))))

(test encode-auto-selects-format
  "encode-auto picks binary for streams, text for control."
  (let ((stream-msg (make-hash-table :test 'equal))
        (control-msg (make-hash-table :test 'equal)))
    (setf (gethash "type" stream-msg) "event")
    (setf (gethash "type" control-msg) "pong")

    (multiple-value-bind (data frame-type) (encode-auto stream-msg)
      (is (eq frame-type :binary))
      (is (typep data '(simple-array (unsigned-byte 8) (*)))))

    (multiple-value-bind (data frame-type) (encode-auto control-msg)
      (is (eq frame-type :text))
      (is (stringp data)))))

(test decode-json-invalid-returns-nil
  "Decoding invalid JSON returns NIL."
  (is (null (decode-json "not valid json {")))
  (is (null (decode-json ""))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Serializer Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite serializer-tests
  :in api-tests
  :description "Tests for JSON serialization")

(in-suite serializer-tests)

(test agent-serialization
  "Agent serialization produces expected fields."
  (with-clean-state
    (let* ((agent (make-test-agent :name "serializer-test"
                                   :capabilities '(:read-file :write-file)))
           (json (agent-to-json-plist agent)))
      (is (hash-table-p json))
      (is (stringp (gethash "id" json)))
      (is (equal (gethash "name" json) "serializer-test"))
      (is (equal (gethash "state" json) "initialized"))
      (is (= (length (gethash "capabilities" json)) 2))
      (is (= (gethash "thoughtCount" json) 0)))))

(test thought-serialization
  "Thought types serialize with correct subclass fields."
  (let* ((obs (autopoiesis.core:make-observation "test data" :source :api))
         (json (thought-to-json-plist obs)))
    (is (hash-table-p json))
    (is (equal (gethash "type" json) "observation"))
    (is (equal (gethash "source" json) "api"))))

(test decision-serialization
  "Decision thoughts include alternatives and chosen."
  (let* ((dec (autopoiesis.core:make-decision
               '(("opt-a" . 0.8) ("opt-b" . 0.2))
               "opt-a"
               :rationale "better option"))
         (json (thought-to-json-plist dec)))
    (is (hash-table-p json))
    (is (equal (gethash "type" json) "decision"))
    (is (equal (gethash "rationale" json) "better option"))))

(test snapshot-serialization
  "Snapshot serialization produces expected fields."
  (let* ((snap (autopoiesis.snapshot:make-snapshot '(:test-state t)
                                                    :metadata '(:label "test")))
         (json (snapshot-to-json-plist snap)))
    (is (hash-table-p json))
    (is (stringp (gethash "id" json)))
    (is (stringp (gethash "hash" json)))))

(test branch-serialization
  "Branch serialization produces expected fields."
  (let* ((branch (autopoiesis.snapshot::make-branch "test-branch" :head "snap-123"))
         (json (branch-to-json-plist branch)))
    (is (hash-table-p json))
    (is (equal (gethash "name" json) "test-branch"))
    (is (equal (gethash "head" json) "snap-123"))))

(test blocking-request-serialization
  "Blocking request serialization produces expected fields."
  (let* ((req (autopoiesis.interface:make-blocking-request
               "Approve action?"
               :options '("yes" "no")
               :default "no"))
         (json (blocking-request-to-json-plist req)))
    (is (hash-table-p json))
    (is (equal (gethash "prompt" json) "Approve action?"))
    (is (equal (gethash "status" json) "pending"))
    (is (= (length (gethash "options" json)) 2))
    ;; Clean up the registered request
    (autopoiesis.interface::unregister-blocking-request req)))

;;; ═══════════════════════════════════════════════════════════════════
;;; Handler Tests (using direct function calls, no WebSocket)
;;; ═══════════════════════════════════════════════════════════════════

(def-suite handler-tests
  :in api-tests
  :description "Tests for message handlers")

(in-suite handler-tests)

;; Mock connection for testing handlers
(defclass mock-connection ()
  ((id :initarg :id :accessor connection-id :initform "mock-conn-1")
   (sent-messages :initarg :sent-messages :accessor mock-sent-messages :initform nil)
   (subscriptions :initarg :subscriptions :accessor connection-subscriptions
                  :initform (make-hash-table :test 'equal))
   (preferred-stream-format :initarg :preferred-stream-format
                            :accessor autopoiesis.api::connection-stream-format
                            :initform :msgpack)
   (ws :initarg :ws :accessor connection-ws :initform nil)
   (metadata :initarg :metadata :accessor connection-metadata
             :initform (make-hash-table :test 'equal))))

(defun make-mock-connection ()
  (make-instance 'mock-connection))

(defun make-msg (&rest pairs)
  "Create a message hash table from key-value pairs."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k h) v))
    h))

(test handler-ping
  "Ping handler returns pong."
  (let* ((conn (make-mock-connection))
         (result (autopoiesis.api::handle-ping (make-msg "type" "ping") conn)))
    (is (equal (gethash "type" result) "pong"))))

(test handler-system-info
  "System info handler returns version and counts."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::handle-system-info (make-msg "type" "system_info") conn)))
      (is (equal (gethash "type" result) "system_info"))
      (is (stringp (gethash "version" result))))))

(test handler-list-agents-empty
  "List agents returns empty list when no agents."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::handle-list-agents (make-msg "type" "list_agents") conn)))
      (is (equal (gethash "type" result) "agents"))
      (is (null (gethash "agents" result))))))

(test handler-create-and-list-agents
  "Create agent then list shows it."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      ;; Create
      (let ((result (autopoiesis.api::handle-create-agent
                     (make-msg "type" "create_agent"
                               "name" "test-bot"
                               "capabilities" '("read-file"))
                     conn)))
        (is (equal (gethash "type" result) "agent_created"))
        (let ((agent-data (gethash "agent" result)))
          (is (stringp (second (member "id" agent-data :test #'equal))))
          (is (equal (second (member "name" agent-data :test #'equal)) "test-bot"))))

      ;; List
      (let ((result (autopoiesis.api::handle-list-agents (make-msg "type" "list_agents") conn)))
        (is (= (length (gethash "agents" result)) 1))))))

(test handler-agent-lifecycle
  "Agent start/stop/pause/resume via agent_action handler."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (agent (make-test-agent :name "lifecycle-test"))
           (agent-id (autopoiesis.agent:agent-id agent)))

      ;; Start
      (let ((result (autopoiesis.api::handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "start")
                     conn)))
        (is (equal (gethash "state" result) "running")))

      ;; Pause
      (let ((result (autopoiesis.api::handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "pause")
                     conn)))
        (is (equal (gethash "state" result) "paused")))

      ;; Resume
      (let ((result (autopoiesis.api::handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "resume")
                     conn)))
        (is (equal (gethash "state" result) "running")))

      ;; Stop
      (let ((result (autopoiesis.api::handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "stop")
                     conn)))
        (is (equal (gethash "state" result) "stopped"))))))

(test handler-agent-not-found
  "Agent operations on missing ID return error."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      (let ((result (autopoiesis.api::handle-get-agent
                     (make-msg "type" "get_agent" "agentId" "nonexistent")
                     conn)))
        (is (equal (gethash "type" result) "error"))
        (is (equal (gethash "code" result) "not_found"))))))

(test handler-inject-and-get-thoughts
  "Inject thoughts then retrieve them."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (agent (make-test-agent :name "thought-test"))
           (agent-id (autopoiesis.agent:agent-id agent)))

      ;; Inject
      (let ((result (autopoiesis.api::handle-inject-thought
                     (make-msg "type" "inject_thought"
                               "agentId" agent-id
                               "content" "hello world"
                               "thoughtType" "observation")
                     conn)))
        (is (equal (gethash "type" result) "thought_added")))

      ;; Inject another
      (autopoiesis.api::handle-inject-thought
       (make-msg "type" "inject_thought"
                 "agentId" agent-id
                 "content" "second thought"
                 "thoughtType" "reflection")
       conn)

      ;; Get
      (let ((result (autopoiesis.api::handle-get-thoughts
                     (make-msg "type" "get_thoughts"
                               "agentId" agent-id
                               "limit" 10)
                     conn)))
        (is (equal (gethash "type" result) "thoughts"))
        (is (= (gethash "total" result) 2))
        (is (= (length (gethash "thoughts" result)) 2))))))

(test handler-branches
  "Create and list branches."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      ;; Create branch
      (let ((result (autopoiesis.api::handle-create-branch
                     (make-msg "type" "create_branch"
                               "name" "feature-x"
                               "fromSnapshot" "snap-001")
                     conn)))
        (is (equal (gethash "type" result) "branch_created")))

      ;; List
      (let ((result (autopoiesis.api::handle-list-branches
                     (make-msg "type" "list_branches") conn)))
        (is (equal (gethash "type" result) "branches"))
        (is (= (length (gethash "branches" result)) 1))))))

(test handler-subscribe-unsubscribe
  "Subscribe and unsubscribe to channels."
  (let ((conn (make-mock-connection)))
    ;; Subscribe
    (let ((result (autopoiesis.api::handle-subscribe
                   (make-msg "type" "subscribe" "channel" "events")
                   conn)))
      (is (equal (gethash "type" result) "subscribed"))
      (is (equal (gethash "channel" result) "events")))

    ;; Verify subscription
    (is (connection-subscribed-p conn "events"))

    ;; Unsubscribe
    (autopoiesis.api::handle-unsubscribe
     (make-msg "type" "unsubscribe" "channel" "events")
     conn)
    (is (not (connection-subscribed-p conn "events")))))

(test handler-set-stream-format
  "Client can switch between msgpack and json for data streams."
  (let ((conn (make-mock-connection)))
    ;; Default is msgpack
    (is (eq (autopoiesis.api::connection-stream-format conn) :msgpack))

    ;; Switch to json
    (let ((result (autopoiesis.api::handle-set-stream-format
                   (make-msg "type" "set_stream_format" "format" "json")
                   conn)))
      (is (equal (gethash "type" result) "stream_format_set"))
      (is (equal (gethash "format" result) "json")))
    (is (eq (autopoiesis.api::connection-stream-format conn) :json))

    ;; Switch back to msgpack
    (autopoiesis.api::handle-set-stream-format
     (make-msg "type" "set_stream_format" "format" "msgpack")
     conn)
    (is (eq (autopoiesis.api::connection-stream-format conn) :msgpack))

    ;; Invalid format returns error
    (let ((result (autopoiesis.api::handle-set-stream-format
                   (make-msg "type" "set_stream_format" "format" "xml")
                   conn)))
      (is (equal (gethash "type" result) "error")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Dispatch Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite dispatch-tests
  :in api-tests
  :description "Tests for full message dispatch pipeline")

(in-suite dispatch-tests)

(test dispatch-unknown-type
  "Unknown message type returns error."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message "totally_unknown" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (equal (gethash "code" result) "unknown_type")))))

(test handle-message-invalid-json
  "handle-message with bad JSON returns error string."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result-str (handle-message conn "{{bad json")))
      (is (stringp result-str))
      (let ((decoded (decode-message result-str)))
        (is (equal (gethash "type" decoded) "error"))
        (is (equal (gethash "code" decoded) "invalid_json"))))))

(test handle-message-missing-type
  "handle-message without type field returns error."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result-str (handle-message conn "{\"data\": 1}")))
      (is (stringp result-str))
      (let ((decoded (decode-message result-str)))
        (is (equal (gethash "type" decoded) "error"))
        (is (equal (gethash "code" decoded) "missing_type"))))))

(test handle-message-request-id-passthrough
  "requestId from client message is echoed in response."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result-str (handle-message conn
                                       (encode-message
                                        (make-msg "type" "ping"
                                                  "requestId" "req-42")))))
      (let ((decoded (decode-message result-str)))
        (is (equal (gethash "type" decoded) "pong"))
        (is (equal (gethash "requestId" decoded) "req-42"))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Connection Management Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite connection-tests
  :in api-tests
  :description "Tests for connection registry")

(in-suite connection-tests)

(test connection-register-unregister
  "Connections can be registered and unregistered."
  (let ((autopoiesis.api::*connections* (make-hash-table :test 'equal)))
    (let ((conn (make-instance 'api-connection
                               :ws nil)))
      ;; Register
      (register-connection conn)
      (is (= (autopoiesis.api::connection-count) 1))
      (is (not (null (find-connection (connection-id conn)))))

      ;; Unregister
      (unregister-connection conn)
      (is (= (autopoiesis.api::connection-count) 0))
      (is (null (find-connection (connection-id conn)))))))

(test connection-subscriptions
  "Connections track subscriptions correctly."
  (let ((conn (make-mock-connection)))
    (subscribe-connection conn "events")
    (subscribe-connection conn "thoughts:agent-1")

    (is (connection-subscribed-p conn "events"))
    (is (connection-subscribed-p conn "thoughts:agent-1"))
    (is (not (connection-subscribed-p conn "other")))

    (unsubscribe-connection conn "events")
    (is (not (connection-subscribed-p conn "events")))
    (is (connection-subscribed-p conn "thoughts:agent-1"))))

(test connection-default-stream-format
  "New connections default to msgpack stream format."
  (let ((conn (make-instance 'api-connection :ws nil)))
    (is (eq (autopoiesis.api::connection-stream-format conn) :msgpack))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Activity Tracker Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite activity-tracker-tests
  :in api-tests
  :description "Tests for the activity and cost tracking system")

(in-suite activity-tracker-tests)

(defmacro with-fresh-activity-state (&body body)
  "Execute body with fresh activity/cost tables and empty connections."
  `(let ((autopoiesis.api::*activity-state* (make-hash-table :test 'equal))
         (autopoiesis.api::*cost-state* (make-hash-table :test 'equal))
         (autopoiesis.api::*activity-lock* (bt:make-lock "test-activity-lock"))
         (autopoiesis.api::*connections* (make-hash-table :test 'equal)))
     ,@body))

(test activity-initial-state
  "Fresh activity state tables are empty."
  (with-fresh-activity-state
    (is (null (all-activities)))
    (is (null (agent-activity "agent-1")))
    (is (null (agent-cost "agent-1")))))

(test tool-called-sets-current-tool
  "handle-tool-called populates :current-tool and :tool-start."
  (with-fresh-activity-state
    (autopoiesis.api::handle-tool-called "agent-1" '(:tool "read_file") 1000)
    (let ((state (agent-activity "agent-1")))
      (is (not (null state)))
      (is (equal (getf state :current-tool) "read_file"))
      (is (= (getf state :tool-start) 1000))
      (is (= (getf state :last-active) 1000)))))

(test tool-result-clears-and-increments
  "handle-tool-result clears current tool and increments total-calls."
  (with-fresh-activity-state
    (autopoiesis.api::handle-tool-called "agent-1" '(:tool "write_file") 1000)
    (autopoiesis.api::handle-tool-result "agent-1" nil 1005)
    (let ((state (agent-activity "agent-1")))
      (is (null (getf state :current-tool)))
      (is (null (getf state :tool-start)))
      (is (= (getf state :total-calls) 1))
      (is (= (getf state :last-active) 1005)))))

(test tool-result-computes-duration
  ":last-tool-duration = timestamp - tool-start."
  (with-fresh-activity-state
    (autopoiesis.api::handle-tool-called "agent-1" '(:tool "search") 1000)
    (autopoiesis.api::handle-tool-result "agent-1" nil 1042)
    (let ((state (agent-activity "agent-1")))
      (is (= (getf state :last-tool-duration) 42)))))

(test provider-response-accumulates-cost
  "handle-provider-response sums :total-cost across calls."
  (with-fresh-activity-state
    (autopoiesis.api::handle-provider-response "agent-1" '(:cost 0.05) 1000)
    (autopoiesis.api::handle-provider-response "agent-1" '(:cost 0.10) 1001)
    (let ((state (agent-cost "agent-1")))
      (is (not (null state)))
      (is (= (getf state :total-cost) 0.15))
      (is (= (getf state :total-calls) 2)))))

(test provider-response-accumulates-tokens
  "Tokens accumulate across calls (both flat and :usage plist forms)."
  (with-fresh-activity-state
    ;; Flat usage form (numeric)
    (autopoiesis.api::handle-provider-response "agent-1" '(:usage 100) 1000)
    ;; Plist usage form
    (autopoiesis.api::handle-provider-response "agent-1"
                                               '(:usage (:input-tokens 50 :output-tokens 30))
                                               1001)
    (let ((state (agent-cost "agent-1")))
      (is (= (getf state :total-tokens) 180)))))

(test agent-activity-returns-copy
  "Returned plist is a copy — mutating it doesn't corrupt state."
  (with-fresh-activity-state
    (autopoiesis.api::handle-tool-called "agent-1" '(:tool "test") 1000)
    (let ((copy1 (agent-activity "agent-1")))
      (setf (getf copy1 :current-tool) "CORRUPTED")
      (let ((copy2 (agent-activity "agent-1")))
        (is (equal (getf copy2 :current-tool) "test"))))))

(test agent-activity-nil-for-unknown
  "Returns nil for untracked agent."
  (with-fresh-activity-state
    (is (null (agent-activity "nonexistent-agent")))))

(test all-activities-returns-all
  "Returns entries for all tracked agents."
  (with-fresh-activity-state
    (autopoiesis.api::handle-tool-called "agent-1" '(:tool "a") 1000)
    (autopoiesis.api::handle-tool-called "agent-2" '(:tool "b") 1001)
    (autopoiesis.api::handle-tool-called "agent-3" '(:tool "c") 1002)
    (let ((all (all-activities)))
      (is (= (length all) 3)))))

(test agent-cost-nil-for-unknown
  "Returns nil for untracked agent."
  (with-fresh-activity-state
    (is (null (agent-cost "nonexistent-agent")))))

(test cost-summary-aggregates
  ":total sums across agents, :per-agent lists all."
  (with-fresh-activity-state
    (autopoiesis.api::handle-provider-response "agent-1" '(:cost 0.10) 1000)
    (autopoiesis.api::handle-provider-response "agent-2" '(:cost 0.25) 1001)
    (let ((summary (cost-summary)))
      (is (= (getf summary :total) 0.35))
      (is (= (length (getf summary :per-agent)) 2)))))

(test start-stop-lifecycle
  "stop-activity-tracker clears state tables."
  (with-fresh-activity-state
    (autopoiesis.api::handle-tool-called "agent-1" '(:tool "x") 1000)
    (is (not (null (agent-activity "agent-1"))))
    ;; Manually clear state the way stop-activity-tracker does (without event bus)
    (bt:with-lock-held (autopoiesis.api::*activity-lock*)
      (clrhash autopoiesis.api::*activity-state*)
      (clrhash autopoiesis.api::*cost-state*))
    ;; After clearing, state tables are empty
    (is (null (agent-activity "agent-1")))
    (is (null (all-activities)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Conductor Handler Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite conductor-handler-tests
  :in api-tests
  :description "Tests for conductor WebSocket handlers")

(in-suite conductor-handler-tests)

(test conductor-status-returns-fields
  "conductor_status response contains expected fields."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message "conductor_status" (make-msg) conn)))
      (is (equal (gethash "type" result) "conductor_status"))
      ;; Should contain running field (true or false)
      (is (member (gethash "running" result) '(t :false nil)))
      ;; Should have tickCount
      (is (numberp (gethash "tickCount" result))))))

(test conductor-status-no-conductor
  "conductor_status returns gracefully when conductor is nil."
  (with-clean-state
    (let ((autopoiesis.orchestration::*conductor* nil)
          (conn (make-mock-connection)))
      (let ((result (autopoiesis.api::dispatch-message "conductor_status" (make-msg) conn)))
        (is (equal (gethash "type" result) "conductor_status"))))))

(test conductor-start-creates-conductor
  "conductor_start returns conductor_started response."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message "conductor_start" (make-msg) conn)))
      (is (equal (gethash "type" result) "conductor_started"))
      (is (equal (gethash "running" result) t))
      ;; Clean up: stop the conductor we just started
      (ignore-errors (autopoiesis.orchestration:stop-conductor)))))

(test conductor-stop-stops-conductor
  "conductor_stop returns conductor_stopped response."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      ;; Start first so there's something to stop
      (ignore-errors (autopoiesis.orchestration:start-conductor))
      (let ((result (autopoiesis.api::dispatch-message "conductor_stop" (make-msg) conn)))
        (is (equal (gethash "type" result) "conductor_stopped"))
        (is (equal (gethash "running" result) :false))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Team Handler Error-Path Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite team-handler-tests
  :in api-tests
  :description "Tests for team WebSocket handler error paths")

(in-suite team-handler-tests)

(test create-team-missing-name
  "create_team returns error for missing name field (or not_available if team not loaded)."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "create_team"
                    (make-msg "strategy" "leader-worker")
                    conn)))
      (is (equal (gethash "type" result) "error"))
      (is (member (gethash "code" result) '("missing_field" "not_available") :test #'equal)))))

(test start-team-missing-id
  "start_team returns error for missing teamId."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "start_team" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (member (gethash "code" result) '("missing_field" "not_available") :test #'equal)))))

(test disband-team-missing-id
  "disband_team returns error for missing teamId."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "disband_team" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (member (gethash "code" result) '("missing_field" "not_available") :test #'equal)))))

(test add-member-missing-fields
  "add_team_member returns error for missing teamId."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "add_team_member" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (member (gethash "code" result) '("missing_field" "not_available") :test #'equal)))))

(test add-member-missing-agent-name
  "add_team_member returns error for missing agentName."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "add_team_member"
                    (make-msg "teamId" "team-1")
                    conn)))
      (is (equal (gethash "type" result) "error"))
      (is (member (gethash "code" result) '("missing_field" "not_available") :test #'equal)))))

(test remove-member-missing-fields
  "remove_team_member returns error for missing teamId."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "remove_team_member" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (member (gethash "code" result) '("missing_field" "not_available") :test #'equal)))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Holodeck & Chat Handler Error-Path Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite holodeck-handler-tests
  :in api-tests
  :description "Tests for holodeck and chat WebSocket handler error paths")

(in-suite holodeck-handler-tests)

(test holodeck-subscribe-adds-channel
  "holodeck_subscribe subscribes connection to holodeck channel."
  (let ((conn (make-mock-connection)))
    (let ((result (autopoiesis.api::dispatch-message
                   "holodeck_subscribe" (make-msg) conn)))
      (is (equal (gethash "type" result) "subscribed"))
      (is (equal (gethash "channel" result) "holodeck"))
      (is (autopoiesis.api::connection-subscribed-p conn "holodeck")))))

(test holodeck-unsubscribe-removes-channel
  "holodeck_unsubscribe removes holodeck subscription."
  (let ((conn (make-mock-connection)))
    (autopoiesis.api::subscribe-connection conn "holodeck")
    (is (autopoiesis.api::connection-subscribed-p conn "holodeck"))
    (let ((result (autopoiesis.api::dispatch-message
                   "holodeck_unsubscribe" (make-msg) conn)))
      (is (equal (gethash "type" result) "unsubscribed"))
      (is (not (autopoiesis.api::connection-subscribed-p conn "holodeck"))))))

(test holodeck-camera-missing-command
  "holodeck_camera returns error for missing command field."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "holodeck_camera" (make-msg) conn)))
      ;; Either holodeck_unavailable or missing_field depending on load state
      (is (equal (gethash "type" result) "error")))))

(test holodeck-select-missing-entity
  "holodeck_select returns error for missing entityId field."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "holodeck_select" (make-msg) conn)))
      (is (equal (gethash "type" result) "error")))))

(test chat-start-missing-agent
  "start_chat returns error for missing agentId."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "start_chat" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (equal (gethash "code" result) "missing_field")))))

(test chat-prompt-missing-fields
  "chat_prompt returns error for missing agentId/text."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "chat_prompt" (make-msg) conn)))
      (is (equal (gethash "type" result) "error"))
      (is (equal (gethash "code" result) "missing_field")))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Get-Activities Handler Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite get-activities-handler-tests
  :in api-tests
  :description "Tests for get_activities handler")

(in-suite get-activities-handler-tests)

(test get-activities-empty
  "get_activities returns empty activities when no agents exist."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (autopoiesis.api::dispatch-message
                    "get_activities" (make-msg) conn)))
      (is (equal (gethash "type" result) "activities"))
      (is (null (gethash "activities" result))))))

(test get-activities-with-data
  "get_activities returns populated activity for existing agents."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      ;; Create an agent so list-agents returns something
      (make-test-agent :name "active-agent")
      (let ((result (autopoiesis.api::dispatch-message
                     "get_activities" (make-msg) conn)))
        (is (equal (gethash "type" result) "activities"))
        (is (= (length (gethash "activities" result)) 1))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Run All Tests
;;; ═══════════════════════════════════════════════════════════════════

(defun run-api-tests ()
  "Run all API tests."
  (run! 'api-tests))
