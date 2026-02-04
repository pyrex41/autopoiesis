---
date: 2026-02-03T12:00:00-08:00
researcher: reuben
git_commit: 392c43a
branch: main
repository: ap
topic: "Comprehensive Autopoiesis Codebase Overview"
tags: [research, codebase, architecture, overview, common-lisp, agent-platform]
status: complete
last_updated: 2026-02-04
last_updated_by: reuben
last_updated_note: "Updated to reflect eight-layer architecture, provider abstraction, current test counts, resolved open questions"
---

# Research: What Is Autopoiesis?

**Date**: 2026-02-03 (updated 2026-02-04)
**Researcher**: reuben
**Git Commit**: 392c43a
**Branch**: main
**Repository**: ap

## Research Question

What is this project? A comprehensive overview of the Autopoiesis codebase — its architecture, components, and how everything fits together.

## Summary

Autopoiesis is a self-configuring, self-extending agent platform built in Common Lisp. The core insight is that because Lisp is homoiconic (code and data share the same representation as S-expressions), agent cognition, conversation state, and configuration can all be represented as S-expressions. This means agents can inspect and modify their own behavior, full state snapshots enable time-travel debugging, and humans can intervene at any point in the agent's cognitive process.

The system is implemented as an eight-layer architecture (77+ source files) with comprehensive tests (2,400+ assertions across 600+ tests in 10 test suites), backed by a content-addressable snapshot DAG for persistence and time-travel. It integrates with Claude via the Anthropic API, supports MCP servers for external tool access, and provides a provider abstraction layer for wrapping external CLI coding tools (Claude Code, Codex, OpenCode, Cursor) as cognitive backends.

**All phases (0-10) are complete.** CLAUDE.md correctly reflects this status.

## Detailed Findings

### The Eight-Layer Architecture

#### Layer 1: Core (`src/core/`) — The S-Expression Foundation

The core layer provides the homoiconic foundation everything else builds on. Eight source files implement:

**S-Expression Utilities** (`src/core/s-expr.lisp`)
- `sexpr-equal` — Deep structural equality checking for atoms, conses, arrays, hash-tables
- `sexpr-hash` — SHA256-based content-addressable hashing via Ironclad
- `sexpr-diff` / `sexpr-patch` — Non-destructive structural diffing and patching of S-expressions. Diffs produce `sexpr-edit` structs with `:replace`/`:insert`/`:delete` operations navigated by `:car`/`:cdr` paths
- `sexpr-serialize` / `sexpr-deserialize` — Readable and JSON serialization formats
- `sexpr-size` — Token estimation for context window management (~4 chars per token)

**Cognitive Primitives** (`src/core/cognitive-primitives.lisp`)
Five CLOS classes representing units of agent cognition, all subclassing `thought`:
- **Thought** — Base class with id, timestamp, content (S-expression), type, confidence (0-1), provenance
- **Decision** — Alternatives as `(option . score)` alist, chosen option, rationale
- **Action** — Capability invocation with arguments, result (or `:pending`), side-effects
- **Observation** — Raw input from source (`:external` default) with interpretation
- **Reflection** — Metacognitive insight about a target thought with optional self-modification

**Thought Stream** (`src/core/thought-stream.lisp`)
An append-only vector-backed stream with hash-table index for O(1) lookups by ID. Supports filtering by type, timestamp range, and compaction with disk archiving when the stream exceeds `keep-last * 2` entries.

**Extension Compiler** (`src/core/extension-compiler.lisp`)
Enables agent-written code with sandboxing. Three sandbox levels (`:strict`, `:moderate`, `:trusted`). The strict sandbox:
- Whitelists safe packages (`COMMON-LISP`, `KEYWORD`, `AUTOPOIESIS.CORE`, `AUTOPOIESIS.AGENT`, `ALEXANDRIA`)
- Forbids dangerous operations (eval, compile, file I/O, external processes, global definitions)
- Walks code recursively, handling lambda, let/let*, flet/labels, quote, function references, loop
- Compiles validated code into extension objects tracked in a registry with invocation counting and automatic rejection after 3 errors

