;;;; packages.lisp - Test package definitions
;;;;
;;;; Defines the test packages using FiveAM.

(in-package #:cl-user)

(defpackage #:autopoiesis.test
  (:use #:cl #:fiveam #:alexandria)
  (:use #:autopoiesis.core)
  (:shadow #:run-all-tests)
  (:export
   #:run-all-tests
   #:run-e2e-tests
   #:substrate-tests
   #:orchestration-tests
   #:conversation-tests
   #:core-tests
   #:agent-tests
   #:snapshot-tests
   #:interface-tests
   #:integration-tests
   #:e2e-tests
   #:security-tests
   #:monitoring-tests
   #:provider-tests
   #:rest-api-tests
   #:prompt-registry-tests
   #:skel-tests
   #:swarm-tests
   #:supervisor-tests
   #:crystallize-tests
   #:git-tools-tests
   #:jarvis-tests))
