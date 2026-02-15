;;;; api-tests.lisp - Tests for the WebSocket API layer
;;;;
;;;; Tests the wire format, serializers, message handlers, connection
;;;; management, and event bridge without requiring actual WebSocket connections.

(defpackage #:autopoiesis.api.test
  (:use #:cl #:fiveam #:autopoiesis.api)
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
      (let ((id (second (member "id" json :test #'equal)))
            (name (second (member "name" json :test #'equal)))
            (state (second (member "state" json :test #'equal)))
            (caps (second (member "capabilities" json :test #'equal)))
            (tc (second (member "thoughtCount" json :test #'equal))))
        (is (stringp id))
        (is (equal name "serializer-test"))
        (is (equal state "initialized"))
        (is (= (length caps) 2))
        (is (= tc 0))))))

(test thought-serialization
  "Thought types serialize with correct subclass fields."
  (let* ((obs (autopoiesis.core:make-observation "test data" :source :api))
         (json (thought-to-json-plist obs)))
    (let ((type-val (second (member "type" json :test #'equal)))
          (source-val (second (member "source" json :test #'equal))))
      (is (equal type-val "observation"))
      (is (equal source-val "api")))))

(test decision-serialization
  "Decision thoughts include alternatives and chosen."
  (let* ((dec (autopoiesis.core:make-decision
               '(("opt-a" . 0.8) ("opt-b" . 0.2))
               "opt-a"
               :rationale "better option"))
         (json (thought-to-json-plist dec)))
    (let ((type-val (second (member "type" json :test #'equal)))
          (rationale (second (member "rationale" json :test #'equal))))
      (is (equal type-val "decision"))
      (is (equal rationale "better option")))))

(test snapshot-serialization
  "Snapshot serialization produces expected fields."
  (let* ((snap (autopoiesis.snapshot:make-snapshot '(:test-state t)
                                                    :metadata '(:label "test")))
         (json (snapshot-to-json-plist snap)))
    (let ((id (second (member "id" json :test #'equal)))
          (hash (second (member "hash" json :test #'equal))))
      (is (stringp id))
      (is (stringp hash)))))

(test branch-serialization
  "Branch serialization produces expected fields."
  (let* ((branch (autopoiesis.snapshot::make-branch "test-branch" :head "snap-123"))
         (json (branch-to-json-plist branch)))
    (let ((name (second (member "name" json :test #'equal)))
          (head (second (member "head" json :test #'equal))))
      (is (equal name "test-branch"))
      (is (equal head "snap-123")))))

(test blocking-request-serialization
  "Blocking request serialization produces expected fields."
  (let* ((req (autopoiesis.interface:make-blocking-request
               "Approve action?"
               :options '("yes" "no")
               :default "no"))
         (json (blocking-request-to-json-plist req)))
    (let ((prompt (second (member "prompt" json :test #'equal)))
          (status (second (member "status" json :test #'equal)))
          (options (second (member "options" json :test #'equal))))
      (is (equal prompt "Approve action?"))
      (is (equal status "pending"))
      (is (= (length options) 2)))
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
;;; Run All Tests
;;; ═══════════════════════════════════════════════════════════════════

(defun run-api-tests ()
  "Run all API tests."
  (run! 'api-tests))