**Recovery System** (`src/core/recovery.lisp`)
- Condition hierarchy: `recoverable-error`, `transient-error`, `resource-error`, `state-inconsistency-error`
- Six standard restarts: continue-with-default, retry-operation, retry-with-delay, use-fallback, skip-operation, abort-operation
- Exponential backoff with jitter for transient failures
- Graceful degradation with three levels (`:minimal`, `:offline`, `:read-only`)
- Component health tracking with automatic degradation triggers
- Recovery logging (last 500 events)

**Other Core Modules**:
- `config.lisp` — Hierarchical configuration with file/env merging and validation
- `profiling.lisp` — Nanosecond-precision timing, metrics collection, LRU-cached hashing, benchmarking, memory tracking
- `conditions.lisp` — Base condition hierarchy with restarts

The core package exports 276 symbols.

---

#### Layer 2: Agent (`src/agent/`) — The Cognitive Runtime

Eight source files implement the autonomous agent runtime:

**Agent Class** (`src/agent/agent.lisp`)
CLOS class with 7 slots: `id` (UUID), `name`, `state` (`:initialized`/`:running`/`:paused`/`:stopped`), `capabilities`, `thought-stream`, `parent`, `children`. State transitions via `start-agent`, `stop-agent`, `pause-agent`, `resume-agent`. Global registry maps agent IDs to instances.

**Cognitive Loop** (`src/agent/cognitive-loop.lisp`)
Five-phase cycle executed by `cognitive-cycle`:
1. **Perceive** — Gather observations from environment
2. **Reason** — Process observations into understanding
3. **Decide** — Choose action based on understanding
4. **Act** — Execute decided action
5. **Reflect** — Reflect on action outcome

All phases are generic functions with default no-op methods, designed for specialization by specific agent types.

**Capability System** (`src/agent/capability.lisp`, `src/agent/builtin-capabilities.lisp`)
Capabilities are named functions with parameter specs, permissions, and descriptions. Registered in a global hash-table registry. The `defcapability` macro provides a declarative definition syntax. Four built-in capabilities:
- **Introspect** — Query agent's own capabilities, thoughts, state, identity, children, parent
- **Spawn** — Create child agents inheriting parent capabilities
- **Communicate** — Send messages to other agents via global mailbox system
- **Receive** — Retrieve messages from mailbox (FIFO order)

**Agent-Defined Capabilities** (`src/agent/agent-capability.lisp`)
Agents can define new capabilities at runtime with a promotion workflow: `:draft` → `:testing` → `:promoted`/`:rejected`. Code is validated by the extension compiler, tested against user-provided test cases, and promoted to the global registry only if all tests pass.

**Context Window** (`src/agent/context-window.lisp`)
Priority queue-based working memory (default 100K tokens). Items added with priority scores, automatically evicted when exceeding token limit. `context-focus` boosts matching items by 2x, `context-defocus` reduces by 0.5x. Recomputes visible content on every modification.

**Learning System** (`src/agent/learning.lisp`)
Pattern extraction from agent experiences:
- **Experience** objects record task-type, context, actions, and outcome (`:success`/`:failure`/`:partial`)
- **N-gram analysis** on action sequences finds repeated patterns
- **Heuristic generation** converts patterns into condition/recommendation pairs with confidence scores
- **Heuristic application** adjusts decision alternative weights at decision time
- **Confidence feedback** updates heuristic reliability based on outcomes (success recalculates, failure decays by 0.9)

**Spawner** (`src/agent/spawner.lisp`)
Creates child agents with parent-child lineage tracking. Children inherit parent capabilities by default.

---

#### Layer 3: Snapshot (`src/snapshot/`) — Time-Travel and Persistence

Twelve source files implement content-addressable persistence with DAG-based time-travel:

**Snapshot Class** (`src/snapshot/snapshot.lisp`)
Each snapshot captures agent state as an S-expression with: `id` (UUID), `timestamp`, `parent` (snapshot ID), `agent-state`, `metadata`, `hash` (SHA256 content hash computed on creation).

**Content-Addressable Storage** (`src/snapshot/content-store.lisp`)
Hash-table backed store with automatic reference counting. `store-put` deduplicates by hash, `store-gc` collects zero-reference entries.

