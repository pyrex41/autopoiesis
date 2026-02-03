# Autopoiesis Implementation Plan

Last updated: 2026-02-02
Current Phase: 3 (Snapshot System)

## Completed

### Phase 0: Foundation
- [x] Create `autopoiesis.asd` system definition with all subsystems
- [x] Create `src/core/packages.lisp` with package definitions
- [x] Create `scripts/build.sh` for command-line building
- [x] Create `scripts/test.sh` for command-line testing
- [x] Create placeholder files for each src/ subdirectory
- [x] Create `src/autopoiesis.lisp` main package with reexports

### Phase 1: Core Primitives (Implemented - Verified)
- [x] Implement `sexpr-equal` in `src/core/s-expr.lisp`
- [x] Implement `sexpr-hash` for content-addressable hashing
- [x] Implement `sexpr-serialize` / `sexpr-deserialize`
- [x] Implement `sexpr-diff` and `sexpr-patch`
- [x] Create `thought` class in `src/core/cognitive-primitives.lisp`
- [x] Create `decision` class (extends thought)
- [x] Create `action` class
- [x] Create `observation` class
- [x] Create `reflection` class
- [x] Implement `thought-stream` class
- [x] Create condition hierarchy in `src/core/conditions.lisp`
- [x] Implement extension compiler with sandbox validation
- [x] Write unit tests for all s-expr operations
- [x] Write unit tests for cognitive primitives

### Phase 2: Agent Runtime (Implemented - Verified)
- [x] Implement base `agent` class in `src/agent/agent.lisp`
- [x] Implement `capability` class in `src/agent/capability.lisp`
- [x] Implement capability registry
- [x] Implement cognitive loop in `src/agent/cognitive-loop.lisp`
- [x] Implement `spawn-agent` and agent registry
- [x] Write tests for agent creation and capability system

### Verification Tasks (Completed)
- [x] Load system in SBCL and fix any compilation errors
- [x] Run all tests and fix failures
- [x] Ensure all packages export correctly

## In Progress

(none currently)

## Next Up (Priority Order)

### Phase 2: Agent Runtime (Remaining)
- [x] Create `defcapability` macro
- [x] Implement `context-window` class
- [x] Implement built-in capabilities (introspect, spawn, communicate)

### Phase 3: Snapshot System
- [x] Implement snapshot persistence to disk
- [x] Implement branch DAG traversal
- [x] Implement event compaction
- [x] Write snapshot system tests

### Phase 4: Human Interface
- [x] Implement CLI-based session
- [x] Implement human input blocking mechanism
- [x] Write interface tests

## Blocked / Needs Human Input

(none yet)

## Future (Waiting for Earlier Phases)

### Phase 5: Claude Integration
- Depends on: Phase 4 complete
- HTTP client for Claude API
- Tool use formatting

### Phase 6+: MCP, Visualization
- Depends on: Phase 5 complete

---

## Notes

- Following phased approach from `docs/specs/07-implementation-roadmap.md`
- Each task should be atomic and testable
- Bootstrap complete - system should now load
- Prioritize fixing any load/compile errors before adding features

## Files Created in Bootstrap

### src/core/
- packages.lisp
- conditions.lisp
- s-expr.lisp
- cognitive-primitives.lisp
- thought-stream.lisp
- extension-compiler.lisp

### src/agent/
- packages.lisp
- agent.lisp
- capability.lisp
- cognitive-loop.lisp
- spawner.lisp
- registry.lisp

### src/snapshot/
- packages.lisp
- snapshot.lisp
- content-store.lisp
- persistence.lisp
- branch.lisp
- diff-engine.lisp
- event-log.lisp
- time-travel.lisp

### src/interface/
- packages.lisp
- navigator.lisp
- viewport.lisp
- annotator.lisp
- entry-points.lisp
- session.lisp
- protocol.lisp

### src/integration/
- packages.lisp
- claude-bridge.lisp
- message-format.lisp
- mcp-client.lisp
- tool-registry.lisp
- config.lisp

### test/
- packages.lisp
- core-tests.lisp
- agent-tests.lisp
- snapshot-tests.lisp
- integration-tests.lisp
- run-tests.lisp
