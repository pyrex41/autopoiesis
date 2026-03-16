# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autopoiesis is a self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation. Agent cognition, conversation, and configuration are represented as S-expressions (code-as-data, data-as-code), enabling agents to modify their own behavior, full state snapshots for time-travel debugging, and human-in-the-loop interaction at any point.

**Current Status:** All phases (0-11) complete plus Command Center frontend. Pure Common Lisp architecture with substrate-backed state management, conductor orchestration, multi-provider agentic loops, and persistent functional agents with O(1) forking via structural sharing. The LFE layer has been removed. The dag-explorer frontend is a SolidJS Command Center with 11 views (dashboard, DAG, timeline, tasks, holodeck, constellation, org chart, budget, approvals, evolution lab, audit log).

## Build & Development Commands

```bash
# Run all tests (from repo root)
./platform/scripts/test.sh

# Build/load the system
./platform/scripts/build.sh
```

```lisp
;; Load the system in SBCL with Quicklisp
(ql:quickload :autopoiesis)

;; Run tests
(asdf:test-system :autopoiesis)

;; Run specific test suite
(5am:run! 'autopoiesis.test::core-tests)
(5am:run! 'autopoiesis.test::e2e-tests)
(5am:run! 'autopoiesis.test::viz-tests)
```

**Environment:** SBCL (recommended), Quicklisp for dependencies, SLIME/SLY for IDE integration.

## Architecture

Autopoiesis adopts a three-layer mental model to reduce cognitive load while preserving all functionality. The platform is organized into **6-7 focused core layers** that represent the unique homoiconic agent substrate, with additional powerful capabilities available as optional extensions.

See `platform/docs/layers.md` for the complete layered architecture with Mermaid diagrams and detailed descriptions.

### Core Platform (6–7 focused layers)

1. **Substrate Layer** (`platform/src/substrate/`) - Datom store with EAV triples, Linda coordination (take!), entity types (event, worker, agent, session, snapshot, turn, context, prompt, department, goal, budget), value indexing, interning, LMDB persistence, blob store
2. **Core Layer** (`platform/src/core/`) - S-expression utilities, cognitive primitives, persistent data structures (fset wrappers: pmap/pvec/pset), extension compiler, recovery, profiling, config
3. **Agent Layer** (`platform/src/agent/`) - Agent runtime, capability registry, cognitive loop, learning system, agent spawner, thread-safe mailboxes, persistent agents (O(1) fork, immutable cognition, lineage, membrane), dual-agent bridge
4. **Snapshot Layer** (`platform/src/snapshot/`) - Content-addressable storage, branch manager, diff engine, time-travel, backup
5. **Orchestration Layer** (`platform/src/orchestration/`) - Conductor tick loop, timer heap, Claude CLI worker, substrate-backed event queue
6. **Integration + API Layer** (`platform/src/integration/`, `platform/src/api/`) - Claude bridge, MCP client, multi-provider agentic loops, REST/WebSocket (Clack/Woo), MCP server, SSE, JSON/MessagePack, Command Center endpoints (departments, goals, budgets, audit, approvals, evolution)
7. **Interface Layer** (`platform/src/interface/`, `platform/src/viz/`) - Navigator, viewport, CLI session, blocking input, 2D ANSI terminal timeline

### Optional Extensions

Powerful capabilities that extend the core platform for specific use cases:

