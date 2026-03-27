---
date: 2026-03-26T15:19:25+0000
researcher: Claude
git_commit: 591727d440f8db741712ad590c72956c88c78229
branch: main
repository: pyrex41/autopoiesis
topic: "Full Codebase Architecture Documentation"
tags: [research, codebase, architecture, substrate, agent, snapshot, orchestration, integration, api, eval, sandbox, frontend]
status: complete
last_updated: 2026-03-26
last_updated_by: Claude
---

# Research: Full Codebase Architecture Documentation

**Date**: 2026-03-26T15:19:25+0000
**Researcher**: Claude
**Git Commit**: 591727d
**Branch**: main
**Repository**: pyrex41/autopoiesis

## Research Question

Comprehensive documentation of the entire Autopoiesis codebase as it exists today, covering all layers, extensions, the frontend, eval system, and how they interconnect.

## Summary

Autopoiesis is a self-configuring agent platform in Common Lisp (~25,000 lines backend) with a SolidJS Command Center frontend (~5,000 lines). The backend is organized as a core ASDF system with 13 optional extension systems. The core has 7 layers (Substrate, Core, Agent, Snapshot, Orchestration, Integration+API, Interface). Extensions include Swarm evolution, Team coordination, Jarvis NL loop, content-addressed Sandbox, agent Eval platform, and others. Tests pass at 145 checks (main suite) plus ~4,300 across all suites. Two PRs merged in this session added the sandbox backend + Command Center redesign (PR #12) and sandbox-eval integration (PR #13).

## Detailed Findings

### 1. Core Platform Layers

#### 1.1 Substrate Layer (`platform/src/substrate/`, 16 files)

The foundation. An EAV (Entity-Attribute-Value) datom store with Linda coordination.

- **`substrate-context`** struct bundles all mutable state (store, entity cache, value index, intern tables, counters) into one object for thread-safe capture via `*substrate*` dynamic variable
- **`datom`** defstruct: `(entity attribute value tx added)` — the atomic fact unit
- **`transact!`** is the primary write path — acquires lock, stamps tx counter, writes to EAVT/AEVT/EA-current indexes, updates entity cache + value index, fires hooks outside lock
- **`take!`** provides O(1) Linda-style atomic claims using the inverted value index — used for task dispatch (`:pending` → `:in-progress`)
- **`define-entity-type`** macro generates CLOS classes with lazy-loading `slot-unbound` methods
- **11 built-in entity types**: event, worker, agent, session, snapshot, turn, context, prompt, department, goal, budget
- LMDB persistence layer optional; in-memory by default for tests
- `with-store` creates fresh context for isolation

#### 1.2 Core Layer (`platform/src/core/`, 10 files)

Immutable utilities and cognitive primitives.

- **S-expression utilities**: `sexpr-hash` (SHA-256), `sexpr-diff`/`sexpr-patch` (structural diff via path-based edits), `sexpr-serialize`/`sexpr-deserialize`
- **Cognitive primitives**: `thought` base class with subclasses `decision`, `action`, `observation`, `reflection` — each carries typed metadata (alternatives, rationale, source, insight)
- **`thought-stream`**: adjustable vector + ID-index hash table; compaction archives older thoughts to `.sexpr` files
- **Persistent data structures**: `pmap-*`/`pvec-*`/`pset-*` wrappers around `fset` library (structural sharing, all operations return new collections)
- **Extension compiler**: validates agent-written code against `*forbidden-symbols*` and `*allowed-packages*` before sandboxed compilation

#### 1.3 Agent Layer (`platform/src/agent/`, 16 files)

Agent runtime with dual mutable/persistent architecture.

- **`agent`** CLOS class: id, name, state, capabilities, thought-stream, parent/children
- **`capability`** CLOS class + `defcapability` macro: name, function, parameters, permissions, description; registered in `*capability-registry*`
- **`cognitive-cycle`**: perceive → reason → decide → act → reflect (5-phase loop, generics with no-op defaults)
- **`persistent-agent`** defstruct: O(1) forking via fset structural sharing (all updates return new structs). Slots: membrane (pmap), genome (list), thoughts (pvec), capabilities (pset), heuristics, children, parent-root, metadata (pmap)
- **`dual-agent`**: subclass of `agent` that auto-syncs to a persistent root via `:after` methods on setters. Uses recursive lock because setter → sync → `(setf dual-agent-root)` re-acquires
- **Learning system**: `experience` records + `heuristic` derivation (condition/recommendation/confidence)
- **Membrane**: pmap of `:allowed-actions` + `:validate-source` controlling what modifications the agent can make to its own genome

#### 1.4 Snapshot Layer (`platform/src/snapshot/`, 13 files)

Content-addressable storage with DAG-based time travel.

- **`snapshot`** CLOS class: id, timestamp, parent, agent-state, tree-root (Merkle hash), tree-entries (filesystem state), metadata, hash
- **`content-store`**: dual hash tables — `data` for S-expressions (keyed by sexpr-hash), `blobs` for byte vectors (keyed by SHA-256). Shared ref-counting GC
- **Filesystem tree operations** (`filesystem-tree.lisp`): `scan-directory-flat` → sorted tree entries; `tree-hash` (Merkle root); `tree-diff` → (:added/:removed/:modified); `materialize-tree` / `materialize-diff`
- **`snapshot-store`**: filesystem-backed persistence (`snapshots/<prefix>/<id>.sexpr`), LRU cache, four-index lookup (by-id, by-parent, by-timestamp, root-ids)
- **DAG traversal**: `checkout-snapshot`, `find-common-ancestor`, `dag-distance`, `walk-ancestors/descendants`
- **Branch manager**: `create-branch`, `switch-branch`, `merge-branches`

### 2. Orchestration & Integration

#### 2.1 Orchestration (`platform/src/orchestration/`, 4 files)

The conductor drives the entire system via a 100ms tick loop.

- **Tick loop** (`conductor-tick-loop`): process-due-timers → process-events (via `take!`) → check-crystallization-triggers → check-periodic-consistency
- **Timer heap**: sorted `(fire-time . action-plist)` list; actions include `:claude` (spawn CLI worker), `:agent-wakeup` (send to mailbox)
- **Event queue**: substrate-backed; `queue-event` writes datoms, `process-events` claims via `take!`
- **Claude CLI worker**: `build-claude-command` assembles shell command, `run-claude-cli` spawns thread + `sb-ext:run-program`, reads stream-json, extracts result
- **`start-system`/`stop-system`**: lifecycle functions that open store, start conductor + monitoring

#### 2.2 Integration (`platform/src/integration/`, 30+ files)

LLM provider abstraction and tool system.

- **LLM client protocol**: `llm-complete` / `llm-auth-headers` generics; `claude-client` and `openai-client` implementations; shared `llm-http-post` transport
- **Agentic loop** (`claude-bridge.lisp`): multi-turn tool-use cycle — call LLM → check stop reason → execute tool calls → format results → loop
- **Provider protocol**: abstract `provider` class with `provider-invoke` → `provider-build-command` → `run-provider-subprocess` → `provider-parse-output`
- **`define-cli-provider` macro**: generates class, constructor, command builder, output parser from declarative form. 8 providers defined: claude-code, codex, opencode, cursor, pi, rho, nanobot, nanosquash
- **`inference-provider`**: direct API calls (no subprocess), wraps `agentic-loop`; convenience constructors for Anthropic, OpenAI, Ollama
- **MCP client**: JSON-RPC 2.0 over stdio; `mcp-connect` discovers tools/resources
- **Integration events**: pub/sub bus with `*event-handlers*` + `*global-event-handlers*`
- **Sandbox tools** (`sandbox-tools.lisp`): `*sandbox-context*`, `with-sandbox-context`, `sandbox-write-file`/`sandbox-delete-file`/`sandbox-exec-command`/`sandbox-snapshot`/`sandbox-fork`/`sandbox-restore` — all use dynamic resolution via `find-symbol`

#### 2.3 API Layer (`platform/src/api/`, 20+ files)

Dual-server: Woo/Clack for WebSocket (port 8080), Hunchentoot for REST (port 8081).

- **WebSocket**: `define-handler` macro registers message handlers in `*message-handlers*`; 20+ message types (agent CRUD, chat, snapshots, branches, blocking requests)
- **REST**: `api-dispatch-handler` routes by URI prefix to handler functions; supports agents, snapshots, branches, events, capabilities, teams, sandboxes, eval, blocking requests
- **Chat protocol**: `handle-chat-prompt` checks for active agent runtime → direct mailbox delivery; otherwise falls through to Jarvis session with streaming support
- **Wire format**: JSON text for control, optional MessagePack binary for stream data
- **SSE**: `sse-broadcast` + heartbeat; wired to integration event bus
- **Sandbox routes** (`sandbox-routes.lisp`): full CRUD + exec/snapshot/fork/restore/tree endpoints using dynamic resolution

### 3. Optional Extensions (11 systems)

#### 3.1 Swarm (`platform/src/swarm/`, 11 files)
Genome evolution. `genome` class encodes heritable traits (capabilities, heuristic-weights, parameters). Genetic operators: uniform crossover, mutation with configurable rate. Selection: tournament, roulette, elitism. `evolve-persistent-agents` bridges persistent agents to/from genomes for evolution. Three built-in fitness functions: thought-diversity, capability-breadth, genome-efficiency.

#### 3.2 Supervisor (`platform/src/supervisor/`, 5 files)
Checkpoint/revert for high-risk operations. `*checkpoint-stack*` of snapshot IDs. `with-checkpoint` macro: on success promotes, on error reverts to snapshot and re-signals. `checkpoint-dual-agent` integrates with persistent agents.

#### 3.3 Crystallize (`platform/src/crystallize/`, 9 files)
Emits runtime-learned capabilities and heuristics to source files. Trigger system (performance threshold, scheduled interval) drives `crystallize-all`. `export-to-git` writes capability files. `emit-asdf-fragment` generates loadable system definitions.

#### 3.4 Conversation (`platform/src/conversation/`, 3 files)
Turn-based conversation context stored as substrate datoms. Turns reference content via blob hashes. Fork is O(1) — new context points at same head turn. History traversal walks `:turn/parent` chain.

#### 3.5 Workspace (`platform/src/workspace/`, 4 files)
Ephemeral execution contexts with pluggable isolation (`:directory`, `:none`, `:sandbox`). Agent home directories. Team coordination via substrate-backed key-value store, task queue (with `take!` for atomic claims), coordination log.

#### 3.6 Team (`platform/src/team/`, 10 files)
Multi-agent coordination with 5 core strategies + 4 extended variants. Strategy protocol: `strategy-initialize`, `strategy-assign-work`, `strategy-collect-results`, `strategy-complete-p`. Leader-worker supports swarm-enhanced task decomposition. Consensus strategy has draft-review-vote loop.

#### 3.7 Jarvis (`platform/src/jarvis/`, 6 files)
NL → tool conversational loop. `start-jarvis` auto-detects rho or pi CLI provider. `jarvis-prompt` implements the tool-use cycle with supervisor checkpoint integration. Query tools (`query-tools.lisp`) return `result-with-blocks` plists for generative UI — 6 capabilities: query-snapshots, diff-snapshots, sandbox-file-tree, list-sandboxes, rollback-sandbox, query-events.

#### 3.8 Security (`platform/src/security/`, 4 files)
Permission system (agent → resource-type → action), audit log (JSON lines with rotation), input validation (12 spec types), authentication (PBKDF2 passwords, token sessions, role-based permission sets).

#### 3.9 Monitoring (`platform/src/monitoring/`, 2 files)
Prometheus-format metrics (counters, gauges, histograms), health/liveness/readiness endpoints, SBCL memory tracking.

#### 3.10 Sandbox (`platform/src/sandbox/`, 10 files)
Content-addressed sandbox with pluggable execution backends (local filesystem, Docker). `sandbox-manager` coordinates backend + content store for lifecycle operations (create/exec/snapshot/fork/restore/destroy). Changeset tracking for O(changed_files) incremental snapshots. All operations tracked as substrate datoms.

#### 3.11 Skel (`platform/src/skel/`, 15 files)
Typed LLM functions. `define-skel-class` + `define-skel-function` macros. SAP (Schema-Aligned Parsing) preprocessor for robust JSON extraction from LLM output. BAML DSL parser and converter. Streaming support with incremental parsing. Standalone — no autopoiesis dependencies at compile time.

### 4. Eval Platform (`platform/src/eval/`, 16 files)

Agent evaluation system with 5 harness types, 10 verifiers, and LLM-as-judge scoring.

- **Scenarios**: substrate entities with prompt, verifier, rubric, domain, tags; 19 built-in across 7 domains (coding, refactoring, research, tool-use, reasoning, sandbox)
- **Harness protocol**: `eval-harness` base class, `harness-run-scenario` generic returning standardized result plist
- **5 harnesses**: provider (single API call), shell (subprocess with timeout/SIGTERM/SIGKILL), ralph (iterative loop), team (multi-agent strategies), sandbox (content-addressed with before/after diffs)
- **10 verifiers**: 7 text-based (exit-zero, contains, not-contains, regex, exact-match, non-empty, always-pass) + 3 filesystem-aware (file-exists, file-count-delta, tree-matches)
- **LLM judge**: multiple judge runs, median aggregation, inter-judge agreement scoring, diff-context support
- **Metrics**: hard (pass-rate, duration, cost, turns with percentiles) + squishy (judge scores by dimension) + sandbox (file counts, bytes, tree hash uniqueness)
- **Run orchestration**: pre-creates all trials, optional `lparallel:pmap` parallelism, judge integration, on-trial-complete callback
- **Comparison**: cross-harness comparison matrix, cross-run comparison, normalized gain (Hake's g), history tracking

### 5. Frontend — Command Center (`dag-explorer/`, ~5000 lines)

SolidJS single-page application with 4 views, 14 reactive stores, and a generative UI block system.

- **Tech stack**: SolidJS 1.9, Vite 6, TypeScript 5.7, d3 (DAG pan/zoom), dagre (layout), Three.js (holodeck)
- **4 views**: Command (full-screen chat + generative blocks), Graph (snapshot DAG), Stream (event/thought timeline), Dashboard (system status)
- **14 stores**: agents, ws, dag, activity, holodeck, conductor, teams, navigation, constellation, timetravel, org, budget, approvals, evolution (+ toast, audit, task, widget)
- **WebSocket**: single persistent connection at `/ws`; JSON text frames; exponential backoff reconnection; channel subscription model
- **Generative UI blocks** (`components/blocks/`): `BlockRenderer` dispatches on `block.type` to 7 typed components: DiffView, FileTree, CodeBlock, TimelineSlice, SnapshotCard, SandboxCard, DataTable
- **Command palette**: 18 commands with keyboard shortcuts; slash/colon prefix in CommandView triggers CLI autocomplete
- **Design system**: CSS custom properties in `reset.css` (void→raised depth scale, signal/warm/emerge/danger accents, JetBrains Mono + Space Grotesk fonts)

### 6. ASDF System Structure

17 `defsystem` forms in `platform/autopoiesis.asd`:
- **Core**: `#:autopoiesis` (15 deps, ~80 source files)
- **API**: `#:autopoiesis/api` (Clack/Woo WebSocket)
- **Extensions**: `/swarm`, `/supervisor`, `/crystallize`, `/team`, `/jarvis`, `/paperclip`, `/holodeck`, `/sandbox-backends`, `/sandbox`, `/research`, `/eval`
- **Test systems**: `/test` (main, 20 files), `/api-test`, `/holodeck-test`, `/swarm-test`, `/supervisor-test`, `/crystallize-test`, `/team-test`, `/jarvis-test`, `/paperclip-test`, `/sandbox-test`, `/eval-test`, `/eval-sandbox-test`

### 7. Test Results

Main test suite: **145/145 pass (100%)**. Documented assertion counts across all suites: ~4,300+.

Key test patterns:
- `with-store ()` for substrate isolation
- `mock-harness` CLOS subclass for eval tests
- `make-temp-store-for-e2e` / `cleanup-e2e-store` for filesystem-backed stores
- `live-llm-tests` explicitly excluded from `run-all-tests` (requires real credentials)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   Command Center (SolidJS)               │
│  CommandView  │  DAGView  │  TimelineView  │  Dashboard  │
│  + BlockRenderer (7 generative UI block types)           │
└──────────────────────┬──────────────────────────────────┘
                       │ WebSocket (JSON) + REST
┌──────────────────────┴──────────────────────────────────┐
│                    API Layer                              │
│  Woo/Clack WS (8080) │ Hunchentoot REST (8081) │ SSE    │
│  define-handler       │ api-dispatch-handler    │        │
├─────────────────────────────────────────────────────────┤
│              Integration Layer                            │
│  claude-bridge │ provider protocol │ MCP client │ tools  │
│  8 CLI providers (define-cli-provider macro)             │
│  agentic-loop │ inference-provider │ sandbox-tools       │
├─────────────────────────────────────────────────────────┤
│              Orchestration Layer                          │
│  conductor tick loop (100ms) │ timer heap │ event queue  │
│  Claude CLI worker │ start-system/stop-system            │
├──────────┬──────────┬──────────┬────────────────────────┤
│ Interface│ Snapshot  │  Agent   │        Core            │
│ blocking │ DAG+CAS  │ runtime  │  S-expr utils          │
│ session  │ tree ops  │ persist  │  cognitive prims       │
│ viewport │ time-     │ dual-    │  fset wrappers         │
│ navigator│ travel    │ agent    │  extension compiler    │
├──────────┴──────────┴──────────┴────────────────────────┤
│                   Substrate Layer                         │
│  datom store │ EAV indexes │ Linda take! │ interning     │
│  entity types │ LMDB │ blob store │ datalog queries      │
└─────────────────────────────────────────────────────────┘

Optional Extensions (separate ASDF systems):
  Swarm │ Supervisor │ Crystallize │ Conversation │ Workspace
  Team │ Jarvis │ Security │ Monitoring │ Sandbox │ Skel │ Eval
```

## Key Architectural Patterns

1. **Substrate as message bus**: Events are datoms claimed atomically via `take!` — the store is both persistence and inter-component communication
2. **Dynamic layer coupling**: `find-package`/`find-symbol` at runtime avoids compile-time circular dependencies between optional extensions
3. **Content-addressed everything**: Snapshots use `sexpr-hash`, filesystem blobs use SHA-256, tree entries produce deterministic Merkle roots
4. **O(1) forking**: Both `persistent-agent` (fset structural sharing) and sandbox `manager-fork` (native COW or DAG materialization) provide cheap branching
5. **`define-cli-provider` code generation**: Provider implementations are data-driven declarative forms that generate 6 forms (class, constructor, methods, serializer)
6. **Generative UI**: Backend returns `result-with-blocks` plists; frontend `BlockRenderer` dispatches typed blocks to SolidJS components
7. **Dual serialization**: WS handlers produce hash-tables, REST handlers produce alists — separate serializer files for each

## Code References

- `platform/src/substrate/store.lisp:118` — `transact!` write path
- `platform/src/substrate/linda.lisp:39` — `take!` atomic claim
- `platform/src/core/s-expr.lisp:81` — `sexpr-hash` SHA-256
- `platform/src/agent/persistent-agent.lisp:13` — `persistent-agent` defstruct
- `platform/src/agent/dual-agent.lisp:12` — `dual-agent` with recursive lock
- `platform/src/snapshot/filesystem-tree.lisp:224` — `tree-hash` Merkle root
- `platform/src/orchestration/conductor.lisp:313` — tick loop
- `platform/src/integration/claude-bridge.lisp:163` — `agentic-loop`
- `platform/src/integration/provider-macro.lisp:103` — `define-cli-provider`
- `platform/src/api/handlers.lisp:30` — WS message dispatch
- `platform/src/api/routes.lisp` — REST route dispatcher
- `platform/src/eval/harness.lisp:29` — `harness-run-scenario` protocol
- `platform/src/eval/harness-sandbox.lisp:194` — `sandbox-execute-trial`
- `platform/src/jarvis/query-tools.lisp` — generative UI block helpers
- `dag-explorer/src/components/blocks/BlockRenderer.tsx` — block dispatch

## Historical Context (from thoughts/)

38 research documents exist in `thoughts/shared/research/`, spanning 2026-02-03 to 2026-03-26:
- `thoughts/shared/research/2026-03-23-agent-eval-platform-feasibility.md` — Eval platform design feasibility study
- `thoughts/shared/research/2026-03-23-generative-ui-revamp-research.md` — Arrow.js generative UI for Command Center
- `thoughts/shared/research/2026-03-23-crdt-vcs-datom-convergence.md` — CRDT VCS vs datom store convergence
- `thoughts/shared/research/2026-03-02-platform-architecture-deep-dive.md` — Earlier architecture deep dive
- `thoughts/shared/research/2026-02-17-what-is-autopoiesis-how-to-use-it.md` — Project orientation guide

## Related Research

This document supersedes the earlier `2026-03-02-platform-architecture-deep-dive.md` with updated coverage of the sandbox system, eval platform, sandbox-eval integration, and Command Center redesign.
