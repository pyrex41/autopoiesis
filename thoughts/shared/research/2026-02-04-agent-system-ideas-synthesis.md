---
date: 2026-02-04T19:00:00Z
researcher: Claude
git_commit: ce02d6e563435d408a5eef84ebe465937f443d97
branch: main
repository: ap
topic: "Synthesis: Vision Documents vs Existing Infrastructure for Real Agent Systems"
tags: [research, synthesis, conductor, workspace, agent-systems, vision-vs-reality]
status: complete
last_updated: 2026-02-04
last_updated_by: Claude
---

# Synthesis: Vision Documents vs Existing Infrastructure

**Date**: 2026-02-04T19:00:00Z
**Researcher**: Claude
**Git Commit**: ce02d6e563435d408a5eef84ebe465937f443d97
**Branch**: main

## Research Question

The `thoughts/` directory contains several vision documents for building real stateful agent systems on top of Autopoiesis. Some visions require extensions of the base platform, others require an extension framework. This research synthesizes what's envisioned vs what's built, identifies gaps, and maps the path from current infrastructure to each vision.

## Source Documents

1. **Cortex Synthesis Plan** (`thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md`) — Conductor pattern for always-on orchestration with dual-mode execution
2. **Workspace Architecture Plan** (`thoughts/shared/plans/2026-02-04-workspace-architecture-plan.md`) — Monorepo with extensions, MCP servers, capabilities, and project isolation
3. **Real Agent Use Cases** (`thoughts/shared/research/2026-02-03-autopoiesis-real-agent-use-cases.md`) — 20 detailed use cases with difficulty ratings
4. **E2E Tests Analysis** (`thoughts/shared/research/2026-02-03-e2e-tests-vs-implementation.md`) — All 19 failing tests fixed; API alignment complete

---

## The Three Big Ideas

The vision documents converge on three distinct but complementary ideas for what to build on top of Autopoiesis:

### Idea 1: The Conductor (Always-On Orchestrator)

An always-running meta-agent that combines programmatic control flow with LLM reasoning. It watches events, runs scheduled jobs, spawns agents for complex work, and decides when to think vs when to just execute code.

**Key insight**: Most orchestration is *fast-path* (pure code, milliseconds). Only novel or complex situations need the *slow-path* (LLM reasoning, seconds). The conductor triages work items and routes accordingly.

### Idea 2: The Workspace (Extension Framework)

A monorepo-based project structure where agents, capabilities, MCP servers, and full projects live as independently loadable extensions. Each project gets isolated storage, its own manifest, and can be loaded/unloaded at runtime.

**Key insight**: The platform becomes a *host* for agent projects rather than a monolithic application. Extensions use ASDF for loading and Archil/S3 for per-project storage.

### Idea 3: The Use Cases (What Gets Built)

20 concrete agent systems ranging from self-healing infrastructure to multi-agent research teams to agent-as-a-service platforms. These are the *tenants* that would run on the conductor and live in the workspace.

---

## What Exists Today (Infrastructure Inventory)

### Fully Implemented and Production-Ready

