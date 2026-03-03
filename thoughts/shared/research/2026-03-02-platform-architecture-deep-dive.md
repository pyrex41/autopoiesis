---
date: "2026-03-02T14:46:36Z"
researcher: reuben
git_commit: 3a082200ece5a0fccec4170becd97da6c11ff556
branch: main
repository: pyrex41/autopoiesis
topic: "Platform Architecture Deep Dive for Planned Improvements"
tags: [research, codebase, architecture, persistent-data, self-modification, orchestration, visualization, workspace, providers]
status: complete
last_updated: "2026-03-02"
last_updated_by: reuben
---

# Research: Platform Architecture Deep Dive for Planned Improvements

**Date**: 2026-03-02T14:46:36Z
**Researcher**: reuben
**Git Commit**: 3a082200ece5a0fccec4170becd97da6c11ff556
**Branch**: main
**Repository**: pyrex41/autopoiesis

## Research Question

Comprehensive documentation of all existing platform systems relevant to planned improvements: persistent data structures, interface/API layer, self-modification/crystallization, recovery/supervision, visualization, and workspace/Git integration. This serves as the baseline for planning initiatives around persistent immutable trees, Jarvis interface, crystallization engine, memory management, and crash isolation.

## Summary

The Autopoiesis platform is a fully operational 11-layer Common Lisp system with 2,775+ test assertions. Agent state is represented as mutable CLOS objects serialized to S-expressions; there are **no persistent/immutable data structures** (no fset, Okasaki trees, HAMTs). Immutability is achieved architecturally through an append-only datom store and a content-addressed snapshot DAG. The platform exposes four server interfaces (monitoring, REST API, WebSocket, MCP), has a complete self-extension pipeline with sandboxed compilation, three visualization systems (2D terminal, 3D holodeck, web DAG explorer), a new workspace manager with pluggable isolation backends, and six provider backends (Claude Code, Codex, Cursor, Pi, NanoBot, Nanosquash). There is **no crystallization mechanism** — live runtime changes do not get written back to source files.

---

## Detailed Findings

### 1. Core Runtime and Data Model

#### Agent State Representation

**`platform/src/agent/agent.lisp:11`** — The `agent` class has 7 slots:

| Slot | Type | Purpose |
|------|------|---------|
| `id` | UUID string | Unique identifier |
| `name` | string | Human-readable label |
| `state` | keyword | `:initialized`, `:running`, `:paused`, `:stopped` |
| `capabilities` | list | Capability names or `capability` objects |
| `thought-stream` | `thought-stream` | Ordered vector of `thought` objects |
| `parent` | string/nil | Parent agent ID |
| `children` | list | Spawned child agent IDs |

Serialization: `agent-to-sexpr` (line 83) produces a tagged plist; `sexpr-to-agent` (line 96) reconstructs from it.

#### Thought Hierarchy

**`platform/src/core/cognitive-primitives.lisp`** — Base `thought` class (line 16) with `id`, `timestamp`, `content`, `type` (`:reasoning`/`:planning`/`:executing`/`:reflecting`/`:generic`), `confidence`, `provenance`. Four subclasses: `decision` (line 85, with `alternatives`/`chosen`/`rationale`), `action` (line 122, with `capability`/`arguments`/`result`/`side-effects`), `observation` (line 153, with `source`/`raw`/`interpreted`), `reflection` (line 181, with `target`/`insight`/`modification`).

#### Thought Stream

**`platform/src/core/thought-stream.lisp:12`** — Uses an adjustable vector with fill pointer + hash table index. `compact-thought-stream` (line 109) archives old thoughts to timestamped `.sexpr` files when stream exceeds threshold.

#### Context Window (Working Memory)

**`platform/src/agent/context-window.lisp:90`** — Token-budgeted priority queue (max 100k tokens default). `recompute-context-content` (line 152) walks items by priority, accumulating via `sexpr-size` until budget is exhausted.

#### Structural Sharing / Persistent Data Structures

**There are none.** No fset, Okasaki, HAMT, finger tree, or persistent vector implementations exist in the codebase. All data structures are conventional mutable Common Lisp objects. Immutability is architectural:
- Substrate EAVT index uses `:append` strategy — existing datoms are never overwritten
- Snapshot DAG never mutates existing snapshots
- `sexpr-patch` uses `copy-tree` before applying edits

