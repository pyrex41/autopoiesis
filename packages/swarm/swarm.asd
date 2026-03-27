;;;; swarm.asd - Swarm evolution engine for Autopoiesis

;;; Swarm evolution extension (optional)
(asdf:defsystem #:autopoiesis/swarm
  :description "Swarm evolution engine for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis #:lparallel)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "genome")
     (:file "fitness")
     (:file "selection")
     (:file "operators")
     (:file "population")
     (:file "production-rules")
     (:file "gpu-stub")
     (:file "persistent-genome-bridge")
     (:file "persistent-evolution")
     (:file "persistent-fitness"))))
  :in-order-to ((test-op (test-op #:autopoiesis/swarm-test))))

;;; Swarm extension tests
(asdf:defsystem #:autopoiesis/swarm-test
  :description "Tests for swarm evolution extension"
  :depends-on (#:autopoiesis/swarm #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "swarm-tests")
     (:file "swarm-integration-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.swarm.test :run-swarm-tests)))
