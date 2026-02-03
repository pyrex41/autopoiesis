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
   STATUS - The HTTP status code to return (default 200)"
  `(let ((*mock-http-response* ,response)
         (*mock-http-status* (or ,status 200))
         (*captured-http-requests* nil))
     (flet ((mock-dex-post (url &key headers content)
              (push (list :url url :headers headers :content content)
                    *captured-http-requests*)
              (values (cl-json:encode-json-to-string *mock-http-response*)
                      *mock-http-status*
                      nil)))
       ;; Temporarily replace the send-api-request internals
       ;; We use a closure to capture the mock behavior
       (let ((original-fn (symbol-function 'autopoiesis.integration::send-api-request)))
         (unwind-protect
              (progn
                (setf (symbol-function 'autopoiesis.integration::send-api-request)
                      (lambda (client endpoint body)
                        (unless (autopoiesis.integration:client-api-key client)
                          (error 'autopoiesis.core:autopoiesis-error
                                 :message "No API key configured"))
                        (let* ((url (format nil "~a~a"
                                            (autopoiesis.integration:client-base-url client)
                                            endpoint))
                               (headers (autopoiesis.integration::make-api-headers client))
                               (json-body (cl-json:encode-json-to-string body)))
                          (push (list :url url :headers headers :content json-body)
                                *captured-http-requests*)
                          (if (and (>= *mock-http-status* 200)
                                   (< *mock-http-status* 300))
                              *mock-http-response*
                              (error 'autopoiesis.core:autopoiesis-error
                                     :message (format nil "API error (~a)" *mock-http-status*))))))
                ,@body)
           (setf (symbol-function 'autopoiesis.integration::send-api-request)
                 original-fn))))))

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