**Persistence** (`src/snapshot/persistence.lisp`)
Filesystem-backed with two-level directory structure (`snapshots/XX/UUID.sexpr`). Features:
- LRU cache (default 1000 entries) with cache-first loading
- Multi-index: by-id (hash), by-parent (hash → child list), by-timestamp (sorted list), root-ids
- Index persistence and rebuild from filesystem scan

**Branch Management** (`src/snapshot/branch.lisp`)
Lightweight named pointers to snapshot heads. Global registry with current branch tracking.

**Diff Engine** (`src/snapshot/diff-engine.lisp`)
Thin wrapper delegating to core `sexpr-diff`/`sexpr-patch`. `snapshot-diff` extracts agent states and diffs them. `snapshot-patch` creates new snapshots with patched state and parent linkage.

**Time-Travel** (`src/snapshot/time-travel.lisp`)
DAG traversal with:
- `checkout-snapshot` — Load and make current
- `find-common-ancestor` — Set intersection on ancestor chains
- `find-path` — Handles ancestor, descendant, and diverged-branch cases
- `walk-ancestors` / `walk-descendants` — Callback-based traversal with early termination
- `find-branch-point` — Finds first ancestor with multiple children

**Lazy Loading** (`src/snapshot/lazy-loading.lisp`)
Proxy objects that store metadata without loading full content. Batch iterators for DAG traversal. Paginated queries with offset/limit.

**Consistency Checking** (`src/snapshot/consistency.lisp`)
Six checks: DAG integrity (broken refs, cycles, reachability), content hash verification, branch consistency, index consistency, agent state structure, timestamp ordering. Includes repair functions for index rebuilding and orphan snapshot handling.

**Backup** (`src/snapshot/backup.lisp`)
Full and incremental backups with SHA256 checksums. Incremental backups chain to parents and only store new snapshots. Point-in-time restore.

**Event Log** (`src/snapshot/event-log.lisp`)
Append-only vector with checkpoint-based compaction.

---

#### Layer 4: Interface (`src/interface/`) — Human-in-the-Loop

Eight source files implement human interaction:

**Protocol** (`src/interface/protocol.lisp`)
Message types: `:query` (agent→human), `:response` (human→agent), `:notification`, `:command`.

**Navigator** (`src/interface/navigator.lisp`)
Tracks current position and history stack for snapshot navigation. Supports back/forward and branch switching.

**Viewport** (`src/interface/viewport.lisp`)
Configurable view into agent state with focus path (drills into nested S-expressions), filter predicates, and three detail levels (`:summary`/`:normal`/`:detailed`).

**Annotator** (`src/interface/annotator.lisp`)
Human annotations on any target (snapshot, thought, etc.). Dual hash-table storage: by annotation ID and by target.

**Blocking Input** (`src/interface/blocking.lisp`)
Thread-safe request/response mechanism using Bordeaux threads locks and condition variables. Agents call `blocking-human-input` which blocks until a human provides a response. Supports timeouts and cancellation. Handles spurious wakeups.

**Entry Points** (`src/interface/entry-points.lisp`)
High-level intervention APIs: `human-override` (inject observation), `human-approve` (set confidence to 1.0), `human-reject` (set confidence to 0.0).

**CLI Session** (`src/interface/session.lisp`)
Full REPL with commands: help, status, start/stop/pause/resume, step (single cognitive cycle), thoughts, inject, detail, back, pending, respond, viz, quit. Command history tracking. Session lifecycle management with global registry.

---

#### Layer 5: Visualization (`src/viz/` and `src/holodeck/`)

**2D Terminal Visualization** (`src/viz/`, 7 files, complete)
ANSI terminal-based timeline explorer:
- 256-color rendering with Unicode box drawing and node glyphs (○ ◆ ◇ ● ★)
- Timeline with chronological snapshot layout and branch connections (fork symbols ┬, vertical bars |)
- Detail panel showing snapshot summaries and thought previews with word-aware line breaking
- hjkl navigation (left/right through time, up/down through branches), Tab for branch cycling, / for search, Enter to select
- Help overlay with keybinding documentation
- Automatic terminal resize handling
- Session integration: converts thought stream to visual timeline

