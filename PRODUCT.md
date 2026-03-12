# Autopoiesis

**A self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation.**

Autopoiesis turns agents into living, evolving entities. Cognition, conversation, configuration, and state are all represented as S-expressions—code-as-data, data-as-code. Agents can inspect themselves, modify their own behavior, fork timelines, and crystallize runtime changes back into source code, all while maintaining full history and safety through persistent immutable structures.

## Vision

Autopoiesis is the operating system for agent swarms. It provides:

- **World-class management console** for directing hundreds of agents
- **Seamless natural language interface** (Jarvis model) for fluid human direction
- **Safe, observable self-configuration** so agents can extend themselves intelligently
- **Time-travel debugging** via content-addressable snapshot DAG
- **Production-grade orchestration** with recurring tasks, coordination strategies, and persistent state

The platform makes the raw power of homoiconic Lisp accessible through intuitive interfaces while preserving the ability for agents to directly access and evolve the full system.

Built on homoiconic Lisp, Autopoiesis enables agents to reason about their own code, state, and behavior—leading to true self-improvement and adaptability. Unlike traditional agent frameworks, Autopoiesis maintains full observability through immutable snapshots and provides human oversight at every level of agent evolution.

## Core Capabilities

### Agent Management & Swarms

Persistent agents form the backbone of Autopoiesis, allowing for safe experimentation and branching without losing history.

- **Persistent Agents**: Agents are immutable structs using fset persistent collections (pmap, pvec, pset) for cognition, capabilities, and metadata. Lineage tracks parent-child relationships; membrane isolates agent state. Dual-agent bridge provides mutable facade over persistent roots with thread-safe locks.
- **Forking & Merging**: O(1) forking via structural sharing creates new agent versions for experimentation. Merging supports append-only changes with conflict resolution.
- **Registry & Discovery**: Substrate-backed agent registry with `list-agents`, `find-agent`, and `register-agent`. Supports dynamic spawning with `make-agent` and `spawn-agent`.
- **Team Coordination**: Five strategies (leader-worker, parallel, pipeline, debate, consensus) with shared workspaces, CV-based await, and task claiming via Linda `take!`.
- **Swarm Evolution**: Genome-based evolution with crossover, mutation, selection, and fitness functions using lparallel for parallel evaluation.

### Orchestration & Tasks

Autopoiesis handles complex workflows with timer-based scheduling and event-driven coordination.

- **Conductor**: Tick loop (100ms) with timer-heap for delayed actions (`schedule-action`). Processes due timers and executes actions like Claude CLI spawns or event queuing.
- **Event Queue**: Substrate-backed with `queue-event` and `take!` for atomic claims. Supports worker tracking and metrics.
- **Workspaces & Tasks**: Ephemeral contexts with isolation backends. Task queues for multi-agent coordination, atomic claiming, and result submission.
- **Recurring Tasks**: Timer actions reschedule themselves for periodic workflows. Supports cron-like DSL via plist parameters.
- **Background Agents**: Persistent agents run continuous processes, integrated with conductor for lifecycle management.

### Jarvis Natural Language Interface

Inspired by JARVIS from Iron Man, the NL interface provides conversational control over the entire platform.

- **Conversational Loop**: NL input → provider (rho-cli, Pi, Claude) → tool parsing (JSON alist) → dispatch via `tool-name-to-lisp-name` → result feedback → next turn.
- **Human-in-the-Loop**: `jarvis-request-human-input` creates blocking requests with interface primitives (CLI or web forms).
- **Tool Registry**: Automatic exposure of capabilities as tools. Supports multi-turn sessions with conversation history.
- **Provider Integration**: Agnostic design with prompt registries for system/consciousness bootstrapping. Includes supervisor for high-risk ops.
- **Session Management**: `start-jarvis`, `jarvis-prompt`, persistent history, and team extensions.

### Self-Configuration & Evolution

Agents bootstrap their own "consciousness" through prompts and can modify themselves safely.

