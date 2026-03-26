;;;; autopoiesis.asd - Core platform system definition
;;;;
;;;; Autopoiesis is a self-configuring, self-extending agent platform
;;;; built on Common Lisp's homoiconic foundation.
;;;;
;;;; This is the core platform. Extensions live in sibling packages/.

(asdf:defsystem #:autopoiesis
  :description "Self-configuring agent platform with time-travel debugging"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:substrate          ; Standalone datom store (packages/substrate/)
                #:alexandria
                #:bordeaux-threads
                #:cl-json
                #:local-time
                #:cl-ppcre
                #:log4cl
                #:ironclad        ; For hashing
                #:flexi-streams   ; For binary streams
                #:babel           ; For UTF-8 encoding
                #:dexador         ; For HTTP client
                #:cl-charms       ; For ncurses terminal UI
                #:hunchentoot     ; For HTTP server (monitoring endpoints)
                #:lparallel       ; For parallel swarm evaluation
                #:fset)           ; Persistent functional collections
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
       (:file "persistent-structs")
       (:file "extension-compiler")
       (:file "profiling")
       (:file "config")))
     (:module "orchestration"
      :serial t
      :depends-on ("core" "monitoring")
      :components
      ((:file "packages")
       (:file "conductor")
       (:file "claude-worker")
       (:file "endpoints")))
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
       (:file "builtin-capabilities")
       (:file "persistent-agent")
       (:file "persistent-cognition")
       (:file "persistent-lineage")
       (:file "persistent-membrane")
       (:file "dual-agent")
       (:file "persistent-substrate")))
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
       (:file "time-travel")
       (:file "consistency")
       (:file "backup")))
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
     (:module "conversation"
      :serial t
      :depends-on ("core")
      :components
      ((:file "packages")
       (:file "turn")
       (:file "context")))
     (:module "integration"
      :serial t
      :depends-on ("core" "agent")
      :components
      ((:file "packages")
       (:file "events")
       (:file "llm-client")
       (:file "claude-bridge")
       (:file "message-format")
       (:file "tool-mapping")
       (:file "prompt-registry")
       (:file "session")
       (:file "mcp-client")
       (:file "tool-registry")
       (:file "builtin-tools")
       (:file "widget-tools")
       (:file "config")
       (:file "provider")
       (:file "provider-result")
       (:file "provider-macro")
       (:file "provider-claude-code")
       (:file "provider-codex")
       (:file "provider-opencode")
       (:file "provider-cursor")
       (:file "provider-pi")
       (:file "provider-rho")
       (:file "provider-nanobot")
       (:file "provider-nanosquash")
       (:file "integrate-primitives")
       (:file "provider-agent")
       (:file "agentic-agent")
       (:file "openai-bridge")
       (:file "provider-inference")
       (:file "agentic-persistent")
       (:file "provider-persistent")))
     (:module "skel"
      :serial t
      :depends-on ("core" "integration")
      :components
      ((:file "packages")
       (:file "types")
       (:file "class")
       (:file "sap")
       (:file "llm-adapter")
       (:file "config")
       (:file "core")
       (:file "partial")
       (:file "streaming")
       (:module "baml"
        :serial t
        :components
        ((:file "package")
         (:file "conditions")
         (:file "structures")
         (:file "tokenizer")
         (:file "parser")
         (:file "converter")
         (:file "import")))))
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
        (:file "validation")
        (:file "authentication")))
     (:module "monitoring"
      :serial t
      :depends-on ("core" "agent" "snapshot")
      :components
      ((:file "packages")
       (:file "endpoints")))
     (:module "api"
      :serial t
      :depends-on ("core" "agent" "snapshot" "interface" "integration")
      :components
      ((:file "packages")
       (:file "auth")
       (:file "serialization")
       (:file "sse")
       (:file "routes")
       (:file "mcp-server")
       (:file "rest-server")))
     (:file "autopoiesis" :depends-on ("core" "orchestration" "conversation" "agent" "snapshot" "interface" "integration" "skel" "viz" "security" "monitoring" "api")))))
  :in-order-to ((test-op (test-op #:autopoiesis/test))))

;;; Test system
(asdf:defsystem #:autopoiesis/test
  :description "Tests for Autopoiesis core platform"
  :depends-on (#:autopoiesis #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "packages")
     (:file "orchestration-tests")
     (:file "conversation-tests")
     (:file "core-tests")
     (:file "agent-tests")
     (:file "snapshot-tests")
     (:file "interface-tests")
     (:file "integration-tests")
     (:file "e2e-tests")
     (:file "viz-tests")
     (:file "security-tests")
     (:file "monitoring-tests")
     (:file "provider-tests")
     (:file "rest-api-tests")
     (:file "prompt-registry-tests")
     (:file "agentic-tests")
     (:file "bridge-protocol-tests")
     (:file "meta-agent-tests")
     (:file "skel-tests")
     (:file "live-llm-tests")
     (:file "persistent-agent-tests")
     (:file "learning-integration-tests")
     (:file "mailbox-integration-tests")
     (:file "run-tests"))))
  :perform (test-op (o c)
             (symbol-call :autopoiesis.test :run-all-tests)))
