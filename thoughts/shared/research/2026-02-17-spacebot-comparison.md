---
date: 2026-02-17T21:55:00Z
researcher: Claude
git_commit: 83d6893be422aae498f78ad178c1649dbb1d5817
branch: main
repository: autopoiesis
topic: "Compare and Contrast Autopoiesis with Spacebot (spacedriveapp/spacebot)"
tags: [research, codebase, comparison, spacebot, architecture, agent-platforms]
status: complete
last_updated: 2026-02-17
last_updated_by: Claude
---

# Research: Compare and Contrast Autopoiesis with Spacebot

**Date**: 2026-02-17T21:55:00Z
**Researcher**: Claude
**Git Commit**: 83d6893be422aae498f78ad178c1649dbb1d5817
**Branch**: main
**Repository**: autopoiesis

## Research Question
Compare and contrast the Autopoiesis agent platform with Spacebot (spacedriveapp/spacebot).

## Summary

Autopoiesis and Spacebot are both AI agent platforms but occupy fundamentally different design spaces. **Spacebot** is a production-oriented, multi-user chat agent (Discord/Slack/Telegram) built in Rust with Tokio, focused on concurrent message handling across communities. **Autopoiesis** is a research-oriented, self-modifying agent platform built in Common Lisp, focused on homoiconicity, time-travel debugging, and agent self-extension. They share several conceptual patterns (process delegation, memory systems, tool dispatch) but implement them with radically different philosophies and trade-offs.

## Detailed Findings

### 1. Language and Runtime Philosophy

| Dimension | Autopoiesis | Spacebot |
|-----------|-------------|----------|
| **Language** | Common Lisp (SBCL) | Rust (edition 2024) |
| **Runtime** | SBCL with bordeaux-threads | Tokio async runtime |
| **Paradigm** | Homoiconic, CLOS-based OOP, dynamic typing | Static typing, async/await, trait-based |
| **Concurrency** | OS threads + locks (`bordeaux-threads`) | Tokio tasks + channels (`mpsc`, `RwLock`, `broadcast`) |
| **Binary** | Requires SBCL + Quicklisp ecosystem | Single static binary, no runtime deps |
| **Hot reload** | Native via REPL (SLIME/SLY) | Config hot-reload via `notify` + `arc-swap` |

Autopoiesis's choice of Common Lisp is fundamental to its identity: S-expressions serve as both code and data, enabling agents to inspect and modify their own behavior. Spacebot's choice of Rust reflects its production focus: memory safety, zero-cost abstractions, and a single deployable binary.

### 2. Architecture and Process Model

**Spacebot** has 5 explicit process types, all running as Tokio tasks:

| Process | Role | Implementation |
|---------|------|----------------|
| **Channel** | User-facing LLM conversation (one per Discord thread/Slack channel) | `src/agent/channel.rs` — owns `ChannelState` with `Arc<RwLock<>>` shared state |
| **Branch** | Fork of channel context for background thinking | `src/agent/branch.rs` — spawned as `tokio::spawn`, gets full channel history |
| **Worker** | Independent task execution (fire-and-forget or interactive) | `src/agent/worker.rs` — `WorkerState` enum {Running, WaitingForInput, Done, Failed} |
| **Compactor** | Programmatic context window monitor | `src/agent/compactor.rs` — monitors token count, triggers compaction at 80/85/95% |
| **Cortex** | System-wide observer, memory bulletin generator | `src/agent/cortex.rs` — receives `Signal`s, generates periodic LLM-curated briefings |

**Autopoiesis** has an 11-layer architecture with a different decomposition:

| Layer | Role | Implementation |
|-------|------|----------------|
| **Substrate** | Datom store (EAV triples), Linda coordination | `platform/src/substrate/` — `transact!`, `take!`, `entity-attr`, `find-entities`, Datalog queries |
| **Core** | S-expression utilities, cognitive primitives | `platform/src/core/` — `make-observation`, `make-decision`, `make-reflection` |
| **Agent** | Agent runtime, capability registry, cognitive loop | `platform/src/agent/` — CLOS `agent` class, `cognitive-cycle`, capability promotion pipeline |
| **Snapshot** | Content-addressable DAG, branching, time-travel | `platform/src/snapshot/` — SHA256-based CAS, `sexpr-diff`/`sexpr-patch` |
| **Conversation** | Turn-based context, fork/merge | `platform/src/conversation/` — conversation context management |
| **Orchestration** | Conductor tick loop, timer heap, Claude CLI worker | `platform/src/orchestration/` — `start-conductor`, `queue-event`, `run-claude-cli` |
| **Integration** | Claude bridge, MCP, tools, event bus, agentic loops | `platform/src/integration/` — multi-provider subprocess management |
| **Viz** | 2D terminal timeline | `platform/src/viz/` — ANSI rendering |
| **Holodeck** | 3D ECS visualization | `platform/src/holodeck/` — shaders, meshes, cameras, ray picking |
| **Interface** | Navigator, viewport, CLI session | `platform/src/interface/` — human-in-the-loop |
| **Cross-cutting** | Security, monitoring | `platform/src/security/`, `platform/src/monitoring/` |

