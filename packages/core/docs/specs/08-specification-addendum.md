# Specification Addendum: Design Decisions & Clarifications

**Version:** 0.1.0-draft
**Date:** 2026-02-02
**Status:** Approved design decisions from specification review

This document captures design decisions made during the specification review process, addressing gaps and ambiguities identified in docs 00-07.

---

## 1. Snapshot Architecture Redesign

### 1.1 Event Sourcing Model

**Decision:** Replace full-state snapshots with an event sourcing architecture.

The original spec implied capturing full agent state on every thought, decision, and action—leading to ~25GB/day per active agent. The revised architecture:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Event Log (Append-Only)                       │
├─────────────────────────────────────────────────────────────────────┤
│ [thought-added] [binding-changed] [decision-made] [CHECKPOINT] ...  │
└─────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    │         Checkpoint Store          │
                    │  (Full state at key moments)      │
                    └───────────────────────────────────┘
```

**Event Types:**
- `(:thought-added :id <uuid> :content <sexpr> :timestamp <time>)`
- `(:binding-changed :name <symbol> :old-value <sexpr> :new-value <sexpr>)`
- `(:capability-granted :name <symbol> :capability <sexpr>)`
- `(:capability-revoked :name <symbol>)`
- `(:decision-made :options <list> :selected <sexpr> :reasoning <sexpr>)`
- `(:action-executed :capability <symbol> :args <list> :result <sexpr>)`
- `(:human-intervention :type <keyword> :payload <sexpr>)`
- `(:checkpoint-created :id <uuid> :full-state <sexpr>)`

**Checkpoints Created At:**
- Decision points (natural "save game" moments)
- Before/after human intervention
- Fork/branch points
- Configurable time intervals (default: hourly)
- Configurable event count intervals (default: every 1000 events)

**State Reconstruction:**
1. Find nearest checkpoint before target point
2. Replay events from checkpoint to target
3. Cache materialized state in memory

**Storage Efficiency:**
- Events: ~1-5KB each, ~170MB/day per active agent
- Checkpoints: ~300KB each, ~7MB/day per active agent
- **Total: ~180MB/day** (vs. ~25GB/day with full snapshots)

### 1.2 Snapshot ID Strategy

**Decision:** UUID for identity, content hash for comparison.

```lisp
(defclass snapshot ()
  ((id :type string
       :initform (generate-uuid)
       :documentation "Unique identifier (UUID v4)")
   (content-hash :type string
                 :documentation "SHA-256 hash of immutable cognitive state")
   (timestamp :type local-time:timestamp)
   (parent-id :type (or null string))
   ...))
```

**Content Hash Includes:**
- Agent bindings (sorted by key)
- Capability set (sorted by name)
- Thought stream content
- Active context items

**Content Hash Excludes:**
- Timestamp
- Sequence numbers
- Annotations (tags, notes, bookmarks)
- Agent ID (enables cross-agent state comparison)

**Benefits:**
- UUIDs: Simple references, no collision risk
- Content hash: O(1) state comparison, branch convergence detection

### 1.3 Checkpoint Retention Policy

**Decision:** User-controlled retention with decision checkpoints kept forever by default.

**Default Policy:**
- Decision checkpoints: Kept forever
- Fork/merge checkpoints: Kept forever
- Human intervention checkpoints: Kept forever
- Time-based checkpoints: Suggest pruning after 7 days (user must confirm)
- Abandoned branch checkpoints: Suggest pruning (user must confirm)

**Key Principle:** System NEVER automatically deletes checkpoints. It may suggest pruning, but user must explicitly approve.

**Configuration:**
```lisp
(defparameter *retention-policy*
  '(:decision-checkpoints :forever
    :fork-checkpoints :forever
    :human-checkpoints :forever
    :time-checkpoints (:suggest-prune-after-days 7)
    :abandoned-branches (:suggest-prune t)))
```

### 1.4 Branch Merging Strategy

**Decision:** Auto-merge with full audit trail (last-write-wins).

When merging two branches that modified the same field:
1. Last-write-wins based on event timestamp
2. Both event sequences preserved in merged log
3. Merge event explicitly records conflict resolution
4. Human can review and revert via event log inspection

```lisp
(:merge-completed
 :source-branch "experiment-a"
 :target-branch "main"
 :conflicts ((:binding "goal"
              :source-value "explore options"
              :target-value "optimize performance"
              :resolved-to :source
              :resolution-reason :last-write-wins))
 :source-events-preserved t
 :target-events-preserved t)
