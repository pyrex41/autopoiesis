;;;; sandbox.asd - Sandbox systems for Autopoiesis

;;; Content-addressed sandbox with pluggable execution backends
;;; No external runtime dependencies -- just needs autopoiesis core
(asdf:defsystem #:autopoiesis/sandbox-backends
  :description "Content-addressed sandbox with pluggable execution backends"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis)
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "entity-types")
     (:file "execution-backend")
     (:file "local-backend")
     (:file "docker-backend")
     (:file "changeset")
     (:file "sandbox-lifecycle")))))

;;; Sandbox integration (squashd container runtime) -- legacy
;;; Separate system requiring Linux + privileged container for full operation
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
     (:file "execution-backend")
     (:file "local-backend")
     (:file "docker-backend")
     (:file "sandbox-provider")
     (:file "conductor-dispatch")
     (:file "workspace-backend")))))

;;; Sandbox integration tests
(asdf:defsystem #:autopoiesis/sandbox-test
  :description "Tests for sandbox and research integration"
  :depends-on (#:autopoiesis/research #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "sandbox-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.sandbox.test :run-sandbox-tests)))
