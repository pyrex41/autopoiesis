;;;; jarvis.asd - NL->tool conversational loop for Autopoiesis

(asdf:defsystem #:autopoiesis/jarvis
  :description "Jarvis NL->tool conversational loop for Autopoiesis"
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
     (:file "session")
     (:file "dispatch")
     (:file "loop")
     (:file "human-in-the-loop")))))

(asdf:defsystem #:autopoiesis/jarvis-test
  :description "Tests for jarvis conversational extension"
  :depends-on (#:autopoiesis/jarvis #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "jarvis-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.jarvis.test :run-jarvis-tests)))