**3D Holodeck** (`src/holodeck/`, 11 files, complete)
Full ECS (Entity Component System) 3D visualization — this is not stubs, it's a complete implementation:

- **ECS Components** (`components.lisp`): 8 component types — `position3d`, `velocity3d`, `scale3d`, `rotation3d`, `visual-style`, `node-label`, `snapshot-binding`, `agent-binding`, `connection`, `interactive`, `detail-level`. Snapshot types map to RGBA colors (genesis=green, decision=gold, action=blue, fork=orange, merge=purple, human=cyan, error=red).
- **ECS Systems** (`systems.lisp`): `movement-system` (velocity integration), `pulse-system` (sine-wave scale animation), `lod-system` (distance-based detail culling). Parallel execution infrastructure with bordeaux-threads.
- **Shaders** (`shaders.lisp`): Three shader programs — hologram-node (Fresnel edge glow + animated scanlines), energy-beam (flow animation for connections), glow (radial billboard falloff). Full CPU-side shader simulation for headless testing. Material classes (`hologram-material`, `energy-beam-material`) with per-type factories.
- **Meshes** (`meshes.lisp`): Three generators — UV-sphere, subdivided octahedron (geodesic), branching-node (sphere + 3 tapered prongs). Each generates 4 LOD levels (4x4 to 32x32 for spheres, 8 to 512 triangles for octahedra). Mesh registry keyed by `(name . lod)`.
- **Rendering** (`rendering.lisp`): Produces backend-agnostic render descriptions as plists. Snapshot entities get mesh, material, color, glow, label. Connection entities get endpoints, beam material, energy-flow animation. LOD-aware: culled entities return nil, low-detail reduces alpha 50% and glow 70%.
- **Camera** (`camera.lisp`): Dual camera modes — orbit camera (spherical coordinates around target, orbit/zoom/pan) and fly camera (FPS-style with yaw/pitch, WASD movement, velocity damping). Seven easing functions for transitions. `animate-camera-to` creates smooth interpolations. Focus helpers: `focus-on-snapshot`, `focus-on-agent`, `camera-overview` (fits scene bounding box).
- **HUD** (`hud.lisp`): 4 panels — position info (top-left), agent info (top-right), timeline scrubber (bottom), keyboard hints (bottom-right). Unicode corner brackets for borders. Timeline scrubber with snapshot markers and current-position highlight. Generates draw commands (fill-rect, line, text, title-bar) for backend rendering.
- **Input** (`input.lisp`): Mouse handler (right-drag orbits, middle-drag pans, scroll zooms). Ray picking: screen-to-world unprojection through inverse view/projection matrices, ray-sphere intersection for entity selection. Hover and selection state tracking.
- **Key Bindings** (`key-bindings.lisp`): 32 default bindings across 5 categories — camera (WASD/QE hold), navigation ([]/Home/End press), branching (F/M/B), view modes (1-4), focus (Tab/Space/O). Action handler registry. Help text formatting by category.
- **Window** (`window.lisp`): Main loop at 60fps with delta-time tracking. Per-frame: process input, apply camera transitions, run ECS systems, collect render descriptions, update HUD. Live agent sync every 0.1s with smooth position lerp. Grid rendering on XZ plane. Event dispatch via typecase on structured event types.

---

#### Layer 6: Integration (`src/integration/`) — External Services

Fourteen source files bridge to external systems:

**Claude Bridge** (`src/integration/claude-bridge.lisp`)
HTTP client for Anthropic Messages API via Dexador. Sends completion requests with optional tools. Parses responses extracting text blocks and tool use blocks.

**Claude Sessions** (`src/integration/session.lisp`)
Conversation state management per agent. Auto-generates system prompts describing agent capabilities. Dual registry: by session ID and by agent ID. Message history tracking.

**MCP Client** (`src/integration/mcp-client.lisp`)
JSON-RPC over stdio protocol (version 2024-11-05). Launches MCP servers as subprocesses, performs initialization handshake, discovers tools and resources. Thread-safe communication with locks. Converts MCP tools to Autopoiesis capabilities via closure-based handlers.

