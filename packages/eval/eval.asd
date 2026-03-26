;;;; eval.asd - Agent evaluation platform for Autopoiesis

(asdf:defsystem #:autopoiesis/eval
  :description "Agent evaluation platform for comparing agent systems"
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
     (:file "entity-types")
     (:file "scenario")
     (:file "harness")
     (:file "harness-provider")
     (:file "verifiers")
     (:file "judge")
     (:file "metrics")
     (:file "run")
     (:file "comparison")
     (:file "harness-shell")
     (:file "harness-ralph")
     (:file "harness-team")
     (:file "harness-sandbox")
     (:file "history")
     (:file "builtin-scenarios")))))

(asdf:defsystem #:autopoiesis/eval-test
  :description "Tests for agent evaluation platform"
  :depends-on (#:autopoiesis/eval #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "eval-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.eval.test :run-eval-tests)))
