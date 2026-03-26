;;;; swarm.asd - Genome evolution engine for Autopoiesis

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
     (:file "persistent-fitness")))))

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
