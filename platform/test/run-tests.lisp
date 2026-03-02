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
  (run! 'substrate-tests)
  (run! 'orchestration-tests)
  (run! 'conversation-tests)
  (run! 'core-tests)
  (run! 'agent-tests)
  (run! 'snapshot-tests)
  (run! 'interface-tests)
  (run! 'integration-tests)
  (run! 'viz-tests)
  (run! 'security-tests)
  (run! 'monitoring-tests)
  (run! 'provider-tests)
  (run! 'rest-api-tests)
  (run! 'prompt-registry-tests)
  (run! 'autopoiesis.test.skel::skel-tests)
  (run! 'swarm-tests)
  (run! 'supervisor-tests)
  (run! 'crystallize-tests)
  (run! 'git-tools-tests)
  (run! 'jarvis-tests)
  (run! 'e2e-tests))

;; Make tests easy to run from REPL
(defun test-substrate ()
  "Run only substrate tests."
  (run! 'substrate-tests))

(defun test-orchestration ()
  "Run only orchestration tests."
  (run! 'orchestration-tests))

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

(defun test-provider ()
  "Run only provider tests."
  (run! 'provider-tests))

(defun test-rest-api ()
  "Run only REST API tests."
  (run! 'rest-api-tests))

(defun test-conversation ()
  "Run only conversation tests."
  (run! 'conversation-tests))

(defun test-prompt-registry ()
  "Run only prompt registry tests."
  (run! 'prompt-registry-tests))

(defun test-swarm ()
  "Run only swarm tests."
  (run! 'swarm-tests))

(defun test-supervisor ()
  "Run only supervisor tests."
  (run! 'supervisor-tests))

(defun test-crystallize ()
  "Run only crystallize tests."
  (run! 'crystallize-tests))

(defun test-git-tools ()
  "Run only git tools tests."
  (run! 'git-tools-tests))

(defun test-jarvis ()
  "Run only jarvis tests."
  (run! 'jarvis-tests))
