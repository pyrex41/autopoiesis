;;;; holodeck.asd - 3D holodeck visualization for Autopoiesis

;;; Holodeck 3D visualization subsystem (Phase 8)
;;; Separate system to avoid requiring OpenGL dependencies for core usage
(asdf:defsystem #:autopoiesis/holodeck
  :description "3D holodeck visualization for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:3d-vectors
               #:3d-matrices
               #:cl-fast-ecs)
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "components")
     (:file "agent-components")
     (:file "team-components")
     (:file "systems")
     (:file "agent-systems")
     (:file "team-systems")
     (:file "agent-entities")
     (:file "window")
     (:file "shaders")
     (:file "meshes")
     (:file "rendering")
     (:file "camera")
     (:file "input")
     (:file "key-bindings")
     (:file "hud"))))
  :in-order-to ((test-op (test-op #:autopoiesis/holodeck-test))))

;;; Holodeck test system
(asdf:defsystem #:autopoiesis/holodeck-test
  :description "Tests for Autopoiesis holodeck"
  :depends-on (#:autopoiesis/holodeck #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "holodeck-tests"))))
  :perform (test-op (o c)
             (symbol-call :autopoiesis.holodeck.test :run-holodeck-tests)))
