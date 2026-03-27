;;;; integration-tests.lisp - Tests for integration layer
;;;;
;;;; Tests external integrations (mostly placeholder tests).

(in-package #:autopoiesis.test)

(def-suite integration-tests
  :description "Integration layer tests")

(in-suite integration-tests)

;;; ═══════════════════════════════════════════════════════════════════
;;; Message Format Tests
;;; ═══════════════════════════════════════════════════════════════════

(test message-formatting
  "Test message formatting for Claude API"
  (let ((msg (autopoiesis.integration::format-user-message "Hello")))
    (is (equal "user" (cdr (assoc "role" msg :test #'string=))))
    (is (equal "Hello" (cdr (assoc "content" msg :test #'string=))))))

(test tool-result-formatting
  "Test tool result message formatting"
  (let ((msg (autopoiesis.integration::format-tool-result "tool-123" "result data")))
    (is (equal "user" (cdr (assoc "role" msg :test #'string=))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Tool Registry Tests
;;; ═══════════════════════════════════════════════════════════════════

(test tool-registration
  "Test external tool registration"
  (let ((registry (make-hash-table :test 'equal))
        (tool (autopoiesis.integration:make-external-tool
               "test-tool"
               (lambda (x) (* x 2))
               :description "Doubles a number")))
    (autopoiesis.integration:register-external-tool tool :registry registry)
    (is (eq tool (autopoiesis.integration:find-external-tool "test-tool" :registry registry)))
    (is (= 2 (autopoiesis.integration:invoke-external-tool "test-tool" '(1) :registry registry)))))

(test tool-schema-generation
  "Test tool to Claude schema conversion"
  (let ((tool (autopoiesis.integration:make-external-tool
               "my-tool"
               #'identity
               :description "Does something")))
    (let ((schema (autopoiesis.integration::tool-to-claude-schema tool)))
      (is (equal "my-tool" (cdr (assoc "name" schema :test #'string=))))
      (is (equal "Does something" (cdr (assoc "description" schema :test #'string=)))))))

;;; ═══════════════════════════════════════════════════════════════════
;;; Configuration Tests
;;; ═══════════════════════════════════════════════════════════════════

(test config-operations
  "Test configuration get/set"
  (let ((config (make-hash-table :test 'equal)))
    (autopoiesis.integration::set-config :test-key "test-value" :config config)
    (is (equal "test-value"
               (autopoiesis.integration::get-config :test-key :config config)))
    (is (equal "default"
               (autopoiesis.integration::get-config :missing :config config :default "default")))))

;;; ===================================================================
;;; Claude Client Tests
;;; ===================================================================

(test claude-client-creation
  "Test creating a Claude client"
  (let ((client (autopoiesis.integration:make-claude-client
                 :api-key "test-key"
                 :model "claude-sonnet-4-20250514"
                 :max-tokens 2048)))
    (is (equal "test-key" (autopoiesis.integration:client-api-key client)))
    (is (equal "claude-sonnet-4-20250514" (autopoiesis.integration:client-model client)))
    (is (= 2048 (autopoiesis.integration:client-max-tokens client)))
    (is (equal "https://api.anthropic.com/v1" (autopoiesis.integration:client-base-url client)))))

(test claude-client-default-model
  "Test default model is set"
  (let ((client (autopoiesis.integration:make-claude-client :api-key "test-key")))
    (is (equal "claude-sonnet-4-20250514" (autopoiesis.integration:client-model client)))))

(test claude-request-body-building
  "Test building request body for Claude API"
  (let ((client (autopoiesis.integration:make-claude-client
                 :api-key "test-key"
                 :model "claude-sonnet-4-20250514"
                 :max-tokens 1024)))
    (let ((body (autopoiesis.integration::build-request-body
                 client
                 '((("role" . "user") ("content" . "Hello"))))))
      (is (equal "claude-sonnet-4-20250514" (cdr (assoc "model" body :test #'string=))))
      (is (= 1024 (cdr (assoc "max_tokens" body :test #'string=))))
      (is (consp (cdr (assoc "messages" body :test #'string=)))))))

(test claude-request-body-with-system
  "Test building request body with system prompt"
  (let ((client (autopoiesis.integration:make-claude-client :api-key "test-key")))
    (let ((body (autopoiesis.integration::build-request-body
                 client
                 '((("role" . "user") ("content" . "Hello")))
                 :system "You are a helpful assistant.")))
      (is (equal "You are a helpful assistant."
                 (cdr (assoc "system" body :test #'string=)))))))

(test claude-api-headers
  "Test API headers generation"
  (let* ((client (autopoiesis.integration:make-claude-client
                  :api-key "test-api-key"))
         (headers (autopoiesis.integration::make-api-headers client)))
    (is (equal "test-api-key" (cdr (assoc "x-api-key" headers :test #'string=))))
    (is (equal "2023-06-01" (cdr (assoc "anthropic-version" headers :test #'string=))))
    (is (equal "application/json" (cdr (assoc "content-type" headers :test #'string=))))))

(test claude-missing-api-key-error
  "Test error when API key is missing"
  (let ((client (make-instance 'autopoiesis.integration:claude-client)))
    (setf (autopoiesis.integration:client-api-key client) nil)
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration::send-api-request
       client "/messages" '(("model" . "test"))))))

(test response-text-extraction
  "Test extracting text from Claude response"
  (let ((response '((:content . (((:type . "text") (:text . "Hello world")))))))
    (is (equal "Hello world"
               (autopoiesis.integration:response-text response)))))

(test response-text-extraction-multiple
  "Test extracting multiple text blocks"
  (let ((response '((:content . (((:type . "text") (:text . "First "))
                                  ((:type . "text") (:text . "Second")))))))
    (is (equal "First Second"
               (autopoiesis.integration:response-text response)))))

(test response-tool-calls-extraction
  "Test extracting tool calls from Claude response"
  (let ((response '((:content . (((:type . "tool_use")
                                   (:id . "tool-123")
                                   (:name . "read_file")
                                   (:input . (("path" . "/tmp/test.txt")))))))))
    (let ((calls (autopoiesis.integration:response-tool-calls response)))
      (is (= 1 (length calls)))
      (let ((call (first calls)))
        (is (equal "tool-123" (getf call :id)))
        (is (equal "read_file" (getf call :name)))
        (is (consp (getf call :input)))))))

;;; ===================================================================
;;; Tool Mapping Tests
;;; ===================================================================

(test lisp-type-to-json-type-conversion
  "Test Lisp type to JSON type conversion"
  (is (equal "string" (autopoiesis.integration:lisp-type-to-json-type 'string)))
  (is (equal "integer" (autopoiesis.integration:lisp-type-to-json-type 'integer)))
  (is (equal "integer" (autopoiesis.integration:lisp-type-to-json-type 'fixnum)))
  (is (equal "number" (autopoiesis.integration:lisp-type-to-json-type 'float)))
  (is (equal "number" (autopoiesis.integration:lisp-type-to-json-type 'number)))
  (is (equal "boolean" (autopoiesis.integration:lisp-type-to-json-type 'boolean)))
  (is (equal "array" (autopoiesis.integration:lisp-type-to-json-type 'list)))
  (is (equal "object" (autopoiesis.integration:lisp-type-to-json-type 'hash-table)))
  ;; Unknown types default to string
  (is (equal "string" (autopoiesis.integration:lisp-type-to-json-type 'my-custom-type)))
  (is (equal "string" (autopoiesis.integration:lisp-type-to-json-type t)))
  (is (equal "string" (autopoiesis.integration:lisp-type-to-json-type nil))))

(test json-type-to-lisp-type-conversion
  "Test JSON type to Lisp type conversion"
  (is (eq 'string (autopoiesis.integration:json-type-to-lisp-type "string")))
  (is (eq 'integer (autopoiesis.integration:json-type-to-lisp-type "integer")))
  (is (eq 'number (autopoiesis.integration:json-type-to-lisp-type "number")))
  (is (eq 'boolean (autopoiesis.integration:json-type-to-lisp-type "boolean")))
  (is (eq 'list (autopoiesis.integration:json-type-to-lisp-type "array")))
  (is (eq 'hash-table (autopoiesis.integration:json-type-to-lisp-type "object")))
  (is (eq 'null (autopoiesis.integration:json-type-to-lisp-type "null")))
  ;; Unknown types default to T
  (is (eq t (autopoiesis.integration:json-type-to-lisp-type "unknown"))))

(test capability-params-to-json-schema
  "Test capability parameters to JSON schema conversion"
  (let* ((params '((path string :required t :doc "File path")
                   (encoding string :default "utf-8")))
         (schema (autopoiesis.integration:capability-params-to-json-schema params)))
    ;; Check top-level type
    (is (equal "object" (cdr (assoc "type" schema :test #'string=))))
    ;; Check properties exist
    (let ((properties (cdr (assoc "properties" schema :test #'string=))))
      (is (not (null properties)))
      ;; Check path property
      (let ((path-prop (cdr (assoc "path" properties :test #'string=))))
        (is (equal "string" (cdr (assoc "type" path-prop :test #'string=))))
        (is (equal "File path" (cdr (assoc "description" path-prop :test #'string=)))))
      ;; Check encoding property
      (let ((enc-prop (cdr (assoc "encoding" properties :test #'string=))))
        (is (equal "string" (cdr (assoc "type" enc-prop :test #'string=))))
        (is (equal "utf-8" (cdr (assoc "default" enc-prop :test #'string=))))))
    ;; Check required array
    (let ((required (cdr (assoc "required" schema :test #'string=))))
      (is (member "path" required :test #'string=))
      (is (not (member "encoding" required :test #'string=))))))

(test json-schema-to-capability-params
  "Test JSON schema to capability parameters conversion"
  (let* ((schema '(("type" . "object")
                   ("properties" . (("query" . (("type" . "string")
                                                ("description" . "Search query")))
                                    ("limit" . (("type" . "integer")
                                                ("default" . 10)))))
                   ("required" . ("query"))))
         (params (autopoiesis.integration:json-schema-to-capability-params schema)))
    (is (= 2 (length params)))
    ;; Check query param
    (let ((query-param (find :query params :key #'first)))
      (is (not (null query-param)))
      (is (eq 'string (second query-param)))
      (is (getf (cddr query-param) :required))
      (is (equal "Search query" (getf (cddr query-param) :doc))))
    ;; Check limit param
    (let ((limit-param (find :limit params :key #'first)))
      (is (not (null limit-param)))
      (is (eq 'integer (second limit-param)))
      (is (not (getf (cddr limit-param) :required)))
      (is (= 10 (getf (cddr limit-param) :default))))))

(test capability-to-claude-tool-conversion
  "Test capability to Claude tool format conversion"
  (let* ((cap (autopoiesis.agent:make-capability
               :read-file
               (lambda (&key path) (format nil "Reading ~a" path))
               :parameters '((path string :required t :doc "File to read"))
               :description "Read a file from disk"))
         (tool (autopoiesis.integration:capability-to-claude-tool cap)))
    ;; Check name - kebab-case converted to snake_case
    (is (equal "read_file" (cdr (assoc "name" tool :test #'string=))))
    ;; Check description
    (is (equal "Read a file from disk" (cdr (assoc "description" tool :test #'string=))))
    ;; Check schema
    (let ((schema (cdr (assoc "input_schema" tool :test #'string=))))
      (is (equal "object" (cdr (assoc "type" schema :test #'string=))))
      (let ((properties (cdr (assoc "properties" schema :test #'string=))))
        (is (not (null (assoc "path" properties :test #'string=))))))))

(test claude-tool-to-capability-conversion
  "Test Claude tool to capability conversion"
  (let* ((tool-def '(("name" . "write_file")
                     ("description" . "Write content to a file")
                     ("input_schema" . (("type" . "object")
                                        ("properties" . (("path" . (("type" . "string")))
                                                         ("content" . (("type" . "string")))))
                                        ("required" . ("path" "content"))))))
         (handler (lambda (&key path content)
                    (format nil "Wrote ~a bytes to ~a" (length content) path)))
         (cap (autopoiesis.integration:claude-tool-to-capability tool-def :handler handler)))
    (is (eq :write-file (autopoiesis.agent:capability-name cap)))
    (is (equal "Write content to a file" (autopoiesis.agent:capability-description cap)))
    ;; Test handler works
    (is (equal "Wrote 5 bytes to /tmp/x"
               (funcall (autopoiesis.agent:capability-function cap)
                        :path "/tmp/x" :content "hello")))))

(test execute-tool-call-success
  "Test successful tool call execution"
  (let* ((cap (autopoiesis.agent:make-capability
               :add-numbers
               (lambda (&key a b) (+ a b))
               :description "Add two numbers"))
         (capabilities (list cap))
         (tool-call '(:id "call-123" :name "add_numbers" :input (("a" . 5) ("b" . 3))))
         (result (autopoiesis.integration:execute-tool-call tool-call capabilities)))
    (is (equal "call-123" (getf result :tool-use-id)))
    (is (equal "8" (getf result :result)))
    (is (null (getf result :is-error)))))

(test execute-tool-call-unknown-tool
  "Test tool call with unknown tool"
  (let* ((capabilities nil)
         (tool-call '(:id "call-456" :name "unknown_tool" :input ()))
         (result (autopoiesis.integration:execute-tool-call tool-call capabilities)))
    (is (equal "call-456" (getf result :tool-use-id)))
    (is (search "Unknown tool" (getf result :result)))
    (is (getf result :is-error))))

(test execute-tool-call-error
  "Test tool call that raises an error"
  (let* ((cap (autopoiesis.agent:make-capability
               :divide
               (lambda (&key a b) (/ a b))
               :description "Divide a by b"))
         (capabilities (list cap))
         (tool-call '(:id "call-789" :name "divide" :input (("a" . 10) ("b" . 0))))
         (result (autopoiesis.integration:execute-tool-call tool-call capabilities)))
    (is (equal "call-789" (getf result :tool-use-id)))
    (is (search "Error:" (getf result :result)))
    (is (getf result :is-error))))

(test format-tool-results
  "Test formatting tool results for Claude API"
  (let* ((results '((:tool-use-id "call-1" :result "Success" :is-error nil)
                    (:tool-use-id "call-2" :result "Failed" :is-error t)))
         (message (autopoiesis.integration:format-tool-results results)))
    (is (equal "user" (cdr (assoc "role" message :test #'string=))))
    (let ((content (cdr (assoc "content" message :test #'string=))))
      (is (= 2 (length content)))
      ;; Check first result
      (let ((first-result (first content)))
        (is (equal "tool_result" (cdr (assoc "type" first-result :test #'string=))))
        (is (equal "call-1" (cdr (assoc "tool_use_id" first-result :test #'string=))))
        (is (equal "Success" (cdr (assoc "content" first-result :test #'string=))))
        (is (null (assoc "is_error" first-result :test #'string=))))
      ;; Check second result (with error)
      (let ((second-result (second content)))
        (is (equal "call-2" (cdr (assoc "tool_use_id" second-result :test #'string=))))
        (is (cdr (assoc "is_error" second-result :test #'string=)))))))

(test handle-tool-use-response-integration
  "Test handling a complete tool use response"
  (let* ((cap (autopoiesis.agent:make-capability
               :greet
               (lambda (&key name) (format nil "Hello, ~a!" name))
               :description "Greet someone"))
         (capabilities (list cap))
         (response '((:content . (((:type . "tool_use")
                                    (:id . "toolu_123")
                                    (:name . "greet")
                                    (:input . (("name" . "World"))))))))
         (result-message (autopoiesis.integration:handle-tool-use-response
                          response capabilities)))
    (is (not (null result-message)))
    (is (equal "user" (cdr (assoc "role" result-message :test #'string=))))
    (let* ((content (cdr (assoc "content" result-message :test #'string=)))
           (tool-result (first content)))
      (is (equal "tool_result" (cdr (assoc "type" tool-result :test #'string=))))
      (is (equal "toolu_123" (cdr (assoc "tool_use_id" tool-result :test #'string=))))
      (is (equal "Hello, World!" (cdr (assoc "content" tool-result :test #'string=)))))))

;;; ===================================================================
;;; Claude Session Management Tests
;;; ===================================================================

(test claude-session-creation
  "Test creating a Claude session"
  (let ((session (autopoiesis.integration:make-claude-session
                  :agent-id "agent-123"
                  :system-prompt "You are a test agent.")))
    (is (not (null (autopoiesis.integration:claude-session-id session))))
    (is (equal "agent-123" (autopoiesis.integration:claude-session-agent-id session)))
    (is (equal "You are a test agent." (autopoiesis.integration:claude-session-system-prompt session)))
    (is (null (autopoiesis.integration:claude-session-messages session)))
    (is (numberp (autopoiesis.integration:claude-session-created-at session)))))

(test claude-session-with-custom-id
  "Test creating Claude session with custom ID"
  (let ((session (autopoiesis.integration:make-claude-session
                  :id "custom-session-id"
                  :agent-id "agent-456")))
    (is (equal "custom-session-id" (autopoiesis.integration:claude-session-id session)))))

(test claude-session-registry-operations
  "Test Claude session registry find and delete"
  ;; Clear registry for test isolation
  (clrhash autopoiesis.integration:*claude-session-registry*)
  (let ((session (autopoiesis.integration:make-claude-session :agent-id "test-agent")))
    ;; Register manually
    (setf (gethash (autopoiesis.integration:claude-session-id session)
                   autopoiesis.integration:*claude-session-registry*)
          session)
    ;; Find it
    (is (eq session (autopoiesis.integration:find-claude-session
                     (autopoiesis.integration:claude-session-id session))))
    ;; Delete it
    (is (autopoiesis.integration:delete-claude-session
         (autopoiesis.integration:claude-session-id session)))
    ;; Should be gone
    (is (null (autopoiesis.integration:find-claude-session
               (autopoiesis.integration:claude-session-id session))))))

(test claude-session-add-message
  "Test adding messages to a Claude session"
  (let ((session (autopoiesis.integration:make-claude-session)))
    ;; Add user message
    (autopoiesis.integration:claude-session-add-message session "user" "Hello!")
    (is (= 1 (length (autopoiesis.integration:claude-session-messages session))))
    ;; Add assistant message
    (autopoiesis.integration:claude-session-add-message session "assistant" "Hi there!")
    (is (= 2 (length (autopoiesis.integration:claude-session-messages session))))
    ;; Verify message structure
    (let ((first-msg (first (autopoiesis.integration:claude-session-messages session))))
      (is (equal "user" (cdr (assoc "role" first-msg :test #'string=))))
      (is (equal "Hello!" (cdr (assoc "content" first-msg :test #'string=)))))))

(test claude-session-add-assistant-response
  "Test adding Claude API response to session"
  (let ((session (autopoiesis.integration:make-claude-session))
        (response '((:content . (((:type . "text") (:text . "Response text")))))))
    (autopoiesis.integration:claude-session-add-assistant-response session response)
    (is (= 1 (length (autopoiesis.integration:claude-session-messages session))))
    (let ((msg (first (autopoiesis.integration:claude-session-messages session))))
      (is (equal "assistant" (cdr (assoc "role" msg :test #'string=)))))))

(test claude-session-add-tool-results
  "Test adding tool results to Claude session"
  (let ((session (autopoiesis.integration:make-claude-session))
        (results '((:tool-use-id "tool-1" :result "Done" :is-error nil))))
    (autopoiesis.integration:claude-session-add-tool-results session results)
    (is (= 1 (length (autopoiesis.integration:claude-session-messages session))))
    (let ((msg (first (autopoiesis.integration:claude-session-messages session))))
      (is (equal "user" (cdr (assoc "role" msg :test #'string=)))))))

(test claude-session-clear-messages
  "Test clearing Claude session messages"
  (let ((session (autopoiesis.integration:make-claude-session)))
    (autopoiesis.integration:claude-session-add-message session "user" "Test")
    (autopoiesis.integration:claude-session-add-message session "assistant" "Reply")
    (is (= 2 (length (autopoiesis.integration:claude-session-messages session))))
    (autopoiesis.integration:claude-session-clear-messages session)
    (is (null (autopoiesis.integration:claude-session-messages session)))))

(test claude-session-serialization
  "Test Claude session serialization and deserialization"
  (let* ((session (autopoiesis.integration:make-claude-session
                   :id "ser-test"
                   :agent-id "agent-ser"
                   :system-prompt "Test prompt"))
         (sexpr (autopoiesis.integration:claude-session-to-sexpr session))
         (restored (autopoiesis.integration:sexpr-to-claude-session sexpr)))
    (is (equal "ser-test" (autopoiesis.integration:claude-session-id restored)))
    (is (equal "agent-ser" (autopoiesis.integration:claude-session-agent-id restored)))
    (is (equal "Test prompt" (autopoiesis.integration:claude-session-system-prompt restored)))))

(test claude-session-serialization-with-messages
  "Test Claude session serialization preserves messages"
  (let ((session (autopoiesis.integration:make-claude-session)))
    (autopoiesis.integration:claude-session-add-message session "user" "Hello")
    (autopoiesis.integration:claude-session-add-message session "assistant" "Hi")
    (let* ((sexpr (autopoiesis.integration:claude-session-to-sexpr session))
           (restored (autopoiesis.integration:sexpr-to-claude-session sexpr)))
      (is (= 2 (length (autopoiesis.integration:claude-session-messages restored)))))))

(test generate-system-prompt
  "Test system prompt generation for agent"
  (let* ((agent (autopoiesis.agent:make-agent :name "TestBot"))
         (prompt (autopoiesis.integration:generate-system-prompt agent)))
    (is (stringp prompt))
    (is (search "TestBot" prompt))
    (is (search "Autopoiesis" prompt))))

(test create-claude-session-for-agent
  "Test creating and registering Claude session for agent"
  ;; Clear registries
  (clrhash autopoiesis.integration:*claude-session-registry*)
  (clrhash autopoiesis.integration::*agent-claude-session-map*)
  (let* ((agent (autopoiesis.agent:make-agent :name "SessionTestAgent"))
         (session (autopoiesis.integration:create-claude-session-for-agent agent)))
    ;; Session should be registered
    (is (eq session (autopoiesis.integration:find-claude-session
                     (autopoiesis.integration:claude-session-id session))))
    ;; Should be findable by agent ID
    (is (eq session (autopoiesis.integration:find-claude-session-for-agent
                     (autopoiesis.agent:agent-id agent))))
    ;; Should have system prompt
    (is (not (null (autopoiesis.integration:claude-session-system-prompt session))))))

(test list-claude-sessions
  "Test listing all Claude sessions"
  ;; Clear registry
  (clrhash autopoiesis.integration:*claude-session-registry*)
  (let ((s1 (autopoiesis.integration:make-claude-session :id "s1"))
        (s2 (autopoiesis.integration:make-claude-session :id "s2")))
    ;; Register them
    (setf (gethash "s1" autopoiesis.integration:*claude-session-registry*) s1)
    (setf (gethash "s2" autopoiesis.integration:*claude-session-registry*) s2)
    (let ((sessions (autopoiesis.integration:list-claude-sessions)))
      (is (= 2 (length sessions)))
      (is (member s1 sessions))
      (is (member s2 sessions)))))

;;; ===================================================================
;;; Name Conversion Tests
;;; ===================================================================

(test lisp-name-to-tool-name-conversion
  "Test converting Lisp names to Claude tool names (kebab-case to snake_case)"
  ;; Keyword symbols
  (is (equal "read_file" (autopoiesis.integration:lisp-name-to-tool-name :read-file)))
  (is (equal "get_user_info" (autopoiesis.integration:lisp-name-to-tool-name :get-user-info)))
  (is (equal "simple" (autopoiesis.integration:lisp-name-to-tool-name :simple)))
  ;; Strings
  (is (equal "read_file" (autopoiesis.integration:lisp-name-to-tool-name "read-file")))
  (is (equal "read_file" (autopoiesis.integration:lisp-name-to-tool-name "READ-FILE")))
  ;; Regular symbols
  (is (equal "some_function" (autopoiesis.integration:lisp-name-to-tool-name 'some-function))))

(test tool-name-to-lisp-name-conversion
  "Test converting Claude tool names to Lisp names (snake_case to kebab-case)"
  (is (eq :read-file (autopoiesis.integration:tool-name-to-lisp-name "read_file")))
  (is (eq :get-user-info (autopoiesis.integration:tool-name-to-lisp-name "get_user_info")))
  (is (eq :simple (autopoiesis.integration:tool-name-to-lisp-name "simple")))
  ;; Uppercase input should still work
  (is (eq :read-file (autopoiesis.integration:tool-name-to-lisp-name "READ_FILE"))))

(test name-conversion-roundtrip
  "Test that name conversion roundtrips correctly"
  (let ((lisp-names '(:read-file :get-user-info :simple :complex-multi-word-name)))
    (dolist (name lisp-names)
      (let* ((tool-name (autopoiesis.integration:lisp-name-to-tool-name name))
             (back (autopoiesis.integration:tool-name-to-lisp-name tool-name)))
        (is (eq name back)
            "Name ~a should roundtrip through ~a" name tool-name)))))

;;; ===================================================================
;;; Mocked Claude API Tests
;;; ===================================================================

(defvar *mock-http-response* nil
  "Mock response for HTTP requests in tests.")

(defvar *mock-http-status* 200
  "Mock status code for HTTP requests in tests.")

(defvar *captured-http-requests* nil
  "List of captured HTTP requests during mocked tests.")

(defmacro with-mocked-http ((&key response status) &body body)
  "Execute BODY with HTTP calls mocked.

   RESPONSE - The response body to return (alist that will be JSON-encoded)
   STATUS - The HTTP status code to return (default 200)

   Mocks both llm-http-post (used by llm-complete protocol) and
   send-api-request (legacy path) so all API calls are intercepted."
  `(let ((*mock-http-response* ,response)
         (*mock-http-status* (or ,status 200))
         (*captured-http-requests* nil))
     ;; Mock llm-http-post (the shared transport used by llm-complete)
     (let ((original-llm-fn (symbol-function 'autopoiesis.integration::llm-http-post))
           (original-send-fn (symbol-function 'autopoiesis.integration::send-api-request)))
       (unwind-protect
            (progn
              (setf (symbol-function 'autopoiesis.integration::llm-http-post)
                    (lambda (client url body)
                      (declare (ignore client))
                      (let ((json-body (cl-json:encode-json-to-string body)))
                        (push (list :url url :headers nil :content json-body)
                              *captured-http-requests*)
                        (if (and (>= *mock-http-status* 200)
                                 (< *mock-http-status* 300))
                            *mock-http-response*
                            (error 'autopoiesis.core:autopoiesis-error
                                   :message (format nil "API error (~a)" *mock-http-status*))))))
              ;; Also mock send-api-request for any legacy callers
              (setf (symbol-function 'autopoiesis.integration::send-api-request)
                    (lambda (client endpoint body)
                      (declare (ignore client))
                      (let* ((json-body (cl-json:encode-json-to-string body)))
                        (push (list :url endpoint :headers nil :content json-body)
                              *captured-http-requests*)
                        (if (and (>= *mock-http-status* 200)
                                 (< *mock-http-status* 300))
                            *mock-http-response*
                            (error 'autopoiesis.core:autopoiesis-error
                                   :message (format nil "API error (~a)" *mock-http-status*))))))
              ,@body)
         (setf (symbol-function 'autopoiesis.integration::llm-http-post)
               original-llm-fn)
         (setf (symbol-function 'autopoiesis.integration::send-api-request)
               original-send-fn)))))

(test mocked-claude-complete-simple
  "Test claude-complete with mocked HTTP response"
  (let ((mock-response '((:id . "msg_123")
                         (:type . "message")
                         (:role . "assistant")
                         (:content . (((:type . "text")
                                        (:text . "Hello! How can I help you?"))))
                         (:model . "claude-sonnet-4-20250514")
                         (:stop--reason . "end_turn"))))
    (with-mocked-http (:response mock-response)
      (let* ((client (autopoiesis.integration:make-claude-client :api-key "test-key"))
             (messages '((("role" . "user") ("content" . "Hello"))))
             (response (autopoiesis.integration:claude-complete client messages)))
        ;; Check response structure
        (is (equal "msg_123" (cdr (assoc :id response))))
        (is (equal "assistant" (cdr (assoc :role response))))
        ;; Check that we captured the request
        (is (= 1 (length *captured-http-requests*)))
        (let ((req (first *captured-http-requests*)))
          (is (search "/messages" (getf req :url))))))))

(test mocked-claude-complete-with-system-prompt
  "Test claude-complete includes system prompt in request"
  (with-mocked-http (:response '((:content . (((:type . "text") (:text . "OK"))))))
    (let* ((client (autopoiesis.integration:make-claude-client :api-key "test-key"))
           (messages '((("role" . "user") ("content" . "Test")))))
      (autopoiesis.integration:claude-complete client messages
                                               :system "You are a test assistant.")
      ;; Verify the request included system prompt
      (let* ((req (first *captured-http-requests*))
             (body (cl-json:decode-json-from-string (getf req :content))))
        (is (equal "You are a test assistant."
                   (cdr (assoc :system body))))))))

(test mocked-claude-complete-with-tools
  "Test claude-complete includes tools in request"
  (with-mocked-http (:response '((:content . (((:type . "text") (:text . "OK"))))))
    (let* ((client (autopoiesis.integration:make-claude-client :api-key "test-key"))
           (messages '((("role" . "user") ("content" . "Read /tmp/test.txt"))))
           (tools '((("name" . "read_file")
                     ("description" . "Read a file")
                     ("input_schema" . (("type" . "object")))))))
      (autopoiesis.integration:claude-complete client messages :tools tools)
      ;; Verify the request included tools
      (let* ((req (first *captured-http-requests*))
             (body (cl-json:decode-json-from-string (getf req :content))))
        (is (not (null (cdr (assoc :tools body)))))))))

(test mocked-claude-complete-tool-use-response
  "Test handling a tool use response from Claude"
  (let ((mock-response '((:id . "msg_456")
                         (:content . (((:type . "text")
                                        (:text . "I'll read that file."))
                                       ((:type . "tool_use")
                                        (:id . "toolu_abc123")
                                        (:name . "read_file")
                                        (:input . (("path" . "/tmp/test.txt"))))))
                         (:stop--reason . "tool_use"))))
    (with-mocked-http (:response mock-response)
      (let* ((client (autopoiesis.integration:make-claude-client :api-key "test-key"))
             (response (autopoiesis.integration:claude-complete
                        client
                        '((("role" . "user") ("content" . "Read /tmp/test.txt"))))))
        ;; Check stop reason
        (is (equal "tool_use" (autopoiesis.integration:response-stop-reason response)))
        ;; Check text extraction
        (is (equal "I'll read that file."
                   (autopoiesis.integration:response-text response)))
        ;; Check tool calls extraction
        (let ((tool-calls (autopoiesis.integration:response-tool-calls response)))
          (is (= 1 (length tool-calls)))
          (let ((call (first tool-calls)))
            (is (equal "toolu_abc123" (getf call :id)))
            (is (equal "read_file" (getf call :name)))
            (is (equal "/tmp/test.txt"
                       (cdr (assoc "path" (getf call :input) :test #'string=))))))))))

(test claude-stream-not-implemented
  "Test that claude-stream signals an error (not yet implemented)"
  (let ((client (autopoiesis.integration:make-claude-client :api-key "test-key")))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration:claude-stream
       client
       '((("role" . "user") ("content" . "Hello")))
       (lambda (chunk) (declare (ignore chunk)))))))

;;; ===================================================================
;;; Full Conversation Flow Tests (Mocked)
;;; ===================================================================

(test mocked-conversation-with-tool-use
  "Test a complete conversation flow with tool use (mocked)"
  (let* ((read-file-called nil)
         (cap (autopoiesis.agent:make-capability
               :read-file
               (lambda (&key path)
                 (setf read-file-called t)
                 (format nil "Contents of ~a" path))
               :description "Read a file"
               :parameters '((path string :required t))))
         (capabilities (list cap))
         ;; First response: tool use
         (tool-response '((:content . (((:type . "tool_use")
                                         (:id . "toolu_test")
                                         (:name . "read_file")
                                         (:input . (("path" . "/test.txt"))))))
                          (:stop--reason . "tool_use")))
         ;; Second response: final answer
         (final-response '((:content . (((:type . "text")
                                          (:text . "The file contains: Contents of /test.txt"))))
                           (:stop--reason . "end_turn"))))
    ;; Simulate the conversation flow
    (with-mocked-http (:response tool-response)
      (let* ((client (autopoiesis.integration:make-claude-client :api-key "test-key"))
             (response1 (autopoiesis.integration:claude-complete
                         client
                         '((("role" . "user") ("content" . "Read /test.txt"))))))
        ;; Handle tool use
        (let ((result-message (autopoiesis.integration:handle-tool-use-response
                               response1 capabilities)))
          ;; Tool should have been called
          (is (eq t read-file-called))
          ;; Result message should be formatted correctly
          (is (equal "user" (cdr (assoc "role" result-message :test #'string=))))
          (let* ((content (cdr (assoc "content" result-message :test #'string=)))
                 (tool-result (first content)))
            (is (equal "tool_result" (cdr (assoc "type" tool-result :test #'string=))))
            (is (equal "toolu_test" (cdr (assoc "tool_use_id" tool-result :test #'string=))))
            (is (equal "Contents of /test.txt"
                       (cdr (assoc "content" tool-result :test #'string=))))))))))

(test mocked-session-conversation-flow
  "Test a conversation using Claude session management (mocked)"
  (let ((mock-response '((:content . (((:type . "text")
                                        (:text . "Hello! I'm here to help."))))
                         (:stop--reason . "end_turn"))))
    ;; Clear registries
    (clrhash autopoiesis.integration:*claude-session-registry*)
    (clrhash autopoiesis.integration::*agent-claude-session-map*)
    (with-mocked-http (:response mock-response)
      (let* ((client (autopoiesis.integration:make-claude-client :api-key "test-key"))
             (session (autopoiesis.integration:make-claude-session
                       :system-prompt "You are a helpful assistant.")))
        ;; Add user message
        (autopoiesis.integration:claude-session-add-message session "user" "Hello!")
        (is (= 1 (length (autopoiesis.integration:claude-session-messages session))))
        ;; Send to Claude
        (let ((response (autopoiesis.integration:claude-complete
                         client
                         (autopoiesis.integration:claude-session-messages session)
                         :system (autopoiesis.integration:claude-session-system-prompt session))))
          ;; Add response to session
          (autopoiesis.integration:claude-session-add-assistant-response session response)
          (is (= 2 (length (autopoiesis.integration:claude-session-messages session))))
          ;; Verify the assistant message was added
          (let ((last-msg (car (last (autopoiesis.integration:claude-session-messages session)))))
            (is (equal "assistant" (cdr (assoc "role" last-msg :test #'string=))))))))))

(test mocked-multi-turn-tool-conversation
  "Test multi-turn conversation with multiple tool calls (mocked)"
  (let* ((call-count 0)
         (cap (autopoiesis.agent:make-capability
               :calculate
               (lambda (&key a b op)
                 (incf call-count)
                 (cond
                   ((string= op "add") (+ a b))
                   ((string= op "multiply") (* a b))
                   (t (error "Unknown operation"))))
               :description "Perform calculation"))
         (capabilities (list cap)))
    ;; Mock response with two tool calls
    (let ((response '((:content . (((:type . "tool_use")
                                     (:id . "calc1")
                                     (:name . "calculate")
                                     (:input . (("a" . 5) ("b" . 3) ("op" . "add"))))
                                    ((:type . "tool_use")
                                     (:id . "calc2")
                                     (:name . "calculate")
                                     (:input . (("a" . 4) ("b" . 7) ("op" . "multiply"))))))
                       (:stop--reason . "tool_use"))))
      ;; Execute all tool calls
      (let ((results (autopoiesis.integration:execute-all-tool-calls response capabilities)))
        ;; Should have called capability twice
        (is (= 2 call-count))
        (is (= 2 (length results)))
        ;; Check results
        (let ((r1 (find "calc1" results :key (lambda (r) (getf r :tool-use-id)) :test #'string=))
              (r2 (find "calc2" results :key (lambda (r) (getf r :tool-use-id)) :test #'string=)))
          (is (equal "8" (getf r1 :result)))  ; 5 + 3
          (is (equal "28" (getf r2 :result))) ; 4 * 7
          (is (null (getf r1 :is-error)))
          (is (null (getf r2 :is-error))))))))

;;; ===================================================================
;;; API Error Handling Tests (Mocked)
;;; ===================================================================

(test mocked-api-error-handling
  "Test handling of API errors"
  (with-mocked-http (:response '((:error . ((:message . "Rate limit exceeded"))))
                     :status 429)
    (let ((client (autopoiesis.integration:make-claude-client :api-key "test-key")))
      (signals autopoiesis.core:autopoiesis-error
        (autopoiesis.integration:claude-complete
         client
         '((("role" . "user") ("content" . "Hello"))))))))

;;; ===================================================================
;;; MCP Client Tests
;;; ===================================================================

(test mcp-server-creation
  "Test creating an MCP server configuration"
  (let ((server (autopoiesis.integration:make-mcp-server
                 "test-server"
                 "echo"
                 :args '("hello")
                 :working-directory "/tmp")))
    (is (equal "test-server" (autopoiesis.integration:mcp-name server)))
    (is (equal "echo" (autopoiesis.integration:mcp-command server)))
    (is (equal '("hello") (autopoiesis.integration:mcp-args server)))
    (is (not (autopoiesis.integration:mcp-connected-p server)))
    (is (null (autopoiesis.integration:mcp-tools server)))))

(test mcp-server-registry
  "Test MCP server registry operations"
  ;; Clear registry for test isolation
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((server (autopoiesis.integration:make-mcp-server "registry-test" "echo")))
    ;; Initially not registered
    (is (null (autopoiesis.integration:find-mcp-server "registry-test")))
    ;; Register
    (autopoiesis.integration:register-mcp-server server)
    (is (eq server (autopoiesis.integration:find-mcp-server "registry-test")))
    ;; List
    (is (member server (autopoiesis.integration:list-mcp-servers)))
    ;; Unregister
    (autopoiesis.integration:unregister-mcp-server "registry-test")
    (is (null (autopoiesis.integration:find-mcp-server "registry-test")))))

(test mcp-jsonrpc-request-creation
  "Test JSON-RPC request creation"
  (let ((req (autopoiesis.integration::make-jsonrpc-request 1 "test/method")))
    (is (equal "2.0" (cdr (assoc "jsonrpc" req :test #'string=))))
    (is (= 1 (cdr (assoc "id" req :test #'string=))))
    (is (equal "test/method" (cdr (assoc "method" req :test #'string=)))))
  ;; With params
  (let ((req (autopoiesis.integration::make-jsonrpc-request 2 "method"
               '(("arg1" . "value1")))))
    (is (consp (cdr (assoc "params" req :test #'string=))))))

(test mcp-jsonrpc-notification-creation
  "Test JSON-RPC notification creation"
  (let ((notif (autopoiesis.integration::make-jsonrpc-notification "notify/done")))
    (is (equal "2.0" (cdr (assoc "jsonrpc" notif :test #'string=))))
    (is (null (assoc "id" notif :test #'string=)))
    (is (equal "notify/done" (cdr (assoc "method" notif :test #'string=))))))

(test mcp-disconnected-server-errors
  "Test that operations on disconnected server raise errors"
  (let ((server (autopoiesis.integration:make-mcp-server "offline" "echo")))
    ;; list-tools should error
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration:mcp-list-tools server))
    ;; call-tool should error
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration:mcp-call-tool server "test" nil))
    ;; get-resource should error
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration:mcp-get-resource server "file:///test"))))

(test mcp-server-status
  "Test MCP server status reporting"
  (let* ((server (autopoiesis.integration:make-mcp-server
                  "status-test" "cmd"
                  :args '("arg1" "arg2")))
         (status (autopoiesis.integration:mcp-server-status server)))
    (is (equal "status-test" (getf status :name)))
    (is (not (getf status :connected)))
    (is (equal "cmd" (getf status :command)))
    (is (equal '("arg1" "arg2") (getf status :args)))
    (is (= 0 (getf status :tools-count)))))

(test mcp-connect-mcp-server-config
  "Test connect-mcp-server-config creates server correctly"
  ;; We can't actually connect (no real server), but we can test that
  ;; the config is parsed correctly by checking what errors
  (let ((config '(:name "config-test"
                  :command "/nonexistent/binary"
                  :args ("--stdio")
                  :working-directory "/tmp")))
    ;; Should fail because binary doesn't exist
    (signals error
      (autopoiesis.integration:connect-mcp-server-config config))))

(test mcp-tool-to-capability-conversion
  "Test converting MCP tool definition to capability"
  ;; Clear registry for test isolation
  (clrhash autopoiesis.integration:*mcp-servers*)
  ;; Create and register a mock server (not connected but in registry)
  (let* ((server (autopoiesis.integration:make-mcp-server "mock-server" "echo")))
    (autopoiesis.integration:register-mcp-server server)
    (let* ((tool '((:name . "read_file")
                   (:description . "Read a file from disk")
                   (:input-schema . (("type" . "object")
                                     ("properties" . (("path" . (("type" . "string")
                                                                 ("description" . "File path")))))
                                     ("required" . ("path"))))))
           (cap (autopoiesis.integration:mcp-tool-to-capability tool "mock-server")))
      ;; Check capability properties
      (is (eq :read-file (autopoiesis.agent:capability-name cap)))
      ;; Description should include MCP server info
      (is (search "Read a file from disk" (autopoiesis.agent:capability-description cap)))
      (is (search "mock-server" (autopoiesis.agent:capability-description cap)))
      ;; Check parameters were converted
      (let ((params (autopoiesis.agent:capability-parameters cap)))
        (is (not (null params)))
        (let ((path-param (find :path params :key #'first)))
          (is (not (null path-param)))
          (is (eq 'string (second path-param))))))))

(test mcp-register-tools-as-capabilities
  "Test registering MCP tools as capabilities"
  ;; Clear registries
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((test-registry (make-hash-table :test 'eq)))
    ;; Create a server with mock tools
    (let ((server (autopoiesis.integration:make-mcp-server "tool-reg-test" "echo")))
      ;; Manually set tools (since we can't connect)
      (setf (autopoiesis.integration:mcp-tools server)
            '(((:name . "tool_one") (:description . "First tool"))
              ((:name . "tool_two") (:description . "Second tool"))))
      (autopoiesis.integration:register-mcp-server server)
      ;; Register as capabilities
      (let ((caps (autopoiesis.integration:register-mcp-tools-as-capabilities
                   server :registry test-registry)))
        (is (= 2 (length caps)))
        ;; Check they're in the registry
        (is (not (null (autopoiesis.agent:find-capability :tool-one :registry test-registry))))
        (is (not (null (autopoiesis.agent:find-capability :tool-two :registry test-registry))))
        ;; Unregister
        (autopoiesis.integration:unregister-mcp-tools server :registry test-registry)
        (is (null (autopoiesis.agent:find-capability :tool-one :registry test-registry)))
        (is (null (autopoiesis.agent:find-capability :tool-two :registry test-registry)))))))

;;; ===================================================================
;;; MCP Protocol Mocking Tests
;;; ===================================================================

;;; These tests mock the I/O to test protocol handling

(defun make-mock-mcp-server ()
  "Create an MCP server with mocked streams for testing."
  (let* ((input-string (make-string-output-stream))
         (server (autopoiesis.integration:make-mcp-server "mock" "echo")))
    ;; Mark as connected without actually connecting
    (setf (autopoiesis.integration::mcp-connected-p server) t)
    server))

(test mcp-request-id-incrementing
  "Test that request IDs increment properly"
  (let ((server (make-mock-mcp-server)))
    (is (= 1 (autopoiesis.integration::next-request-id server)))
    (is (= 2 (autopoiesis.integration::next-request-id server)))
    (is (= 3 (autopoiesis.integration::next-request-id server)))))

(test mcp-disconnect-all
  "Test disconnecting all MCP servers"
  ;; Clear and add some test servers
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((s1 (autopoiesis.integration:make-mcp-server "s1" "echo"))
        (s2 (autopoiesis.integration:make-mcp-server "s2" "echo")))
    (autopoiesis.integration:register-mcp-server s1)
    (autopoiesis.integration:register-mcp-server s2)
    (is (= 2 (hash-table-count autopoiesis.integration:*mcp-servers*)))
    ;; Disconnect all
    (autopoiesis.integration:disconnect-all-mcp-servers)
    (is (= 0 (hash-table-count autopoiesis.integration:*mcp-servers*)))))

;;; ===================================================================
;;; MCP Resource Handling Tests
;;; ===================================================================

(test mcp-list-resources-disconnected-error
  "Test that list-resources errors on disconnected server"
  (let ((server (autopoiesis.integration:make-mcp-server "offline" "echo")))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration:mcp-list-resources server))))

(test mcp-get-resource-disconnected-error
  "Test that get-resource errors on disconnected server"
  (let ((server (autopoiesis.integration:make-mcp-server "offline" "echo")))
    (signals autopoiesis.core:autopoiesis-error
      (autopoiesis.integration:mcp-get-resource server "file:///test.txt"))))

(test mcp-resources-cached
  "Test that resources are cached after discovery"
  (let ((server (make-mock-mcp-server)))
    ;; Manually set resources (simulating discovery)
    (setf (autopoiesis.integration:mcp-resources server)
          '(((:uri . "file:///config.json")
             (:name . "config")
             (:description . "Configuration file")
             (:mime-type . "application/json"))
            ((:uri . "file:///readme.md")
             (:name . "readme")
             (:description . "Documentation"))))
    ;; mcp-list-resources should return cached value
    (let ((resources (autopoiesis.integration:mcp-resources server)))
      (is (= 2 (length resources)))
      ;; Check first resource
      (let ((first-res (first resources)))
        (is (equal "file:///config.json" (cdr (assoc :uri first-res))))
        (is (equal "config" (cdr (assoc :name first-res))))
        (is (equal "Configuration file" (cdr (assoc :description first-res))))
        (is (equal "application/json" (cdr (assoc :mime-type first-res)))))
      ;; Check second resource
      (let ((second-res (second resources)))
        (is (equal "file:///readme.md" (cdr (assoc :uri second-res))))
        (is (equal "readme" (cdr (assoc :name second-res))))))))

(test mcp-server-status-includes-resources
  "Test that MCP server status includes resource count"
  (let ((server (autopoiesis.integration:make-mcp-server "status-res" "cmd")))
    ;; Set some mock resources
    (setf (autopoiesis.integration:mcp-resources server)
          '(((:uri . "res1")) ((:uri . "res2")) ((:uri . "res3"))))
    (let ((status (autopoiesis.integration:mcp-server-status server)))
      (is (= 3 (getf status :resources-count))))))

(test mcp-discover-resources-checks-capabilities
  "Test that discover-resources respects server capabilities"
  (let ((server (make-mock-mcp-server)))
    ;; Server with no resource capability
    (setf (autopoiesis.integration:mcp-server-capabilities server)
          '((:tools . t)))  ; No :resources capability
    ;; discover-resources should return nil without making a request
    (is (null (autopoiesis.integration::mcp-discover-resources server)))
    (is (null (autopoiesis.integration:mcp-resources server)))))

(test mcp-resource-uri-format
  "Test that resource URIs are handled correctly"
  ;; This test verifies our understanding of MCP resource URIs
  (let ((server (make-mock-mcp-server)))
    (setf (autopoiesis.integration:mcp-resources server)
          '(((:uri . "file:///home/user/doc.txt")
             (:name . "doc"))
            ((:uri . "https://example.com/api/config")
             (:name . "remote-config"))
            ((:uri . "custom://internal/resource")
             (:name . "internal"))))
    ;; Check different URI schemes are preserved
    (let ((resources (autopoiesis.integration:mcp-resources server)))
      (is (equal "file:///home/user/doc.txt"
                 (cdr (assoc :uri (first resources)))))
      (is (equal "https://example.com/api/config"
                 (cdr (assoc :uri (second resources)))))
      (is (equal "custom://internal/resource"
                 (cdr (assoc :uri (third resources))))))))

;;; ===================================================================
;;; Mocked MCP Protocol Tests
;;; ===================================================================

;;; These tests simulate full MCP protocol interactions using mocked I/O streams

(defclass mock-mcp-test-harness ()
  ((server :accessor mock-server :initform nil)
   (responses :accessor mock-responses :initform nil
              :documentation "Queue of responses to return")
   (requests :accessor mock-requests :initform nil
             :documentation "Captured requests")
   (input-string :accessor mock-input-string)
   (output-string :accessor mock-output-string))
  (:documentation "Test harness for mocking MCP server I/O"))

(defun make-mock-test-harness ()
  "Create a test harness with mocked streams."
  (let ((harness (make-instance 'mock-mcp-test-harness)))
    (setf (mock-input-string harness) (make-string-output-stream)
          (mock-output-string harness) (make-string-input-stream ""))
    harness))

(defun queue-mock-response (harness response)
  "Queue a JSON-RPC response for the mock server to return."
  (push response (mock-responses harness)))

(defun create-jsonrpc-response (id result)
  "Create a JSON-RPC 2.0 success response."
  `((:jsonrpc . "2.0")
    (:id . ,id)
    (:result . ,result)))

(defun create-jsonrpc-error (id code message)
  "Create a JSON-RPC 2.0 error response."
  `((:jsonrpc . "2.0")
    (:id . ,id)
    (:error . ((:code . ,code)
               (:message . ,message)))))

(test mcp-mock-server-setup
  "Test that mock MCP servers can be set up correctly"
  (let ((server (autopoiesis.integration:make-mcp-server
                 "mock-test" "echo"
                 :args '("test")
                 :working-directory "/tmp")))
    (is (equal "mock-test" (autopoiesis.integration:mcp-name server)))
    (is (equal "echo" (autopoiesis.integration:mcp-command server)))
    (is (equal '("test") (autopoiesis.integration:mcp-args server)))
    ;; working-directory is internal, access via package internals
    (is (equal "/tmp" (autopoiesis.integration::mcp-working-directory server)))
    (is (not (autopoiesis.integration:mcp-connected-p server)))))

(test mcp-multiple-servers-registry
  "Test managing multiple MCP servers in registry"
  ;; Clear registry
  (clrhash autopoiesis.integration:*mcp-servers*)
  ;; Create multiple servers
  (let ((server1 (autopoiesis.integration:make-mcp-server "server-1" "cmd1"))
        (server2 (autopoiesis.integration:make-mcp-server "server-2" "cmd2"))
        (server3 (autopoiesis.integration:make-mcp-server "server-3" "cmd3")))
    ;; Register all
    (autopoiesis.integration:register-mcp-server server1)
    (autopoiesis.integration:register-mcp-server server2)
    (autopoiesis.integration:register-mcp-server server3)
    ;; List should return all
    (let ((servers (autopoiesis.integration:list-mcp-servers)))
      (is (= 3 (length servers)))
      (is (member server1 servers))
      (is (member server2 servers))
      (is (member server3 servers)))
    ;; Find each
    (is (eq server1 (autopoiesis.integration:find-mcp-server "server-1")))
    (is (eq server2 (autopoiesis.integration:find-mcp-server "server-2")))
    (is (eq server3 (autopoiesis.integration:find-mcp-server "server-3")))
    ;; Unregister one
    (autopoiesis.integration:unregister-mcp-server "server-2")
    (is (= 2 (length (autopoiesis.integration:list-mcp-servers))))
    (is (null (autopoiesis.integration:find-mcp-server "server-2")))
    ;; Clean up
    (clrhash autopoiesis.integration:*mcp-servers*)))

(test mcp-tool-definition-parsing
  "Test parsing various MCP tool definitions"
  ;; Tool with complex schema
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((server (autopoiesis.integration:make-mcp-server "schema-test" "echo")))
    (autopoiesis.integration:register-mcp-server server)
    (let* ((tool '((:name . "search_files")
                   (:description . "Search for files matching a pattern")
                   (:input-schema . (("type" . "object")
                                     ("properties" . (("pattern" . (("type" . "string")
                                                                    ("description" . "Glob pattern")))
                                                      ("directory" . (("type" . "string")
                                                                      ("description" . "Directory to search")))
                                                      ("recursive" . (("type" . "boolean")
                                                                      ("default" . t)))))
                                     ("required" . ("pattern"))))))
           (cap (autopoiesis.integration:mcp-tool-to-capability tool "schema-test")))
      ;; Check name conversion
      (is (eq :search-files (autopoiesis.agent:capability-name cap)))
      ;; Check description includes MCP server info
      (is (search "Search for files" (autopoiesis.agent:capability-description cap)))
      (is (search "schema-test" (autopoiesis.agent:capability-description cap)))
      ;; Check parameters were parsed
      (let ((params (autopoiesis.agent:capability-parameters cap)))
        (is (not (null params)))
        ;; pattern should be required
        (let ((pattern-param (find :pattern params :key #'first)))
          (is (not (null pattern-param)))
          (is (eq 'string (second pattern-param)))
          (is (getf (cddr pattern-param) :required)))
        ;; recursive should have default
        (let ((recursive-param (find :recursive params :key #'first)))
          (is (not (null recursive-param)))
          (is (eq 'boolean (second recursive-param)))))))
  ;; Clean up
  (clrhash autopoiesis.integration:*mcp-servers*))

(test mcp-tool-minimal-definition
  "Test parsing minimal MCP tool definition"
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((server (autopoiesis.integration:make-mcp-server "minimal-test" "echo")))
    (autopoiesis.integration:register-mcp-server server)
    (let* ((tool '((:name . "simple_tool")))  ; Minimal - just a name
           (cap (autopoiesis.integration:mcp-tool-to-capability tool "minimal-test")))
      ;; Should still work
      (is (eq :simple-tool (autopoiesis.agent:capability-name cap)))
      ;; Should have MCP server in description
      (is (search "minimal-test" (autopoiesis.agent:capability-description cap))))
    ;; Clean up
    (clrhash autopoiesis.integration:*mcp-servers*)))

(test mcp-capability-invocation-without-server
  "Test that MCP capability invocation errors when server is not found"
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((server (autopoiesis.integration:make-mcp-server "temp-server" "echo")))
    (autopoiesis.integration:register-mcp-server server)
    (let* ((tool '((:name . "test_tool") (:description . "Test")))
           (cap (autopoiesis.integration:mcp-tool-to-capability tool "temp-server")))
      ;; Now unregister the server
      (autopoiesis.integration:unregister-mcp-server "temp-server")
      ;; Invoking should fail
      (signals autopoiesis.core:autopoiesis-error
        (funcall (autopoiesis.agent:capability-function cap)
                 :arg "value")))))

(test mcp-server-capabilities-tracking
  "Test tracking server capabilities from initialization"
  (let ((server (make-mock-mcp-server)))
    ;; Simulate various capability combinations
    (setf (autopoiesis.integration:mcp-server-capabilities server)
          '((:tools . t) (:resources . t) (:prompts . t)))
    (let ((caps (autopoiesis.integration:mcp-server-capabilities server)))
      (is (cdr (assoc :tools caps)))
      (is (cdr (assoc :resources caps)))
      (is (cdr (assoc :prompts caps))))
    ;; Test with minimal capabilities
    (setf (autopoiesis.integration:mcp-server-capabilities server)
          '((:tools . t)))
    (let ((caps (autopoiesis.integration:mcp-server-capabilities server)))
      (is (cdr (assoc :tools caps)))
      (is (null (cdr (assoc :resources caps)))))))

(test mcp-server-info-storage
  "Test storing and retrieving server info"
  (let ((server (make-mock-mcp-server)))
    (setf (autopoiesis.integration:mcp-server-info server)
          '((:name . "test-mcp-server")
            (:version . "1.0.0")
            (:protocol-version . "2024-11-05")))
    (let ((info (autopoiesis.integration:mcp-server-info server)))
      (is (equal "test-mcp-server" (cdr (assoc :name info))))
      (is (equal "1.0.0" (cdr (assoc :version info))))
      (is (equal "2024-11-05" (cdr (assoc :protocol-version info)))))))

(test mcp-tool-arguments-conversion
  "Test that MCP tool arguments are correctly converted"
  (clrhash autopoiesis.integration:*mcp-servers*)
  ;; Create a "connected" mock server that we can use
  (let ((server (make-mock-mcp-server)))
    (setf (autopoiesis.integration:mcp-name server) "arg-test")
    (autopoiesis.integration:register-mcp-server server)
    ;; Create a tool
    (let* ((tool '((:name . "echo_args")))
           (cap (autopoiesis.integration:mcp-tool-to-capability tool "arg-test")))
      ;; The capability function converts keyword args to alist
      ;; We can't actually call it (no real server), but we can check it exists
      (is (not (null (autopoiesis.agent:capability-function cap))))))
  ;; Clean up
  (clrhash autopoiesis.integration:*mcp-servers*))

(test mcp-multiple-tools-registration
  "Test registering multiple tools from one server"
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((test-registry (make-hash-table :test 'eq))
        (server (autopoiesis.integration:make-mcp-server "multi-tool" "echo")))
    ;; Set up multiple tools
    (setf (autopoiesis.integration:mcp-tools server)
          '(((:name . "tool_alpha") (:description . "Alpha tool"))
            ((:name . "tool_beta") (:description . "Beta tool"))
            ((:name . "tool_gamma") (:description . "Gamma tool"))
            ((:name . "tool_delta") (:description . "Delta tool"))))
    (autopoiesis.integration:register-mcp-server server)
    ;; Register all tools
    (let ((caps (autopoiesis.integration:register-mcp-tools-as-capabilities
                 server :registry test-registry)))
      (is (= 4 (length caps)))
      ;; Check all are registered
      (is (not (null (autopoiesis.agent:find-capability :tool-alpha :registry test-registry))))
      (is (not (null (autopoiesis.agent:find-capability :tool-beta :registry test-registry))))
      (is (not (null (autopoiesis.agent:find-capability :tool-gamma :registry test-registry))))
      (is (not (null (autopoiesis.agent:find-capability :tool-delta :registry test-registry))))
      ;; Verify descriptions include MCP server name
      (let ((alpha (autopoiesis.agent:find-capability :tool-alpha :registry test-registry)))
        (is (search "multi-tool" (autopoiesis.agent:capability-description alpha)))))
    ;; Unregister all
    (autopoiesis.integration:unregister-mcp-tools server :registry test-registry)
    (is (null (autopoiesis.agent:find-capability :tool-alpha :registry test-registry)))
    (is (null (autopoiesis.agent:find-capability :tool-beta :registry test-registry)))
    ;; Clean up
    (clrhash autopoiesis.integration:*mcp-servers*)))

(test mcp-tool-name-collision-handling
  "Test handling tools with names that need conversion"
  ;; Tools with special characters in names
  (clrhash autopoiesis.integration:*mcp-servers*)
  (let ((server (autopoiesis.integration:make-mcp-server "name-test" "echo")))
    (autopoiesis.integration:register-mcp-server server)
    ;; Various naming patterns
    (let ((tool1 (autopoiesis.integration:mcp-tool-to-capability
                  '((:name . "read_file")) "name-test"))
          (tool2 (autopoiesis.integration:mcp-tool-to-capability
                  '((:name . "READ_FILE")) "name-test"))  ; uppercase
          (tool3 (autopoiesis.integration:mcp-tool-to-capability
                  '((:name . "readFile")) "name-test")))  ; camelCase
      ;; All should convert to keyword symbols
      (is (keywordp (autopoiesis.agent:capability-name tool1)))
      (is (keywordp (autopoiesis.agent:capability-name tool2)))
      (is (keywordp (autopoiesis.agent:capability-name tool3))))
    ;; Clean up
    (clrhash autopoiesis.integration:*mcp-servers*)))

(test mcp-jsonrpc-request-id-uniqueness
  "Test that request IDs are unique and incrementing"
  (let ((server (make-mock-mcp-server)))
    (let ((ids (loop repeat 100 collect (autopoiesis.integration::next-request-id server))))
      ;; All IDs should be unique
      (is (= 100 (length (remove-duplicates ids))))
      ;; Should be incrementing
      (is (apply #'< ids)))))

(test mcp-jsonrpc-request-with-params
  "Test JSON-RPC request creation with various parameter types"
  ;; Simple params
  (let ((req (autopoiesis.integration::make-jsonrpc-request 1 "test/method"
               '(("key" . "value")))))
    (is (equal "test/method" (cdr (assoc "method" req :test #'string=))))
    (let ((params (cdr (assoc "params" req :test #'string=))))
      (is (equal "value" (cdr (assoc "key" params :test #'string=))))))
  ;; Nested params
  (let ((req (autopoiesis.integration::make-jsonrpc-request 2 "nested"
               '(("outer" . (("inner" . "deep")))))))
    (let* ((params (cdr (assoc "params" req :test #'string=)))
           (outer (cdr (assoc "outer" params :test #'string=))))
      (is (equal "deep" (cdr (assoc "inner" outer :test #'string=))))))
  ;; Array params (list)
  (let ((req (autopoiesis.integration::make-jsonrpc-request 3 "array"
               '(("items" . (1 2 3))))))
    (let* ((params (cdr (assoc "params" req :test #'string=)))
           (items (cdr (assoc "items" params :test #'string=))))
      (is (equal '(1 2 3) items)))))

(test mcp-server-environment-variables
  "Test MCP server with environment variables"
  (let ((server (autopoiesis.integration:make-mcp-server
                 "env-test" "echo"
                 :env '(("API_KEY" . "secret123")
                        ("DEBUG" . "true")
                        ("PATH" . "/usr/bin")))))
    ;; mcp-env is internal, access via package internals
    (is (equal '(("API_KEY" . "secret123")
                 ("DEBUG" . "true")
                 ("PATH" . "/usr/bin"))
               (autopoiesis.integration::mcp-env server)))))

(test mcp-full-status-report
  "Test comprehensive status report from MCP server"
  (let ((server (autopoiesis.integration:make-mcp-server
                 "status-full" "cmd"
                 :args '("--arg1" "--arg2"))))
    ;; Set up mock state
    (setf (autopoiesis.integration:mcp-tools server)
          '(((:name . "t1")) ((:name . "t2")) ((:name . "t3"))))
    (setf (autopoiesis.integration:mcp-resources server)
          '(((:uri . "r1")) ((:uri . "r2"))))
    (setf (autopoiesis.integration:mcp-server-info server)
          '((:name . "TestServer") (:version . "2.0")))
    ;; Get status
    (let ((status (autopoiesis.integration:mcp-server-status server)))
      (is (equal "status-full" (getf status :name)))
      (is (not (getf status :connected)))
      (is (equal "cmd" (getf status :command)))
      (is (equal '("--arg1" "--arg2") (getf status :args)))
      (is (= 3 (getf status :tools-count)))
      (is (= 2 (getf status :resources-count)))
      (is (not (null (getf status :server-info)))))))

(test mcp-discover-resources-with-no-capability
  "Test that resource discovery gracefully handles servers without resource capability"
  (let ((server (make-mock-mcp-server)))
    ;; Server with only tools capability (no resources)
    (setf (autopoiesis.integration:mcp-server-capabilities server)
          '((:tools . t)))
    ;; discover-resources should return nil without error
    (let ((resources (autopoiesis.integration::mcp-discover-resources server)))
      (is (null resources)))))

(test mcp-discover-tools-with-no-capability
  "Test that tool discovery gracefully handles servers without tool capability"
  (let ((server (make-mock-mcp-server)))
    ;; Server with only resources capability (no tools)
    (setf (autopoiesis.integration:mcp-server-capabilities server)
          '((:resources . t)))
    ;; discover-tools should return nil without error
    (let ((tools (autopoiesis.integration::mcp-discover-tools server)))
      (is (null tools)))))

;;; ===================================================================
;;; MCP Event Integration Tests
;;; ===================================================================

(test mcp-events-on-connect-disconnect
  "Test that MCP connection events are properly handled"
  ;; Set up event capture
  (autopoiesis.integration:clear-event-handlers)
  (autopoiesis.integration:clear-event-history)
  (let ((connect-events nil)
        (disconnect-events nil))
    (autopoiesis.integration:subscribe-to-event
     :mcp-connected
     (lambda (e) (push e connect-events)))
    (autopoiesis.integration:subscribe-to-event
     :mcp-disconnected
     (lambda (e) (push e disconnect-events)))
    ;; Simulate connection event
    (autopoiesis.integration:emit-integration-event
     :mcp-connected :mcp-test-server
     '(:server-name "test-server" :tools-count 5))
    (is (= 1 (length connect-events)))
    (is (equal "test-server"
               (getf (autopoiesis.integration:integration-event-data
                      (first connect-events))
                     :server-name)))
    ;; Simulate disconnect event
    (autopoiesis.integration:emit-integration-event
     :mcp-disconnected :mcp-test-server
     '(:server-name "test-server" :reason "shutdown"))
    (is (= 1 (length disconnect-events)))
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test mcp-tool-call-events
  "Test that MCP tool call events are emitted"
  (autopoiesis.integration:clear-event-handlers)
  (autopoiesis.integration:clear-event-history)
  (let ((tool-calls nil))
    (autopoiesis.integration:subscribe-to-event
     :mcp-tool-call
     (lambda (e) (push e tool-calls)))
    ;; Simulate MCP tool call event
    (autopoiesis.integration:emit-integration-event
     :mcp-tool-call :mcp-filesystem
     '(:tool "read_file" :server "filesystem" :arguments (:path "/tmp/test.txt")))
    (is (= 1 (length tool-calls)))
    (let ((event (first tool-calls)))
      (is (eq :mcp-tool-call (autopoiesis.integration:integration-event-kind event)))
      (is (eq :mcp-filesystem (autopoiesis.integration:integration-event-source event)))
      (is (equal "read_file"
                 (getf (autopoiesis.integration:integration-event-data event) :tool))))
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test mcp-error-events
  "Test that MCP error events are properly captured"
  (autopoiesis.integration:clear-event-handlers)
  (autopoiesis.integration:clear-event-history)
  (let ((errors nil))
    (autopoiesis.integration:subscribe-to-event
     :mcp-error
     (lambda (e) (push e errors)))
    ;; Simulate MCP error
    (autopoiesis.integration:emit-integration-event
     :mcp-error :mcp-broken-server
     '(:error "Connection refused" :code -32000 :server "broken-server"))
    (is (= 1 (length errors)))
    (let ((error-event (first errors)))
      (is (equal "Connection refused"
                 (getf (autopoiesis.integration:integration-event-data error-event) :error)))
      (is (= -32000
             (getf (autopoiesis.integration:integration-event-data error-event) :code))))
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

;;; ===================================================================
;;; Built-in Tools Tests
;;; ===================================================================

;;; Note: defcapability registers capabilities under their symbol name in the
;;; package where they're defined (autopoiesis.integration). So we use
;;; 'autopoiesis.integration::read-file instead of :read-file.

(test list-builtin-tools
  "Test listing all builtin tools"
  (let ((tools (autopoiesis.integration:list-builtin-tools)))
    ;; Should return a list of tool names
    (is (listp tools))
    (is (>= (length tools) 10))  ; Should have at least 10+ tools
    ;; Check key tools are present (symbols in autopoiesis.integration)
    (is (member 'autopoiesis.integration::read-file tools))
    (is (member 'autopoiesis.integration::write-file tools))
    (is (member 'autopoiesis.integration::web-fetch tools))
    (is (member 'autopoiesis.integration::run-command tools))
    (is (member 'autopoiesis.integration::git-status tools))))

(test register-builtin-tools
  "Test registering builtin tools in capability registry"
  (let ((test-registry (make-hash-table :test 'equal)))
    ;; Initially empty
    (is (= 0 (hash-table-count test-registry)))
    ;; Register tools
    (let ((registered (autopoiesis.integration:register-builtin-tools
                       :registry test-registry)))
      ;; Should return list of registered names
      (is (listp registered))
      (is (> (length registered) 0))
      ;; Check tools are in registry (using correct symbols)
      (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::read-file :registry test-registry))))
      (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::write-file :registry test-registry))))
      (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::web-fetch :registry test-registry))))
      (is (not (null (autopoiesis.agent:find-capability 'autopoiesis.integration::run-command :registry test-registry)))))
    ;; Unregister
    (autopoiesis.integration:unregister-builtin-tools :registry test-registry)
    ;; Should be empty again
    (is (null (autopoiesis.agent:find-capability 'autopoiesis.integration::read-file :registry test-registry)))))

(test builtin-file-read-capability
  "Test read-file capability"
  ;; The capability should be defined by defcapability
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::read-file)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::read-file (autopoiesis.agent:capability-name cap)))
    ;; Should have a description
    (is (> (length (autopoiesis.agent:capability-description cap)) 0))))

(test builtin-file-write-capability
  "Test write-file capability"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::write-file)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::write-file (autopoiesis.agent:capability-name cap)))))

(test builtin-web-fetch-capability
  "Test web-fetch capability"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::web-fetch)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::web-fetch (autopoiesis.agent:capability-name cap)))))

(test builtin-run-command-capability
  "Test run-command capability"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::run-command)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::run-command (autopoiesis.agent:capability-name cap)))))

(test builtin-read-file-execution
  "Test actually executing read-file on a temp file"
  (let ((test-file (merge-pathnames "autopoiesis-test-read.txt"
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           ;; Create test file
           (with-open-file (out test-file :direction :output
                                          :if-exists :supersede)
             (format out "Line 1~%Line 2~%Line 3~%"))
           ;; Use the capability
           (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::read-file))
                  (result (funcall (autopoiesis.agent:capability-function cap)
                                   :path (namestring test-file))))
             (is (stringp result))
             (is (search "Line 1" result))
             (is (search "Line 2" result))
             (is (search "Line 3" result))))
      ;; Cleanup
      (when (probe-file test-file)
        (delete-file test-file)))))

(test builtin-read-file-with-line-range
  "Test read-file with start-line and end-line"
  (let ((test-file (merge-pathnames "autopoiesis-test-range.txt"
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           ;; Create test file with multiple lines
           (with-open-file (out test-file :direction :output
                                          :if-exists :supersede)
             (format out "Line 1~%Line 2~%Line 3~%Line 4~%Line 5~%"))
           ;; Read only lines 2-4
           (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::read-file))
                  (result (funcall (autopoiesis.agent:capability-function cap)
                                   :path (namestring test-file)
                                   :start-line 2
                                   :end-line 4)))
             (is (stringp result))
             (is (not (search "Line 1" result)))
             (is (search "Line 2" result))
             (is (search "Line 3" result))
             (is (search "Line 4" result))
             (is (not (search "Line 5" result)))))
      ;; Cleanup
      (when (probe-file test-file)
        (delete-file test-file)))))

(test builtin-read-file-nonexistent
  "Test read-file returns error for nonexistent file"
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::read-file))
         (result (funcall (autopoiesis.agent:capability-function cap)
                          :path "/nonexistent/path/to/file.txt")))
    (is (stringp result))
    (is (search "Error" result))))

(test builtin-write-file-execution
  "Test actually executing write-file on a temp file"
  (let ((test-file (merge-pathnames "autopoiesis-test-write.txt"
                                    (uiop:temporary-directory))))
    (unwind-protect
         (progn
           ;; Use the capability to write
           (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::write-file))
                  (content "Test content for write")
                  (result (funcall (autopoiesis.agent:capability-function cap)
                                   :path (namestring test-file)
                                   :content content)))
             (is (stringp result))
             (is (search "Successfully wrote" result))
             ;; Verify file was written
             (is (probe-file test-file))
             (with-open-file (in test-file)
               (is (equal content (read-line in))))))
      ;; Cleanup
      (when (probe-file test-file)
        (delete-file test-file)))))

(test builtin-file-exists-p-execution
  "Test file-exists-p capability"
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::file-exists-p))
         (existing-result (funcall (autopoiesis.agent:capability-function cap)
                                   :path (namestring (truename ".")))))
    (is (equal "true" existing-result)))
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::file-exists-p))
         (nonexistent-result (funcall (autopoiesis.agent:capability-function cap)
                                      :path "/definitely/does/not/exist")))
    (is (equal "false" nonexistent-result))))

(test builtin-list-directory-execution
  "Test list-directory capability"
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::list-directory))
         (result (funcall (autopoiesis.agent:capability-function cap)
                          :path (namestring (uiop:temporary-directory)))))
    (is (stringp result))
    ;; Should either list files or say no files
    (is (or (> (length result) 0)
            (search "No files" result)))))

(test builtin-run-command-execution
  "Test run-command capability with simple echo"
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::run-command))
         (result (funcall (autopoiesis.agent:capability-function cap)
                          :command "echo 'Hello World'")))
    (is (stringp result))
    (is (search "Hello World" result))))

(test builtin-run-command-with-directory
  "Test run-command with working-directory"
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::run-command))
         (result (funcall (autopoiesis.agent:capability-function cap)
                          :command "pwd"
                          :working-directory "/tmp")))
    (is (stringp result))
    (is (search "/tmp" result))))

(test builtin-run-command-exit-code
  "Test run-command reports non-zero exit code"
  (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::run-command))
         (result (funcall (autopoiesis.agent:capability-function cap)
                          :command "false")))  ; false always exits with 1
    (is (stringp result))
    (is (search "Exit code:" result))))

(test builtin-git-status-capability
  "Test git-status capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-status)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::git-status (autopoiesis.agent:capability-name cap)))))

(test builtin-git-diff-capability
  "Test git-diff capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-diff)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::git-diff (autopoiesis.agent:capability-name cap)))))

(test builtin-git-log-capability
  "Test git-log capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::git-log)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::git-log (autopoiesis.agent:capability-name cap)))))

(test builtin-grep-files-capability
  "Test grep-files capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::grep-files)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::grep-files (autopoiesis.agent:capability-name cap)))))

(test builtin-glob-files-capability
  "Test glob-files capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::glob-files)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::glob-files (autopoiesis.agent:capability-name cap)))))

(test builtin-delete-file-tool-capability
  "Test delete-file-tool capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::delete-file-tool)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::delete-file-tool (autopoiesis.agent:capability-name cap)))))

(test builtin-delete-file-execution
  "Test delete-file-tool capability execution"
  (let ((test-file (merge-pathnames "autopoiesis-test-delete.txt"
                                    (uiop:temporary-directory))))
    ;; Create file first
    (with-open-file (out test-file :direction :output :if-exists :supersede)
      (write-string "to be deleted" out))
    (is (probe-file test-file))
    ;; Delete it
    (let* ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::delete-file-tool))
           (result (funcall (autopoiesis.agent:capability-function cap)
                            :path (namestring test-file))))
      (is (stringp result))
      (is (search "Successfully deleted" result))
      (is (null (probe-file test-file))))))

(test builtin-web-head-capability
  "Test web-head capability is defined"
  (let ((cap (autopoiesis.agent:find-capability 'autopoiesis.integration::web-head)))
    (is (not (null cap)))
    (is (eq 'autopoiesis.integration::web-head (autopoiesis.agent:capability-name cap)))))

;;; ===================================================================
;;; Integration Event System Tests
;;; ===================================================================

(test event-creation
  "Test creating an integration event"
  (let ((event (autopoiesis.integration:make-integration-event
                :tool-called
                :claude
                :agent-id "agent-123"
                :data '(:tool "read-file" :arguments (:path "/tmp/test.txt")))))
    (is (not (null (autopoiesis.integration:integration-event-id event))))
    (is (eq :tool-called (autopoiesis.integration:integration-event-kind event)))
    (is (eq :claude (autopoiesis.integration:integration-event-source event)))
    (is (equal "agent-123" (autopoiesis.integration:integration-event-agent-id event)))
    (is (equal "read-file" (getf (autopoiesis.integration:integration-event-data event) :tool)))
    (is (numberp (autopoiesis.integration:integration-event-timestamp event)))))

(test event-serialization
  "Test event serialization and deserialization"
  (let* ((event (autopoiesis.integration:make-integration-event
                 :mcp-connected
                 :mcp-filesystem
                 :data '(:server-name "filesystem" :tools-count 10)))
         (sexpr (autopoiesis.integration:event-to-sexpr event))
         (restored (autopoiesis.integration:sexpr-to-event sexpr)))
    (is (equal (autopoiesis.integration:integration-event-id event)
               (autopoiesis.integration:integration-event-id restored)))
    (is (eq (autopoiesis.integration:integration-event-kind event)
            (autopoiesis.integration:integration-event-kind restored)))
    (is (eq (autopoiesis.integration:integration-event-source event)
            (autopoiesis.integration:integration-event-source restored)))
    (is (equal (autopoiesis.integration:integration-event-data event)
               (autopoiesis.integration:integration-event-data restored)))
    (is (= (autopoiesis.integration:integration-event-timestamp event)
           (autopoiesis.integration:integration-event-timestamp restored)))))

(test event-emit-and-subscribe
  "Test emitting events and subscribing to them"
  (let ((received-events nil))
    ;; Clear handlers for test isolation
    (autopoiesis.integration:clear-event-handlers)
    (autopoiesis.integration:clear-event-history)
    ;; Subscribe to tool-called events
    (autopoiesis.integration:subscribe-to-event
     :tool-called
     (lambda (event) (push event received-events)))
    ;; Emit an event
    (autopoiesis.integration:emit-integration-event
     :tool-called :builtin
     '(:tool "read-file")
     :agent-id "test-agent")
    ;; Should have received the event
    (is (= 1 (length received-events)))
    (is (eq :tool-called (autopoiesis.integration:integration-event-kind (first received-events))))
    ;; Emit a different event type - shouldn't be received
    (autopoiesis.integration:emit-integration-event
     :mcp-connected :mcp-server
     '(:server-name "test"))
    (is (= 1 (length received-events)))  ; Still just one
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test event-unsubscribe
  "Test unsubscribing from events"
  (let ((call-count 0)
        (handler nil))
    (autopoiesis.integration:clear-event-handlers)
    ;; Subscribe
    (setf handler (autopoiesis.integration:subscribe-to-event
                   :tool-result
                   (lambda (e) (declare (ignore e)) (incf call-count))))
    ;; Emit - should be called
    (autopoiesis.integration:emit-integration-event
     :tool-result :builtin '(:result "ok"))
    (is (= 1 call-count))
    ;; Unsubscribe
    (is (autopoiesis.integration:unsubscribe-from-event :tool-result handler))
    ;; Emit again - should NOT be called
    (autopoiesis.integration:emit-integration-event
     :tool-result :builtin '(:result "ok2"))
    (is (= 1 call-count))  ; Still just one
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test event-global-handler
  "Test global event handlers"
  (let ((all-events nil))
    (autopoiesis.integration:clear-event-handlers)
    ;; Subscribe to all events
    (autopoiesis.integration:subscribe-to-all-events
     (lambda (event) (push event all-events)))
    ;; Emit different event types
    (autopoiesis.integration:emit-integration-event
     :tool-called :builtin '(:tool "test"))
    (autopoiesis.integration:emit-integration-event
     :claude-request :claude '(:messages 1))
    (autopoiesis.integration:emit-integration-event
     :mcp-connected :mcp-fs '(:server-name "fs"))
    ;; Should have received all three
    (is (= 3 (length all-events)))
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test event-history
  "Test event history tracking"
  (autopoiesis.integration:clear-event-handlers)
  (autopoiesis.integration:clear-event-history)
  ;; Emit some events
  (autopoiesis.integration:emit-integration-event
   :tool-called :builtin '(:tool "t1") :agent-id "a1")
  (autopoiesis.integration:emit-integration-event
   :tool-called :builtin '(:tool "t2") :agent-id "a2")
  (autopoiesis.integration:emit-integration-event
   :mcp-connected :mcp-server '(:server-name "s1"))
  ;; Get all history
  (let ((history (autopoiesis.integration:get-event-history)))
    (is (= 3 (length history))))
  ;; Filter by type
  (let ((tool-events (autopoiesis.integration:get-event-history :type :tool-called)))
    (is (= 2 (length tool-events))))
  ;; Filter by source
  (let ((mcp-events (autopoiesis.integration:get-event-history :source :mcp-server)))
    (is (= 1 (length mcp-events))))
  ;; Filter by agent
  (let ((agent-events (autopoiesis.integration:get-event-history :agent-id "a1")))
    (is (= 1 (length agent-events))))
  ;; Clean up
  (autopoiesis.integration:clear-event-history))

(test event-count
  "Test event counting"
  (autopoiesis.integration:clear-event-handlers)
  (autopoiesis.integration:clear-event-history)
  ;; Emit events
  (autopoiesis.integration:emit-integration-event
   :tool-called :builtin '(:tool "t1"))
  (autopoiesis.integration:emit-integration-event
   :tool-called :builtin '(:tool "t2"))
  (autopoiesis.integration:emit-integration-event
   :tool-result :builtin '(:result "ok"))
  ;; Count all
  (is (= 3 (autopoiesis.integration:count-events)))
  ;; Count by type
  (is (= 2 (autopoiesis.integration:count-events :type :tool-called)))
  (is (= 1 (autopoiesis.integration:count-events :type :tool-result)))
  ;; Clean up
  (autopoiesis.integration:clear-event-history))

(test with-events-disabled-macro
  "Test with-events-disabled macro"
  (autopoiesis.integration:clear-event-handlers)
  (autopoiesis.integration:clear-event-history)
  ;; Emit inside disabled block
  (autopoiesis.integration:with-events-disabled
    (autopoiesis.integration:emit-integration-event
     :tool-called :builtin '(:tool "hidden")))
  ;; Should not be in history
  (is (= 0 (length (autopoiesis.integration:get-event-history))))
  ;; Emit normally
  (autopoiesis.integration:emit-integration-event
   :tool-called :builtin '(:tool "visible"))
  ;; Should be in history
  (is (= 1 (length (autopoiesis.integration:get-event-history))))
  ;; Clean up
  (autopoiesis.integration:clear-event-history))

(test with-event-handler-macro
  "Test with-event-handler temporary subscription"
  (let ((calls 0))
    (autopoiesis.integration:clear-event-handlers)
    ;; Use temporary handler
    (autopoiesis.integration:with-event-handler
        (:external-error (lambda (e) (declare (ignore e)) (incf calls)))
      (autopoiesis.integration:emit-integration-event
       :external-error :test '(:error "oops"))
      (is (= 1 calls)))
    ;; Handler should be gone now
    (autopoiesis.integration:emit-integration-event
     :external-error :test '(:error "oops2"))
    (is (= 1 calls))  ; Still just one
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test event-handler-error-isolation
  "Test that handler errors don't break event emission"
  (let ((second-handler-called nil))
    (autopoiesis.integration:clear-event-handlers)
    ;; Subscribe a handler that throws
    (autopoiesis.integration:subscribe-to-event
     :tool-called
     (lambda (e) (declare (ignore e)) (error "Intentional test error")))
    ;; Subscribe a second handler
    (autopoiesis.integration:subscribe-to-event
     :tool-called
     (lambda (e) (declare (ignore e)) (setf second-handler-called t)))
    ;; Emit - should not error, and second handler should still be called
    (finishes
      (autopoiesis.integration:emit-integration-event
       :tool-called :builtin '(:tool "test")))
    (is (eq t second-handler-called))
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test default-event-handlers
  "Test setting up and removing default handlers"
  ;; Ensure clean state
  (autopoiesis.integration:remove-default-event-handlers)
  (is (null autopoiesis.integration:*default-handlers-installed*))
  ;; Set up defaults
  (autopoiesis.integration:setup-default-event-handlers)
  (is (eq t autopoiesis.integration:*default-handlers-installed*))
  ;; Setting up again should be a no-op
  (autopoiesis.integration:setup-default-event-handlers)
  (is (eq t autopoiesis.integration:*default-handlers-installed*))
  ;; Remove
  (autopoiesis.integration:remove-default-event-handlers)
  (is (null autopoiesis.integration:*default-handlers-installed*)))

(test multiple-handlers-same-type
  "Test multiple handlers for the same event type"
  (let ((results nil))
    (autopoiesis.integration:clear-event-handlers)
    ;; Subscribe multiple handlers
    (autopoiesis.integration:subscribe-to-event
     :tool-called
     (lambda (e) (push (cons 1 (autopoiesis.integration:integration-event-id e)) results)))
    (autopoiesis.integration:subscribe-to-event
     :tool-called
     (lambda (e) (push (cons 2 (autopoiesis.integration:integration-event-id e)) results)))
    (autopoiesis.integration:subscribe-to-event
     :tool-called
     (lambda (e) (push (cons 3 (autopoiesis.integration:integration-event-id e)) results)))
    ;; Emit
    (autopoiesis.integration:emit-integration-event
     :tool-called :builtin '(:tool "test"))
    ;; All three should have been called
    (is (= 3 (length results)))
    (is (member 1 results :key #'car))
    (is (member 2 results :key #'car))
    (is (member 3 results :key #'car))
    ;; Clean up
    (autopoiesis.integration:clear-event-handlers)))

(test event-history-limit
  "Test that event history respects max limit"
  (autopoiesis.integration:clear-event-history)
  (let ((autopoiesis.integration:*max-event-history* 5))
    ;; Emit 10 events
    (dotimes (i 10)
      (autopoiesis.integration:emit-integration-event
       :tool-called :builtin `(:index ,i)))
    ;; Should only keep last 5
    (is (= 5 (length autopoiesis.integration:*event-history*)))
    ;; Most recent should be index 9
    (is (= 9 (getf (autopoiesis.integration:integration-event-data
                    (first autopoiesis.integration:*event-history*))
                   :index))))
  ;; Clean up
  (autopoiesis.integration:clear-event-history))
