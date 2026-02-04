# Autopoiesis Implementation Plan

Last updated: 2026-02-03
Current Phase: Complete - All phases implemented and tested

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

(All phases complete - no pending tasks)

## Recently Completed

### Phase 10: Production (Completed)
- [x] Implement LRU cache for hot snapshots
- [x] Implement `parallel-ecs-update` for independent systems
- [x] Implement `compact-thought-stream` for memory reduction
- [x] Profile and optimize critical paths
- [x] Implement lazy loading for large DAGs
- [x] Define permission system (resource × action matrix)
- [x] Implement `check-permission` and `with-permission-check`
- [x] Implement audit logging with rotation
- [x] Implement input validation framework
- [x] Security test sandbox escape attempts
- [x] Implement error recovery with restarts
- [x] Add state consistency checks
- [x] Implement backup/restore functionality
- [x] Add graceful degradation on failures
- [x] Create Dockerfile with SBCL and dependencies
- [x] Implement configuration management (load/merge)
- [x] Implement health check endpoints
- [x] Implement metrics collection
- [x] Create docker-compose for full stack
- [x] Write deployment documentation

### Phase 9: Self-Extension (Completed)
- [x] Define sandbox rules (*allowed-packages*, *forbidden-symbols*, *allowed-special-forms*)
- [x] Implement `validate-extension-code` walker
- [x] Implement `compile-extension` with error handling
- [x] Create extension registry and `extension` class
- [x] Implement `register-extension` and `invoke-extension`
- [x] Create `agent-capability` class extending `capability`
- [x] Implement `agent-define-capability` with validation
- [x] Implement `test-agent-capability` with test cases
- [x] Implement `promote-capability` workflow
- [x] Define `experience` and `heuristic` classes
- [x] Implement `extract-patterns` from experiences
- [x] Implement `extract-action-sequences` (n-gram analysis)
- [x] Implement `generate-heuristic` from patterns
- [x] Implement `apply-heuristics` to decisions
- [x] Implement `update-heuristic-confidence` feedback loop

### Phase 8: 3D Holodeck (Completed)
- [x] Add `3d-matrices`, `3d-vectors`, `cl-fast-ecs` dependencies
- [x] Define spatial, visual, data binding, and interaction components
- [x] Implement movement-system, pulse-system, lod-system
- [x] Create `holodeck-window` class extending Trial main
- [x] Implement hologram-node and energy-beam shaders
- [x] Create mesh primitives (sphere, octahedron, branching-node)
- [x] Implement orbit and fly camera systems with smooth transitions
- [x] Create HUD panel system with timeline scrubber
- [x] Implement ray picking and input handling
- [x] Implement `launch-holodeck` entry point and render loop

### Phase 7: 2D Terminal Visualization (Completed)
- [x] Create viz package with terminal utilities and configuration
- [x] Implement timeline and viewport classes
- [x] Implement ASCII timeline rendering with branch connections
- [x] Create detail panel with snapshot summary and thought preview
- [x] Implement timeline navigator with cursor movement and search
- [x] Implement interactive terminal UI with keyboard input handler
- [x] Implement branch visualization and switching
- [x] Write visualization tests

### Phase 6: MCP Integration (Completed)
- [x] Implement MCP server management (stdio transport)
- [x] Implement MCP protocol (initialize, tools/list, tools/call)
- [x] Implement MCP resource handling (resources/list, resources/read)
- [x] Implement built-in tools (file, web, shell)
- [x] Implement integration event system
- [x] Write MCP integration tests (mocked)

### Phase 5: Claude Integration (Completed)
- [x] Implement Claude API HTTP communication (dexador)
- [x] Implement tool mapping (capability → Claude tool)
- [x] Implement session management
- [x] Write Claude integration tests (mocked)

### Phase 4: Human Interface (Completed)
- [x] Implement CLI-based session
- [x] Implement human input blocking mechanism
- [x] Write interface tests

### Phase 3: Snapshot System (Completed)
- [x] Implement snapshot persistence to disk
- [x] Implement branch DAG traversal
- [x] Implement event compaction
- [x] Write snapshot system tests

## Blocked / Needs Human Input

(none)

## Future Enhancements

All planned phases (0-10) are complete. Potential future work:
- Additional MCP server integrations
- Performance tuning for large-scale deployments
- Extended visualization modes
- Additional learning algorithms

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
- events.lisp
- claude-bridge.lisp
- message-format.lisp
- tool-mapping.lisp
- session.lisp
- mcp-client.lisp
- tool-registry.lisp
- builtin-tools.lisp
- config.lisp

### test/
- packages.lisp
- core-tests.lisp
- agent-tests.lisp
- snapshot-tests.lisp
- integration-tests.lisp
- run-tests.lisp
