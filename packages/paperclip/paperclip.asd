;;;; paperclip.asd - Paperclip AI BYOA adapter for Autopoiesis

;;; Paperclip AI BYOA adapter (optional)
(asdf:defsystem #:autopoiesis/paperclip
  :description "Paperclip AI BYOA adapter for Autopoiesis"
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
     (:file "adapter")
     (:file "skills"))))
  :in-order-to ((test-op (test-op #:autopoiesis/paperclip-test))))

;;; Paperclip adapter tests
(asdf:defsystem #:autopoiesis/paperclip-test
  :description "Tests for Paperclip adapter"
  :depends-on (#:autopoiesis/paperclip #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "paperclip-adapter-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.paperclip.test :run-paperclip-tests)))
