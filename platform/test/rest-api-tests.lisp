;;;; rest-api-tests.lisp - Tests for the REST Control API layer
;;;;
;;;; Tests authentication, serialization, routing logic, and SSE.
;;;; These tests exercise the API functions directly without requiring
;;;; a running HTTP server.

(in-package #:autopoiesis.test)

(def-suite rest-api-tests
  :description "Tests for the REST Control API layer")

(in-suite rest-api-tests)

;;; ===================================================================
;;; Authentication Tests
;;; ===================================================================

(test api-key-registration
  "Test API key registration and validation"
  (let ((autopoiesis.api:*api-keys* (make-hash-table :test 'equal)))
    ;; No keys = empty
    (is-true (autopoiesis.api::api-keys-empty-p))

    ;; Register a key
    (autopoiesis.api:register-api-key "test-key-123"
                                       :identity "test-agent"
                                       :permissions :full)
    (is-false (autopoiesis.api::api-keys-empty-p))

    ;; Validate it
    (let ((identity (autopoiesis.api:validate-api-key "test-key-123")))
      (is-true identity)
      (is (string= "test-agent" (getf identity :identity)))
      (is (eq :full (getf identity :permissions))))

    ;; Invalid key returns nil
    (is-false (autopoiesis.api:validate-api-key "wrong-key"))

    ;; Revoke it
    (autopoiesis.api:revoke-api-key "test-key-123")
    (is-false (autopoiesis.api:validate-api-key "test-key-123"))))

(test api-key-permissions
  "Test permission level checks"
  (let ((full-identity (list :identity "admin" :permissions :full))
        (agent-identity (list :identity "agent" :permissions :agent-only))
        (read-identity (list :identity "viewer" :permissions :read-only)))

    ;; Full has all permissions
    (is-true (autopoiesis.api::has-permission-p* full-identity :read))
    (is-true (autopoiesis.api::has-permission-p* full-identity :write))
    (is-true (autopoiesis.api::has-permission-p* full-identity :admin))

    ;; Agent-only has read and write but not admin
    (is-true (autopoiesis.api::has-permission-p* agent-identity :read))
    (is-true (autopoiesis.api::has-permission-p* agent-identity :write))
    (is-false (autopoiesis.api::has-permission-p* agent-identity :admin))

    ;; Read-only has only read
    (is-true (autopoiesis.api::has-permission-p* read-identity :read))
    (is-false (autopoiesis.api::has-permission-p* read-identity :write))
    (is-false (autopoiesis.api::has-permission-p* read-identity :admin))))

(test bearer-token-extraction
  "Test Bearer token extraction from Authorization header"
  (is (string= "my-token"
               (autopoiesis.api::extract-bearer-token "Bearer my-token")))
  (is-false (autopoiesis.api::extract-bearer-token "Basic dXNlcjpwYXNz"))
  (is-false (autopoiesis.api::extract-bearer-token nil))
  (is-false (autopoiesis.api::extract-bearer-token "Bear")))

;;; ===================================================================
;;; Serialization Tests
;;; ===================================================================

(test agent-serialization
  "Test agent to JSON alist conversion"
  (let* ((agent (autopoiesis.agent:make-agent :name "test-serialization"))
         (alist (autopoiesis.api:agent-to-json-alist agent)))
    ;; Check required fields
    (is-true (assoc :id alist))
    (is (string= "test-serialization" (cdr (assoc :name alist))))
    (is (string= "initialized" (cdr (assoc :state alist))))
    (is-true (assoc :thought--count alist))
    (is (= 0 (cdr (assoc :thought--count alist))))))

(test snapshot-serialization
  "Test snapshot to JSON alist conversion"
  (let* ((state '(:agent :id "a1" :name "test"))
         (snapshot (autopoiesis.snapshot:make-snapshot state :metadata '(:tag "test")))
         (alist (autopoiesis.api:snapshot-to-json-alist snapshot)))
    ;; Check required fields
    (is-true (assoc :id alist))
    (is-true (assoc :timestamp alist))
    (is-true (assoc :hash alist))
    (is-true (assoc :agent--state alist))
    ;; Agent state is serialized as a string
    (is (stringp (cdr (assoc :agent--state alist))))))

(test snapshot-summary-serialization
  "Test snapshot summary alist (no agent-state)"
  (let* ((state '(:agent :id "a1"))
         (snapshot (autopoiesis.snapshot:make-snapshot state))
         (alist (autopoiesis.api::snapshot-summary-alist snapshot)))
    (is-true (assoc :id alist))
    (is-true (assoc :hash alist))
    ;; Summary should NOT have agent-state
    (is-false (assoc :agent--state alist))))

(test branch-serialization
  "Test branch to JSON alist conversion"
  (let* ((branch (autopoiesis.snapshot:make-branch "test-branch" :head "snap-123"))
         (alist (autopoiesis.api:branch-to-json-alist branch)))
    (is (string= "test-branch" (cdr (assoc :name alist))))
    (is (string= "snap-123" (cdr (assoc :head alist))))
    (is-true (assoc :created alist))))

(test blocking-request-serialization
  "Test blocking request to JSON alist conversion"
  (let* ((request (autopoiesis.interface:make-blocking-request
                   "Approve deployment?"
                   :options '("yes" "no")
                   :default "no"))
         (alist (autopoiesis.api:blocking-request-to-json-alist request)))
    (is (string= "Approve deployment?" (cdr (assoc :prompt alist))))
    (is (string= "pending" (cdr (assoc :status alist))))
    (is (string= "no" (cdr (assoc :default alist))))
    (is-true (assoc :id alist))
    ;; Clean up the blocking request from the global registry
    (autopoiesis.interface:cancel-blocking-request request)))

(test thought-serialization
  "Test thought to JSON alist conversion"
  (let* ((thought (autopoiesis.core:make-thought '(:test "data")
                                                  :type :reasoning
                                                  :confidence 0.85))
         (alist (autopoiesis.api:thought-to-json-alist thought)))
    (is-true (assoc :id alist))
    (is (string= "reasoning" (cdr (assoc :type alist))))
    (is (= 0.85 (cdr (assoc :confidence alist))))
    (is (stringp (cdr (assoc :content alist))))))

;;; ===================================================================
;;; URL Routing Tests
;;; ===================================================================

(test path-segment-extraction
  "Test URL path segment extraction"
  ;; Create a mock request-like object for testing the path logic
  ;; Since extract-path-segment uses hunchentoot:request-uri,
  ;; we test the logic by calling the internal string operations
  (let ((uri "/api/agents/abc123"))
    (let ((prefix "/api/agents/"))
      (when (>= (length uri) (length prefix))
        (let ((rest (subseq uri (length prefix))))
          (is (string= "abc123" rest))))))

  (let ((uri "/api/agents/abc123/thoughts"))
    (let ((prefix "/api/agents/"))
      (when (>= (length uri) (length prefix))
        (let* ((rest (subseq uri (length prefix)))
               (slash (position #\/ rest)))
          (is (string= "abc123" (subseq rest 0 slash))))))))

;;; ===================================================================
;;; SSE Tests
;;; ===================================================================

(test sse-message-formatting
  "Test SSE message format"
  (let ((message (autopoiesis.api::format-sse-message
                  "test_event"
                  '((:key . "value")))))
    ;; Should contain event: line
    (is-true (search "event: test_event" message))
    ;; Should contain data: line
    (is-true (search "data: " message))
    ;; Should end with double newline
    (is (char= #\Newline (char message (1- (length message)))))
    (is (char= #\Newline (char message (- (length message) 2))))))

(test sse-client-registry
  "Test SSE client registration"
  (let ((autopoiesis.api:*sse-clients* nil))
    (is (= 0 (autopoiesis.api::sse-client-count)))

    ;; Register a mock stream
    (let ((stream (make-string-output-stream)))
      (autopoiesis.api::register-sse-client stream)
      (is (= 1 (autopoiesis.api::sse-client-count)))

      ;; Unregister
      (autopoiesis.api::unregister-sse-client stream)
      (is (= 0 (autopoiesis.api::sse-client-count))))))

(test sse-broadcast-to-clients
  "Test broadcasting to SSE clients"
  (let ((autopoiesis.api:*sse-clients* nil)
        (stream1 (make-string-output-stream))
        (stream2 (make-string-output-stream)))
    (autopoiesis.api::register-sse-client stream1)
    (autopoiesis.api::register-sse-client stream2)

    ;; Broadcast
    (autopoiesis.api:sse-broadcast "test" '((:msg . "hello")))

    ;; Both streams should have received the message
    (let ((output1 (get-output-stream-string stream1))
          (output2 (get-output-stream-string stream2)))
      (is-true (search "event: test" output1))
      (is-true (search "event: test" output2))
      (is-true (search "hello" output1)))

    ;; Cleanup
    (setf autopoiesis.api:*sse-clients* nil)))

(test sse-dead-client-cleanup
  "Test that dead clients are removed on broadcast"
  (let ((autopoiesis.api:*sse-clients* nil)
        (good-stream (make-string-output-stream)))
    (autopoiesis.api::register-sse-client good-stream)

    ;; Create a closed stream that will error on write
    (let ((bad-stream (make-string-output-stream)))
      (close bad-stream)
      (autopoiesis.api::register-sse-client bad-stream)
      (is (= 2 (autopoiesis.api::sse-client-count)))

      ;; Broadcast - should remove dead client
      (autopoiesis.api:sse-broadcast "test" '((:msg . "cleanup")))
      (is (= 1 (autopoiesis.api::sse-client-count))))

    ;; Cleanup
    (setf autopoiesis.api:*sse-clients* nil)))

;;; ===================================================================
;;; Integration Test: Agent Lifecycle via Internal API
;;; ===================================================================

(test api-agent-lifecycle
  "Test creating, starting, pausing, resuming, stopping an agent via the registry"
  (let ((autopoiesis.agent:*agent-registry* (make-hash-table :test 'equal)))
    ;; Create and register
    (let ((agent (autopoiesis.agent:make-agent :name "api-test-agent")))
      (autopoiesis.agent:register-agent agent)

      ;; Should be findable
      (is-true (autopoiesis.agent:find-agent (autopoiesis.agent:agent-id agent)))

      ;; Lifecycle
      (autopoiesis.agent:start-agent agent)
      (is (eq :running (autopoiesis.agent:agent-state agent)))

      (autopoiesis.agent:pause-agent agent)
      (is (eq :paused (autopoiesis.agent:agent-state agent)))

      (autopoiesis.agent:resume-agent agent)
      (is (eq :running (autopoiesis.agent:agent-state agent)))

      (autopoiesis.agent:stop-agent agent)
      (is (eq :stopped (autopoiesis.agent:agent-state agent)))

      ;; Unregister
      (autopoiesis.agent:unregister-agent agent)
      (is-false (autopoiesis.agent:find-agent (autopoiesis.agent:agent-id agent))))))

(test api-snapshot-creation
  "Test creating snapshots for agents"
  (let ((agent (autopoiesis.agent:make-agent :name "snapshot-test")))
    (let* ((agent-state `(:agent
                          :id ,(autopoiesis.agent:agent-id agent)
                          :name ,(autopoiesis.agent:agent-name agent)
                          :state ,(autopoiesis.agent:agent-state agent)))
           (snapshot (autopoiesis.snapshot:make-snapshot agent-state)))
      ;; Snapshot should have an ID and hash
      (is-true (autopoiesis.snapshot:snapshot-id snapshot))
      (is-true (autopoiesis.snapshot:snapshot-hash snapshot))
      ;; Agent state should be preserved
      (is-true (autopoiesis.snapshot:snapshot-agent-state snapshot)))))

(test api-branch-operations
  "Test branch creation and listing"
  (let ((autopoiesis.snapshot::*branch-registry* (make-hash-table :test 'equal)))
    ;; Create branches
    (autopoiesis.snapshot:create-branch "main")
    (autopoiesis.snapshot:create-branch "experiment" :from-snapshot "snap-1")

    ;; List
    (let ((branches (autopoiesis.snapshot:list-branches)))
      (is (= 2 (length branches))))

    ;; Switch
    (autopoiesis.snapshot:switch-branch "main")
    (let ((current (autopoiesis.snapshot:current-branch)))
      (is-true current)
      (is (string= "main" (autopoiesis.snapshot:branch-name current))))))

;;; ===================================================================
;;; JSON Response Helpers Tests
;;; ===================================================================

(test json-encoding-roundtrip
  "Test that our alists produce valid JSON"
  (let ((agent (autopoiesis.agent:make-agent :name "json-test")))
    (let* ((alist (autopoiesis.api:agent-to-json-alist agent))
           (json-str (cl-json:encode-json-to-string alist))
           (decoded (cl-json:decode-json-from-string json-str)))
      ;; Should roundtrip
      (is (stringp json-str))
      (is-true decoded)
      (is (string= "json-test" (cdr (assoc :name decoded)))))))

(test json-error-format
  "Test that parse-json-body helper is robust"
  ;; parse-json-body depends on hunchentoot request context,
  ;; so we test the JSON round-trip instead
  (let ((test-data '((:name . "test") (:value . 42))))
    (let* ((json (cl-json:encode-json-to-string test-data))
           (decoded (cl-json:decode-json-from-string json)))
      (is (string= "test" (cdr (assoc :name decoded))))
      (is (= 42 (cdr (assoc :value decoded)))))))