**Key difference**: Spacebot's process model is about _concurrent conversation handling_ (many users talking simultaneously). Autopoiesis's layer model is about _cognitive depth_ (one agent reasoning through observations, decisions, reflections, with full state snapshots).

### 3. Concurrency Model

**Spacebot**: Pure async via Tokio. Inter-process communication uses:
- `mpsc::channel` for message delivery (channel ↔ messaging layer)
- `broadcast::Receiver` for process events
- `Arc<RwLock<>>` for shared state (history, active branches/workers)
- `tokio::spawn` for concurrent branch/worker processes
- `tokio::task::JoinHandle` for cancellation via `abort()`

```rust
// Channel owns shared state, tools get Arc clones
pub struct ChannelState {
    pub active_branches: Arc<RwLock<HashMap<BranchId, JoinHandle<()>>>>,
    pub active_workers: Arc<RwLock<HashMap<WorkerId, Worker>>>,
    pub worker_inputs: Arc<RwLock<HashMap<WorkerId, mpsc::Sender<String>>>>,
    // ...
}
```

**Autopoiesis**: Thread-based via bordeaux-threads. Inter-process communication uses:
- Linda `take!` for atomic state transitions on substrate datoms
- Event bus with type-specific handlers (`subscribe-to-event`/`emit-integration-event`)
- Conductor tick loop polling substrate-backed event queue
- Special variable rebinding for thread-spawned workers

```lisp
;; Linda coordination — atomic claim of pending events
(take! :event/status :pending :new-value :processing)

;; Event bus
(emit-integration-event :tool-called :claude :data (list :tool "shell" :arguments "ls"))
```

### 4. Memory and State

**Spacebot** has a dedicated typed memory system:
- **Storage**: SQLite (structured data) + LanceDB (vector embeddings + full-text search)
- **Memory types**: 8 enum variants — `Fact`, `Preference`, `Decision`, `Identity`, `Event`, `Observation`, `Goal`, `Todo`
- **Graph edges**: `Association` struct with `RelationType` — `RelatedTo`, `Updates`, `Contradicts`, `CausedBy`, `ResultOf`, `PartOf`
- **Retrieval**: Hybrid search (vector similarity + full-text via Tantivy), merged with Reciprocal Rank Fusion
- **Embeddings**: Local via FastEmbed (no external API calls)
- **Importance scoring**: Per-type defaults (Identity=1.0, Goal=0.9, Decision=0.8, etc.)
- **Memory bulletin**: Cortex generates periodic LLM-curated briefing injected into all conversations

```rust
pub struct Memory {
    pub id: String,
    pub content: String,
    pub memory_type: MemoryType,
    pub importance: f32,
    pub access_count: i64,
    pub forgotten: bool, // soft-delete
    // ...
}
```

**Autopoiesis** has a fundamentally different state model:
- **Storage**: EAV datom store (in-memory hash tables + optional LMDB persistence)
- **State representation**: Everything is S-expressions — agent thoughts, snapshots, events, worker state
- **Thought stream**: Append-only stream of typed thoughts (`observation`, `decision`, `reflection`, `action`)
- **Snapshot DAG**: Content-addressable storage using SHA256 — every state has a hash, branches form a DAG
- **Time-travel**: `sexpr-diff`/`sexpr-patch` enable navigating between any two states
- **Datalog queries**: Pattern matching over datoms with variable binding and joins

```lisp
;; Thoughts are typed S-expressions
(make-observation "Claude completed successfully" :source :claude)
(make-decision '(:option-a :option-b) :option-a :rationale "faster" :confidence 0.8)

;; Datalog queries over substrate
(query '((?e :agent/status :running) (?e :agent/name ?name)))
```

**Key difference**: Spacebot's memory is about _persistence and retrieval_ for long-running conversations across many users. Autopoiesis's state model is about _inspectability and reproducibility_ — every state is a snapshot that can be diffed, branched, and time-traveled.

### 5. LLM Integration

**Spacebot**:
- Uses the **Rig** framework (v0.30) for agentic loops, tool execution, and hooks
- **Multi-provider**: Anthropic, OpenAI, OpenRouter, Z.ai/GLM, Groq, Together, Fireworks, DeepSeek, xAI, Mistral, OpenCode Zen
- **Model routing**: 4-level system (process-type defaults → task-type overrides → prompt complexity scoring → fallback chains)
- **Rate limit handling**: 429'd models deprioritized across all agents with configurable cooldown
- **Context management**: Compactor monitors context window, triggers summarization at 80/85/95% thresholds

```rust
pub struct RoutingConfig {
    pub channel: String,          // e.g., "anthropic/claude-sonnet-4"
    pub worker: String,           // e.g., "anthropic/claude-haiku-4.5"
    pub task_overrides: HashMap<String, String>,  // "coding" → better model
    pub fallbacks: HashMap<String, Vec<String>>,  // retry chain
}
```