#### Substrate Layer (Datom Store)

**`platform/src/substrate/`** — EAV triple store with in-memory hash tables backed by optional LMDB.

Key components:
- **Datom** (`datom.lisp:9`): struct with `entity` (u64), `attribute` (u32), `value`, `tx` (u64), `added` (boolean)
- **Intern table** (`intern.lisp:31`): Bidirectional term↔integer mapping via `intern-id`/`resolve-id`
- **Store** (`store.lisp:14`): Three default indexes — EAVT (append, entity-centric), AEVT (append, attribute-centric), EA-CURRENT (replace, write-through cache)
- **`transact!`** (`store.lisp:118`): Single write path. Under lock: stamp tx, write indexes, update entity cache and value index, optionally write LMDB. Outside lock: fire hooks.
- **Linda coordination** (`linda.lisp:39`): `take!` atomically claims entities by attribute value
- **Entity cache** (`entity.lisp:41`): O(1) current value lookup. `entity-as-of` (line 139) performs temporal queries.
- **LMDB backend** (`lmdb-backend.lisp:15`): 256MB default map, 6+ named databases, values serialized via `prin1-to-string`/`read-from-string`

#### Snapshot Layer (Content-Addressed Storage)

**`platform/src/snapshot/`** — Git-like DAG of content-hashed agent states.

- **Snapshot** (`snapshot.lisp:11`): `id`, `timestamp`, `parent` (→ DAG link), `agent-state` (S-expression), `metadata`, `hash` (SHA-256 of agent-state)
- **Content store** (`content-store.lisp:11`): In-memory deduplication with reference counting and GC
- **Filesystem persistence** (`persistence.lisp:11`): Directory layout `snapshots/<prefix>/<id>.sexpr`, LRU cache (default 1000), rebuild-from-disk index recovery
- **DAG navigation** (`time-travel.lisp`): `collect-ancestor-ids`, `find-common-ancestor`, `find-path`, `walk-ancestors`, `walk-descendants` (BFS with visited set)
- **Diff engine** (`diff-engine.lisp:11`): Delegates to `autopoiesis.core:sexpr-diff` (structural `:car`/`:cdr` path-based diffing)
- **Branches** (`branch.lisp:11`): In-memory `*branch-registry*` hash table. `merge-branches` is declared but unimplemented.
- **Lazy loading** (`lazy-loading.lisp`): `lazy-snapshot` proxy, paginated DAG iteration in configurable batches
- **Consistency checks** (`consistency.lisp:504`): DAG integrity, hash verification, index cross-reference, timestamp ordering

#### S-Expression Utilities

**`platform/src/core/s-expr.lisp`**:
- `sexpr-hash` (line 81): Ironclad SHA-256, recursive type-tagged hashing
- `sexpr-diff` (line 163): Minimal edit list via `:car`/`:cdr` path recursion, emitting `:replace` edits
- `sexpr-patch` (line 178): `copy-tree` then apply edits via path navigation

---

### 2. Interface and API Layer

#### HTTP Endpoints (4 servers on 2 ports)

**Port 8081** — Hunchentoot shared dispatch table:

1. **Monitoring** (`platform/src/monitoring/endpoints.lisp`): `/healthz`, `/readyz`, `/health` (full JSON), `/metrics` (Prometheus format). Health checks: core packages, key functions, SBCL heap (1GB threshold), component health.

2. **Conductor** (`platform/src/orchestration/endpoints.lisp`): `GET /conductor/status`, `POST /conductor/webhook` (JSON → `queue-event`).

3. **REST API** (`platform/src/api/rest-server.lisp`, `routes.lisp`): Full CRUD for agents (13 endpoints), snapshots (4 endpoints), branches (4 endpoints), pending requests (3 endpoints), system info, SSE event stream. All routes require API key authentication with `:read`/`:write`/`:admin` permission levels.

4. **MCP Server** (`platform/src/api/mcp-server.lisp`): Mounted at `/mcp`. MCP Streamable HTTP transport, protocol version `"2025-03-26"`. Exposes 21 tools mirroring the REST API functionality. Session-based with `Mcp-Session-Id` header.

**Port 8080** — WebSocket server (Clack/Woo):

