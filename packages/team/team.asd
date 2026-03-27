;;;; team.asd - Multi-agent team coordination for Autopoiesis

;;; Team coordination extension (optional)
(asdf:defsystem #:autopoiesis/team
  :description "Multi-agent team coordination for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:module "team"
      :serial t
      :components
      ((:file "packages")
       (:file "team")
       (:file "strategy")
       (:module "strategies"
        :serial t
        :components
        ((:file "leader-worker")
         (:file "parallel")
         (:file "pipeline")
         (:file "debate")
         (:file "consensus")))))
     (:module "workspace"
      :serial t
      :depends-on ("team")
      :components
      ((:file "packages")
       (:file "agent-home")
       (:file "workspace")
       (:file "capabilities")
       (:file "team-coordination"))))))
  :in-order-to ((test-op (test-op #:autopoiesis/team-test))))

;;; Team extension tests
(asdf:defsystem #:autopoiesis/team-test
  :description "Tests for team coordination extension"
  :depends-on (#:autopoiesis/team #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "team-tests")
     (:file "workspace-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.team.test :run-team-tests)))
