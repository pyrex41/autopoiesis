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
               #:babel)          ; For UTF-8 encoding
  :components
  ((:module "src"
    :components
    ((:module "core"
      :serial t
      :components
      ((:file "packages")
       (:file "conditions")
       (:file "s-expr")
       (:file "cognitive-primitives")
       (:file "thought-stream")
       (:file "extension-compiler")))
     (:module "agent"
      :serial t
      :depends-on ("core")
      :components
      ((:file "packages")
       (:file "capability")
       (:file "context-window")
       (:file "agent")
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
       (:file "persistence")
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
       (:file "claude-bridge")
       (:file "message-format")
       (:file "mcp-client")
       (:file "tool-registry")
       (:file "config")))
     ;; Main package that reexports everything
     (:file "autopoiesis" :depends-on ("core" "agent" "snapshot" "interface" "integration")))))
  :in-order-to ((test-op (test-op #:autopoiesis/test))))

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
     (:file "run-tests"))))
  :perform (test-op (o c)
             (symbol-call :autopoiesis.test :run-all-tests)))