**Autopoiesis**:
- **Multi-provider subprocess management**: Providers are CLI subprocesses (Claude CLI, etc.)
- **Provider result tracking**: `provider-result` CLOS class captures text, tool-calls, turns, cost, duration, exit-code
- **Thought stream recording**: Provider exchanges recorded as sequences of observations/actions/reflections
- **Integration event bus**: All LLM interactions emit typed events (`:claude-request`, `:claude-response`, `:provider-request`, `:provider-response`)
- **Claude CLI specifics**: `run-claude-cli` spawns subprocess with `--output-format stream-json`

```lisp
(defclass provider-result ()
  ((provider-name ...) (text ...) (tool-calls ...) (turns ...)
   (cost ...) (duration ...) (exit-code ...) (session-id ...)))
```

**Key difference**: Spacebot integrates LLMs as _library calls_ via Rig with sophisticated routing. Autopoiesis integrates LLMs as _subprocesses_ with full exchange recording in the thought stream.

### 6. Tool Systems

**Spacebot** has 19 tool files in `src/tools/`:
- **Chat tools**: `reply`, `react`, `skip`, `set_status`, `send_file`, `route`
- **Delegation tools**: `branch_tool`, `spawn_worker`, `cancel`
- **Memory tools**: `memory_recall`, `memory_save`, `memory_delete`, `channel_recall`
- **Execution tools**: `shell`, `file`, `exec`, `browser`, `web_search`
- **Scheduling**: `cron`

Tools are Rig `Tool` trait implementations with JSON Schema input definitions.

**Autopoiesis** has tools defined in `platform/src/integration/`:
- **Built-in tools**: Defined in `tools.lisp` — mapped via `tool-name-to-lisp-name` conversion
- **MCP server integration**: External tools via MCP protocol
- **Agent capabilities**: Built-in capabilities (`introspect`, `spawn`, `communicate`, `receive`) in `builtin-capabilities.lisp`
- **Capability promotion pipeline**: Agent-defined capabilities go through `draft → testing → promoted/rejected`

**Key difference**: Spacebot's tools are oriented toward _user interaction_ (reply, react, send files, route messages). Autopoiesis's tools are oriented toward _agent cognition_ (introspect own state, spawn children, communicate with other agents).

### 7. Messaging and External Interfaces

**Spacebot** has native messaging adapters:
- `src/messaging/discord.rs` — Serenity-based Discord gateway
- `src/messaging/slack.rs` — slack-morphism with Socket Mode
- `src/messaging/telegram.rs` — teloxide
- `src/messaging/webhook.rs` — generic webhook
- `src/messaging/traits.rs` — common adapter trait
- **Message coalescing**: Batches rapid-fire messages into single LLM turns
- **Per-channel permissions**: Guild, channel, and DM-level access control

**Autopoiesis** has:
- `platform/src/interface/` — CLI session, navigator, viewport, blocking input
- `platform/src/monitoring/endpoints.lisp` — Hunchentoot HTTP server with `/health`, `/healthz`, `/readyz`, `/metrics` (Prometheus-compatible)
- No native chat platform adapters — interaction is via CLI, REPL, or the REST API

**Key difference**: Spacebot is built as a _chat platform bot_ — its primary interface is Discord/Slack/Telegram. Autopoiesis is built as a _developer tool_ — its primary interface is the REPL, CLI, and visualization layers.

### 8. Visualization

**Spacebot**: Has a web-based control UI (`src/api/` with Axum + embedded static assets) for monitoring and admin.

**Autopoiesis**: Has two unique visualization systems:
- **2D Terminal Timeline** (`platform/src/viz/`) — ANSI-rendered timeline of agent thoughts with interactive navigation
- **3D Holodeck** (`platform/src/holodeck/`) — Full ECS (Entity-Component-System) with shaders, meshes, dual cameras, HUD, and ray picking for exploring snapshot DAGs in 3D space

### 9. Self-Extension and Code-as-Data

This is where the projects diverge most fundamentally.

**Spacebot**: Fixed architecture. The system is what was compiled. Agents can use tools, save memories, and spawn workers, but cannot modify the system itself. Skills are markdown files with frontmatter, not executable code.

**Autopoiesis**: Self-modifying architecture. Because everything is S-expressions:
- Agents can define new capabilities at runtime (`make-agent-capability`)
- Capabilities go through a promotion pipeline: `draft → testing → promoted`
- The extension compiler (`platform/src/core/`) can compile agent-written code
- Full state snapshots enable safe experimentation with rollback
- Agent cognition is represented as inspectable data structures

### 10. Persistence and Deployment

