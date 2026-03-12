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
  :depends-on (#:substrate          ; Standalone datom store (substrate.asd)
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
     (:module "substrate"
      :serial t
      :depends-on ("core")
      :components
      ((:file "builtin-types")
       (:file "migration")))
     (:module "orchestration"
      :serial t
      :depends-on ("core" "substrate" "monitoring")
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
      :depends-on ("core" "substrate")
      :components
      ((:file "packages")
       (:file "turn")
       (:file "context")))
     (:module "integration"
      :serial t
      :depends-on ("core" "substrate" "agent")
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
      ;; Optional extensions moved to separate ASDF systems:
      ;; - autopoiesis/swarm: Genome evolution and fitness
      ;; - autopoiesis/supervisor: Checkpoint/revert operations
      ;; - autopoiesis/crystallize: Runtime-to-source emission
      ;; - autopoiesis/team: Multi-agent coordination strategies
      ;; - autopoiesis/jarvis: NL→tool conversational loop
      ;; Main package that reexports core functionality
      ;; Optional extensions provide additional packages
      (:file "autopoiesis" :depends-on ("core" "substrate" "orchestration" "conversation" "agent" "snapshot" "interface" "integration" "skel" "viz" "security" "monitoring" "api")))))
  :in-order-to ((test-op (test-op #:autopoiesis/test))))

;;; WebSocket API server (Clack/Lack/Woo)
;;; Separate system so core doesn't require web server dependencies
(asdf:defsystem #:autopoiesis/api
  :description "WebSocket API server for Autopoiesis frontends"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:clack                ; Web application environment
               #:lack                 ; Middleware composition
               #:woo                  ; Async HTTP server (event-driven)
               #:websocket-driver     ; WebSocket protocol
               #:com.inuoe.jzon      ; Fast, safe JSON (control messages)
               #:cl-messagepack)     ; Binary encoding (data streams)
   :components
   ((:module "src/api"
     :serial t
     :components
     ((:file "packages")
      (:file "wire-format")
      (:file "serializers")
      (:file "connections")
      (:file "handlers")
      (:file "team-handlers")
      (:file "chat-handlers")
      (:file "events")
      (:file "activity-tracker")
      (:file "holodeck-bridge")
      (:file "web-console")
      (:file "server")))))

;;; API test system
(asdf:defsystem #:autopoiesis/api-test
  :description "Tests for Autopoiesis WebSocket API"
  :depends-on (#:autopoiesis/api #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "api-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.api.test :run-api-tests)))

;;; Swarm evolution extension (optional)
(asdf:defsystem #:autopoiesis/swarm
  :description "Swarm evolution engine for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis #:lparallel)
  :serial t
  :components
  ((:module "src/swarm"
    :serial t
    :components
    ((:file "packages")
     (:file "genome")
     (:file "fitness")
     (:file "selection")
     (:file "operators")
     (:file "population")
     (:file "production-rules")
     (:file "gpu-stub")
     (:file "persistent-genome-bridge")
     (:file "persistent-evolution")
     (:file "persistent-fitness")))))

;;; Supervisor checkpointing extension (optional)
(asdf:defsystem #:autopoiesis/supervisor
  :description "Supervisor checkpoint/revert for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src/supervisor"
    :serial t
    :components
    ((:file "packages")
     (:file "checkpoint")
     (:file "supervisor")
     (:file "integration")
     (:file "persistent-supervisor-bridge")))))

;;; Crystallize runtime-to-source extension (optional)
(asdf:defsystem #:autopoiesis/crystallize
  :description "Crystallize runtime changes to source files"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
   :components
    ((:module "src/crystallize"
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
       (:file "git-export")))))

;;; Team coordination extension (optional)
(asdf:defsystem #:autopoiesis/team
  :description "Multi-agent team coordination for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src/team"
    :serial t
    :components
    ((:file "packages")
     (:file "team")
     (:file "strategy")
     (:module "strategies"
      :serial t
      :components
      ((:file "leader-worker")
       (:file "parallel")
       (:file "pipeline")
       (:file "debate")
       (:file "consensus")))))
   (:module "src/workspace"
    :serial t
    :depends-on ("src/team")
    :components
    ((:file "packages")
     (:file "agent-home")
     (:file "workspace")
     (:file "capabilities")
     (:file "team-coordination")))))

;;; Jarvis conversational extension (optional)
(asdf:defsystem #:autopoiesis/jarvis
  :description "Jarvis NL→tool conversational loop for Autopoiesis"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :depends-on (#:autopoiesis)
  :serial t
  :components
  ((:module "src/jarvis"
    :serial t
    :components
    ((:file "packages")
     (:file "session")
     (:file "dispatch")
     (:file "loop")
     (:file "human-in-the-loop")))))

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
     (:file "substrate-tests")
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
      ;; Optional extension tests moved to separate systems:
      ;; - autopoiesis/team-test (includes workspace-tests)
      ;; - autopoiesis/swarm-test (includes swarm-tests, swarm-integration-tests)
      ;; - autopoiesis/supervisor-test
      ;; - autopoiesis/crystallize-test (includes git-tools-tests)
      ;; - autopoiesis/jarvis-test
      (:file "persistent-agent-tests")
      (:file "run-tests"))))
  :perform (test-op (o c)
             (symbol-call :autopoiesis.test :run-all-tests)))

;;; Sandbox integration (squashd container runtime)
;;; Separate system requiring Linux + privileged container for full operation
(asdf:defsystem #:autopoiesis/sandbox
  :description "Container sandbox integration via squashd"
  :author "Autopoiesis Contributors"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on (#:autopoiesis
               #:squashd-core)
  :components
  ((:module "src/sandbox"
    :serial t
    :components
    ((:file "packages")
     (:file "entity-types")
     (:file "sandbox-provider")
     (:file "conductor-dispatch")
     (:file "workspace-backend")))))

;;; Research campaign layer (sandbox-backed parallel investigation)
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
  ((:module "src/research"
    :serial t
    :components
    ((:file "packages")
     (:file "tools")
     (:file "campaign")
     (:file "interface")))))

;;; Swarm extension tests
(asdf:defsystem #:autopoiesis/swarm-test
  :description "Tests for swarm evolution extension"
  :depends-on (#:autopoiesis/swarm #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "swarm-tests")
     (:file "swarm-integration-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.swarm.test :run-swarm-tests)))

;;; Supervisor extension tests
(asdf:defsystem #:autopoiesis/supervisor-test
  :description "Tests for supervisor checkpoint extension"
  :depends-on (#:autopoiesis/supervisor #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "supervisor-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.supervisor.test :run-supervisor-tests)))

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

;;; Team extension tests
(asdf:defsystem #:autopoiesis/team-test
  :description "Tests for team coordination extension"
  :depends-on (#:autopoiesis/team #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "team-tests")
     (:file "workspace-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.team.test :run-team-tests)))

;;; Jarvis extension tests
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

;;; Sandbox integration tests
(asdf:defsystem #:autopoiesis/sandbox-test
  :description "Tests for sandbox and research integration"
  :depends-on (#:autopoiesis/research #:fiveam)
  :serial t
  :components
  ((:module "test"
    :serial t
    :components
    ((:file "sandbox-tests"))))
  :perform (test-op (o c)
            (symbol-call :autopoiesis.sandbox.test :run-sandbox-tests)))
