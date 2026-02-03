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
