;;;; research.asd - Sandbox-backed parallel research campaigns

(asdf:defsystem #:autopoiesis/research
  :description "Sandbox-backed parallel research campaigns"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:autopoiesis/sandbox
               #:cl-base64)
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "tools")
     (:file "campaign")
     (:file "interface")))))