| Component | Location | What It Does |
|-----------|----------|-------------|
| **Cognitive Loop** | `src/agent/cognitive-loop.lisp` | Five-phase generic cycle: perceive → reason → decide → act → reflect. Specializable via CLOS methods. |
| **Agent Class** | `src/agent/agent.lisp` | Agent with ID, name, state, capabilities, thought-stream, parent/children hierarchy. Lifecycle: initialized → running → paused → stopped. |
| **Agent Registry** | `src/agent/registry.lisp` | Global hash table mapping agent IDs to agents. Register, unregister, find, list, running-agents. |
| **Agent Spawning** | `src/agent/spawner.lisp` | `spawn-agent` creates child from parent, inherits capabilities, tracks parent-child. |
| **Message Passing** | `src/agent/builtin-capabilities.lisp` | Per-agent mailboxes (`*agent-mailboxes*`). `send-message` / `receive-messages` with clear-on-read. |
| **Capability System** | `src/agent/capability.lisp` | Global capability registry. `defcapability` macro. `invoke-capability` by name. |
| **Agent-Defined Capabilities** | `src/agent/agent-capability.lisp` | Agents can define, test, and promote their own capabilities through a draft → testing → promoted lifecycle. |
| **Extension Compiler** | `src/core/extension-compiler.lisp` | Sandboxed compilation with three levels (strict/moderate/trusted). Forbidden symbol blacklist, allowed symbol whitelist. Auto-disable after 3 errors. |
| **Learning System** | `src/agent/learning.lisp` | Experience recording, n-gram pattern extraction, heuristic generation, confidence tracking, decision weight adjustment. |
| **Thought Stream** | `src/core/thought-stream.lisp` | Append-only vector with ID index. Compaction, archiving, serialization. |
| **Context Window** | `src/agent/context-window.lisp` | Priority queue with token-budget. Focus/defocus operations. |
| **Event Bus** | `src/integration/events.lisp` | Pub/sub with 14 event types. Type-specific and global handlers. Circular history buffer (1000 events). |
| **Provider System** | `src/integration/provider*.lisp` | Abstract provider protocol with Claude Code implementation. Subprocess management, timeout, JSON parsing. |
| **Provider-Backed Agent** | `src/integration/provider-agent.lisp` | Agent subclass that delegates cognition to CLI providers. Records exchanges as thoughts. |
| **Claude API Bridge** | `src/integration/claude-bridge.lisp` | Direct HTTP client for Claude API. Request/response, tool use. |
| **MCP Client** | `src/integration/mcp-client.lisp` | Full MCP stdio transport. Connect, discover tools/resources, call tools. Auto-registers as capabilities. |
| **Session Management** | `src/integration/session.lisp` | Per-agent Claude conversation sessions with message history, tool sync. |
| **Tool Registry** | `src/integration/tool-registry.lisp` | External tool wrapping with schema generation for Claude. |
| **Builtin Tools** | `src/integration/builtin-tools.lisp` | 14 tools: file ops, web fetch, shell commands, git operations. |
| **Snapshot DAG** | `src/snapshot/` | Content-addressable (SHA256) storage, branching, diffing, time-travel, event log, LRU cache, lazy loading, consistency checks, backup. |
| **Human Interface** | `src/interface/` | Navigator, viewport, annotator, blocking requests, entry points, CLI sessions. |
| **Configuration** | `src/core/config.lisp` | Hierarchical config with file loading, env overrides, merging, validation. |
| **Security** | `src/security/` | Permissions, audit logging, validation. |
| **Monitoring** | `src/monitoring/` | Health check HTTP endpoints. |
| **Holodeck** | `src/holodeck/` | Full ECS-based 3D visualization with components, systems, shaders, meshes, camera, HUD, input. 442 tests. |

### What's Basic/Stub

| Component | Location | What's Missing |
|-----------|----------|---------------|
| **Agent Spawning** | `src/agent/spawner.lisp` | No supervision trees. No restart strategies. No resource limits. No thread management. `spawn-with-snapshot` is a placeholder. `agent-lineage` only traverses one level. |
| **Agent Registry** | `src/agent/registry.lisp` | No persistence. No distributed coordination. Thread safety relies on hash-table atomicity. |
| **Event Bus** | `src/integration/events.lisp` | Fire-and-forget only. No event queue/deferred processing. No backpressure. No persistence. |

---

## Gap Analysis: Vision vs Reality

### Gap 1: The Conductor Has No Home Yet

**What the vision describes**: An always-running orchestrator with event queue, timer heap, work-item classification, dual-mode execution (fast/slow path), agent supervision trees, blackboard state, trigger system, and agent profiles.

**What exists**: The *building blocks* are all there but not assembled:

| Conductor Component | Existing Building Block | Gap |
|-------------------|----------------------|-----|
| Event queue | `*event-handlers*` pub/sub in `events.lisp` | Need a **durable event queue** that buffers events for the conductor loop to drain. Current system is fire-and-forget. |
| Timer heap | Nothing | Need **scheduled action system** — timer heap data structure, cron parsing, next-run-time computation. |
| Work-item classification | Nothing | Need **triage logic** that classifies incoming work as fast-path vs slow-path. |
| Agent spawning with supervision | `spawn-agent` in `spawner.lisp` + `register-agent` in `registry.lisp` | Need **supervision trees** — restart strategies (retry/escalate/compensate), failure classification, resource limits, thread management. |
| Mailboxes for agent ↔ conductor | `*agent-mailboxes*` in `builtin-capabilities.lisp` | Exists but needs **structured message types** for result reporting, failure notification, progress updates. |
| Blackboard shared state | Nothing | Need **thread-safe shared knowledge store** with pattern-based queries. |
| Trigger system | Nothing | Need `deftrigger` macro mapping conditions/schedules to actions. |
| Agent profiles | Nothing | Need **profile definitions** — CORE.md paths, capability sets, approval rules, timeouts, retry policies. |
| Main loop | `cognitive-cycle` in `cognitive-loop.lisp` | Need a **conductor-specific loop** that drains all work sources and routes to fast/slow paths. |

