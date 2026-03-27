;;;; supervisor.asd - Supervisor checkpoint/revert for Autopoiesis

;;; Supervisor checkpointing extension (optional)
(asdf:defsystem #:autopoiesis/supervisor
  :description "Supervisor checkpoint/revert for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "checkpoint")
     (:file "supervisor")
     (:file "integration")
     (:file "persistent-supervisor-bridge"))))
  :in-order-to ((test-op (test-op #:autopoiesis/supervisor-test))))

;;; Supervisor extension tests
(asdf:defsystem #:autopoiesis/supervisor-test
  :description "Tests for supervisor checkpoint extension"
  :depends-on (#:autopoiesis/supervisor #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "supervisor-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.supervisor.test :run-supervisor-tests)))