- **Swarm Layer** (`platform/src/swarm/`) - Genome evolution, crossover/mutation, selection, persistent agent evolution, fitness functions
- **Supervisor Layer** (`platform/src/supervisor/`) - Checkpoint/revert for high-risk ops, stable state tracking, dual-agent bridge
- **Crystallize Layer** (`platform/src/crystallize/`) - Emit runtime changes to source files, ASDF fragments, Git export
- **Conversation Layer** (`platform/src/conversation/`) - Turn-based conversation context, fork/merge, history tracking
- **Workspace Layer** (`platform/src/workspace/`) - Ephemeral execution contexts, isolation backends, agent home directories, team coordination
- **Team Layer** (`platform/src/team/`) - Multi-agent coordination with 5 strategies (leader-worker, parallel, pipeline, debate, consensus), shared workspace, CV-based await
- **Jarvis Layer** (`platform/src/jarvis/`) - NL→tool conversational loop, Pi RPC provider, human-in-the-loop
- **Security/Monitoring** (`platform/src/security/`, `platform/src/monitoring/`) - Permissions, audit logging, input validation, health endpoints, metrics
- **Separate systems**: Holodeck (3D ECS viz), Sandbox (squashd containers), Research (parallel campaigns)

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
| 12 | Command Center (org hierarchy, budget, approvals, evolution lab, audit) | Complete |

## Key Dependencies

- `bordeaux-threads` - Concurrency
- `cl-json` - Serialization
- `dexador` - HTTP client (Claude API)
- `ironclad` - SHA256 hashing (content-addressable storage)
- `babel` - UTF-8 encoding
- `local-time` - Timestamps
- `alexandria` - Utilities
- `fiveam` - Testing
- `uiop` - System utilities
- `hunchentoot` - HTTP server (monitoring endpoints)
- `cl-ppcre` - Regex (input validation)
- `3d-vectors` - Vector math (holodeck)
- `3d-matrices` - Matrix math (holodeck)
- `cl-fast-ecs` - Entity-Component-System (holodeck)
- `fset` - Persistent functional collections (persistent agents: pmaps, pvecs, psets)
- `lparallel` - Parallel evaluation (swarm fitness)

## Test Suites

4,300+ assertions across 28 test suites:

- `substrate-tests` - Datom store, interning, transact!, hooks, take!, entity types, defsystem (112 checks)
- `orchestration-tests` - Conductor, timer heap, event queue, workers, Claude CLI (91 checks)
- `core-tests` - S-expression operations, cognitive primitives, persistent structs (470 checks)
- `agent-tests` - Agent creation, capabilities, context window, learning (363 checks)
- `snapshot-tests` - Persistence, DAG traversal, compaction (267 checks)
- `conversation-tests` - Turn creation, context management, forking, history (45 checks)
- `interface-tests` - Blocking requests, sessions (40 checks)
- `viz-tests` - Timeline rendering, navigation, filters, help overlay (92 checks)
- `integration-tests` - Claude API, MCP, tools, events, agentic loops (649 checks)
- `agentic-tests` - Agentic loop, tool dispatch, provider integration (195 checks)
- `provider-tests` - Multi-provider subprocess management (70 checks)
- `prompt-registry-tests` - Prompt templates, registration, retrieval (71 checks)
- `skel-tests` - Typed LLM functions, BAML parser, SAP, JSON schema (523 checks)
- `rest-api-tests` - REST API serialization and dispatch (73 checks)
- `swarm-tests` - Genome evolution, crossover, mutation, selection (110 checks)
- `supervisor-tests` - Checkpoint/revert, stable state, promotion (63 checks)
- `crystallize-tests` - Emit capabilities/heuristics/genomes to source (66 checks)
- `git-tools-tests` - Git read/write tool integration (38 checks)
- `jarvis-tests` - NL dispatch, tool invocation, session management (69 checks)
- `team-tests` - Mailbox concurrency, CV-based await, strategies, workspace coordination (30 checks)
- `workspace-tests` - Ephemeral contexts, isolation, team coordination (69 checks)
- `persistent-agent-tests` - Persistent structs, cognition, fork, lineage, membrane, dual-agent (80 checks)
- `swarm-integration-tests` - Genome bridge, persistent evolution, fitness (23 checks)
- `bridge-protocol-tests` - Claude bridge protocol, message format (14 checks)
- `meta-agent-tests` - Meta-agent capabilities, self-inspection (36 checks)
- `security-tests` - Permissions, audit, validation, sandbox escapes (322 checks)
- `monitoring-tests` - Metrics, health checks, HTTP endpoints (48 checks)
- `e2e-tests` - End-to-end user story tests (134 checks)
- `holodeck-tests` - ECS, shaders, meshes, camera, HUD, ray picking (1,193 checks, separate ASDF system)

