# Autopoiesis Implementation Plan

Last updated: 2026-02-02
Current Phase: 7 (2D Visualization) - Ready for implementation

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

### Phase 7.1: Package and Foundation Setup
- [x] Create `src/viz/packages.lisp` with package definitions for visualization subsystem
- [x] Add `cl-charms` dependency to `autopoiesis.asd` for ncurses bindings
- [x] Create `src/viz/util.lisp` with terminal utility functions (color codes, cursor movement)
- [x] Create `src/viz/config.lisp` with visualization configuration (colors, symbols, dimensions)

### Phase 7.2: Terminal Timeline Core
- [x] Create `src/viz/timeline.lisp` with `timeline` class (holds snapshot references, viewport state)
- [x] Implement `timeline-viewport` class (visible window into timeline: start, end, width, height)
- [x] Implement basic ASCII timeline rendering function `render-timeline-row`
- [x] Implement render-branch-connections for fork visualization (vertical lines, corners)

### Phase 7.3: Timeline Renderer
- [x] Implement `snapshot-glyph` function (map snapshot type to ASCII symbol: ○ ◆ ● □ etc.)
- [x] Implement `render-snapshot-node` with type-based coloring
- [ ] Implement `render-timeline` main function combining rows, branches, legend

### Phase 7.4: Snapshot Detail Panel
- [ ] Create `detail-panel` class with panel dimensions and content buffer
- [ ] Implement `render-snapshot-summary` (ID, timestamp, type, parent)
- [ ] Implement `render-thought-preview` with truncation and expand/collapse state

### Phase 7.5: Navigation Integration
- [ ] Implement `timeline-navigator` class wrapping snapshot navigator
- [ ] Implement cursor movement functions (left, right, up-branch, down-branch)
- [ ] Implement jump-to-snapshot by ID
- [ ] Implement search function (find snapshot by content/type)

### Phase 7.6: Interactive Terminal UI
- [ ] Implement `terminal-ui` main class with ncurses screen management
- [ ] Implement keyboard input handler (hjkl navigation, Enter select, q quit, / search)
- [ ] Implement `run-terminal-ui` main loop (input → update → render cycle)
- [ ] Implement status bar with current position, branch name, help hints

### Phase 7.7: Branch Visualization
- [ ] Implement `compute-branch-layout` (assign y-positions to branches)
- [ ] Implement `render-branch-labels` (show branch names at fork points)
- [ ] Implement branch switching in UI (Tab or number keys)

### Phase 7.8: Tests
- [ ] Create `test/viz-tests.lisp` with test package
- [ ] Write tests for timeline rendering (string output comparison)
- [ ] Write tests for navigation (cursor movement, jump)
- [ ] Write tests for snapshot glyph mapping

### Phase 7.9: Integration and Polish
- [ ] Integrate terminal UI with existing interface/session system
- [ ] Add resize handling for terminal window changes
- [ ] Implement help overlay (? key shows keybindings)
- [ ] Update `autopoiesis.asd` to include viz subsystem in main load

## Recently Completed

### Phase 6: MCP Integration (Completed)
- [x] Implement MCP server management (stdio transport)
- [x] Implement MCP protocol (initialize, tools/list, tools/call)
- [x] Implement MCP resource handling (resources/list, resources/read)
- [x] Implement built-in tools (file, web, shell)
- [x] Implement integration event system
- [x] Write MCP integration tests (mocked)

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

### Phase 5: Claude Integration
- [x] Implement Claude API HTTP communication (dexador)
- [x] Implement tool mapping (capability → Claude tool)
- [x] Implement session management
- [x] Write Claude integration tests (mocked)

## Blocked / Needs Human Input

(none yet)

## Future (Ready for Planning)

### Phase 8: 3D Holodeck
- Depends on: Phase 7 complete
- ECS setup, 3D rendering (Trial/Raylib), scene management, camera, input, HUD, visual effects

### Phase 9: Self-Extension
- Depends on: Phase 8 complete
- Agent macros, self-modification, learning system, capability generation

### Phase 10: Production
- Depends on: Phase 9 complete
- Performance optimization, security hardening, deployment, documentation

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
