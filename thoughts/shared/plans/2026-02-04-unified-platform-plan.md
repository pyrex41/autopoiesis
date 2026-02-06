---
date: 2026-02-04T14:30:00-08:00
author: reuben
branch: main
repository: ap
topic: "Unified Platform Plan: Autopoiesis + Cortex with Per-Project Conductors"
tags: [plan, architecture, conductor, cortex, zmq, projects, capabilities, storage]
status: draft
last_updated: 2026-02-04
last_updated_by: reuben
last_updated_note: "Synthesized from workspace-architecture-plan and cortex-synthesis-plan"
supersedes:
  - 2026-02-04-workspace-architecture-plan.md
  - "Autopoiesis + Cortex Synthesis Plan.md"
---

# Unified Platform Plan: Autopoiesis + Cortex

**Date**: 2026-02-04
**Author**: reuben
**Status**: Draft

## Executive Summary

Autopoiesis becomes a platform where each **project** is a self-contained autonomous agent system with its own **conductor** — an always-running orchestrator that combines fast programmatic execution with slow LLM reasoning. Projects run in **separate SBCL processes** for true isolation. They communicate with Cortex via **ZMQ** for low-latency S-expression streaming. Storage is local filesystem backed transparently by **Archil/S3**.

This plan synthesizes and supersedes the two prior plans:
- *Workspace Architecture & Agent Projects* (monorepo structure, storage, project manifests)
- *Autopoiesis + Cortex Synthesis* (conductor pattern, event-driven architecture, Cortex integration)

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Conductor scope | Per-project | Each project is fully isolated with its own conductor instance |
| Cortex wire protocol | ZMQ | Both CL, native S-expressions, streaming events, lower latency than MCP |
| Storage | Local FS + Archil | Archil transparently syncs to S3. App just uses local paths |
| MCP servers | Not building custom ones | Cortex exposes its own MCP. ZMQ is the tight integration path |
| Extensions vs capabilities | Merged into capabilities | One abstraction: optional, shared, overridable modules |
| Config format | sexpr + markdown | project.sexpr for structure, CORE.md for LLM behavioral guidance |
| Process isolation | Separate SBCL per project | True isolation. Projects communicate via ZMQ/IPC only |
| State model | Separate concerns | Blackboard = ephemeral runtime. Snapshot DAG = durable history |
| LLM management | Per-profile config | Each agent profile specifies provider, model, budget |
| CLI | Later | REPL-first. CLI as thin wrapper after core works |
| First projects | Compliance + Infra Watcher | Read-only agents first. Write/healing capabilities later |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SBCL Process: Project A                         │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                      CONDUCTOR                                │  │
│  │  Event Queue ──┐                                              │  │
│  │  Timer Heap  ──┼──▶ Tick Handler ──┬──▶ Fast Path (code)     │  │
│  │  Mailboxes   ──┘                   ├──▶ Spawn Agent (thread) │  │
│  │                                    └──▶ Slow Path (LLM)      │  │
│  └───────────────────────────────────────────────────────────────┘  │
│       │              │                    │                          │
│       │ ZMQ          │ Threads            │ Claude/LLM              │
│       ▼              ▼                    ▼                          │
│  ┌─────────┐   ┌──────────┐   ┌──────────────────────────┐         │
│  │ Cortex  │   │ Agent 1  │   │ Autopoiesis Core         │         │
│  │ Bridge  │   │ Agent 2  │   │ - Cognitive Loop         │         │
│  │ (ZMQ)   │   │ Agent N  │   │ - Snapshot DAG           │         │
│  └────┬────┘   └──────────┘   │ - Capabilities           │         │
│       │                       │ - Security / Permissions  │         │
│       │                       └──────────────────────────┘         │
│       │                                                             │
│  ┌────▼────────────────────────────────────────────────────────┐   │
│  │ Storage (local FS, Archil-backed)                            │   │
│  │ /mnt/archil/projects/project-a/{snapshots,agents,state.db}  │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
         │ ZMQ
         ▼