## Specification Documents

- `platform/docs/specs/00-overview.md` - Vision, architecture overview, key differentiators
- `platform/docs/specs/01-core-architecture.md` - Core layer design, packages, S-expression foundation
- `platform/docs/specs/02-cognitive-model.md` - Agent architecture, thought representation, cognitive loop
- `platform/docs/specs/03-snapshot-system.md` - Snapshot DAG model, branching, diffing
- `platform/docs/specs/04-human-interface.md` - Human-in-the-loop protocol, entry points
- `platform/docs/specs/05-visualization.md` - ECS architecture, 3D holodeck design
- `platform/docs/specs/06-integration.md` - Claude bridge, MCP integration
- `platform/docs/specs/07-implementation-roadmap.md` - Phased implementation plan
- `platform/docs/specs/08-specification-addendum.md` - Event sourcing, security architecture, resource management
- `platform/docs/specs/08-remaining-phases.md` - Phase 7-10 detailed specifications
- `platform/docs/user-stories.md` - 15 practical user stories with examples
- `platform/docs/DEPLOYMENT.md` - Docker deployment documentation

## Code Conventions

- Package hierarchy: `autopoiesis.substrate`, `autopoiesis.core`, `autopoiesis.agent`, `autopoiesis.snapshot`, `autopoiesis.conversation`, `autopoiesis.orchestration`, etc. with top-level `autopoiesis` reexporting public APIs
- CLOS classes with `:initarg`, `:accessor`, `:initform`, and `:documentation` on slots
- Condition hierarchy with restarts for error handling
- Pure functions preferred (e.g., `sexpr-diff`, `sexpr-patch` are non-mutating)
- Content-addressable storage using structural hashing for snapshots
- Substrate datoms for mutable state: events, workers, agents, sessions stored as EAV triples via `transact!`
- Linda coordination via `take!` for atomic state transitions (e.g., claiming pending events)
- FiveAM for testing with descriptive test names

## Key Function Signatures

```lisp
;; Substrate (datom store)
(with-store (&key path) body...)       ; open store with dynamic bindings
(transact! datoms)                     ; write datoms atomically
(entity-attr eid attribute)            ; read single attribute
(entity-state eid)                     ; read all attributes as plist
(find-entities attribute value)        ; query by attribute value
(take! attribute value &key new-value) ; Linda-style atomic claim
(intern-id name)                       ; name -> entity-id
(resolve-id eid)                       ; entity-id -> name

;; Orchestration (conductor)
(start-conductor &key store)           ; start tick loop thread
(stop-conductor &key conductor)        ; stop and join tick thread
(schedule-action conductor delay plist); schedule timed action
(queue-event type data &key store)     ; queue substrate-backed event
(register-worker conductor task-id thread) ; track running worker
(run-claude-cli config &key timeout on-complete on-error) ; spawn Claude CLI

;; System lifecycle
(start-system &key store-path port)    ; open store + start conductor + monitoring
(stop-system)                          ; stop conductor + monitoring + close store

;; Creating observations and decisions
(make-observation raw &key source interpreted)
(make-decision alternatives chosen &key rationale confidence)

;; Agent cognitive loop
(cognitive-cycle agent environment)

;; Stream operations (returns vector, use helpers for lists)
(stream-length stream)
(stream-last stream n)  ; returns list of last n thoughts

;; Tool name conversion (returns keyword)
(tool-name-to-lisp-name "snake_case")  ; => :SNAKE-CASE
(lisp-name-to-tool-name :kebab-case)   ; => "kebab_case"

;; Holodeck
(launch-holodeck &key store)           ; start 3D visualization
(make-snapshot-entity snapshot-id ...)  ; create ECS entity
(holodeck-frame dt)                    ; run one frame, returns render descriptions

;; Security
(check-permission agent-id resource-type action)
(with-permission-check (agent resource action) body...)

;; Monitoring
(start-monitoring-server &key port host)
(record-metric name value &key type labels)

;; Persistent data structures (fset wrappers)
(pmap-empty) (pmap-get m k) (pmap-put m k v) (pmap-remove m k)
(pvec-empty) (pvec-push v elem) (pvec-ref v idx) (pvec-length v)
(pset-empty) (pset-add s elem) (pset-contains-p s elem) (pset-union s1 s2)

;; Persistent agents
(make-persistent-agent :name n :capabilities caps)  ; immutable agent struct
(persistent-fork agent)                              ; O(1) fork via structural sharing
(persistent-cognitive-cycle agent env)               ; returns new agent, old unchanged
(persistent-agent-diff a b)                          ; structural diff
(persistent-agent-merge a b)                         ; append-only merge

;; Dual-agent bridge (mutable ↔ persistent)
(upgrade-to-dual agent)                              ; upgrade mutable agent
(dual-agent-root dual)                               ; thread-safe persistent root access
(dual-agent-undo dual)                               ; revert to previous version

;; Swarm evolution of persistent agents
(evolve-persistent-agents agents evaluator env :generations 10)
(make-standard-pa-evaluator)                         ; composite fitness evaluator
```

