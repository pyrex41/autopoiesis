# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autopoiesis is a self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation. Agent cognition, conversation, and configuration are represented as S-expressions (code-as-data, data-as-code), enabling agents to modify their own behavior, full state snapshots for time-travel debugging, and human-in-the-loop interaction at any point.

**Current Status:** All phases (0-12) complete plus Command Center frontend. Pure Common Lisp architecture with substrate-backed state management, conductor orchestration, multi-provider agentic loops, and persistent functional agents with O(1) forking via structural sharing.

## Monorepo Structure

The project follows a Pi-style `packages/` monorepo layout with tiered dependencies:

```
autopoiesis/
  packages/
    substrate/          # Tier 1: Standalone datom store (zero internal deps)
    core/               # Tier 2: Core agent platform (depends on substrate)
    api-server/         # Tier 3: WebSocket API server (depends on core)
    jarvis/             # Tier 3: NL→tool conversational loop
    swarm/              # Tier 3: Genome evolution
    team/               # Tier 3: Multi-agent coordination + workspace
    supervisor/         # Tier 3: Checkpoint/revert
    crystallize/        # Tier 3: Runtime→source emission
    holodeck-ecs/       # Tier 3: CL-side 3D ECS
    sandbox/            # Tier 3: Container runtime (squashd)
    research/           # Tier 3: Parallel campaigns
    eval/               # Tier 3: Agent evaluation
    paperclip/          # Tier 3: BYOA adapter
    EXTENSION_TEMPLATE/ # Copyable starter for new extensions
  frontends/
    command-center/     # SolidJS web UI (11 views)
    tui/                # Go terminal UI
  holodeck/             # Rust 3D holodeck
  nexus/                # Rust workspace (5 crates)
  sdk/                  # Go SDK
  docs/                 # Specs, layers, deployment
  scripts/              # Build/test orchestration
  vendor/               # Vendored CL dependencies
  e2e/                  # Integration tests
```

Each package under `packages/` is self-contained with its own `.asd`, `src/`, and `test/`.

## Build & Development Commands

```bash
# Run all tests (from repo root)
./scripts/test.sh

# Build/load the system
./scripts/build.sh
```

```lisp
;; Register all packages for ASDF discovery
(dolist (dir (directory "packages/*/"))
  (push dir asdf:*central-registry*))

;; Load the core system
(ql:quickload :autopoiesis)

;; Load specific extensions
(ql:quickload :autopoiesis/jarvis)
(ql:quickload :autopoiesis/swarm)

;; Run core tests
(asdf:test-system :autopoiesis)

;; Run specific test suite
(5am:run! 'autopoiesis.test::core-tests)
(5am:run! 'autopoiesis.test::e2e-tests)
```

**Environment:** SBCL (recommended), Quicklisp for dependencies, SLIME/SLY for IDE integration.

## Architecture

### Dependency Tiers

```
Tier 1 (Foundation):
  substrate                     (standalone datom store, zero internal deps)

Tier 2 (Core Platform):
  core/autopoiesis              (depends on: substrate)

Tier 3 (Extensions + Apps):
  jarvis, swarm, team, supervisor, crystallize, holodeck-ecs,
  sandbox, research, eval, paperclip, api-server
  (each depends only on autopoiesis, independent of each other)

Tier 4 (Frontends — no CL deps):
  command-center, tui, holodeck (Rust), nexus (Rust)
  (consume REST/WS API)
```

See `docs/layers.md` for the complete layered architecture with Mermaid diagrams.

### Core Platform Modules (packages/core/)

1. **Core** (`src/core/`) - S-expression utilities, cognitive primitives, persistent data structures (fset wrappers: pmap/pvec/pset), extension compiler, recovery, profiling, config
2. **Agent** (`src/agent/`) - Agent runtime, capability registry, cognitive loop, learning system, agent spawner, thread-safe mailboxes, persistent agents (O(1) fork, immutable cognition, lineage, membrane), dual-agent bridge
3. **Snapshot** (`src/snapshot/`) - Content-addressable storage, branch manager, diff engine, time-travel, backup
4. **Orchestration** (`src/orchestration/`) - Conductor tick loop, timer heap, Claude CLI worker, substrate-backed event queue
5. **Integration** (`src/integration/`) - Claude bridge, MCP client, multi-provider agentic loops
6. **API** (`src/api/`) - REST server, MCP server, SSE, Command Center endpoints
7. **Interface** (`src/interface/`, `src/viz/`) - Navigator, viewport, CLI session, 2D ANSI terminal timeline
8. **Security/Monitoring** (`src/security/`, `src/monitoring/`) - Permissions, audit, validation, health

