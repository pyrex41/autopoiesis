# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autopoiesis is a self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation. Agent cognition, conversation, and configuration are represented as S-expressions (code-as-data, data-as-code), enabling agents to modify their own behavior, full state snapshots for time-travel debugging, and human-in-the-loop interaction at any point.

**Current Status:** Phases 0-6 complete, Phase 7 (2D Visualization) in progress. Core functionality is implemented and tested.

## Build & Development Commands

```bash
# Run all tests
./scripts/test.sh

# Build/load the system
./scripts/build.sh
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

Six-layer architecture (bottom to top):

1. **Core Layer** (`src/core/`) - S-expression utilities, cognitive primitives, extension compiler
2. **Agent Layer** (`src/agent/`) - Agent runtime, capability registry, agent spawner
3. **Snapshot Layer** (`src/snapshot/`) - Content-addressable storage, branch manager, diff engine
4. **Human Interface Layer** (`src/interface/`) - Navigator, viewport, annotator for human-in-the-loop
5. **Visualization Layer** (`src/viz/`) - 2D terminal timeline (in progress), 3D holodeck (planned)
6. **Integration Layer** (`src/integration/`) - Claude bridge, MCP servers, external tools

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
| 7 | 2D terminal visualization | In Progress |
| 8 | 3D holodeck visualization | Planned |
| 9 | Self-extension, agent-written code | Planned |
| 10 | Performance, security, deployment | Planned |

## Key Dependencies

- `bordeaux-threads` - Concurrency
- `cl-json` - Serialization
- `dexador` - HTTP client (Claude API)
- `local-time` - Timestamps
- `alexandria` - Utilities
- `fiveam` - Testing
- `uiop` - System utilities

## Test Suites

All tests passing (801+ checks):

- `core-tests` - S-expression operations, cognitive primitives (35 checks)
- `agent-tests` - Agent creation, capabilities, context window (94 checks)
- `snapshot-tests` - Persistence, DAG traversal, compaction (83 checks)
- `interface-tests` - Blocking requests, sessions (40 checks)
- `integration-tests` - Claude API, MCP, tools (404 checks)
- `e2e-tests` - End-to-end user story tests (134 checks)
- `viz-tests` - Visualization rendering (11 checks)

## Specification Documents

- `docs/specs/00-overview.md` - Vision, architecture overview, key differentiators
- `docs/specs/01-core-architecture.md` - Core layer design, packages, S-expression foundation
- `docs/specs/02-cognitive-model.md` - Agent architecture, thought representation, cognitive loop
- `docs/specs/03-snapshot-system.md` - Snapshot DAG model, branching, diffing
- `docs/specs/04-human-interface.md` - Human-in-the-loop protocol, entry points
- `docs/specs/05-visualization.md` - ECS architecture, 3D holodeck design
- `docs/specs/06-integration.md` - Claude bridge, MCP integration
- `docs/specs/07-implementation-roadmap.md` - Phased implementation plan
- `docs/user-stories.md` - 15 practical user stories with examples

## Code Conventions

- Package hierarchy: `autopoiesis.core`, `autopoiesis.agent`, `autopoiesis.snapshot`, etc. with top-level `autopoiesis` reexporting public APIs
- CLOS classes with `:initarg`, `:accessor`, `:initform`, and `:documentation` on slots
- Condition hierarchy with restarts for error handling
- Pure functions preferred (e.g., `sexpr-diff`, `sexpr-patch` are non-mutating)
- Content-addressable storage using structural hashing for snapshots
- FiveAM for testing with descriptive test names

## Key Function Signatures

```lisp
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
```

## Development Notes

- The `ralph/` directory contains automation tooling for implementation
- See `ralph/IMPLEMENTATION_PLAN.md` for current task status
- Research documents are in `thoughts/shared/research/`
