;;;; extension-template.asd - Template for new Autopoiesis extensions
;;;;
;;;; To create a new extension:
;;;; 1. Copy this directory to packages/my-extension/
;;;; 2. Rename this file to my-extension.asd
;;;; 3. Replace "extension-template" with "my-extension" throughout
;;;; 4. Update the package name in src/packages.lisp
;;;; 5. Implement your extension in src/
;;;; 6. Write tests in test/

(asdf:defsystem #:autopoiesis/extension-template
  :description "A template extension for Autopoiesis"
  :author "Your Name"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "extension-template")))))

(asdf:defsystem #:autopoiesis/extension-template-test
  :description "Tests for extension-template"
  :depends-on (#:autopoiesis/extension-template #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "extension-template-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.extension-template.test :run-tests)))