**Provider Abstraction** (`src/integration/provider.lisp`, `provider-agent.lisp`, `provider-*.lisp`)
A novel architecture for wrapping external CLI coding tools as cognitive backends. This is unique to Autopoiesis — no other agent framework treats CLI agents as interchangeable inference engines while maintaining thought-stream introspection.

- **Abstract Provider Protocol** (`provider.lisp`): Base `provider` class with generic functions `provider-invoke`, `provider-build-command`, `provider-parse-output`. Subprocess execution with timeout, streaming support, and thread-safe locking. Global provider registry with find/list/register operations.
- **Provider-Backed Agent** (`provider-agent.lisp`): Extends the `agent` class to delegate cognition to external CLI tools. Full cognitive loop specialization: `perceive` coerces environment to prompt, `reason` prepends system prompt and gathers tool specs, `decide` records delegation decision, `act` invokes provider and records exchange in thought stream, `reflect` evaluates success/failure.
- **Claude Code Provider** (`provider-claude-code.lisp`): Wraps `claude` CLI with `--output-format json`, `--max-turns`, `--dangerously-skip-permissions`, `--allowedTools`, `--max-budget` flags. Parses JSON output extracting result, cost, turns, session ID.
- **Codex Provider** (`provider-codex.lisp`): Wraps `codex exec` with JSONL streaming output. Parses newline-delimited JSON events (`response.completed`, `item.completed`, `turn.completed`).
- **OpenCode Provider** (`provider-opencode.lisp`): Wraps `opencode` CLI with JSONL streaming.
- **Cursor Provider** (`provider-cursor.lisp`): Wraps `cursor-agent` with `--force` flag for non-interactive execution. Shorter default timeout (120s) due to hang risk.

**Tool Mapping** (`src/integration/tool-mapping.lisp`)
Bidirectional conversion between Lisp conventions (kebab-case keywords, Lisp types) and Claude conventions (snake_case strings, JSON Schema types). Executes tool calls from Claude responses and formats results back.

**Built-in Tools** (`src/integration/builtin-tools.lisp`)
13 tools: Filesystem (read, write, list, exists, delete, glob, grep), web (fetch, head), shell (run-command, git-status, git-diff, git-log).

**Event Bus** (`src/integration/events.lisp`)
Pub/sub event system with type-specific and global handlers. 1000-event history for debugging. 13 event types including provider events: tool-called, tool-result, claude-request, claude-response, mcp-connected, provider-request, provider-response, provider-session-started, provider-session-ended, provider-error, etc.

---

### Cross-Cutting Concerns

**Security** (`src/security/`, 3 files)
- Permission system with resource x action matrix (7 resource types, 6 action types), wildcard matching, admin override
- Audit logging with thread-safe rotation, ISO 8601 timestamps, JSON serialization, file rotation at 10MB
- Input validation framework supporting 17 types with combinators (`:and`, `:or`, `:not`, `:nullable`), HTML sanitization, predefined specs for agent IDs, snapshot IDs, branch names

**Monitoring** (`src/monitoring/`, 2 files)
- Prometheus-compatible metrics endpoint with counters, gauges, histograms
- Kubernetes-style probes: `/healthz` (liveness), `/readyz` (readiness), `/health` (detailed), `/metrics`
- Thread-safe metrics registry with labeled dimensions
- Hunchentoot HTTP server on port 8081

**Top-Level Package** (`src/autopoiesis.lisp`)
Reexports public APIs from all sub-packages. Provides `initialize`, `version` (0.1.0-bootstrap), `health-check`, and `help` functions.

---

### Build and Test Infrastructure

**ASDF System Definition** (`autopoiesis.asd`)
Single system definition loading all layers in dependency order.

**Scripts**:
- `scripts/build.sh` — Loads system in SBCL with Quicklisp
- `scripts/test.sh` — Runs all test suites

