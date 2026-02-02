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