## Development Notes

- The `platform/ralph/` directory contains automation tooling for implementation
- See `platform/ralph/IMPLEMENTATION_PLAN.md` for current task status
- Research documents are in `thoughts/shared/research/`
- The LFE layer has been removed; all orchestration is now in pure Common Lisp
- Substrate special variables (`*intern-table*`, `*resolve-table*`, etc.) are NOT exported — use `autopoiesis.substrate::*intern-table*` when capturing bindings for child threads
- `with-store` creates dynamic bindings that threads do NOT inherit — always capture and rebind substrate specials when spawning threads
- Persistent agents use `fset` library for structural sharing — all updates return new structs, old roots are never modified
- `dual-agent` uses `bt:make-recursive-lock` (not plain lock) because `:after` methods on `(setf agent-name)` etc. call `(setf dual-agent-root)` which re-acquires the lock
- `persistent-supervisor-bridge.lisp` lives in the `supervisor` module (not `agent`) because it depends on both `autopoiesis.agent` and `autopoiesis.supervisor` packages
- Holodeck agent embodiment uses `*persistent-root-table*` side hash-table because `cl-fast-ecs` components can't hold object references

## SCUD Task Management

This project uses SCUD Task Manager for task management.

### Session Workflow

1. **Start of session**: Run `scud warmup` to orient yourself
   - Shows current working directory and recent git history
   - Displays active tag, task counts, and any stale locks
   - Identifies the next available task

2. **Get a task**: Use `/scud:next` or `scud next`
   - Shows the next available task based on DAG dependencies
   - Use `scud set-status <id> in-progress` to mark you're working on it

3. **Work on the task**: Implement the requirements
   - Reference task details with `/scud:task-show <id>`
   - Dependencies are automatically tracked by the DAG

4. **Commit with context**: Use `scud commit -m "message"` or `scud commit -a -m "message"`
   - Automatically prefixes commits with `[TASK-ID]`
   - Uses task title as default commit message if none provided

5. **Complete the task**: Mark done with `/scud:task-status <id> done`
   - The stop hook will prompt for task completion

### Progress Journaling

Keep a brief progress log during complex tasks:

```
## Progress Log

### Session: 2025-01-15
- Investigated auth module, found issue in token refresh
- Updated refresh logic to handle edge case
- Tests passing, ready for review
```

This helps maintain continuity across sessions and provides context for future work.

### Key Commands

- `scud warmup` - Session orientation
- `scud next` - Find next available task
- `scud show <id>` - View task details
- `scud set-status <id> <status>` - Update task status
- `scud commit` - Task-aware git commit
- `scud stats` - View completion statistics