| Dimension | Autopoiesis | Spacebot |
|-----------|-------------|----------|
| **Persistence** | LMDB (substrate), SHA256 CAS (snapshots), blob store | SQLite (relational), LanceDB (vectors), redb (KV) |
| **Deployment** | SBCL + Quicklisp, Docker | Single Rust binary, Docker, hosted (spacebot.sh) |
| **Config** | Lisp forms | TOML with hot-reload via file watcher |
| **Secrets** | N/A (dev-focused) | AES-256-GCM encrypted at rest |
| **Daemon mode** | N/A | Built-in daemonize with PID tracking |
| **Multi-agent** | Agent spawning via capability system | Multiple agents per instance, each with own workspace |

### 11. Testing

**Autopoiesis**: 2,775+ assertions across 14 test suites (plus 1,193 holodeck assertions). Uses FiveAM.

**Spacebot**: Test infrastructure present (`tests/` directory, `dev-dependencies` include `tokio-test`, `tempfile`). Exact test count not assessed.

### 12. Scale and Maturity

| Dimension | Autopoiesis | Spacebot |
|-----------|-------------|----------|
| **Codebase size** | ~1.1M lines of Rust equivalent (Lisp is more dense) | ~1.1M bytes of Rust + ~400K bytes of TypeScript |
| **Created** | Earlier (multi-phase development) | Feb 11, 2026 |
| **Stars** | Private | 336 |
| **License** | Private | FSL-1.1-ALv2 (converts to Apache 2.0 after 2 years) |
| **Focus** | Research platform, developer tool | Production deployment, community management |

## Architecture Documentation

### Shared Patterns

Both projects exhibit several common architectural patterns:

1. **Process delegation**: Both separate "thinking" from "doing" — Spacebot with branches/workers, Autopoiesis with the conductor dispatching to Claude CLI workers
2. **Event-driven architecture**: Spacebot uses `broadcast::channel` for `ProcessEvent`; Autopoiesis uses an event bus with `subscribe-to-event`/`emit-integration-event`
3. **Typed thought/memory models**: Both distinguish between observations, decisions, and other cognitive categories
4. **Context window management**: Spacebot has automatic compaction; Autopoiesis has snapshot-based state management
5. **Tool dispatch**: Both map LLM tool calls to executable functions with schema validation

### Fundamental Divergences

1. **Code-as-data**: Autopoiesis's homoiconicity is its defining feature — agents can inspect and modify their own cognitive processes. Spacebot has no equivalent.
2. **Time-travel**: Autopoiesis's snapshot DAG with content-addressable storage enables navigating between any two states. Spacebot has no equivalent.
3. **Multi-user concurrency**: Spacebot's architecture exists specifically to handle 50+ simultaneous users across chat platforms. Autopoiesis is single-user.
4. **Memory retrieval**: Spacebot's hybrid vector+full-text search with RRF is production-grade information retrieval. Autopoiesis's Datalog queries are structural pattern matching.
5. **Model routing**: Spacebot has sophisticated 4-level routing with fallback chains and rate-limit awareness. Autopoiesis routes to a single provider subprocess.

## Code References

### Spacebot
- `src/agent.rs` — Process type module declarations
- `src/agent/channel.rs` — Channel process with `ChannelState` shared via `Arc`
- `src/agent/worker.rs` — Worker with `WorkerState` enum and fire-and-forget/interactive modes
- `src/agent/cortex.rs` — Cortex with `Signal` enum and memory bulletin generation
- `src/memory/types.rs` — `Memory`, `MemoryType`, `Association`, `RelationType`
- `src/llm/routing.rs` — `RoutingConfig` with process-type/task-type/fallback routing
- `src/tools/` — 19 tool implementations
- `src/messaging/` — Discord, Slack, Telegram, webhook adapters

### Autopoiesis
- `platform/src/substrate/datalog.lisp` — Datalog query engine with variable binding and joins
- `platform/src/agent/builtin-capabilities.lisp` — Built-in capabilities (introspect, spawn, communicate)
- `platform/src/integration/events.lisp` — Event bus with type-specific handlers
- `platform/src/integration/provider-result.lisp` — `provider-result` class with thought stream recording
- `platform/src/orchestration/packages.lisp` — Conductor, timer heap, event queue, Claude CLI worker exports
- `platform/src/monitoring/endpoints.lisp` — Prometheus-compatible metrics, K8s-style health probes

## Summary Table

| Dimension | Autopoiesis | Spacebot |
|-----------|-------------|----------|
| **Core thesis** | Self-modifying agent on homoiconic foundation | Concurrent multi-user chat agent |
| **Language** | Common Lisp | Rust |
| **State model** | S-expression datoms + snapshot DAG | SQLite + LanceDB + redb |
| **Concurrency** | Threads + Linda coordination | Tokio async + channels |
| **LLM integration** | Subprocess management | Rig framework (library) |
| **Primary interface** | REPL / CLI / 3D Holodeck | Discord / Slack / Telegram |
| **Memory** | Thought streams + Datalog queries | Typed graph with hybrid search |
| **Self-extension** | Yes (core design principle) | No |
| **Time-travel** | Yes (content-addressable snapshots) | No |
| **Multi-user** | No | Yes (core design principle) |
| **Model routing** | Single provider | 4-level routing with fallbacks |
| **Visualization** | 2D terminal + 3D holodeck | Web admin UI |
| **Deployment** | Developer environment | Production daemon + hosted |

