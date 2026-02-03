;;;; autopoiesis.asd - System definition for Autopoiesis
;;;;
;;;; Autopoiesis is a self-configuring, self-extending agent platform
;;;; built on Common Lisp's homoiconic foundation.

(asdf:defsystem #:autopoiesis
  :description "Self-configuring agent platform with time-travel debugging"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:alexandria
               #:bordeaux-threads
               #:cl-json
               #:local-time
               #:cl-ppcre
               #:log4cl
               #:ironclad        ; For hashing
               #:flexi-streams   ; For binary streams
               #:babel           ; For UTF-8 encoding
               #:dexador         ; For HTTP client
               #:cl-charms)      ; For ncurses terminal UI
  :components
  ((:module "src"
    :components
    ((:module "core"
      :serial t
      :components
      ((:file "packages")
       (:file "conditions")
       (:file "recovery")
       (:file "s-expr")
       (:file "cognitive-primitives")
       (:file "thought-stream")
       (:file "extension-compiler")
       (:file "profiling")))
     (:module "agent"
      :serial t
      :depends-on ("core")
      :components
      ((:file "packages")
       (:file "capability")
       (:file "context-window")
       (:file "agent")
       (:file "agent-capability")
       (:file "learning")
       (:file "cognitive-loop")
       (:file "spawner")
       (:file "registry")
       (:file "builtin-capabilities")))
     (:module "snapshot"
      :serial t
      :depends-on ("core" "agent")
      :components
      ((:file "packages")
       (:file "snapshot")
       (:file "content-store")
       (:file "lru-cache")
       (:file "persistence")
       (:file "lazy-loading")
       (:file "event-log")
       (:file "branch")
       (:file "diff-engine")
       (:file "time-travel")))
     (:module "interface"
      :serial t
      :depends-on ("core" "agent" "snapshot")
      :components
      ((:file "packages")
       (:file "navigator")
       (:file "viewport")
       (:file "annotator")
       (:file "entry-points")
       (:file "blocking")
       (:file "session")
       (:file "protocol")))
     (:module "integration"
      :serial t
      :depends-on ("core" "agent")
      :components
      ((:file "packages")
       (:file "events")
       (:file "claude-bridge")
       (:file "message-format")
       (:file "tool-mapping")
       (:file "session")
       (:file "mcp-client")
       (:file "tool-registry")
       (:file "builtin-tools")
       (:file "config")))
      (:module "viz"
       :serial t
       :depends-on ("core" "snapshot" "interface")
       :components
       ((:file "packages")
        (:file "util")
        (:file "config")
        (:file "timeline")
        (:file "detail-panel")
        (:file "navigator")
        (:file "terminal-ui")))
     (:module "security"
      :serial t
      :depends-on ("core" "agent")
      :components
      ((:file "packages")
       (:file "permissions")
       (:file "audit")
       (:file "validation")))
     ;; Main package that reexports everything
     (:file "autopoiesis" :depends-on ("core" "agent" "snapshot" "interface" "integration" "viz" "security")))))
  :in-order-to ((test-op (test-op #:autopoiesis/test))))

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
  ((:module "src/holodeck"
    :serial t
    :components
    ((:file "packages")
     (:file "components")
     (:file "systems")
     (:file "window")
     (:file "shaders")
     (:file "meshes")
     (:file "rendering")
     (:file "camera")
     (:file "input")
     (:file "key-bindings")
     (:file "hud")))))

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

;;; Test system
(asdf:defsystem #:autopoiesis/test
  :description "Tests for Autopoiesis"
  :depends-on (#:autopoiesis #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "packages")
     (:file "core-tests")
     (:file "agent-tests")
     (:file "snapshot-tests")
     (:file "interface-tests")
     (:file "integration-tests")
     (:file "e2e-tests")
     (:file "viz-tests")
     (:file "security-tests")
     (:file "run-tests"))))
  :perform (test-op (o c)
             (symbol-call :autopoiesis.test :run-all-tests)))