**Test Suite** (`test/`, 12 files)
10 test suites using FiveAM framework (2,400+ assertions across 600+ tests):
| Suite | Tests | Assertions | Covers |
|-------|-------|------------|--------|
| core-tests | — | 35 | S-expr, cognitive primitives, extension compiler, profiling, recovery, config |
| agent-tests | — | 94 | Agent lifecycle, capabilities, context window, learning, spawning |
| snapshot-tests | — | 83 | Persistence, DAG traversal, compaction, branches |
| interface-tests | — | 40 | Blocking requests, sessions |
| integration-tests | — | 404 | Claude API, MCP, tools, events |
| provider-tests | — | — | Provider protocol, registry, cognitive loop integration, mock provider |
| e2e-tests | — | 134 | End-to-end user stories |
| viz-tests | 25 | 92 | Timeline rendering, navigation, resize, filters, session integration, help |
| holodeck-tests | 442 | 1,193 | ECS components/systems, shaders, meshes, camera, HUD, input, ray picking, key bindings, live agent sync |
| security-tests | 123 | 321 | Permissions, audit logging, input validation, sandbox escape attempts |
| monitoring-tests | 19 | 48 | Metrics registry, health checks, HTTP endpoints |

**Deployment** (`Dockerfile`, `docker-compose.yml`, `docs/DEPLOYMENT.md`)
Docker container definition and compose orchestration for full stack deployment.

---

### Automation Tooling (`ralph/`)

The `ralph/` directory contains automation for implementation:
- `IMPLEMENTATION_PLAN.md` — Task tracking
- `AGENTS.md` — Agent definitions
- `loop.sh` / `supervised.sh` / `run-once.sh` — Automation scripts
- `stream_display.py` — Stream display utility
- Prompt templates for build and planning

### Key Dependencies

| Dependency | Purpose |
|------------|---------|
| bordeaux-threads | Concurrency (blocking input, thread-safe registries, provider locks) |
| cl-json | JSON serialization (Claude API, MCP protocol, provider output parsing) |
| dexador | HTTP client (Claude API, web tools) |
| ironclad | SHA256 hashing (content-addressable storage) |
| babel | UTF-8 encoding (hash computation) |
| local-time | Timestamps |
| alexandria | Utilities (shuffle, hash-table ops) |
| fiveam | Testing framework |
| uiop | System utilities (process execution, environment) |
| hunchentoot | HTTP server (monitoring endpoints on port 8081) |
| cl-ppcre | Regex (input validation) |
| 3d-vectors | Vector math (holodeck) |
| 3d-matrices | Matrix math (holodeck) |
| cl-fast-ecs | Entity-Component-System (holodeck) |

## Code References

- `src/core/s-expr.lisp:163-176` — S-expression diff algorithm
- `src/core/cognitive-primitives.lisp:16-203` — Five cognitive primitive classes
- `src/core/extension-compiler.lisp:232-383` — Extension code validator (code walker)
- `src/agent/cognitive-loop.lisp:50-58` — Five-phase cognitive cycle
- `src/agent/context-window.lisp:90-109` — Priority-based context window
- `src/agent/learning.lisp:398-462` — Pattern extraction from experiences
- `src/snapshot/persistence.lisp:98-151` — Snapshot save/load with cache
- `src/snapshot/time-travel.lisp:50-66` — Common ancestor finding
- `src/interface/blocking.lisp:110-141` — Thread-safe blocking input
- `src/interface/session.lisp:373-410` — CLI REPL loop
- `src/integration/claude-bridge.lisp:62-91` — Claude API HTTP communication
- `src/integration/mcp-client.lisp:196-244` — MCP server connection lifecycle
- `src/integration/provider.lisp:13-68` — Abstract provider base class
- `src/integration/provider.lisp:89-126` — Default `provider-invoke` with subprocess execution
- `src/integration/provider-agent.lisp:56-122` — Provider-backed cognitive loop specialization
- `src/integration/provider-claude-code.lisp:52-72` — Claude Code CLI command building
- `src/integration/events.lisp:136-168` — Event emission with type-specific and global dispatch
- `src/viz/terminal-ui.lisp:181-193` — Terminal UI main loop
- `src/autopoiesis.lisp:112-147` — System health check

## Architecture Documentation

### Data Flow

