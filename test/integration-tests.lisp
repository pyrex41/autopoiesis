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