┌─────────────────────────────────────┐
│ Cortex (separate process)           │
│ - Adapters (ECS, Git, ...)          │
│ - LMDB event store                  │
│ - Query engine                      │
│ - Alert detector                    │
│ - ZMQ server + MCP server           │
└─────────────────────────────────────┘
```

Each project is an independent SBCL process. Multiple projects can run simultaneously on the same machine, connected to the same Cortex instance via ZMQ.

---

## Monorepo Directory Structure

```
ap/
├── autopoiesis.asd                    # Main system (core framework)
│
├── src/                               # Core framework
│   ├── core/
│   │   ├── packages.lisp
│   │   ├── s-expr.lisp
│   │   ├── cognitive-primitives.lisp
│   │   ├── thought-stream.lisp
│   │   ├── extension-compiler.lisp
│   │   ├── recovery.lisp
│   │   ├── profiling.lisp
│   │   ├── config.lisp
│   │   ├── conditions.lisp
│   │   ├── project-loader.lisp       # NEW: Project loading & manifest parsing
│   │   └── project-storage.lisp      # NEW: Per-project storage (Archil-backed)
│   ├── agent/
│   ├── snapshot/
│   ├── interface/
│   ├── viz/
│   ├── holodeck/
│   ├── conductor/                     # NEW: Per-project conductor
│   │   ├── packages.lisp
│   │   ├── conductor.lisp            # Main struct, loop, work-item classification
│   │   ├── scheduler.lisp            # Timer heap, cron parsing
│   │   ├── events.lisp               # Event queue, routing
│   │   ├── spawner.lisp              # Agent spawning, supervision (bt:make-thread)
│   │   ├── blackboard.lisp           # Ephemeral shared state
│   │   ├── triggers.lisp             # deftrigger macro, scheduled + conditional
│   │   └── profiles.lisp             # Agent profile loading (sexpr + CORE.md)
│   ├── integration/
│   │   ├── cortex-bridge.lisp        # NEW: ZMQ bridge to Cortex
│   │   ├── claude-bridge.lisp        # Existing Claude API
│   │   └── ...
│   ├── security/
│   ├── monitoring/
│   └── autopoiesis.lisp
│
├── capabilities/                      # Shared capability library (NEW)
│   ├── capabilities.asd
│   ├── common/
│   │   ├── packages.lisp
│   │   ├── git-ops.lisp              # Git operations
│   │   ├── file-analysis.lisp        # Code analysis
│   │   ├── reporting.lisp            # Report generation
│   │   └── cost-tracking.lisp        # Token/cost metering, budgets
│   ├── infra/
│   │   ├── packages.lisp
│   │   ├── k8s-ops.lisp              # K8s read operations
│   │   ├── diagnostics.lisp          # System diagnostics
│   │   └── remediation.lisp          # Common fixes (future)
│   ├── compliance/
│   │   ├── packages.lisp
│   │   ├── rules-engine.lisp         # Rule evaluation
│   │   ├── evidence.lisp             # Evidence collection
│   │   └── reporting.lisp            # Compliance reports
│   └── knowledge-graph/
│       ├── packages.lisp
│       ├── graph.lisp                # S-expr graph structure
│       ├── queries.lisp              # Pattern matching
│       └── persistence.lisp          # Graph serialization
│
├── projects/                          # Agent projects (NEW)
│   ├── compliance-agent/
│   │   ├── project.sexpr             # Project manifest
│   │   ├── compliance-agent.asd      # ASDF system
│   │   ├── src/
│   │   │   ├── packages.lisp
│   │   │   ├── agent.lisp            # Agent class definition
│   │   │   ├── scanner.lisp          # Compliance scanning
│   │   │   └── reporter.lisp         # Report generation
│   │   ├── rules/                    # Compliance rules (sexpr)
│   │   │   ├── soc2/
│   │   │   ├── hipaa/
│   │   │   └── gdpr/
│   │   ├── capabilities/             # Project-local capability overrides
│   │   ├── profiles/                 # Agent profiles for this project
│   │   │   ├── conductor/
│   │   │   │   └── CORE.md           # Conductor behavior for this project
│   │   │   └── compliance-scanner/
│   │   │       └── CORE.md           # Scanner agent behavior
│   │   ├── config/
│   │   │   ├── dev.sexpr
│   │   │   └── prod.sexpr
│   │   └── test/
│   │       └── compliance-tests.lisp
│   │
│   └── infra-watcher/
│       ├── project.sexpr
│       ├── infra-watcher.asd
│       ├── src/
│       │   ├── packages.lisp
│       │   ├── agent.lisp            # Agent class definition
│       │   ├── watcher.lisp          # Anomaly detection
│       │   └── diagnoser.lisp        # Root cause analysis (read-only)
│       ├── profiles/
│       │   ├── conductor/
│       │   │   └── CORE.md
│       │   └── infra-watcher/
│       │       └── CORE.md
│       ├── config/
│       │   ├── dev.sexpr
│       │   └── prod.sexpr
│       └── test/
│           └── infra-tests.lisp
│
├── test/                              # Core framework tests
├── docs/
├── thoughts/
├── ralph/
├── scripts/
│   ├── test.sh
│   ├── build.sh
│   └── run-project.sh                # NEW: Launch a project in its own SBCL
├── Dockerfile
└── docker-compose.yml
```

---

## Core Components

### 1. Conductor (`src/conductor/conductor.lisp`)

Each project gets its own conductor — the always-running orchestrator within that project's SBCL process.

```lisp
(defstruct conductor
  project-id       ; Which project this conductor manages
  event-queue      ; External events (Cortex alerts, webhooks, IPC)
  timer-heap       ; Scheduled actions (cron-style)
  mailboxes        ; Messages from spawned agents
  running-agents   ; Active child agents being supervised (threads)
  pending-results  ; Async work awaiting completion
  blackboard       ; Ephemeral runtime state (metrics, agent status)
  profiles         ; Loaded agent profiles
  config           ; Project configuration
  state)           ; :running, :paused, :stopping

