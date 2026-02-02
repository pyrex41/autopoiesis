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
   #:core-tests
   #:agent-tests
   #:snapshot-tests
   #:integration-tests))
