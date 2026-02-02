# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autopoiesis is a self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation. Agent cognition, conversation, and configuration are represented as S-expressions (code-as-data, data-as-code), enabling agents to modify their own behavior, full state snapshots for time-travel debugging, and human-in-the-loop interaction at any point.

**Current Status:** Specification-only (v0.1.0-draft). No implementation code exists yet. The repository contains comprehensive specification documents in `docs/specs/`.

## Build & Development Commands (Planned)

```lisp
;; Load the system
(ql:quickload :autopoiesis)
(autopoiesis:initialize)

;; Run tests
(asdf:test-system :autopoiesis)
```

**Environment:** SBCL (recommended), Quicklisp for dependencies, SLIME/SLY for IDE integration.

## Architecture

Six-layer architecture (bottom to top):

1. **Core Layer** (`src/core/`) - S-expression utilities, cognitive primitives, extension compiler
2. **Agent Layer** (`src/agent/`) - Agent runtime, capability registry, agent spawner
3. **Snapshot Layer** (`src/snapshot/`) - Content-addressable storage, branch manager, diff engine
4. **Human Interface Layer** (`src/interface/`) - Navigator, viewport, annotator for human-in-the-loop
5. **Visualization Layer** (`src/viz/`) - ECS-based 3D "Jarvis-style" holodeck, timeline view
6. **Integration Layer** (`src/integration/`) - Claude bridge, MCP servers, external tools

## Key Dependencies (Planned)

- `cl-fast-ecs` - ECS for visualization
- `bordeaux-threads` - Concurrency
- `cl-json` - Serialization
- `dexador` - HTTP client (Claude API)
- `local-time` - Timestamps
- `alexandria` - Utilities
- `fiveam` - Testing
- Trial or Raylib - 3D rendering

## Implementation Roadmap

The project follows a 10-phase implementation plan (see `docs/specs/07-implementation-roadmap.md`):

- **Phase 0:** Project setup, ASDF system definition, dependencies
- **Phase 1:** S-expression utilities, cognitive primitives
- **Phase 2:** Agent class, capability system, cognitive loop
- **Phase 3:** Snapshot persistence, branching, time-travel navigation
- **Phase 4:** Human entry points, viewport, CLI human-in-the-loop
- **Phase 5:** Claude API integration
- **Phase 6:** MCP server integration
- **Phase 7-8:** 2D terminal and 3D holodeck visualization
- **Phase 9:** Self-extension, agent-written code
- **Phase 10:** Performance, security, deployment

## Specification Documents

- `docs/specs/00-overview.md` - Vision, architecture overview, key differentiators
- `docs/specs/01-core-architecture.md` - Core layer design, packages, S-expression foundation
- `docs/specs/02-cognitive-model.md` - Agent architecture, thought representation, cognitive loop
- `docs/specs/03-snapshot-system.md` - Snapshot DAG model, branching, diffing
- `docs/specs/04-human-interface.md` - Human-in-the-loop protocol, entry points
- `docs/specs/05-visualization.md` - ECS architecture, 3D holodeck design
- `docs/specs/06-integration.md` - Claude bridge, MCP integration
- `docs/specs/07-implementation-roadmap.md` - Phased implementation plan

## Code Conventions

- Package hierarchy: `autopoiesis.core`, `autopoiesis.agent`, `autopoiesis.snapshot`, etc. with top-level `autopoiesis` reexporting all
- CLOS classes with `:initarg`, `:accessor`, `:initform`, and `:documentation` on slots
- Condition hierarchy with restarts for error handling
- Pure functions preferred (e.g., `sexpr-diff`, `sexpr-patch` are non-mutating)
- Content-addressable storage using structural hashing for snapshots