(defun conductor-loop (conductor)
  "Main orchestrator loop."
  (loop while (eq (conductor-state conductor) :running)
    do (let ((work-items (collect-pending-work conductor)))
         (dolist (item work-items)
           (case (work-item-type item)
             ;; FAST PATH: Pure programmatic, no LLM
             (:timer-fired     (execute-scheduled-action conductor item))
             (:event-received  (route-event-to-handler conductor item))
             (:agent-completed (handle-agent-result conductor item))
             (:agent-failed    (handle-agent-failure conductor item))
             ;; SLOW PATH: Needs LLM reasoning
             (:needs-triage    (spawn-triage-agent conductor item))
             (:needs-decision  (run-cognitive-cycle conductor item)))))
       (sleep 0.1)))

(defun collect-pending-work (conductor)
  "Non-blocking check of all work sources. Returns list of work-items."
  (nconc
    (drain-queue (conductor-event-queue conductor))
    (pop-due-timers (conductor-timer-heap conductor))
    (collect-agent-messages (conductor-mailboxes conductor))
    (collect-completed-futures (conductor-pending-results conductor))))
```

### 2. Work Item Classification

The conductor decides: **code or cognition?**

```lisp
(defstruct work-item
  id
  type            ; :timer-fired, :event-received, :needs-decision, etc.
  source          ; Where it came from (:cortex, :timer, :agent, :user)
  payload         ; The actual data
  requires-llm-p  ; Does this need LLM reasoning?
  priority        ; For ordering
  deadline)       ; Optional time constraint

(defun classify-work-item (raw-event)
  "Decide if work can be handled programmatically or needs LLM."
  (cond
    ((scheduled-action-p raw-event)
     (make-work-item :type :timer-fired :requires-llm-p nil))
    ((agent-result-p raw-event)
     (make-work-item :type :agent-completed :requires-llm-p nil))
    ((and (event-p raw-event)
          (handler-registered-p (event-type raw-event)))
     (make-work-item :type :event-received :requires-llm-p nil))
    (t (make-work-item :type :needs-triage :requires-llm-p t))))
```

### 3. Agent Spawner (Threads within project process)

```lisp
(defun spawn-agent (conductor profile task)
  "Spawn a child agent as a thread within this project's process."
  (let ((agent (make-agent
                 :profile profile
                 :task task
                 :mailbox (make-mailbox)
                 :parent-conductor conductor)))
    (push agent (conductor-running-agents conductor))
    (bt:make-thread
      (lambda () (agent-run agent))
      :name (format nil "agent-~a" (agent-id agent)))
    agent))

(defun handle-agent-failure (conductor work-item)
  "Supervision: retry, escalate, or mark failed."
  (let ((agent-id (work-item-source work-item))
        (error (work-item-payload work-item)))
    (case (classify-failure error)
      (:transient  (retry-agent conductor agent-id))
      (:permanent  (mark-failed conductor agent-id))
      (:unknown    (escalate-to-llm conductor agent-id error)))))
