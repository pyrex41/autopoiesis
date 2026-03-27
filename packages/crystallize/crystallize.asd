;;;; crystallize.asd - Crystallize runtime changes to source files

;;; Crystallize runtime-to-source extension (optional)
(asdf:defsystem #:autopoiesis/crystallize
  :description "Crystallize runtime changes to source files"
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
     (:file "trigger-conditions")
     (:file "emitter")
     (:file "capability-crystallizer")
     (:file "heuristic-crystallizer")
     (:file "genome-crystallizer")
     (:file "snapshot-integration")
     (:file "asdf-fragment")
     (:file "git-export"))))
  :in-order-to ((test-op (test-op #:autopoiesis/crystallize-test))))

;;; Crystallize extension tests
(asdf:defsystem #:autopoiesis/crystallize-test
  :description "Tests for crystallize extension"
  :depends-on (#:autopoiesis/crystallize #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "crystallize-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.crystallize.test :run-crystallize-tests)))