1. **Agent Creation**: `make-agent` → registers in global registry → empty thought stream and context window
2. **Cognitive Cycle**: `perceive` → `reason` → `decide` → `act` → `reflect` → thoughts appended to stream
3. **Claude Integration**: Agent capabilities → converted to Claude tools → sent with API request → tool calls extracted → capabilities invoked → results sent back
4. **Provider-Backed Agent**: Provider created and registered → `make-provider-backed-agent` → cognitive cycle delegates to CLI tool → `provider-build-command` constructs args → subprocess executed → output parsed → exchange recorded to thought stream as 4 thoughts (prompt observation, tool actions, result observation, reflection)
5. **Snapshot Persistence**: Agent state → `sexpr-hash` → content-addressable store → filesystem with LRU cache → index updated
6. **Time-Travel**: `checkout-snapshot` → load from cache or disk → set as current → return agent state
7. **Human Interaction**: Agent calls `blocking-human-input` → blocks on condition variable → CLI displays prompt → human types response → condition signaled → agent continues
8. **MCP Integration**: Launch subprocess → JSON-RPC initialize → discover tools → convert to capabilities → register in agent

### Key Design Patterns

- **Content-Addressable Storage** — SHA256 hashing for deduplication and integrity
- **Registry Pattern** — Global hash tables for agents, capabilities, sessions, tools, annotations, MCP servers, providers
- **Generic Function Dispatch** — Cognitive cycle phases as generic functions for specialization
- **Protocol Pattern** — Provider defines abstract protocol via generic functions, specialized by concrete implementations
- **Factory Pattern** — Provider creation uses factory functions (`make-claude-code-provider`, `make-codex-provider`, etc.)
- **Adapter Pattern** — Bidirectional: `mcp-tool-to-capability` (MCP→Autopoiesis) and `capability-to-claude-tool` (Autopoiesis→Claude)
- **Bridge Pattern** — Claude bridge, MCP client, and provider abstraction each decouple agents from external protocol specifics
- **Condition/Restart System** — Lisp condition system for error recovery with six standard restarts
- **Closure-Based Handlers** — MCP tool→capability bridge captures server reference in closure
- **Priority Queue Eviction** — Context window manages working memory by token budget
- **Observer Pattern** — Event bus allows subscribers to observe all integration events

## Related Research

- `thoughts/shared/research/2026-02-03-e2e-tests-vs-implementation.md` — Analysis of 19 failing E2E tests, identifying API signature mismatches between spec-first tests and actual implementation
- `thoughts/shared/research/2026-02-03-autopoiesis-real-agent-use-cases.md` — 20 powerful real-world agent system use cases for Autopoiesis, with integration requirements and difficulty assessments

## Configuration

Environment variables used by the integration layer (loaded via `src/core/config.lisp`):

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Claude API key |
| `AUTOPOIESIS_MODEL` | Default model name |
| `MCP_CONFIG_PATH` | Path to MCP configuration |
| `CLAUDE_CODE_PATH` | Path to `claude` CLI binary |
| `CODEX_PATH` | Path to `codex` CLI binary |
| `OPENCODE_PATH` | Path to `opencode` CLI binary |
| `CURSOR_AGENT_PATH` | Path to `cursor-agent` CLI binary |
| `AUTOPOIESIS_DATA_DIR` | Data directory (Docker, defaults to /data) |
| `AUTOPOIESIS_LOG_DIR` | Log directory (Docker, defaults to /data/logs) |
| `AUTOPOIESIS_LOG_LEVEL` | Log level: debug, info, warn, error |
| `AUTOPOIESIS_HOST` | Server bind address (defaults to 0.0.0.0) |
| `AUTOPOIESIS_PORT` | Main application port (defaults to 8080) |
| `AUTOPOIESIS_MONITORING_PORT` | Monitoring port (defaults to 8081) |

## Open Questions

- The learning system has a full pattern extraction pipeline — has it been exercised with real agent runs?
- MCP client and provider abstraction use SBCL-specific process management (`sb-ext:run-program`) — is portability to other CL implementations planned?
- Branch merging in the snapshot layer raises "not yet implemented" — is this blocking any workflows?
- Claude streaming is stubbed (`claude-bridge.lisp:109`) — is streaming support needed for production use?
- Provider-backed agents record exchanges as thoughts but don't currently integrate with the snapshot DAG for branching — should they?
