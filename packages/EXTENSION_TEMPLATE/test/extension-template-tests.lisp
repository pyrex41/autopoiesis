;;;; extension-template-tests.lisp - Tests for extension-template

(defpackage #:autopoiesis.extension-template.test
  (:use #:cl #:fiveam #:autopoiesis.extension-template)
  (:export #:run-tests))

(in-package #:autopoiesis.extension-template.test)

(def-suite extension-template-tests
  :description "Tests for extension-template")

(in-suite extension-template-tests)

(test basic-test
  "A basic test to verify the extension loads"
  (is (eq t t)))

(defun run-tests ()
  (run! 'extension-template-tests))
