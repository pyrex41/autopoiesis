;;;; sandbox.asd - Container sandbox integration via squashd

(asdf:defsystem #:autopoiesis/sandbox
  :description "Container sandbox integration via squashd"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:squashd-core)
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "entity-types")
     (:file "sandbox-provider")
     (:file "conductor-dispatch")
     (:file "workspace-backend")))))

(asdf:defsystem #:autopoiesis/sandbox-test
  :description "Tests for sandbox integration"
  :depends-on (#:autopoiesis/sandbox #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "sandbox-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.sandbox.test :run-sandbox-tests)))