5. **WebSocket API** (`platform/src/api/server.lisp`): 17+ message types including `list_agents`, `create_agent`, `agent_action`, `step_agent`, `inject_thought`, snapshot/branch management, blocking request handling. Binary MessagePack for data streams, JSON for control.

#### Authentication

**`platform/src/api/auth.lisp`**: SHA-256 hashed API keys, `Authorization: Bearer` or `X-Api-Key` headers, constant-time comparison, configurable `*api-require-auth*`.

#### SSE Event Streaming

**`platform/src/api/sse.lisp`**: Broadcasts all integration events to connected clients. 30-second heartbeat keepalive.

#### CLI Session Interface

**`platform/src/interface/session.lisp`**: REPL-based interface with 12 commands: `help`, `status`, `start`/`stop`/`pause`/`resume`, `step`, `thoughts`, `inject`, `detail`, `back`, `pending`, `respond`, `viz`, `quit`. Navigator tracks position/history in snapshot DAG.

---

### 3. Tool System and Providers

#### Built-in Tools

**`platform/src/integration/builtin-tools.lisp`** — 21 capabilities registered via `defcapability`:
- File system (7): `read-file`, `write-file`, `list-directory`, `file-exists-p`, `delete-file-tool`, `glob-files`, `grep-files`
- Web (2): `web-fetch`, `web-head`
- Shell (4): `run-command`, `git-status`, `git-diff`, `git-log`
- Self-extension (3): `define-capability-tool`, `test-capability-tool`, `promote-capability-tool`
- Introspection (2): `list-capabilities-tool`, `inspect-thoughts`
- Orchestration (3): `spawn-agent`, `query-agent`, `await-agent`
- Branching (2): `fork-branch`, `compare-branches`
- Session (2): `save-session`, `resume-session`

#### Tool Mapping

**`platform/src/integration/tool-mapping.lisp`**: Bidirectional `kebab-case` ↔ `snake_case` conversion. `capability-to-claude-tool` (line 143) converts to Claude API JSON tool format. `execute-tool-call` (line 209) dispatches by name lookup.

#### Provider System (6 backends)

**Base class** (`platform/src/integration/provider.lisp:13`): CLOS class with subprocess lifecycle management. `run-provider-subprocess` (line 237) uses two reader threads for stdout/stderr to avoid deadlock.

| Provider | File | Modes | Command | Output Format |
|----------|------|-------|---------|---------------|
| Claude Code | `provider-claude-code.lisp` | one-shot, streaming | `claude` | JSON object |
| Codex | `provider-codex.lisp` | one-shot | `codex exec` | JSONL events |
| Cursor | `provider-cursor.lisp` | one-shot | `cursor-agent` | JSON object |
| Pi | `provider-pi.lisp` | one-shot, streaming (RPC) | `pi` | JSON object |
| NanoBot | `provider-nanobot.lisp` | one-shot | `nanobot agent` | JSON object |
| Nanosquash | `provider-nanosquash.lisp` | one-shot | `nanosquash exec` / native FFI | Text / native |

**Meta-dispatcher** (`integrate-primitives.lisp:12`): `select-coding-backend` keyword-matches prompts to route to Pi (refactor/bulk), OpenCode (GitHub/PR), or Claude Code (default).

#### MCP Client

**`platform/src/integration/mcp-client.lisp`**: JSON-RPC over stdin/stdout subprocess protocol (version `"2024-11-05"`). `mcp-connect` starts process, initializes, discovers tools/resources. `mcp-tool-to-capability` bridges MCP tools into the capability registry.

---

### 4. Self-Modification and Extension

#### Extension Compiler

**`platform/src/core/extension-compiler.lisp`**:
- **Sandbox** (lines 64–197): Whitelists of allowed packages (6), allowed special forms (16), allowed symbols (100+), forbidden symbols (30+). Recursive S-expression walker validates operator positions.
- **Validation** (`validate-extension-source`, line 232): Recursive `check-form` walker handles `lambda`, `let`/`let*`, `flet`/`labels`, `quote`, `function`, `loop` structurally. Three sandbox levels: `:strict`, `:moderate`, `:trusted`.
- **Compilation** (`compile-extension`, line 389): Wraps in `(lambda () ...)`, calls `(compile nil ...)`, produces `extension` instances.
- **Registry** (`*extension-registry*`, line 437): Global hash table with dependency checking on install. Auto-disable after 3 errors via `invoke-extension` (line 560).