## Supplementary: Autopoiesis Substrate, Snapshot, and Agent Detail

From deeper analysis of the lower layers:

### Substrate Layer

**Datom structure** (`substrate/datom.lisp`):
```lisp
(defstruct datom entity attribute value tx added)
; (entity u64, attribute u32, value any, tx u64, added t/nil for retract)
```

**Three default indexes** — all maintain consistent in-memory caches plus optional LMDB:
- `:eavt` — entity-centric (key = `[entity:8][attribute:4][tx:8]`)
- `:aevt` — attribute-centric
- `:ea-current` — current value per `(entity, attribute)`, strategy `:replace`

**`transact!`** runs in two phases: (1) under lock: updates entity-cache `(eid.aid -> value)` + inverted value-index `(aid.value -> hash-set of eids)` + LMDB if present; (2) outside lock: fires hooks by priority. Batch mode via `with-batch-transaction` queues datoms and flushes atomically on exit.

**`take!` implementation** (`substrate/linda.lisp`): acquires store lock, O(1) lookup of `(aid . match-value)` in value-index, atomically swaps the value — all inside the same lock, bypassing `transact!` to avoid double-lock. This is the sole concurrency mechanism for work-stealing.

**Datalog**: `query` processes clauses left-to-right maintaining binding alists. First clause uses value-index for O(1) lookup when attribute+value are concrete; subsequent clauses do hash lookups or scans. Negation via `(not (?e :attr :val))` filters binding list.

**Entity types** (`define-entity-type`): generates a CLOS class with lazy-loading `slot-unbound` (loads from `entity-attr` on first access). Builtin types: `:event`, `:worker`, `:agent`, `:session`, `:snapshot`, `:turn`, `:context`.

**Blob store**: SHA-256 keyed, stored in LMDB `"blobs"` database or `*memory-blobs*` hash-table fallback.

### Snapshot Layer

**Content-addressable**: `snapshot-hash` = `sexpr-hash` of `agent-state`. `content-store` is a ref-counted hash-table; `store-gc` sweeps zero-ref entries.

**Persistence**: Files at `snapshots/<id[0:2]>/<id>.sexpr` as `prin1` S-expressions. LRU cache (default 1000 entries) with MRU-order list + hash-table.

**Snapshot index**: Three lookup structures: `by-id`, `by-parent`, and `by-timestamp` (sorted via `merge 'list`). `entity-as-of eid tx-id` scans EAVT index keeping latest value per attribute — this is how time-travel reads past states.

**DAG traversal** (`time-travel.lisp`): `find-common-ancestor` builds hash-set of one lineage, walks the other until intersection. `find-path from to` handles ancestor, descendant, and diverged-branch cases via common ancestor merge.

**Backup system**: Full backup copies `.sexpr` files + index + SHA-256 checksum over all files. Incremental backups diff against parent backup snapshot list.

### Conversation Layer

**Turn append is atomic**: A single `transact!` call writes all turn datoms AND updates `:context/head` to the new turn entity. No orphaned turns possible.

**Content in blob store**: Turn content stored as blob (SHA-256), not inline in datom value. `turn-content eid` = `load-blob (entity-attr eid :turn/content-hash)`.

**Fork is O(1)**: `fork-context` reads `:context/head` from source, creates new context entity pointing at same head. No turn data copied — forked contexts share the same history chain up to the fork point.

### Agent Layer

**Capability promotion pipeline** (`agent-capability.lisp`):
1. `agent-define-capability` → validates code via `validate-extension-code`, calls `(compile nil full-code)` → `:draft` status
2. `test-agent-capability` → runs test cases, stores `:pass/:fail/:error` results → `:testing` status
3. `promote-capability` → verifies all tests `:pass` → `:promoted`, registers globally via `register-capability`

**Context window**: Priority queue (sorted list) + `recompute-context-content` that greedily fills until `max-size` (default 100K tokens). `context-focus predicate :boost` multiplies matching item priorities.

**Learning system**: n-gram analysis of action sequences (up to n=4), frequency thresholding (≥0.2 per experience). `apply-heuristics` adjusts decision weights: prefer → multiply score by `(1 + confidence*0.5)`, avoid → multiply by `(1 - confidence*0.5)`. Confidence updated as `successes/applications` on success, ×0.9 on failure.

## Supplementary: Autopoiesis Orchestration Detail

From deeper analysis of the orchestration layer:

