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
   #:core-tests
   #:agent-tests
   #:snapshot-tests
   #:interface-tests
   #:integration-tests
   #:e2e-tests
   #:security-tests
   #:monitoring-tests
   #:provider-tests
   #:api-tests))