#### Agent Self-Extension Pipeline

**`platform/src/agent/agent-capability.lisp`**:

```
agent-define-capability (line 72)
  → validate-extension-code (strict sandbox)
  → (compile nil full-code)
  → push agent-capability onto agent's capabilities list
  → status: :draft

test-agent-capability (line 128)
  → run test cases via (apply cap-fn args)
  → store results
  → status: :testing

promote-capability (line 199)
  → verify all tests pass
  → register-capability into global *capability-registry*
  → status: :promoted
```

#### Crystallization

**There is no crystallization mechanism.** No `crystallize-to-source`, `emit-source`, or `serialize-to-source` function exists. Agent-written code lives as runtime objects (compiled functions + source S-expressions in memory) and is not written back to `.lisp` files.

#### Learning System

**`platform/src/agent/learning.lisp`**: Experience recording → pattern extraction (action n-grams + context key frequency) → heuristic generation → confidence-weighted decision adjustment. `apply-heuristics` (line 831) modifies `decision-alternatives` scores in-place. Confidence feedback via success/failure decay.

---

### 5. Error Recovery and Orchestration

#### Conductor

**`platform/src/orchestration/conductor.lisp:16`**: Background tick loop (100ms interval) processing timer heap and substrate-backed event queue.

- **Timer heap** (line 48): Sorted cons-cell list of `(fire-time . action-plist)`. Dispatches `:tick`, `:claude` (spawn worker), or queues as event.
- **Event queue** (line 120): Substrate datom entities with `:event/status` claimed via `take!` (`:pending` → `:processing` → `:complete`/`:failed`).
- **Worker tracking** (line 165): Substrate-backed datom entities. Exponential backoff on failure: `min(300, 2^count)` seconds (line 221).
- **Tick loop** (line 234): Catches all errors, logs and counts them, never terminates.

#### Claude CLI Worker

**`platform/src/orchestration/claude-worker.lisp:64`**: Spawns `/bin/sh -c` with `</dev/null` stdin redirect. Stream-JSON line reader with timeout enforcement (SIGTERM → 2s → SIGKILL).

#### System Lifecycle

**`platform/src/orchestration/endpoints.lisp:45`**: `start-system` opens store → starts monitoring → registers endpoints → starts conductor. `stop-system` reverses in order.

#### Condition Hierarchy

Three condition trees:
1. **Core** (`platform/src/core/conditions.lisp`): `autopoiesis-error`, `serialization-error`, `deserialization-error`, `validation-error`. `with-autopoiesis-restarts` provides `continue-anyway`, `use-value`, `retry`.
2. **Substrate** (`platform/src/substrate/conditions.lisp`): `substrate-error`, `substrate-validation-error`, `unknown-entity-type`.
3. **Security** (`platform/src/security/permissions.lisp`): `permission-denied`.

#### Recovery System

**`platform/src/core/recovery.lisp`**: Full recovery framework with:
- **Typed conditions**: `recoverable-error`, `transient-error`, `resource-error`, `state-inconsistency-error`
- **Strategy registry** (`*recovery-strategies*`, line 106): Error type → sorted strategy list
- **`with-recovery`** (line 201): `handler-bind` that tries registered strategies in priority order
- **6 restarts** (line 159): `continue-with-default`, `retry-operation`, `retry-with-delay`, `use-fallback`, `skip-operation`, `abort-operation`
- **`retry-with-backoff`** (line 253): Exponential backoff with jitter (base 0.1s, max 30s)
- **Degradation system** (line 314): Three levels (`:minimal`, `:offline`, `:read-only`) with auto-triggers for network/storage failures
- **Component health** (line 455): Per-component failure tracking with threshold-based degradation entry

#### Security

**`platform/src/security/permissions.lisp`**: 7 resource types × 6 action types. Per-agent permission lists. `with-permission-check` macro. Three predefined sets: default, admin, sandbox.

**`platform/src/security/audit.lisp`**: JSON-line audit log with 10MB rotation (5 files max). `with-audit` macro for automatic success/error/failure logging.

**`platform/src/security/validation.lisp`**: 14 validator types with combinators (`and`/`or`/`not`/`nullable`). String sanitization with control character removal.

---

### 6. Visualization

#### 3D Holodeck (`platform/src/holodeck/`)