```

### 1.5 Agent Spawn Hierarchy

**Decision:** Shared ancestry with independent futures (fork-based spawning).

When parent agent spawns child:
1. Child's event log starts as a fork from parent's current state
2. Child receives a checkpoint of parent's state at spawn time
3. From spawn point forward, logs diverge independently
4. Metadata links parent spawn event to child genesis event

```
Parent Log: ─[E1]─[E2]─[E3]─[spawn-child]─[E4]─[E5]─ ...
                          │
                          └─► Child Log: ─[genesis]─[C1]─[C2]─ ...
```

---

## 2. Security Architecture

### 2.1 Threat Model

**Primary Security Boundary:** Firecracker microVM

```
┌─────────────────────────────────────────────────────────────┐
│  Host (trusted orchestrator)                                │
│  ┌───────────────────┐  ┌───────────────────┐              │
│  │  Firecracker VM   │  │  Firecracker VM   │  ...         │
│  │  ┌─────────────┐  │  │  ┌─────────────┐  │              │
│  │  │ Agent (Lisp)│  │  │  │ Agent (Lisp)│  │              │
│  │  │  Sandbox    │  │  │  │  Sandbox    │  │              │
│  │  └─────────────┘  │  │  └─────────────┘  │              │
│  └───────────────────┘  └───────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

**Defense Layers:**

| Layer | Responsibility |
|-------|----------------|
| Firecracker VM | Process isolation, resource hard limits, network policy |
| Lisp Sandbox | Crash isolation, prevent accidental damage |
| Policy Engine | Approval gates for dangerous operations |
| Audit Trail | Full event log for investigation |

### 2.2 Lisp Sandbox Purpose

**Decision:** Sandbox focuses on crash isolation, not adversarial security.