### Conductor Tick Loop
- 100ms tick: `(process-due-timers conductor)` + `(process-events conductor)` — `conductor.lisp`
- Timer heap: sorted list of `(fire-time . action-plist)` using `merge #'< :key #'car`
- `execute-timer-action` dispatches `:claude` → `run-claude-cli`, others → `queue-event`
- **Substrate capture pattern**: `start-conductor` captures `*substrate*` and `*store*` before `bt:make-thread`, rebinds inside the thread lambda — the same pattern is used in `spawn-agent` (builtin-tools)

### Claude CLI Worker Detail
- `build-claude-command` always appends `</dev/null` (required to prevent hanging)
- Flags: `-p <quoted>`, `--output-format stream-json`, `--verbose`, `--max-turns`, `--dangerously-skip-permissions`
- `run-claude-cli` reads stdout line-by-line, JSON-decodes each, filters for `"type": "result"` entries
- Deadline check per line; SIGTERM → 2s wait → SIGKILL on timeout

### Linda Event Queue
- `queue-event` transacts 4 datoms: `:event/type`, `:event/data`, `:event/status :pending`, `:event/created-at`
- `process-events` uses `(take! :event/status :pending :new-value :processing)` in a loop — atomically claims events without a separate mutex
- On completion: status → `:complete`; on error: status → `:failed` + `:event/error`

### Multi-Provider Hierarchy
```
provider (base)
├── inference-provider         ; direct API (Anthropic, OpenAI-compat, Ollama)
├── provider-backed-agent      ; delegates to CLI subprocess
└── define-cli-provider macro  ; generates:
    ├── claude-code-provider
    ├── codex-provider
    ├── opencode-provider
    └── cursor-provider
```
- `define-cli-provider` macro at `provider-macro.lisp` generates: class, constructor, `provider-supported-modes`, `provider-build-command`, `provider-parse-output`
- Parser types: `:json-object` (single JSON blob), `:jsonl-events` (line-by-line streaming), or custom function
- OpenAI responses converted to Claude format by `openai-response-to-claude-format` so `agentic-loop` stays format-agnostic

### Agentic Loop (Direct API)
- `agentic-loop` in `claude-bridge.lisp` is the pure CL multi-turn loop
- `*claude-complete-function*` dynamic var enables test injection without mocking call sites
- CLOS cognitive loop: `perceive` → `reason` → `decide` → `act` → `reflect`
- `act` calls `agentic-loop`, then sets `agent-conversation-history` to accumulated messages

### Built-in Tools (26 total)
File system: read, write, list, glob, grep, delete
Web: fetch, head
Shell: run-command, git-status/diff/log
Self-extension: define-capability-tool, test-capability-tool, promote-capability-tool
Introspection: list-capabilities-tool, inspect-thoughts
Orchestration: spawn-agent, query-agent, await-agent, fork-branch, compare-branches, save-session, resume-session

## Supplementary: Autopoiesis Visualization and Interface Detail

From deeper analysis of the upper layers:

### 2D Terminal Timeline (`platform/src/viz/`)

- ANSI escape sequences written directly to `*standard-output*` — no curses or TUI library
- Terminal size detection via `stty size` invoked through `uiop:run-program`
- 8 node types with Unicode glyphs (○◆◇◈●★◉□) and 256-color ANSI codes
- Layout: 20 slots across terminal width, snapshot nodes evenly distributed; branches at alternating ±4 row offsets (−4, +4, −8, +8, ...)
- `render-timeline` draws legend → branch labels → main row → branch connections in fixed row positions
- Navigation: `h/l` = left/right cursor, `k/j` = up/down branch, `Tab` = cycle branches, `?` = help overlay
- `session-to-timeline` converts agent thought stream → `snapshot` objects with each thought as a node, all on "main" branch

### 3D Holodeck (`platform/src/holodeck/`)

- **Backend-agnostic**: `holodeck-frame` returns render description *plists*, not OpenGL calls. A rendering backend would consume these.
- **ECS via `cl-fast-ecs`**: 3 systems — `movement-system`, `pulse-system` (scale oscillation via `sin(*elapsed-time* * pulse-rate)`), `lod-system` (sets `:high`/`:low`/`:culled` based on camera distance)
- **Mesh types**: sphere (general), octahedron (decisions/actions, recursive midpoint subdivision), branching-node (forks — central sphere + 3 tapered cylindrical prongs at 120°)
- **Shaders**: Hologram shader (Fresnel glow + scanlines: `sin(y*50 + time*2)`), energy-beam shader (animated `vProgress` along connection), glow billboard shader (Gaussian falloff). CPU-side math replicates GPU for headless mode.
- **Dual cameras**: orbit (spherical coords, theta/phi/distance) and fly (velocity-based with 0.9 damping). Smooth transitions with easing (linear/ease-in-quad/ease-out-cubic).
- **Ray picking**: `screen-to-world-ray` via inverse projection+view matrices, `ray-sphere-intersect-p` via discriminant test
- **HUD**: 4 panels (position, agent detail, timeline scrubber, key hints). Rendered as render command plists — `:fill-rect`, `:line`, `:text`, `:scrubber-marker`.
- **Live agent sync**: `sync-live-agents` queries `running-agents`, creates/updates/deletes ECS entities. Agent y-position encodes state: running=2.0, paused=1.5, initialized=1.0.
- **Dynamic dispatch for CLI integration**: `:viz` CLI command resolves `autopoiesis.viz:launch-session-viz` at runtime via `find-package`/`find-symbol`/`funcall` to avoid compile-time coupling.