ECS-based 3D visualization using `cl-fast-ecs`:
- **Components** (`components.lisp`): Position/velocity/scale/rotation (spatial), visual-style/node-label (visual), snapshot-binding/agent-binding/connection (data), interactive/detail-level (interaction)
- **Systems** (`systems.lisp`): Movement (velocity integration), pulse (sinusoidal scale animation), LOD (distance-based detail)
- **Shaders** (`shaders.lisp`): Hologram-node (Fresnel + scanlines), energy-beam (flow animation), glow post-effect. CPU-side implementations for testing.
- **Meshes** (`meshes.lisp`): UV sphere, subdivided octahedron, branching-node. 4 LOD levels each.
- **Camera** (`camera.lisp`): Orbit camera (spherical coordinates) + fly camera (first-person). Smooth transitions with 7 easing functions. Ray picking for entity selection.
- **HUD** (`hud.lisp`): 4 panels (position, agent, timeline, hints). Scrubber for timeline navigation. Draw commands as plists.
- **Frame loop** (`window.lisp:526`): Input → transitions → sync camera → run ECS systems → collect render descriptions → render HUD. Terminal fallback with Bresenham line drawing.
- **Live agent sync** (`window.lisp:948`): Periodically maps running agents to ECS entities with lerped position.

#### 2D Terminal Visualization (`platform/src/viz/`)

ANSI-based horizontal timeline with Unicode glyphs, branch layout with fork connections, vi-like navigation (h/j/k/l), detail panel, help overlay. `session-to-timeline` converts thought streams to timeline data.

#### Web DAG Explorer (`dag-explorer/`)

SolidJS + Dagre + Canvas2D. Sugiyama hierarchical layout, collapsible subtrees, path highlighting, color schemes (branch/agent/depth/time/mono), diff view, command palette, minimap. Connects to REST API or uses mock data.

**ECS↔Persistent State relationship**: The ECS is ephemeral (initialized fresh each session). Snapshot entities carry `snapshot-binding` with the snapshot ID as a one-way copy. Agent entities are synced periodically from the live agent registry. The DAG explorer connects to the REST API when in live mode.

---

### 7. Workspace and Git Integration

#### Git Capabilities (Read-Only)

**`platform/src/integration/builtin-tools.lisp:230-269`**: Three shell-wrapper capabilities: `git-status` (porcelain), `git-diff` (optional staged), `git-log` (configurable count/format). No commit creation, no branch switching, no worktree management in platform code.

#### Workspace Manager

**`platform/src/workspace/`** (added in commit `3a08220`):

- **Isolation backend protocol** (`workspace.lisp:17-39`): Abstract `isolation-backend` class with 5 generic functions: `create`, `destroy`, `exec`, `write-file`, `read-file`.
- **`:directory` backend** (`workspace.lisp:56-107`): Filesystem directories under agent home (`/data/agents/<id>/workspaces/<uuid>/`).
- **`:none` backend** (`workspace.lisp:109-162`): Pass-through to current working directory.
- **`:sandbox` backend** (`workspace-backend.lisp:15`): Squashfs-based container isolation via `squashd`. References snapshotted as squashfs modules via `mksquashfs`.
- **Workspace class** (`workspace.lisp:166-205`): `id`, `agent-id`, `task`, `isolation`, `root`, `sandbox-id`, `references`, `status`, `metadata`.
- **`with-workspace` macro** (`workspace.lisp:377`): RAII pattern with `unwind-protect` cleanup.
- **Agent home** (`agent-home.lisp`): Per-agent directory structure with `config.sexp`, `history/`, `learning/`, `workspaces/`.
- **Workspace capabilities** (`capabilities.lisp`): `ws-read-file`, `ws-write-file`, `ws-exec`, `ws-install` (pip/npm/apk).

#### Sandbox System

**`platform/src/sandbox/`** — ASDF system `autopoiesis/sandbox`, depends on `squashd-core`:
- **Sandbox provider** (`sandbox-provider.lisp`): `create-sandbox`, `destroy-sandbox`, `exec-in-sandbox`, `snapshot-sandbox`, `restore-sandbox`. All operations tracked as substrate datoms.
- **Conductor dispatch** (`conductor-dispatch.lisp`): Handles `:sandbox` timer actions, creates ephemeral sandboxes in spawned threads.
- **Entity types** (`entity-types.lisp`): `:sandbox-instance` and `:sandbox-exec` substrate entities.