**Sandbox Goals:**
- Catch infinite loops (via resource budgets)
- Prevent memory exhaustion (via allocation monitoring)
- Isolate crashes (one agent crash doesn't affect others in same VM)
- Block obviously dangerous symbols (`eval`, `compile`, `load`, etc.)

**Sandbox Non-Goals:**
- Preventing determined adversarial escape (that's the VM's job)
- Capability-level isolation (that's the policy engine's job)

### 2.3 Policy Engine for Dangerous Operations

**Decision:** Policy-based auto-approval for dangerous operations.

**Dangerous Operations:**
- Filesystem writes outside sandbox directory
- Network access
- Self-modification (capability/heuristic changes)
- Spawning new agents
- High-cost LLM API calls (configurable threshold)

**Policy Format:**
```lisp
(defparameter *default-policy*
  '(;; Network policies
    (:allow :network :to "*.anthropic.com")
    (:allow :network :to "localhost:*")
    (:deny :network :to "*" :action :require-approval)

    ;; Filesystem policies
    (:allow :filesystem :write :path "/tmp/agent-sandbox/*")
    (:deny :filesystem :write :path "*" :action :require-approval)

    ;; Self-modification policies
    (:allow :self-modify :type :heuristic :action :sandbox-then-approve)
    (:deny :self-modify :type :capability :action :require-approval)

    ;; Cost policies
    (:deny :llm-call :cost-above 0.10 :action :require-approval)))
```

**Policy Actions:**
- `:allow` - Proceed without approval
- `:deny` with `:require-approval` - Block until human approves
- `:deny` with `:sandbox-then-approve` - Apply to sandbox, human promotes to active

### 2.4 Self-Modification Sandbox

**Decision:** Self-modifications apply to sandbox state first; human promotes to active.

**Workflow:**
1. Agent proposes self-modification (new capability, heuristic, etc.)
2. Modification applied to "draft" sandbox state
3. Agent can test draft state in isolation
4. Human reviews and either:
   - Promotes to active state
   - Discards draft
   - Requests modifications

**Configurable:** Policy can allow auto-promotion for low-risk modifications.

### 2.5 Agent Introspection Limits

**Decision:** Hide security-sensitive data; everything else visible.

**Hidden from Agent Introspection:**
- API keys and credentials
- Human override history (prevents gaming)
- Security policy definitions (prevents circumvention)
- Other agents' internal state

**Visible to Agent:**
- Own thought stream
- Own bindings and capabilities
- Own event history
- Own checkpoint content
- Feedback context (transparent and editable)

---

## 3. Resource Management

### 3.1 Per-Agent Resource Budgets

**Decision:** Configurable per-agent budgets with automatic pause on exceed.

**Budget Types:**
```lisp
(defclass agent-budget ()
  ((cpu-seconds :initform 3600 :documentation "Max CPU seconds per hour")
   (memory-mb :initform 1024 :documentation "Max memory in MB")
   (events-per-hour :initform 10000 :documentation "Max events written per hour")
   (llm-calls-per-hour :initform 100 :documentation "Max LLM API calls per hour")
   (llm-cost-per-day :initform 10.0 :documentation "Max LLM cost in USD per day")))
```

**On Budget Exceeded:**
1. Create checkpoint
2. Pause agent
3. Notify human with budget details
4. Human decides: increase budget, resume with warning, terminate task

### 3.2 Stuck Detection

**Decision:** Resource limits + pattern detection (no confidence decay).

**Pattern Detection:**
- Repeated identical thoughts (>5 in sequence)
- Oscillating decisions (A→B→A→B pattern)
- Reasoning cycles (returning to same state within N events)

**On Stuck Detected:**
1. Create checkpoint
2. Pause agent
3. Notify human with pattern analysis
4. Human decides: redirect, provide input, terminate

---

## 4. Human Interface

### 4.1 Multi-Agent Attention Management

**Decision:** Priority queue with human context switching.

**Request Queue:**
```lisp
(defclass human-request-queue ()
  ((pending :type priority-queue :documentation "Pending requests by priority")
   (active :type (or null request) :documentation "Currently active interaction")
   (notification-count :type integer :initform 0)))
```

**Priority Levels:**
1. Critical: Errors, security alerts, policy violations
2. High: Approval requests for dangerous operations
3. Normal: Decision reviews, checkpoint suggestions
4. Low: Status updates, completion notifications

**Human Experience:**
- Notification count always visible
- Can switch context to any queued request
- Current interaction auto-checkpoints when switching
- Timeout applies per-request, not globally

### 4.2 Timeout Behavior (Configurable)

**Decision:** Action-based options, configurable per-project and per-agent.

**Available Actions:**
- `:suspend` - Checkpoint and wait indefinitely
- `:use-default` - Proceed with pre-configured safe default
- `:escalate` - Try alternate notification channels, then suspend
- `:retry` - Retry with longer timeout
- `:abort-task` - Abort current task, checkpoint state

**Configuration:**
```lisp
(defparameter *timeout-config*
  '(:default-timeout-seconds 300
    :default-action :suspend
    :escalation-channels (:email :sms)
    :escalation-timeout-seconds 900
    :per-severity
    ((:critical :action :escalate :timeout 60)
     (:high :action :suspend :timeout 300)
     (:normal :action :suspend :timeout 600)
     (:low :action :use-default :timeout 120))))
```

### 4.3 Human Interface Modes

**Decision:** Terminal REPL + simple web dashboard for MVP.

**Terminal Interface:**
- Primary interface for deep interaction
- Viewport with agent state, recent events, context
- Command-based input (continue, pause, redirect, etc.)
- Event log streaming

**Web Dashboard:**
- Monitoring multiple agents simultaneously
- High-level status overview
- Notification queue management
- Branch/checkpoint visualization
- Links to terminal for deep dives

### 4.4 Agent-to-Agent Communication

**Decision:** Policy-controlled direct communication.

**Default:** Agents can communicate directly within same project/deployment.

**Policy Controls:**
```lisp
(defparameter *agent-communication-policy*
  '(;; Allow direct communication within project
    (:allow :communicate :scope :same-project)
    ;; Require approval for cross-project
    (:deny :communicate :scope :cross-project :action :require-approval)
    ;; Log all communications (for audit)
    (:audit :communicate :all t)))
```

Human approves/configures policy once; doesn't need to review individual messages unless policy requires it.

---

## 5. LLM Integration Architecture

### 5.1 Abstraction Layer with Adapters

**Decision:** Abstract interface with pluggable adapters.

```
┌─────────────────────────────────────────┐
│         Agent Reasoning Layer           │
│  (uses abstract 'reasoning' capability) │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│           LLM Adapter Interface          │
├──────────┬──────────┬───────────────────┤
│ Claude   │ Opencode │  Direct API       │
│ Code     │ Adapter  │  Adapter          │
│ Adapter  │          │                   │
└──────────┴──────────┴───────────────────┘
```

**Adapter Interface:**
```lisp
(defgeneric llm-complete (adapter prompt &key model max-tokens tools))
(defgeneric llm-available-models (adapter))
(defgeneric llm-estimate-cost (adapter prompt model))
```

**Claude Code Adapter (Primary):**
- Uses Claude Code in headless mode (`-p` flag)
- Inherits Claude Code's model management and defaults
- Benefits from Claude Code pricing tiers
- Tool system passthrough

**Configuration:**
```lisp
(defparameter *llm-config*
  '(:adapter :claude-code
    :claude-code-path "/usr/local/bin/claude"
    :default-model :use-adapter-default  ; or specific model
    :fallback-adapter :direct-api
    :direct-api-key-env "ANTHROPIC_API_KEY"))
```

### 5.2 MCP Tool Namespace

**Decision:** Namespace by server with user-configurable aliases.

**Default Naming:**
```
server-name:tool-name

Examples:
  filesystem:read-file
  filesystem:write-file
  github:create-pr
  github:list-issues
```

**User Aliases:**
```lisp
(defparameter *tool-aliases*
  '(("read" . "filesystem:read-file")
    ("write" . "filesystem:write-file")
    ("pr" . "github:create-pr")))
```

**Conflict Resolution:**
- Namespaced names never conflict
- Aliases are user-controlled; conflicts warn but allow override
- First-defined alias wins if multiple defined

---

## 6. Crash Recovery

### 6.1 Write-Ahead Log (WAL)

**Decision:** WAL for all state-modifying operations.

**WAL Entry Format:**
```lisp
(:wal-entry
 :sequence <monotonic-id>
 :operation <operation-type>
 :payload <operation-data>
 :status :pending)  ; or :committed, :rolled-back
```

**Recovery Process:**
1. On startup, scan WAL for pending entries
2. For each pending entry:
   - If operation was partially applied, roll back
   - If operation was not started, discard
3. Mark all pending as rolled-back
4. Resume from last committed state

**Checkpoint Coordination:**
- Checkpoint includes WAL sequence number
- Events between checkpoint and WAL tip can be replayed
- Provides point-in-time recovery

---

## 7. Testing Strategy

### 7.1 Multi-Layered Testing Approach

**Decision:** Comprehensive testing with unit, property-based, and behavior-driven tests.

**Unit Tests (Core Layer):**
- S-expression utilities (hash, diff, patch, serialize)
- Event log operations (append, read, compact)
- Checkpoint creation and restoration
- WAL operations

**Property-Based Tests:**
- Any event sequence can be replayed to identical state
- Checkpoint + deltas = full state reconstruction
- Serialization round-trip preserves equality
- Content hash is deterministic for identical states

**Integration Tests (Per Phase):**
- Phase 1: S-expr utilities work with various data shapes
- Phase 2: Agent cognitive loop completes without errors
- Phase 3: Checkpoint/restore preserves agent state
- Phase 4: Human commands affect agent correctly
- Phase 5+: End-to-end scenarios with mocked LLM

**Behavior-Driven Scenarios:**
Each phase includes example scenarios that must pass:
```gherkin
Scenario: Agent restores from checkpoint
  Given an agent with 100 events after checkpoint
  When the system crashes and restarts
  Then the agent state matches pre-crash state
  And no events are duplicated or lost
```

### 7.2 Phase Validation Gates

**Decision:** Each phase ends with a validation gate before proceeding.

**Gate Criteria:**
1. All tests pass (unit, property, integration)
2. Demo scenario works end-to-end
3. Performance benchmarks met (if applicable)
4. Documentation updated
5. Security review (for phases with new attack surface)

**Phase-Specific Benchmarks:**
- Phase 1: S-expr operations < 1ms for typical sizes
- Phase 3: Checkpoint creation < 100ms, restoration < 500ms
- Phase 4: Human command response < 50ms
- Phase 5: LLM round-trip measured (baseline established)

---

## 8. Behavioral Model

### 8.1 Task-Scoped Behavior (No Persistent Personality)

**Decision:** Agents are blank slates; behavior configured per-task.

**Task Configuration:**
```lisp
(defclass task-config ()
  ((verbosity :type (member :minimal :normal :verbose))
   (exploration :type (member :conservative :balanced :exploratory))
   (confirmation-threshold :type float :documentation "0.0-1.0, when to ask human")
   (context-hints :type list :documentation "Domain-specific guidance")))
```

**Rationale:**
- Predictable behavior (no hidden learned state)
- Easy to test (same config = same behavior)
- Explicit control (user sets parameters, not emergent)

### 8.2 Feedback as Transparent Context

**Decision:** Past feedback shapes future reasoning via context, not hidden learning.

**Feedback Storage:**
```lisp
(:feedback
 :timestamp <time>
 :decision-id <uuid>
 :human-response :disagreed
 :human-reasoning "Should have checked permissions first"
 :context-injection "When performing file operations, always verify permissions before attempting write.")
```

**Key Properties:**
- All feedback visible in event log
- Feedback-derived context can be viewed and edited by human
- No opaque "weight adjustment" or hidden state changes
- Human can remove or modify feedback context entries

---

## 9. Visualization (MVP)

### 9.1 Simplified 3D Approach

**Decision:** Basic 3D with nodes and edges; defer visual polish.

**MVP Features:**
- Nodes represent checkpoints (spheres)
- Edges represent event sequences (lines)
- Color indicates checkpoint type (decision=blue, human=green, etc.)
- Click to inspect checkpoint details
- Basic camera controls (pan, zoom, rotate)

**Deferred to Post-MVP:**
- Hologram/glow effects
- Animated trails
- LOD system
- Fancy shaders

### 9.2 Terminal + Web Dashboard

**Terminal:**
- ASCII tree view of recent checkpoints
- Event log streaming
- Agent status display
- Command input

**Web Dashboard:**
- Agent cards with status
- Notification queue
- Simple branch visualization (2D graph)
- Links to terminal sessions

---

## 10. Scope Boundaries (v1.0)

### 10.1 Target Scale

**Decision:** Single user, 1-10 concurrent agents, single machine.

**Implications:**
- SQLite sufficient for storage
- No multi-tenant isolation needed
- No distributed coordination
- Optimize for simplicity over scale

### 10.2 Non-Goals (v1.0)

- **Not a multi-tenant SaaS platform** - Single user/deployment focus
- **Not a pre-built workflow library** - Agents define their own workflows
- **Not a conversation/chatbot framework** - Focus on autonomous reasoning
- **Not a general LLM wrapper** - Specific to agent cognition model

---

## Appendix A: Configuration Reference

### A.1 Complete Default Configuration

```lisp
(defparameter *autopoiesis-default-config*
  '(;; Storage
    :storage-backend :sqlite
    :storage-path #P"~/.autopoiesis/data/"
    :wal-enabled t

    ;; Checkpoints
    :checkpoint-interval-events 1000
    :checkpoint-interval-seconds 3600
    :checkpoint-on-decision t
    :checkpoint-on-human-intervention t

    ;; Retention
    :retention-policy (:decision-checkpoints :forever
                       :time-checkpoints (:suggest-prune-after-days 7))

    ;; Resource Budgets (per-agent defaults)
    :default-budget (:cpu-seconds 3600
                     :memory-mb 1024
                     :events-per-hour 10000
                     :llm-calls-per-hour 100
                     :llm-cost-per-day 10.0)

    ;; Human Interface
    :timeout-config (:default-timeout-seconds 300
                     :default-action :suspend)

    ;; LLM
    :llm-adapter :claude-code
    :llm-model :use-adapter-default

    ;; Security
    :sandbox-level :standard
    :policy-file #P"~/.autopoiesis/policy.lisp"

    ;; Visualization
    :viz-backend :simple-3d
    :web-dashboard-port 8080))
```

---

## Appendix B: Event Type Reference

### B.1 Complete Event Type Enumeration

```lisp
;; Cognitive Events
(:thought-added :id :content :timestamp :confidence)
(:binding-changed :name :old-value :new-value :reason)
(:decision-made :options :selected :reasoning :confidence)
(:action-executed :capability :args :result :duration)

;; Capability Events
(:capability-granted :name :capability :source)
(:capability-revoked :name :reason)
(:capability-modified :name :changes)

;; Checkpoint Events
(:checkpoint-created :id :type :trigger :full-state-size)
(:checkpoint-restored :id :events-replayed)

;; Branch Events
(:branch-created :name :from-checkpoint :reason)
(:branch-merged :source :target :conflicts :resolution)
(:branch-abandoned :name :reason)

;; Human Events
(:human-intervention :type :payload :human-id)
(:human-feedback :decision-id :response :reasoning)
(:human-override :original :replacement :reasoning)

;; Agent Lifecycle Events
(:agent-spawned :parent-id :child-id :initial-config)
(:agent-paused :reason :checkpoint-id)
(:agent-resumed :from-checkpoint)
(:agent-terminated :reason :final-checkpoint)

;; System Events
(:resource-limit-reached :resource :limit :actual)
(:stuck-detected :pattern :events-analyzed)
(:policy-violation :operation :policy-rule :action-taken)

;; Communication Events
(:message-sent :to-agent :content)
(:message-received :from-agent :content)
```

---

*End of Specification Addendum*