- **Prompt Registry**: `cognitive-base` establishes agent persona, capabilities, and entry points. Supports forking and rendering with variable substitution.
- **Learning**: Experience recording (task/context/actions/outcome) → heuristic extraction with decay. Stored in agent heuristics for adaptive behavior.
- **Extension Compiler**: Sandboxed compilation with whitelist (strict/moderate/trusted levels). Validates source against forbidden symbols, handles lambda/flet safely.
- **Crystallize**: Runtime changes → source emission (capabilities, heuristics, genomes). Supports ASDF fragments and Git export for persistence.
- **Safe Modification Flow**: Introspect identity → propose changes via tools → supervisor checkpoint → sandboxed compile → crystallize to source → persistent fork.
- **Protected vs Modifiable**: Core (substrate, compiler, supervisor, persistent roots) immutable; extensions (prompts, heuristics, capabilities) evolve.

### Visualization & Time Travel

Autopoiesis provides multiple visual interfaces for observing and controlling agents.

- **SolidJS Web Console**: Evolved dag-explorer with performant canvas (requestAnimationFrame, DPR scaling), particles, glows, starfield. DAG layout (dagre Sugiyama), minimap, command palette, keyboard navigation (h/j/k/l for siblings/children).
- **Holodeck 3D**: ECS-based immersive viz with cognitive phase colors (perceive/reason/decide/act/reflect), lineage layouts, metabolic glow, and swarm embodiment. Camera controls, HUD, and realtime sync.
- **Timeline & Snapshots**: Content-addressable DAG with SHA-256 hashing. Branching, diffing, compaction. Lazy loading for performance.
- **Terminal UI**: ANSI timeline with viewport navigation, detail panels, and search/filter. Supports CLI sessions and TUI primitives.
- **Realtime Updates**: WS/SSE for live thoughts, agent states, blocking requests. Event types: `thought_added`, `agent_state_changed`, `holodeck_frame`.

## Web Console Experience

The primary interface is a world-class SolidJS web application (dag-explorer evolved):

- **Live Agent Swarm Dashboard**: Table/list of agents with status (active/paused), current thoughts stream, lineage tree, capabilities list. Buttons for spawn/fork/pause/stop/upgrade-to-dual.
- **Interactive 2D/3D DAG Explorer**: Force-directed layout for snapshots, nodes colored by agent/branch/time. Click to scrub timeline, hover for details, diff mode for changes. Optional Three.js upgrade for 3D force layouts with orbiting camera.
- **Task Scheduler**: Visual calendar/grid for recurring tasks, form to add new schedules (plist-based), queue monitor with claiming status. Integration with workspace teams.
- **Jarvis Chat Pane**: Floating or docked NL input box. Types: direct commands ("spawn agent for monitoring"), self-mod ("crystallize heuristics"), task setup ("schedule daily report"). Responses include tool calls and human approvals.
- **Self-Config Tools**: Prompt editor for cognitive-base forking, heuristic viewer with confidence bars, crystallize preview (diff of proposed source changes), approve/reject with supervisor integration.
- **Game-Like Aesthetic**: Responsive controls (keyboard shortcuts, mouse pan/zoom), particles on active paths, radial gradients, scanlines for sci-fi feel.

Users direct agents via intuitive UI controls *or* fluid NL prompts ("add a recurring monitoring agent", "tweak my cognitive loop based on last 10 experiences", "crystallize these heuristics").

### UX Flows

- **Managing Swarms**: Dashboard → select agents → fork for testing → apply changes via crystallize → merge back.
- **Setting Recurring Tasks**: Scheduler UI → define action plist → schedule → monitor queue → Jarvis for dynamic adjustments.
- **Self-Configuration**: Chat "inspect my heuristics" → view in UI → propose tweak → preview diff → approve → crystallize.
- **Time Travel**: DAG click → load snapshot → branch new timeline → experiment → revert if needed.

## Technical Foundation

Autopoiesis is a layered architecture reducing cognitive load while enabling full homoiconicity.

### Substrate Layer
- EAV datoms (entity-attribute-value) for mutable state.
- `transact!` for atomic writes, `take!` for Linda-style coordination.
- LMDB persistence, blob store, interning, reactive `defsystem`.
- Functions: `entity-attr`, `entity-state`, `find-entities`, `intern-id`, `resolve-id`.

### Core Layer
- S-expression utilities (diff, patch, hash), cognitive primitives (Observation/Decision).
- Persistent data structures (fset wrappers: pmap/pvec/pset).
- Extension compiler with validation and invocation tracking.