#### Snapshot DAG vs Git

The snapshot branch system (`platform/src/snapshot/branch.lisp`) is entirely independent of Git. Branches point to snapshot IDs (content-hashed S-expression state), not Git commits. The DAG topology comes from each snapshot's `:parent` slot. `merge-branches` is declared but unimplemented.

---

## Code References

### Core Data Model
- `platform/src/agent/agent.lisp:11` — Agent class definition
- `platform/src/core/cognitive-primitives.lisp:16` — Thought hierarchy
- `platform/src/core/thought-stream.lisp:12` — Thought stream with compaction
- `platform/src/agent/context-window.lisp:90` — Priority-queue context window
- `platform/src/core/s-expr.lisp:81` — Content-addressable hashing
- `platform/src/core/s-expr.lisp:163` — Structural diff
- `platform/src/core/s-expr.lisp:178` — Structural patch

### Substrate
- `platform/src/substrate/datom.lisp:9` — Datom struct
- `platform/src/substrate/store.lisp:14` — Store class with indexes
- `platform/src/substrate/store.lisp:118` — `transact!` write path
- `platform/src/substrate/linda.lisp:39` — `take!` atomic claim
- `platform/src/substrate/entity.lisp:139` — `entity-as-of` temporal query
- `platform/src/substrate/lmdb-backend.lisp:15` — LMDB persistence

### Snapshot
- `platform/src/snapshot/snapshot.lisp:11` — Snapshot class
- `platform/src/snapshot/persistence.lisp:11` — Filesystem store with LRU cache
- `platform/src/snapshot/time-travel.lisp` — DAG navigation
- `platform/src/snapshot/branch.lisp:11` — Branch class
- `platform/src/snapshot/lazy-loading.lisp:13` — Lazy proxy + paginated iteration
- `platform/src/snapshot/consistency.lisp:504` — Integrity checks

### APIs
- `platform/src/monitoring/endpoints.lisp:391` — Monitoring routes
- `platform/src/orchestration/endpoints.lisp:31` — Conductor endpoints
- `platform/src/api/routes.lisp:597` — REST API dispatch
- `platform/src/api/mcp-server.lisp:577` — MCP server handler
- `platform/src/api/server.lisp:236` — WebSocket server
- `platform/src/api/auth.lisp:79` — Authentication
- `platform/src/api/sse.lisp:45` — SSE broadcast

### Self-Extension
- `platform/src/core/extension-compiler.lisp:232` — Sandbox validation
- `platform/src/core/extension-compiler.lisp:389` — Compilation
- `platform/src/agent/agent-capability.lisp:72` — Agent-defined capabilities
- `platform/src/agent/agent-capability.lisp:199` — Capability promotion
- `platform/src/agent/learning.lisp:398` — Pattern extraction

### Orchestration & Recovery
- `platform/src/orchestration/conductor.lisp:16` — Conductor class
- `platform/src/orchestration/conductor.lisp:234` — Tick loop
- `platform/src/orchestration/claude-worker.lisp:64` — Claude CLI worker
- `platform/src/core/recovery.lisp:201` — `with-recovery` handler
- `platform/src/core/recovery.lisp:253` — Retry with backoff
- `platform/src/core/recovery.lisp:314` — Degradation system
- `platform/src/security/permissions.lisp:212` — Permission check

### Visualization
- `platform/src/holodeck/components.lisp:18` — ECS storage init
- `platform/src/holodeck/systems.lisp:47` — Movement/pulse/LOD systems
- `platform/src/holodeck/window.lisp:526` — Frame loop
- `platform/src/viz/timeline.lisp:12` — 2D terminal timeline
- `dag-explorer/src/graph/layout.ts:21` — DAG layout engine

### Workspace
- `platform/src/workspace/workspace.lisp:17` — Isolation backend protocol
- `platform/src/workspace/workspace.lisp:272` — `create-workspace`
- `platform/src/workspace/workspace.lisp:377` — `with-workspace` macro
- `platform/src/workspace/workspace.lisp:419` — `snapshot-directory-to-module`
- `platform/src/sandbox/sandbox-provider.lisp:55` — Sandbox lifecycle
- `platform/src/sandbox/workspace-backend.lisp:15` — Sandbox backend

