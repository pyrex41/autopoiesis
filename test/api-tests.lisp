;;;; api-tests.lisp - Tests for the WebSocket API layer
;;;;
;;;; Tests the serializers, message handlers, connection management,
;;;; and event bridge without requiring actual WebSocket connections.

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
      (is (stringp (getf json "id" nil))
          "Agent should have string ID")
      ;; plist with string keys - use position-based access
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
;;; Message Encoding/Decoding Tests
;;; ═══════════════════════════════════════════════════════════════════

(def-suite message-tests
  :in api-tests
  :description "Tests for message encoding and decoding")

(in-suite message-tests)

(test encode-decode-roundtrip
  "Messages survive JSON encode/decode roundtrip."
  (let* ((original (let ((h (make-hash-table :test 'equal)))
                     (setf (gethash "type" h) "test"
                           (gethash "data" h) "hello"
                           (gethash "number" h) 42)
                     h))
         (json-str (encode-message original))
         (decoded (decode-message json-str)))
    (is (stringp json-str))
    (is (equal (gethash "type" decoded) "test"))
    (is (equal (gethash "data" decoded) "hello"))
    (is (= (gethash "number" decoded) 42))))

(test decode-invalid-json
  "Decoding invalid JSON returns NIL."
  (is (null (decode-message "not valid json {")))
  (is (null (decode-message ""))))

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
         (result (handle-ping (make-msg "type" "ping") conn)))
    (is (equal (gethash "type" result) "pong"))))

(test handler-system-info
  "System info handler returns version and counts."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (handle-system-info (make-msg "type" "system_info") conn)))
      (is (equal (gethash "type" result) "system_info"))
      (is (stringp (gethash "version" result))))))

(test handler-list-agents-empty
  "List agents returns empty list when no agents."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (result (handle-list-agents (make-msg "type" "list_agents") conn)))
      (is (equal (gethash "type" result) "agents"))
      (is (null (gethash "agents" result))))))

(test handler-create-and-list-agents
  "Create agent then list shows it."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      ;; Create
      (let ((result (handle-create-agent
                     (make-msg "type" "create_agent"
                               "name" "test-bot"
                               "capabilities" '("read-file"))
                     conn)))
        (is (equal (gethash "type" result) "agent_created"))
        (let ((agent-data (gethash "agent" result)))
          (is (stringp (second (member "id" agent-data :test #'equal))))
          (is (equal (second (member "name" agent-data :test #'equal)) "test-bot"))))

      ;; List
      (let ((result (handle-list-agents (make-msg "type" "list_agents") conn)))
        (is (= (length (gethash "agents" result)) 1))))))

(test handler-agent-lifecycle
  "Agent start/stop/pause/resume via agent_action handler."
  (with-clean-state
    (let* ((conn (make-mock-connection))
           (agent (make-test-agent :name "lifecycle-test"))
           (agent-id (autopoiesis.agent:agent-id agent)))

      ;; Start
      (let ((result (handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "start")
                     conn)))
        (is (equal (gethash "state" result) "running")))

      ;; Pause
      (let ((result (handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "pause")
                     conn)))
        (is (equal (gethash "state" result) "paused")))

      ;; Resume
      (let ((result (handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "resume")
                     conn)))
        (is (equal (gethash "state" result) "running")))

      ;; Stop
      (let ((result (handle-agent-action
                     (make-msg "type" "agent_action"
                               "agentId" agent-id
                               "action" "stop")
                     conn)))
        (is (equal (gethash "state" result) "stopped"))))))

(test handler-agent-not-found
  "Agent operations on missing ID return error."
  (with-clean-state
    (let ((conn (make-mock-connection)))
      (let ((result (handle-get-agent
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
      (let ((result (handle-inject-thought
                     (make-msg "type" "inject_thought"
                               "agentId" agent-id
                               "content" "hello world"
                               "thoughtType" "observation")
                     conn)))
        (is (equal (gethash "type" result) "thought_added")))

      ;; Inject another
      (handle-inject-thought
       (make-msg "type" "inject_thought"
                 "agentId" agent-id
                 "content" "second thought"
                 "thoughtType" "reflection")
       conn)

      ;; Get
      (let ((result (handle-get-thoughts
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
      (let ((result (handle-create-branch
                     (make-msg "type" "create_branch"
                               "name" "feature-x"
                               "fromSnapshot" "snap-001")
                     conn)))
        (is (equal (gethash "type" result) "branch_created")))

      ;; List
      (let ((result (handle-list-branches
                     (make-msg "type" "list_branches") conn)))
        (is (equal (gethash "type" result) "branches"))
        (is (= (length (gethash "branches" result)) 1))))))

(test handler-subscribe-unsubscribe
  "Subscribe and unsubscribe to channels."
  (let ((conn (make-mock-connection)))
    ;; Subscribe
    (let ((result (handle-subscribe
                   (make-msg "type" "subscribe" "channel" "events")
                   conn)))
      (is (equal (gethash "type" result) "subscribed"))
      (is (equal (gethash "channel" result) "events")))

    ;; Verify subscription
    (is (connection-subscribed-p conn "events"))

    ;; Unsubscribe
    (handle-unsubscribe
     (make-msg "type" "unsubscribe" "channel" "events")
     conn)
    (is (not (connection-subscribed-p conn "events")))))

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
           (result (dispatch-message "totally_unknown" (make-msg) conn)))
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
      (is (= (connection-count) 1))
      (is (not (null (find-connection (connection-id conn)))))

      ;; Unregister
      (unregister-connection conn)
      (is (= (connection-count) 0))
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

;;; ═══════════════════════════════════════════════════════════════════
;;; Run All Tests
;;; ═══════════════════════════════════════════════════════════════════

(defun run-api-tests ()
  "Run all API tests."
  (run! 'api-tests))