### Agent Layer
- Agent runtime, capability registry, cognitive loop (`cognitive-cycle`).
- Persistent agents: `make-persistent-agent`, `persistent-fork`, `persistent-cognitive-cycle`.
- Dual-bridge: `upgrade-to-dual`, `dual-agent-root`, `dual-agent-undo`.

### Snapshot Layer
- Content-addressable storage, DAG traversal, diff engine, compaction.
- Functions: `sexpr-diff`, `sexpr-patch`, time-travel via `snapshot-branch`, `snapshot-merge`.

### Orchestration Layer
- Conductor: `start-conductor`, `stop-conductor`, `schedule-action`, `queue-event`.
- Timer heap, event queue, worker tracking, Claude CLI integration.

### Integration + API Layer
- Multi-provider agentic loops, MCP client, REST/WebSocket (Clack/Woo), SSE, JSON/MessagePack.
- Serialization: `agent-to-json-*`, `snapshot-to-json-*`.
- Chat handlers for Jarvis bridge.

### Interface Layer
- Navigator, viewport, CLI sessions, blocking input, ANSI terminal timeline.

### Optional Extensions
- Swarm: Genome evolution, fitness evaluation.
- Supervisor: Checkpoint/revert for high-risk ops.
- Crystallize: Emit to source/ASDF/Git.
- Conversation: Turn-based context, fork/merge.
- Workspace: Ephemeral isolation.
- Team: Multi-agent strategies.
- Jarvis: NL conversational loop.
- Security/Monitoring: Permissions, audit, health endpoints.
- Holodeck: 3D ECS viz.

## Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Project setup, ASDF, dependencies | Complete |
| 1 | S-expression utilities, cognitive primitives | Complete |
| 2 | Agent class, capability system, cognitive loop | Complete |
| 3 | Snapshot persistence, branching, time-travel | Complete |
| 4 | Human entry points, viewport, CLI session | Complete |
| 5 | Claude API integration | Complete |
| 6 | MCP server integration | Complete |
| 7 | 2D terminal visualization | Complete |
| 8 | 3D holodeck visualization | Complete |
| 9 | Self-extension, agent-written code | Complete |
| 10 | Performance, security, deployment | Complete |
| 11 | Persistent agent architecture (fset, dual-agent, swarm integration) | Complete |

## Test Suites

4,300+ assertions across 28 test suites + 109 browser E2E assertions across 14 suites:

- `substrate-tests` (112 checks): Datom store, interning, transact!, hooks, take!, entity types.
- `orchestration-tests` (91 checks): Conductor, timer heap, event queue, workers, Claude CLI.
- `core-tests` (470 checks): S-expression operations, cognitive primitives, persistent structs.
- `agent-tests` (363 checks): Agent creation, capabilities, context window, learning.
- `snapshot-tests` (267 checks): Persistence, DAG traversal, compaction.
- `conversation-tests` (45 checks): Turn creation, context management, forking, history.
- `interface-tests` (40 checks): Blocking requests, sessions.
- `viz-tests` (92 checks): Timeline rendering, navigation, filters, help overlay.
- `integration-tests` (649 checks): Claude API, MCP, tools, events, agentic loops.
- `agentic-tests` (195 checks): Agentic loop, tool dispatch, provider integration.
- `provider-tests` (70 checks): Multi-provider subprocess management.
- `prompt-registry-tests` (71 checks): Prompt templates, registration, retrieval.
- `skel-tests` (523 checks): Typed LLM functions, BAML parser, SAP, JSON schema.
- `rest-api-tests` (73 checks): REST API serialization and dispatch.
- `swarm-tests` (110 checks): Genome evolution, crossover, mutation, selection.
- `supervisor-tests` (63 checks): Checkpoint/revert, stable state, promotion.
- `crystallize-tests` (60 checks): Emit capabilities/heuristics/genomes to source.
- `git-tools-tests` (38 checks): Git read/write tool integration.
- `jarvis-tests` (402 checks): Session creation, tool parsing, dispatch, HIL.
- `team-tests` (30 checks): Mailbox concurrency, CV-based await, strategies, workspace coordination.
- `workspace-tests` (69 checks): Ephemeral contexts, isolation, team coordination.
- `persistent-agent-tests` (80 checks): Persistent structs, cognition, fork, lineage, membrane, dual-agent.
- `swarm-integration-tests` (23 checks): Genome bridge, persistent evolution, fitness.
- `bridge-protocol-tests` (14 checks): Claude bridge protocol, message format.
- `meta-agent-tests` (36 checks): Meta-agent capabilities, self-inspection.
- `security-tests` (322 checks): Permissions, audit, validation, sandbox escapes.
- `monitoring-tests` (48 checks): Metrics, health checks, HTTP endpoints.
- `e2e-tests` (134 checks): End-to-end user story tests.
- `holodeck-tests` (1,193 checks): ECS, shaders, meshes, camera, HUD, ray picking.
- `browser-e2e` (109 assertions across 14 suites): Dashboard, DAG, timeline, tasks, holodeck, agent lifecycle, conductor, teams, Jarvis, command palette, activity, cost, WebSocket. Uses rodney (Chrome CDP) with SolidJS-aware helpers. Run via `tilt trigger e2e-tests`.

