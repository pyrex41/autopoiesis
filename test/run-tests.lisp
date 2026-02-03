;;;; run-tests.lisp - Test runner
;;;;
;;;; Main entry point for running tests.

(in-package #:autopoiesis.test)

(def-suite all-tests
  :description "All Autopoiesis tests")

(in-suite all-tests)

;; Add all test suites
(def-suite* all-tests)

(defun run-all-tests ()
  "Run all Autopoiesis tests."
  (run! 'core-tests)
  (run! 'agent-tests)
  (run! 'snapshot-tests)
  (run! 'interface-tests)
  (run! 'integration-tests)
  (run! 'viz-tests)
  (run! 'security-tests)
  (run! 'monitoring-tests)
  (run! 'e2e-tests))

;; Make tests easy to run from REPL
(defun test-core ()
  "Run only core tests."
  (run! 'core-tests))

(defun test-agent ()
  "Run only agent tests."
  (run! 'agent-tests))

(defun test-snapshot ()
  "Run only snapshot tests."
  (run! 'snapshot-tests))

(defun test-interface ()
  "Run only interface tests."
  (run! 'interface-tests))

(defun test-integration ()
  "Run only integration tests."
  (run! 'integration-tests))

(defun test-e2e ()
  "Run only E2E user story tests."
  (run! 'e2e-tests))

(defun test-viz ()
  "Run only visualization tests."
  (run! 'viz-tests))

(defun test-security ()
  "Run only security tests."
  (run! 'security-tests))

(defun test-monitoring ()
  "Run only monitoring tests."
  (run! 'monitoring-tests))