### Providers
- `platform/src/integration/provider.lisp:13` — Provider base class
- `platform/src/integration/provider-claude-code.lisp:8` — Claude Code
- `platform/src/integration/provider-pi.lisp:9` — Pi (one-shot + RPC streaming)
- `platform/src/integration/provider-nanobot.lisp:8` — NanoBot
- `platform/src/integration/provider-nanosquash.lisp:12` — Nanosquash (native FFI + CLI)
- `platform/src/integration/integrate-primitives.lisp:12` — Meta-dispatcher

---

## Architecture Documentation

### Gap Analysis: Current State vs Planned Improvements

| Planned Initiative | Current State | Gap |
|---|---|---|
| **Persistent immutable trees** | All mutable CLOS objects. Immutability is architectural (append-only datoms, immutable snapshots). | No structural sharing, no O(log n) forking, no persistent data structures library. |
| **Stable supervisor wrapper** | Conductor tick loop catches all errors and continues. Recovery system has `with-recovery` + strategies + degradation. Component health tracking exists. | No separate stable-root pointer. No automatic revert-to-last-known-good on self-modification failure. |
| **Jarvis/Pi interface** | Pi provider exists with one-shot and RPC streaming modes. REST/WebSocket/MCP APIs exist. 21 built-in tools available. | No unified "Jarvis" dispatch loop. No natural-language → tool routing beyond `select-coding-backend`. |
| **Git worktrees + overlayfs** | Workspace manager with `:directory` and `:sandbox` isolation. Squashfs-based read-only layers. Git tools are read-only shell wrappers. | No Git worktree creation/management in platform code. No overlayfs mounting. No commit creation. |
| **Crystallize-to-source** | Extension compiler stores source S-expressions in memory. Agent capabilities carry `source-code` slot. | No mechanism to emit `.lisp` files, update ASDF definitions, or create Git commits from live changes. |
| **Memory ceilings and pruning** | Thought stream compaction, snapshot LRU cache (1000 cap), content store reference-counting GC. | No global memory monitoring. No swarm-level pruning. No fitness-based branch pruning. |
| **Hybrid language (Clojure)** | Pure SBCL Common Lisp. No Clojure, no ABCL, no JVM interop. | Complete gap — would require new bridge layer. |
| **Bend/HVM GPU metabolism** | All computation on CPU. cl-fast-ecs for holodeck rendering. | Complete gap — no GPU compute pipeline. |

### Existing Patterns That Support Planned Work

1. **Snapshot DAG** already implements branching, diffing, time-travel, and content-addressable storage — a natural foundation for persistent tree work.
2. **Extension compiler sandbox** already validates and compiles agent-written code with the `source-code` S-expression preserved — a starting point for crystallization.
3. **Workspace manager** with pluggable backends already supports `:sandbox` isolation via squashfs — a foundation for per-agent isolated workspaces.
4. **Recovery system** with strategies, degradation levels, and component health — a foundation for the stable supervisor wrapper.
5. **Provider system** with Pi RPC streaming — a foundation for the Jarvis conversational interface.
6. **`record-provider-exchange`** already appends 4 structured thoughts per provider interaction — a foundation for agent-level provenance tracking.

---

## Related Research

- `thoughts/shared/research/2026-02-03-autopoiesis-codebase-overview.md` — Earlier codebase overview
- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Jarvis meta-agent feasibility study
- `thoughts/shared/research/2026-02-17-what-is-autopoiesis-how-to-use-it.md` — Platform usage guide
- `thoughts/shared/research/2026-03-01-project-scope-and-pr-review.md` — Recent project scope review

## Open Questions

1. **Persistent data structure library**: Should this use an existing CL library (e.g., `fset`) or a custom implementation optimized for S-expression structural sharing?
2. **Crystallization scope**: Should crystallization emit complete standalone `.lisp` files or incremental patches to existing source?
3. **Jarvis dispatch**: Should the Jarvis loop be a new conductor action type, a separate process, or an extension of the existing CLI session?
4. **Branch merging**: `merge-branches` is declared but unimplemented — is this needed before persistent trees, or does the persistent tree approach supersede it?
5. **Squashd maturity**: The sandbox backend depends on `squashd-core` which is vendored with patches — is this stable enough for production workspace isolation?
