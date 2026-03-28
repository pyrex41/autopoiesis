;;;; autopoiesis-shen.asd - Shen Prolog integration for Autopoiesis
;;;;
;;;; Provides a unified logic layer via Shen's embedded Prolog.
;;;; Shen itself is loaded at runtime (not an ASDF dependency) —
;;;; the extension compiles and loads without Shen installed,
;;;; but Prolog queries require shen-cl to be available.

(asdf:defsystem #:autopoiesis-shen
  :description "Shen Prolog integration — unified logic layer"
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
     (:file "bridge")
     (:file "rules")
     (:file "verifier")
     (:file "reasoning")))))

(asdf:defsystem #:autopoiesis-shen/test
  :description "Tests for Shen Prolog integration"
  :depends-on (#:autopoiesis-shen #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "shen-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.shen.test :run-shen-tests)))