```

### 4. Cortex Bridge (`src/integration/cortex-bridge.lisp`)

ZMQ-based S-expression protocol for tight Cortex integration:

```lisp
(defvar *cortex-zmq-endpoint* "tcp://localhost:5555"
  "ZMQ endpoint for Cortex communication")

(defun cortex-query (query &key timeout)
  "Send S-expression query to Cortex, receive S-expression response."
  (zmq-send *cortex-socket* query)
  (zmq-recv *cortex-socket* :timeout (or timeout 5000)))

(defun cortex-query-recent-events (&key (since 300) entity-type)
  "Query Cortex for events in the last N seconds."
  (cortex-query
    `(query :entity-type ,entity-type :since ,(- (get-universal-time) since))))

(defun cortex-subscribe-alerts (handler)
  "Subscribe to Cortex alert stream via ZMQ PUB/SUB."
  (let ((sub-socket (zmq-subscribe *cortex-alert-endpoint* :alert)))
    (bt:make-thread
      (lambda ()
        (loop (let ((alert (zmq-recv sub-socket)))
                (funcall handler alert))))
      :name "cortex-alert-listener")))

(defun start-cortex-bridge (conductor)
  "Connect Cortex event stream to conductor's event queue."
  (cortex-subscribe-alerts
    (lambda (alert)
      (queue-event (conductor-event-queue conductor)
        (make-work-item
          :type :event-received
          :source :cortex
          :payload alert
          :requires-llm-p (alert-needs-reasoning-p alert)
          :priority (alert-severity-to-priority alert))))))
```

### 5. Trigger System (`src/conductor/triggers.lisp`)

```lisp
(defmacro deftrigger (name &key type event-type condition cron interval
                               action requires-llm)
  "Define a trigger that the conductor evaluates."
  `(register-trigger *conductor*
     (make-trigger
       :name ',name
       :type ,type
       :event-type ,event-type
       :condition ,condition
       :cron ,cron
       :interval ,interval
       :action ,action
       :requires-llm-p ,requires-llm)))

;; Scheduled (fast path)
(deftrigger periodic-health-check
  :type :scheduled
  :interval 30
  :action (lambda () (ping-all-services))
  :requires-llm nil)

;; Condition-based (may need slow path)
(deftrigger infrastructure-alert
  :type :condition
  :event-type :cortex
  :condition (lambda (event) (>= (event-severity event) :warning))
  :action :spawn-incident-agent
  :requires-llm t)
```

### 6. Agent Profiles (`src/conductor/profiles.lisp`)

Profiles combine structured sexpr config with markdown LLM guidance:

```lisp
(defstruct agent-profile
  name
  core-prompt-path         ; Path to CORE.md
  core-prompt              ; Loaded content of CORE.md
  llm-config               ; (:provider :claude :model "opus" :budget 100)
  enabled-capabilities     ; What this profile can do
  human-approval-actions   ; Actions requiring approval
  max-runtime              ; Timeout before killing
  retry-policy)            ; (:max-retries 3 :backoff :exponential)

(defun load-profile (project-path profile-name)
  "Load agent profile from project's profiles/ directory."
  (let* ((profile-dir (merge-pathnames
                        (format nil "profiles/~a/" profile-name)
                        project-path))
         (core-md (merge-pathnames "CORE.md" profile-dir))
         (config-sexpr (merge-pathnames "config.sexpr" profile-dir)))
    (make-agent-profile
      :name profile-name
      :core-prompt-path core-md
      :core-prompt (when (probe-file core-md)
                     (uiop:read-file-string core-md))
      ;; Structured config from sexpr
      ;; ... load and merge with defaults
      )))
```

### 7. Blackboard (Ephemeral Runtime State)

Separate from the durable snapshot DAG. Holds metrics, agent status, working hypotheses:

```lisp
(defstruct blackboard
  (entities (make-hash-table :test 'equal))     ; Known entities (from Cortex)
  (agent-states (make-hash-table :test 'equal)) ; Status of spawned agents
  (metrics (make-hash-table :test 'equal))      ; Counters, gauges
  (hypotheses '())                               ; Current theories
  (lock (bt:make-lock "blackboard")))            ; Thread safety

(defun blackboard-put (bb key value)
  (bt:with-lock-held ((blackboard-lock bb))
    (setf (gethash key (blackboard-entities bb)) value)))

(defun blackboard-get (bb key)
  (bt:with-lock-held ((blackboard-lock bb))
    (gethash key (blackboard-entities bb))))
```

The snapshot DAG remains the durable store — decisions, observations, agent thoughts, and full state snapshots go there for time-travel. The blackboard is lost on restart.

### 8. Project Storage (`src/core/project-storage.lisp`)

Per-project isolated storage. Archil transparently handles S3 sync — the code just uses local filesystem paths:

```lisp
(defvar *storage-base-path*
  (pathname (or (uiop:getenv "AUTOPOIESIS_STORAGE_PATH")
                "/mnt/archil/"))
  "Base path for project storage. Archil mounts S3 here transparently.")

(defclass project-storage ()
  ((project-id :initarg :project-id :accessor project-id)
   (base-path :initarg :base-path :accessor base-path)
   (snapshot-store :accessor project-snapshot-store)
   (branch-manager :accessor project-branch-manager)
   (state-db-path :accessor state-db-path)
   (initialized-p :initform nil :accessor initialized-p)))

(defun make-project-storage (project-id)
  "Create storage namespace for a project."
  (let* ((project-path (merge-pathnames
                         (make-pathname :directory
                           (list :relative "projects" project-id))
                         *storage-base-path*))
         (storage (make-instance 'project-storage
                    :project-id project-id
                    :base-path project-path)))
    (ensure-project-directories project-path)
    (setf (state-db-path storage) (merge-pathnames "state.db" project-path))
    (setf (project-snapshot-store storage)
          (make-instance 'persistence-manager
            :base-path (merge-pathnames "snapshots/" project-path)))
    (setf (project-branch-manager storage)
          (make-instance 'branch-manager
            :persistence (project-snapshot-store storage)))
    (setf (initialized-p storage) t)
    storage))
```

Storage layout on disk (Archil-backed):
```
/mnt/archil/projects/
├── compliance-agent/
│   ├── state.db          # SQLite metadata
│   ├── snapshots/        # Content-addressable snapshot DAG
│   ├── agents/           # Per-agent state
│   ├── branches/         # Branch metadata
│   ├── logs/             # Project logs
│   └── cache/            # LRU cache
└── infra-watcher/
    └── ...
```

### 9. Project Manifest (`project.sexpr`)

```lisp
(:project
 :id "compliance-agent"
 :name "Compliance Agent"
 :version "0.1.0"
 :system-name :compliance-agent

 :dependencies
 (:capabilities ("compliance/rules-engine"
                  "compliance/evidence"
                  "compliance/reporting"
                  "common/git-ops"
                  "common/reporting"))

 :profiles
 ((:name "conductor"
   :llm (:provider :claude :model "sonnet" :budget-usd 10.0))
  (:name "compliance-scanner"
   :llm (:provider :claude :model "haiku" :budget-usd 5.0)
   :capabilities (scan-k8s-config scan-git-repos evaluate-rules)
   :human-approval-actions ()
   :max-runtime 600))

 :cortex
 (:zmq-endpoint "tcp://localhost:5555"
  :subscribe-alerts t
  :alert-filter (:entity-types (:ecs-service :ecs-task)))

 :storage
 (:namespace "compliance-agent"
  :cache-size 500)

 :description "Continuous compliance monitoring agent"
 :author "reuben"
 :tags ("compliance" "soc2" "hipaa" "gdpr"))
```

---

## Integration Points

### Cortex → Autopoiesis (Perception)

| Cortex concept | Autopoiesis mapping |
|----------------|---------------------|
| `trace-event` | `make-observation :source :cortex` |
| `entity` | Focus in agent's context window |
| `alert` | High-priority work-item in conductor's event queue |
| `checkpoint` | Cross-linked to Autopoiesis snapshot ID |

### Autopoiesis → Cortex (Action)

| Autopoiesis concept | Cortex mapping |
|---------------------|----------------|
| Action thought | Logged to Cortex event store via ZMQ |
| Snapshot created | Checkpoint ID stored in metadata |
| Decision made | Event with rationale stored for audit |

---

## Capabilities (Shared + Overridable)

Capabilities are optional modules that projects declare as dependencies. They load via ASDF and register themselves with the agent's capability system.

**Shared capabilities** live in `capabilities/`. Projects list which ones they need in `project.sexpr`.

**Project-local overrides** live in `projects/<name>/capabilities/`. If a project provides a capability with the same name as a shared one, the project-local version takes precedence.

Loading order:
1. Shared capabilities from `capabilities/` (as declared in manifest)
2. Project-local capabilities from `projects/<name>/capabilities/` (override)
3. Capability registry updated with final set

---

## Implementation Phases

### Phase 1: Conductor Core

**Goal**: Per-project conductor with event loop, timer heap, work-item classification.

**New files**:
- `src/conductor/packages.lisp`
- `src/conductor/conductor.lisp` — Main struct and loop
- `src/conductor/scheduler.lisp` — Timer heap, cron parsing
- `src/conductor/events.lisp` — Event queue, routing
- `src/conductor/work-items.lisp` — Classification logic
- `src/conductor/blackboard.lisp` — Ephemeral state

**Modified files**:
- `autopoiesis.asd` — Add conductor module

**Deliverables**:
- [ ] Conductor struct with event queue, timer heap, mailboxes
- [ ] `conductor-loop` runs and processes work items
- [ ] `classify-work-item` distinguishes fast/slow path
- [ ] Timer heap fires scheduled actions
- [ ] Blackboard for ephemeral state
- [ ] Tests for conductor loop, timer, classification

### Phase 2: Project Infrastructure

**Goal**: Project loading, storage, manifest parsing, process isolation.

**New files**:
- `src/core/project-loader.lisp` — Manifest parsing, ASDF loading
- `src/core/project-storage.lisp` — Archil-backed per-project storage
- `scripts/run-project.sh` — Launch project in separate SBCL process

**New directories**:
- `capabilities/` with `capabilities.asd`
- `projects/` directory

**Deliverables**:
- [ ] `(load-project "compliance-agent")` parses manifest, loads deps, initializes storage
- [ ] Per-project snapshot isolation verified on Archil mount
- [ ] `run-project.sh` launches a project in its own SBCL process
- [ ] Manifest validation with clear error messages
- [ ] Tests for manifest parsing, storage initialization

### Phase 3: Cortex ZMQ Bridge

**Goal**: Connect Cortex to conductor via ZMQ.

**New files**:
- `src/integration/cortex-bridge.lisp` — ZMQ client, query, subscribe

**Cortex-side work**:
- ZMQ server endpoint in Cortex (S-expression protocol)
- Alert PUB/SUB channel

**Deliverables**:
- [ ] `cortex-query` sends S-expression, receives S-expression response
- [ ] `cortex-subscribe-alerts` streams alerts to conductor event queue
- [ ] Conductor receives Cortex alerts and classifies them
- [ ] Tests with mock ZMQ endpoint

### Phase 4: Agent Spawning & Profiles

**Goal**: Conductor spawns agents from profiles with supervision.

**New files**:
- `src/conductor/spawner.lisp` — Thread-based agent spawning, supervision
- `src/conductor/profiles.lisp` — Profile loading (sexpr + CORE.md)
- `src/conductor/triggers.lisp` — `deftrigger` macro

**Modified files**:
- `src/agent/cognitive-loop.lisp` — Add `perceive-from-cortex` method

**New directories** (per project):
- `projects/<name>/profiles/conductor/CORE.md`
- `projects/<name>/profiles/<agent>/CORE.md`

**Deliverables**:
- [ ] `spawn-agent` creates thread with profile-defined capabilities
- [ ] Supervision: retry transient, escalate permanent, LLM for unknown failures
- [ ] Profiles load CORE.md + sexpr config
- [ ] `deftrigger` for scheduled and condition-based triggers
- [ ] LLM calls respect per-profile provider/model/budget config
- [ ] Tests for spawning, supervision, profile loading

### Phase 5: Compliance Agent (First Project)

**Goal**: Complete read-only compliance agent project.

**New files**:
- `projects/compliance-agent/project.sexpr`
- `projects/compliance-agent/compliance-agent.asd`
- `projects/compliance-agent/src/{packages,agent,scanner,reporter}.lisp`
- `projects/compliance-agent/rules/soc2/*.sexpr`
- `projects/compliance-agent/rules/hipaa/*.sexpr`
- `projects/compliance-agent/rules/gdpr/*.sexpr`
- `projects/compliance-agent/profiles/conductor/CORE.md`
- `projects/compliance-agent/profiles/compliance-scanner/CORE.md`
- `projects/compliance-agent/config/{dev,prod}.sexpr`

**Shared capabilities**:
- `capabilities/compliance/rules-engine.lisp`
- `capabilities/compliance/evidence.lisp`
- `capabilities/compliance/reporting.lisp`
- `capabilities/common/git-ops.lisp`
- `capabilities/common/reporting.lisp`

**Deliverables**:
- [ ] Compliance agent scans K8s configs and git repos via Cortex
- [ ] SOC2/HIPAA/GDPR rule evaluation
- [ ] Report generation
- [ ] Full audit trail in snapshot DAG
- [ ] E2E test: Cortex alert → scan → detect → report

### Phase 6: Infrastructure Watcher (Second Project)

**Goal**: Read-only infrastructure monitoring agent.

**New files**:
- `projects/infra-watcher/project.sexpr`
- `projects/infra-watcher/infra-watcher.asd`
- `projects/infra-watcher/src/{packages,agent,watcher,diagnoser}.lisp`
- `projects/infra-watcher/profiles/conductor/CORE.md`
- `projects/infra-watcher/profiles/infra-watcher/CORE.md`
- `projects/infra-watcher/config/{dev,prod}.sexpr`

**Shared capabilities**:
- `capabilities/infra/k8s-ops.lisp`
- `capabilities/infra/diagnostics.lisp`

**Deliverables**:
- [ ] Watcher detects anomalies from Cortex event stream
- [ ] Diagnoser performs read-only root cause analysis
- [ ] Findings reported (no remediation — that comes later)
- [ ] E2E test: Cortex alert → detect anomaly → diagnose → report

### Phase 7: Cost Tracking & Polish

**Goal**: Budget enforcement, developer docs, cross-project cleanup.

**Deliverables**:
- [ ] `capabilities/common/cost-tracking.lisp` — Per-profile LLM budget enforcement
- [ ] Budget alerts (warn at 80%, stop at 100%)
- [ ] Project creation guide (REPL-based)
- [ ] Capability development guide
- [ ] Profile authoring guide (CORE.md patterns)

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| ZMQ integration complexity | Medium | Medium | Start with simple REQ/REP, add PUB/SUB incrementally |
| Archil latency for SQLite | High | Medium | Local SSD cache, batch writes, test early |
| Per-process overhead | Medium | Low | SBCL images are lightweight. Only concern at 10+ projects |
| Cortex ZMQ server doesn't exist yet | High | High | Must build Cortex-side ZMQ endpoint in Phase 3 |
| Thread safety in conductor | High | Medium | Careful lock discipline, blackboard lock, agent mailboxes |
| LLM cost runaway | Medium | Medium | Per-profile budgets enforced in cost-tracking capability |

---

## Success Metrics

### Phase 1-2 (Foundation)
- [ ] Conductor loop runs, processes timer events, classifies work items
- [ ] `(load-project "compliance-agent")` works in own SBCL process
- [ ] Snapshots persist correctly on Archil mount

### Phase 3-4 (Integration)
- [ ] Cortex alerts arrive in conductor event queue via ZMQ
- [ ] Conductor spawns agent threads from profiles
- [ ] Agent failures are supervised (retry/escalate)

### Phase 5-6 (Agent Projects)
- [ ] Compliance agent scans real infrastructure via Cortex
- [ ] Infra watcher detects anomalies from Cortex event stream
- [ ] Full audit trail in snapshot DAG for both

### Phase 7 (Polish)
- [ ] LLM budgets enforced per-profile
- [ ] Documentation covers project creation and capability development

---

## Open Questions

1. **Capability versioning**: How to handle breaking changes to shared capabilities?
   - Leaning toward: SemVer in capabilities.asd, projects pin versions in manifest

2. **Cross-project communication**: If two projects need to talk (e.g., compliance finding → infra watcher), how?
   - Leaning toward: Via Cortex as intermediary (both write/read events). No direct IPC between project processes.

3. **Cortex ZMQ protocol spec**: Need to define the exact S-expression message format.
   - Needs design work before Phase 3.