## Key Function Signatures

```lisp
;; Substrate
(with-store (&key path) body...)       ; open store with dynamic bindings
(transact! datoms)                     ; write datoms atomically
(entity-attr eid attribute)            ; read single attribute
(entity-state eid)                     ; read all attributes as plist
(find-entities attribute value)        ; query by attribute value
(take! attribute value &key new-value) ; Linda-style atomic claim

;; Orchestration
(start-conductor &key store)           ; start tick loop thread
(stop-conductor &key conductor)        ; stop and join tick thread
(schedule-action conductor delay plist); schedule timed action
(queue-event type data &key store)     ; queue substrate-backed event

;; Agents
(make-persistent-agent :name n :capabilities caps) ; immutable agent struct
(persistent-fork agent)                            ; O(1) fork via structural sharing
(persistent-cognitive-cycle agent env)            ; returns new agent, old unchanged

;; Jarvis
(start-jarvis &key provider)             ; start NL session
(jarvis-prompt session message)          ; process NL input

;; Crystallize
(crystallize-capabilities agent)         ; emit to source
(crystallize-heuristics agent)           ; extract and emit heuristics

;; Visualization
(launch-holodeck &key store)             ; start 3D viz
(holodeck-frame dt)                      ; run one frame
```

## Target Users

- AI researchers and platform engineers building production agent systems
- Teams needing observable, debuggable, self-improving agent swarms
- Developers who want both high-level NL control and low-level homoiconic power
- Organizations requiring auditable, time-travel-capable agent workflows

## Getting Started

**Fastest path** (recommended): Install [Tilt](https://tilt.dev/), then `tilt up --port 14400`. This orchestrates Earthly build, Docker backend, and bun frontend dev server. Web console at `http://localhost:14403`.

**Manual path:**

1. **Install Dependencies**: SBCL, Quicklisp for libraries (bordeaux-threads, cl-json, dexador, ironclad, fset, etc.). Bun for the web console.

2. **Build System**:
```bash
./platform/scripts/build.sh
```

3. **Run Tests**:
```bash
./platform/scripts/test.sh
```

4. **Load and Start**:
```lisp
(ql:quickload :autopoiesis)
(asdf:test-system :autopoiesis)
(start-system &key store-path port)
```

5. **Start Web Console**:
```bash
cd dag-explorer && bun install && bun run dev -- --port 14403
```

6. **First Agent**: Use Jarvis chat: "Create a persistent agent for monitoring system health" or UI: spawn button → configure capabilities.

7. **Self-Modify**: Prompt "inspect my current heuristics" → tweak via UI → crystallize.

See `platform/docs/QUICKSTART.md`, `CLAUDE.md`, and `platform/docs/layers.md` for detailed guides.

## Roadmap

- **Short-term**: Wire live SSE to SolidJS console, add agent/task panels, integrate Three.js for 3D DAG.
- **Medium-term**: Multi-user auth, mobile responsive, advanced team strategies.
- **Long-term**: Bevy/Rust desktop client, VR holodeck, automated crystallize triggers.

**Autopoiesis: Where agents become self-aware, self-improving, and truly alive.**

---

*This product description is based on the current implementation as of phases 0-11 complete. All layers are production-ready with extensive testing.*