**Assessment**: This requires **new code** — a `src/conductor/` module. But it wires together existing primitives (agents, capabilities, events, cognitive loop, snapshots) rather than replacing them.

### Gap 2: The Workspace Has No Loader Yet

**What the vision describes**: A monorepo with `extensions/`, `mcp-servers/`, `capabilities/`, `projects/` directories. Runtime ASDF loading with FASL caching. Per-project S3-backed storage via Archil. Project manifests in S-expression format.

**What exists**:

| Workspace Component | Existing Building Block | Gap |
|-------------------|----------------------|-----|
| Extension loading | `extension-compiler.lisp` compiles and registers extensions | Need **ASDF-based file loading** — discover .asd files, `ql:quickload` at runtime, FASL cache management. |
| Capability registration | `*capability-registry*` + `register-capability` | Exists. Extensions just need to call it. |
| MCP server management | `mcp-client.lisp` connects to MCP servers | Need **server lifecycle management** — start/stop MCP servers, discovery from config. |
| Project storage | Nothing | Need **per-project namespaced storage** — S3 backend via Archil, local filesystem fallback. |
| Project manifests | Nothing | Need **manifest schema** — project name, version, dependencies, capabilities, entry points. |
| Directory structure | Nothing (flat `src/` tree) | Need **convention-based directory layout** with auto-discovery. |

**Assessment**: This requires **new infrastructure code** — an extension loader and project storage layer. The extension compiler handles *agent-written code* (sandboxed lambdas), but the workspace needs to handle *developer-written systems* (full ASDF systems loaded at runtime).

### Gap 3: Use Cases Need Cross-Cutting Integrations