### Human Interface Layer (`platform/src/interface/`)

- **Blocking input**: `blocking-input-request` uses a per-request bordeaux-threads lock + condition variable. `wait-for-response` loops on `bt:condition-wait`. `provide-response` acquires lock, sets response, calls `bt:condition-notify`. Multiple concurrent blocking requests possible.
- **CLI session commands** (15+): `:start`/`:stop`/`:pause`/`:resume`, `:step` (one cognitive-cycle), `:thoughts N`, `:inject <text>`, `:detail`, `:respond <req-id> <text>`, `:viz`, `:quit`
- **Viewport focus**: `follow-path` uses `reduce` — numeric steps → `nth`, other steps → `getf`
- **Human override protocol**: `human-override` appends observation with `:source :human-override`; `human-approve` sets `thought-confidence` to 1.0; `human-reject` sets to 0.0 + prepends "REJECTED: " to rationale

### Security Layer (`platform/src/security/`)

- **Permission model**: 7 resource types × 6 action types. `:admin` action on any resource grants all actions for that resource type.
- **Three predefined sets**: `*default-agent-permissions*` (read+execute), `*admin-permissions*` (admin on all), `*sandbox-permissions*` (read-only)
- **Audit log**: JSON Lines format (one JSON object per line). 10MB max with up to 5 rotated files. Lock is a recursive mutex. `with-audit` macro captures both normal return (`:success`) and conditions (`:error`).
- **Validation**: 14 spec types — `:string`, `:integer`, `:number`, `:boolean`, `:keyword`, `:symbol`, `:list`, `:plist`, `:alist`, `:one-of`, `:and`, `:or`, `:not`, `:nullable`. Full recursive validation of nested structures.

### Monitoring Layer (`platform/src/monitoring/`)

- **Prometheus-compatible** `/metrics` endpoint: counter, gauge, histogram with label formatting `name{k=v}`. Each metric: HELP comment + TYPE declaration + value line.
- **K8s-style probes**: `/health` (full JSON check), `/healthz` (liveness — just checks key packages + functions are loaded), `/readyz` (readiness — same as liveness currently).
- **Memory check**: SBCL-specific `sb-kernel:dynamic-usage` — warns at >1GB.
- **HTTP via Hunchentoot** on port 8081, registered by prepending to `hunchentoot:*dispatch-table*` (saved and restored on stop).

**Contrast with Spacebot**: Spacebot serves its admin/monitoring UI via Axum (async Rust HTTP) with embedded static assets (`rust-embed`) and Server-Sent Events for real-time updates. Autopoiesis uses Hunchentoot (synchronous Common Lisp HTTP). Spacebot's UI is a rich web interface; Autopoiesis's is Prometheus scraping + ANSI terminal + 3D holodeck.

## Deep Dive: Open Questions

### Q1: OpenCode Integration vs Claude CLI Worker Model

**Spacebot's OpenCode integration** (`src/opencode/`) is architecturally distinct from its built-in workers in two key ways:

**Persistent server process**: OpenCode runs as `opencode serve --port <N>` — a long-lived HTTP+SSE server, not a one-shot CLI invocation. `OpenCodeServerPool` manages a pool of these, keyed by working directory. Port assignment is deterministic (`hash(directory) % port_range`), enabling **reattach after restart** — if Spacebot restarts, it can reconnect to an already-running OpenCode server via `try_reattach`. The server is spawned with `Stdio::null()` stdin and `kill_on_drop(true)`.

**HTTP+SSE communication**: The `OpenCodeWorker` creates a named session via `POST /session`, sends the task via `POST /session/{id}/message`, then streams `SseEvent`s — `MessageUpdated`, `MessagePartUpdated` (with `Part::Text` or `Part::Tool`), `SessionCompleted`, `PermissionRequest` — from `GET /session/{id}/events`. This is fundamentally different from stdout-line parsing.

**Interactive follow-up**: `OpenCodeWorker::new_interactive` creates an `mpsc::Sender<String>` used to send follow-up messages as additional `POST /session/{id}/message` calls while the SSE stream is still open. The channel's `route` tool delivers follow-ups through `worker_inputs` into this sender.

**Autopoiesis's equivalent**: The `opencode-provider` generated by `define-cli-provider` runs `opencode` as a one-shot subprocess (`:one-shot` mode), parses its JSON output, and returns a `provider-result`. There is no server pool, no SSE streaming, and no reattach capability. The `inference-provider` path achieves interactivity via accumulated `conversation-history` across `cognitive-cycle` calls — but that's in-process, not subprocess-level interactivity.