### Extension Packages (packages/*/)

Each extension is a self-contained ASDF system under `packages/`:

- **jarvis** - NL→tool conversational loop, Pi RPC provider, human-in-the-loop
- **swarm** - Genome evolution, crossover/mutation, selection, persistent agent evolution, fitness
- **team** - Multi-agent coordination with 5 strategies + workspace layer
- **supervisor** - Checkpoint/revert for high-risk ops, stable state tracking
- **crystallize** - Emit runtime changes to source files, ASDF fragments, Git export
- **holodeck-ecs** - 3D Entity-Component-System visualization
- **sandbox** - squashd container integration
- **research** - Sandbox-backed parallel campaigns
- **eval** - Agent evaluation and comparison platform
- **paperclip** - Paperclip AI BYOA adapter
- **api-server** - WebSocket API server (Clack/Woo)

### Adding a New Extension

1. Copy `packages/EXTENSION_TEMPLATE/` to `packages/my-extension/`
2. Rename `.asd` and update package names
3. Implement in `src/`, test in `test/`
4. Load with `(ql:quickload :autopoiesis/my-extension)`

## Key Dependencies

- `bordeaux-threads` - Concurrency
- `cl-json` - Serialization
- `dexador` - HTTP client (Claude API)
- `ironclad` - SHA256 hashing (content-addressable storage)
- `babel` - UTF-8 encoding
- `local-time` - Timestamps
- `alexandria` - Utilities
- `fiveam` - Testing
- `hunchentoot` - HTTP server (monitoring endpoints)
- `cl-ppcre` - Regex (input validation)
- `fset` - Persistent functional collections (persistent agents)
- `lparallel` - Parallel evaluation (swarm fitness)
- `3d-vectors`/`3d-matrices`/`cl-fast-ecs` - Holodeck ECS

## Test Suites

4,300+ assertions across 28 test suites. Core tests are in `packages/core/test/`, extension tests are co-located with each package under `packages/*/test/`.

## Specification Documents

- `docs/specs/00-overview.md` - Vision, architecture overview, key differentiators
- `docs/specs/01-core-architecture.md` - Core layer design, packages, S-expression foundation
- `docs/specs/02-cognitive-model.md` - Agent architecture, thought representation, cognitive loop
- `docs/specs/03-snapshot-system.md` - Snapshot DAG model, branching, diffing
- `docs/specs/04-human-interface.md` - Human-in-the-loop protocol, entry points
- `docs/specs/05-visualization.md` - ECS architecture, 3D holodeck design
- `docs/specs/06-integration.md` - Claude bridge, MCP integration
- `docs/specs/07-implementation-roadmap.md` - Phased implementation plan
- `docs/specs/08-specification-addendum.md` - Event sourcing, security architecture
- `docs/specs/08-remaining-phases.md` - Phase 7-10 detailed specifications
- `docs/user-stories.md` - 15 practical user stories with examples
- `docs/DEPLOYMENT.md` - Docker deployment documentation

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

- The `ralph/` directory contains automation tooling for implementation
- See `ralph/IMPLEMENTATION_PLAN.md` for current task status
- Research documents are in `thoughts/shared/research/`
- The LFE layer has been removed; all orchestration is now in pure Common Lisp
- Substrate special variables (`*intern-table*`, `*resolve-table*`, etc.) are NOT exported — use `autopoiesis.substrate::*intern-table*` when capturing bindings for child threads
- `with-store` creates dynamic bindings that threads do NOT inherit — always capture and rebind substrate specials when spawning threads
- Persistent agents use `fset` library for structural sharing — all updates return new structs, old roots are never modified
- `dual-agent` uses `bt:make-recursive-lock` (not plain lock) because `:after` methods on `(setf agent-name)` etc. call `(setf dual-agent-root)` which re-acquires the lock
- `persistent-supervisor-bridge.lisp` lives in the `supervisor` package (not `agent`) because it depends on both `autopoiesis.agent` and `autopoiesis.supervisor` packages
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