**What the 20 use cases need most** (from the research document's priority analysis):

| Integration | Use Cases Needing It | Exists? |
|------------|---------------------|---------|
| MCP Server SDK | 15+ use cases | Partial — MCP *client* exists, but no *server* SDK for building new MCP servers |
| Git/GitHub MCP | Code-touching use cases | Not built-in, but achievable via `run-command` capability + MCP |
| Database queries | Data-intensive use cases | Not built-in |
| Inter-agent messaging | Multi-agent use cases | Exists via mailboxes |
| Web search/fetch | Research use cases | Exists as builtin tools |
| File operations | All use cases | Exists as builtin tools |
| Human approval | Safety-critical use cases | Exists via blocking requests |

---

## How the Ideas Connect

```
┌─────────────────────────────────────────────────────────────┐
│                     WORKSPACE                                │
│  (Extension framework - where things live)                   │
│                                                              │
│  extensions/          mcp-servers/        projects/           │
│  ├── cortex-bridge/   ├── git-mcp/       ├── infra-healer/  │
│  ├── scheduler/       ├── db-mcp/        ├── compliance/     │
│  └── ...              └── ...            ├── research-team/  │
│                                          └── ...             │
├──────────────────────────────────────────────────────────────┤
│                     CONDUCTOR                                │
│  (Always-on orchestrator - what runs things)                 │
│                                                              │
│  Event Queue ──┐                                             │
│  Timer Heap ───┼──→ Tick Handler ──→ Fast Path (code)        │
│  Mailboxes ────┘         │                                   │
│                          └──→ Slow Path (spawn agent)        │
├──────────────────────────────────────────────────────────────┤
│                   AUTOPOIESIS CORE                           │
│  (Foundation - what everything is built on)                   │
│                                                              │
│  Cognitive Loop │ Snapshots │ Extensions │ Learning           │
│  Capabilities   │ Events    │ Providers  │ Security           │
└──────────────────────────────────────────────────────────────┘
```

The **Workspace** provides the *structure* — where code lives, how it's loaded, how projects are isolated.

The **Conductor** provides the *runtime* — the always-on loop that watches for work, triages it, and dispatches to agents or code.

The **Use Cases** are *tenants* — each one is a project in the workspace that the conductor knows how to spawn and supervise.

---

## What Requires Base Extensions vs Extension Framework

### Requires Base Extensions (changes to `src/`)

These changes strengthen the foundation that everything else builds on:

1. **Supervision trees for agent spawning** (`src/agent/spawner.lisp`)
   - Restart strategies: retry with backoff, escalate to parent, compensate
   - Failure classification: transient vs permanent vs unknown
   - Resource limits: max runtime, max memory, max tool calls
   - Thread management: `bt:make-thread` for spawned agents, join/kill semantics

2. **Durable event queue** (`src/integration/events.lisp`)
   - Queue data structure that buffers events for polling
   - Backpressure when queue is full
   - Optional persistence for crash recovery

3. **Timer heap / scheduler** (new, could be `src/core/scheduler.lisp`)
   - Min-heap ordered by next-run-time
   - Cron expression parsing
   - Interval-based recurring actions
   - One-shot delayed actions

4. **MCP Server SDK** (new, `src/integration/mcp-server.lisp`)
   - Complement to existing MCP *client*
   - JSON-RPC server over stdio
   - Tool and resource registration
   - Needed by 15+ use cases

5. **Extension loader** (new, `src/core/extension-loader.lisp`)
   - Runtime ASDF system discovery and loading
   - FASL cache management
   - Dependency resolution
   - Hot-reload support

### Requires Extension Framework (new `src/conductor/` module)

These are the conductor itself — a new top-level module:

1. **Conductor main loop** (`src/conductor/conductor.lisp`)
   - `conductor-loop` that drains event queue + timer heap + mailboxes
   - `classify-work-item` for fast/slow routing
   - Blackboard shared state

2. **Trigger system** (`src/conductor/triggers.lisp`)
   - `deftrigger` macro
   - Condition-based triggers (event matching)
   - Scheduled triggers (cron/interval)

3. **Agent profiles** (`src/conductor/profiles.lisp`)
   - Profile definitions with CORE.md, capabilities, approval rules
   - Profile-based agent spawning

4. **Cortex bridge** (`src/integration/cortex-bridge.lisp`)
   - ZMQ or library-level integration with Cortex
   - Event subscription, entity queries, alert routing

### Requires Only the Workspace Convention (no base changes)

These are *projects* that live in the workspace and use existing infrastructure:

1. **Compliance Agent** — Uses cognitive loop + capabilities + human approval
2. **Infrastructure Healer** — Uses cognitive loop + Cortex bridge + capabilities
3. **Research Team** — Uses agent spawning + message passing + capabilities
4. **Code Archaeologist** — Uses capabilities + snapshot DAG + learning

---

## Synthesis: What's Not Yet Synthesized in the Vision

The three vision documents are largely complementary but have some unresolved tensions:

### 1. Conductor vs Provider-Backed Agents

The Conductor plan describes spawning agents as threads with their own cognitive loops. But the current codebase's most powerful agents are *provider-backed* (`provider-agent.lisp`) — they delegate cognition to CLI tools like Claude Code.

**Unresolved**: Does the conductor spawn "native" agents (Lisp cognitive loops) or "provider-backed" agents (CLI subprocesses)? Probably both, but the supervision model differs:
- Native agents: Thread supervision, shared heap, fast messaging
- Provider agents: Process supervision, stdio communication, timeout management

The provider system already handles process lifecycle (`run-provider-subprocess`). The conductor would need to wrap this with its supervision logic.

### 2. Extension Compiler vs Extension Loader

Two different extension mechanisms serve different purposes:
- **Extension compiler** (`extension-compiler.lisp`): For *agent-written* code — sandboxed, validated, promotable
- **Extension loader** (workspace plan): For *developer-written* systems — full ASDF, trusted, hot-reloadable

These should coexist. Agent-written extensions are sandboxed lambdas. Developer-written extensions are full Lisp systems. The workspace contains developer extensions; the extension compiler handles agent self-modification.

### 3. Storage: Snapshots vs Project Storage

Two storage models:
- **Snapshot DAG**: Content-addressable, SHA256-hashed, branch-based — for agent state
- **Project storage** (workspace plan): Per-project namespaced, S3-backed — for project data

These are complementary. Snapshots capture *agent cognitive state*. Project storage holds *domain data* (configs, analysis results, generated artifacts). A project's agents would snapshot their own state via the DAG while storing domain artifacts in project storage.

### 4. Learning at the Wrong Level

The learning system (`learning.lisp`) operates at the individual agent level — extracting patterns from one agent's experiences. But the most valuable learning happens at the *system* level:
- Which agent profiles work best for which types of work?
- Which fast-path handlers handle which event patterns reliably?
- What supervision strategies reduce failure rates?

The conductor would need a *system-level learning loop* that treats the entire system's behavior as its experience stream.

### 5. The 20 Use Cases Lack Prioritization Against the Architecture

The use cases document rates difficulty and lists requirements, but doesn't map against what the conductor and workspace actually need. A suggested prioritization:

**Build first** (exercises the most infrastructure):
1. **Infrastructure Healer** (Use Case #1) — Needs conductor + Cortex bridge + agent profiles + human approval. Exercises every conductor component.
2. **Compliance Agent** (Use Case #7) — Needs scheduled triggers + file capabilities + learning. Good test of trigger system.

**Build second** (extends the framework):
3. **Multi-Agent Research Team** (Use Case #8) — Needs agent spawning with coordination + message passing. Tests supervision.
4. **Agent Factory** (Use Case #9) — Meta-use-case that tests the extension framework itself.

---

## Recommended Implementation Order

Based on the gap analysis, the most efficient path builds infrastructure bottom-up while testing it with real use cases:

### Layer 1: Base Extensions

1. **Supervision trees** — Upgrade `spawner.lisp` with restart strategies, failure classification, thread management
2. **Timer heap** — New scheduler module with cron parsing and min-heap
3. **Durable event queue** — Upgrade event bus with buffering and poll semantics

### Layer 2: Conductor Core

4. **Conductor struct and main loop** — Wire together event queue + timer heap + mailboxes + fast/slow routing
5. **Trigger system** — `deftrigger` macro mapping events/schedules to actions
6. **Agent profiles** — Profile definitions with CORE.md, capability sets, approval rules

### Layer 3: Workspace Framework

7. **Extension loader** — Runtime ASDF discovery and loading
8. **Project storage** — Per-project namespaced storage with local/S3 backends
9. **MCP Server SDK** — Server-side MCP for building new tool servers

### Layer 4: First Tenants

10. **Infrastructure Healer** as first project — validates the full stack
11. **Compliance Agent** as second project — validates triggers and learning

---

## Key Architectural Decisions Needed

1. **Threading model for conductor**: Single-threaded event loop (simple, predictable) vs multi-threaded with work-stealing (parallel, complex)? The vision document suggests starting single-threaded.

2. **Cortex coupling**: Library-level import (same process, direct function calls) vs ZMQ protocol (separate processes, message passing)? Vision suggests library-first, ZMQ later.

3. **Project isolation**: Same Lisp image (shared heap, fast) vs separate processes (isolated, safe)? For trusted developer extensions, same image is fine. For agent-written extensions, the existing sandbox handles it.

4. **MCP Server SDK scope**: Just the protocol layer (JSON-RPC over stdio) or full framework with tool/resource definition DSL?

5. **System-level learning**: Who learns from the conductor's operational data? A meta-agent? The conductor itself? A separate analytics pipeline?

---

## Code References

### Existing infrastructure most relevant to the vision:

- `src/agent/spawner.lisp:11-19` — `spawn-agent` (needs supervision upgrade)
- `src/agent/builtin-capabilities.lisp:53-83` — Message passing via mailboxes
- `src/agent/cognitive-loop.lisp:50-58` — `cognitive-cycle` (the inner loop the conductor orchestrates)
- `src/integration/events.lisp:136-168` — `emit-integration-event` (needs queue semantics)
- `src/integration/provider-agent.lisp:92-108` — Provider-backed `act` method
- `src/core/extension-compiler.lisp:232-383` — `validate-extension-source` (sandbox model)
- `src/agent/learning.lisp:398-462` — `extract-patterns` (needs system-level counterpart)
- `src/agent/agent-capability.lisp:72-122` — `agent-define-capability` (promotion workflow)
- `src/core/config.lisp:87-107` — `load-config` (hierarchical config pattern to reuse)
- `src/integration/mcp-client.lisp:196-244` — `mcp-connect` (reference for MCP server SDK)

## Open Questions

1. Should the conductor live in the same Lisp image as Cortex, or should it be a separate process connected via ZMQ?
2. Should agent profiles be S-expression files (fits the homoiconic philosophy) or Markdown files (more human-friendly for CORE.md)?
3. How should the conductor handle multiple simultaneous slow-path invocations? Queue them? Run in parallel? Budget-constrain?
4. Should the workspace use ASDF's built-in dependency resolution or build something custom that understands the project manifest format?
5. Is the existing event bus's global handler model sufficient, or does the conductor need first-class event routing (like Akka's actor supervision)?