**Schema of the difference:**
```
Spacebot OpenCode:        opencode serve --port N  ← persistent server
                          POST /session/msg         → triggers work
                          GET /session/events       → SSE stream of progress
                          POST /session/msg (again) → interactive follow-up

Autopoiesis opencode-provider: opencode <flags>    ← one-shot subprocess
                               stdout               → JSON blob → provider-result
```

The Spacebot approach gives OpenCode its full lifecycle management advantage; Autopoiesis's approach is simpler but loses the ability to inject follow-ups mid-run.

---

### Q2: Message Coalescing for Multi-Agent Coordination

**Spacebot's coalescing** (`channel.rs`) buffers `InboundMessage`s into `coalesce_buffer` with a `coalesce_deadline` (a `tokio::time::Instant`). On each message arrival, if no deadline is set, one is created `debounce_ms` in the future. When the deadline fires, the buffer is flushed as a single LLM turn. The LLM sees all messages together with timing context. DMs bypass coalescing entirely.

**Autopoiesis has no equivalent**. The conductor's `process-events` loop claims events one at a time via `take!` in FIFO order. There is no debounce, no deadline, no buffer accumulation. Events are processed as fast as the tick loop runs (100ms cadence). The `with-batch-transaction` macro batches *writes* atomically but that's the opposite concern.

The closest analog in Autopoiesis would be the Linda `take!` loop itself — it drains all pending events per tick — but it processes them sequentially without any "read the room" LLM call over the batch.

For multi-agent coordination specifically: `await-agent` provides sequential synchronization (wait for one child to complete), and `query-agent` reads a child's state, but there is no primitive for "wait until the burst of messages from multiple children settles, then respond to all of them together."

---

### Q3: Snapshot/Time-Travel for Conversation State

**Spacebot's conversation persistence** schema (from `20260211000002_conversations.sql`):
```sql
CREATE TABLE conversation_messages (
    id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL,
    role TEXT NOT NULL,        -- 'user' or 'assistant'
    sender_name TEXT,
    sender_id TEXT,
    content TEXT NOT NULL,
    metadata TEXT,             -- JSON blob
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

This is a simple append-only log. The in-memory `Vec<Message>` in `Arc<RwLock<>>` is the live working set. Compaction works by summarizing the oldest 30–50% of messages and replacing them in-place in the `Vec` — the original messages are gone from memory and not persisted individually. The compaction schema (`20260211000004_compaction.sql`) was actually *removed* ("Those tables have been removed as redundant"), meaning summaries aren't even stored durably — they only exist in the live `Vec`.

There is **no going back**. Fork/branch creates a new `Vec` seeded with a copy of the channel's current history at fork time — not a DAG pointer, a full copy. No common ancestor relationship is tracked.

**Autopoiesis's approach** is the structural inverse: every state is immutable and content-addressed. `fork-context` is O(1) (pointer copy). `entity-as-of tx-id` reads any past state. The snapshot DAG with `find-common-ancestor` and `find-path` enables navigation between any two historical states.

The trade-off is clear: Spacebot optimizes for **bounded memory** (compaction is destructive by design); Autopoiesis optimizes for **complete reproducibility** (everything is kept, GC'd only when explicitly dereferenced).

---

### Q4: Testing Philosophies

**Spacebot** has exactly **4 test files** in `tests/`:
- `tests/bulletin.rs` — E2E test requiring real `~/.spacebot/config.toml` with valid LLM credentials; bootstraps full `AgentDeps` stack against real databases. Marked "run with: `cargo test --test bulletin -- --nocapture`". Not in CI (requires live credentials).
- `tests/opencode_sse.rs` — Unit tests for SSE event parsing against captured real event fixtures. No mocking needed; pure deserialization. Has ~10 `#[test]` functions covering `MessageUpdated`, `MessagePartUpdated` (text and tool variants), `SessionCompleted`, etc.
- `tests/opencode_stream.rs` — Similar fixture-based parsing tests for the OpenCode streaming protocol.
- `tests/context_dump.rs` — Tests for context window dump/serialization format.

Zero inline `#[test]` functions found in `src/memory.rs`, `src/llm/routing.rs`, or `src/agent/channel.rs`. No `#[cfg(test)]` modules in the modules checked.

**Autopoiesis** has 2,775+ assertions across 14 named FiveAM suites, including 134 E2E user-story tests, 322 security tests (including sandbox escape attempts), and 1,193 holodeck assertions. Every layer has dedicated test coverage.

**Summary of the difference**: Spacebot's test suite is currently narrow — a handful of parsing tests and one live-credential E2E smoke test. The system correctness relies heavily on Rust's type system (no invalid state transitions compile, the `WorkerState` state machine is compiler-enforced, etc.). Autopoiesis compensates for dynamic typing with extensive FiveAM test coverage. Both approaches are coherent given their language choices: Rust's compile-time guarantees reduce the need for runtime tests; Common Lisp's dynamism requires more runtime verification.
