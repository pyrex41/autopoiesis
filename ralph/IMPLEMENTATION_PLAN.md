# Autopoiesis Implementation Plan

Last updated: 2026-02-03
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

### Phase 8.2: Rendering
- [x] Create `holodeck-window` class extending Trial main
- [x] Implement hologram-node shader (fresnel, scanlines, glow)
- [x] Implement energy-beam shader (animated flow)
- [x] Create mesh primitives (sphere, octahedron, branching-node)
- [x] Implement `render-snapshot-entity` with LOD
- [x] Implement `render-connection-entity` with energy beams

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
- [x] Implement `render-timeline` main function combining rows, branches, legend

### Phase 7.4: Snapshot Detail Panel
- [x] Create `detail-panel` class with panel dimensions and content buffer
- [x] Implement `render-snapshot-summary` (ID, timestamp, type, parent)
- [x] Implement `render-thought-preview` with truncation and expand/collapse state

### Phase 7.5: Navigation Integration
- [x] Implement `timeline-navigator` class wrapping snapshot navigator
- [x] Implement cursor movement functions (left, right, up-branch, down-branch)
- [x] Implement jump-to-snapshot by ID
- [x] Implement search function (find snapshot by content/type)

### Phase 7.6: Interactive Terminal UI
- [x] Implement terminal-ui main class with screen management
- [x] Implement keyboard input handler (hjkl navigation, Enter select, q quit, / search)
- [x] Implement `run-terminal-ui` main loop (input → update → render cycle)
- [x] Implement status bar with current position, branch name, help hints

### Phase 7.7: Branch Visualization
- [x] Implement \`compute-branch-layout\` (assign y-positions to branches)
- [x] Implement `render-branch-labels` (show branch names at fork points)
- [x] Implement branch switching in UI (Tab or number keys)

### Phase 7.8: Tests
- [x] Create `test/viz-tests.lisp` with test package
- [x] Write tests for timeline rendering (string output comparison)
- [x] Write tests for navigation (cursor movement, jump)
- [x] Write tests for snapshot glyph mapping

### Phase 7.9: Integration and Polish
- [x] Integrate terminal UI with existing interface/session system
- [x] Add resize handling for terminal window changes
- [x] Implement help overlay (? key shows keybindings)
- [x] Update `autopoiesis.asd` to include viz subsystem in main load

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

## Future (Fully Specified)

See `docs/specs/08-remaining-phases.md` for complete specifications.

### Phase 8: 3D Holodeck
- Depends on: Phase 7 complete
- **Estimated effort: 6-8 weeks**

#### 8.1: ECS Setup
- [x] Add `3d-matrices`, `3d-vectors`, `cl-fast-ecs` dependencies (as separate `autopoiesis/holodeck` ASDF subsystem)
- [x] Define spatial components (position3d, velocity3d, scale3d, rotation3d)
- [x] Define visual components (visual-style, node-label)
- [x] Define data binding components (snapshot-binding, agent-binding, connection)
- [x] Define interaction components (interactive, detail-level)
- [x] Implement movement-system, pulse-system, lod-system
- [x] Write holodeck ECS tests (73 checks passing)

#### 8.2: Rendering
- [x] Create `holodeck-window` class extending Trial main
- [x] Implement hologram-node shader (fresnel, scanlines, glow)
- [x] Implement energy-beam shader (animated flow)
- [x] Create mesh primitives (sphere, octahedron, branching-node)
- [x] Implement `render-snapshot-entity` with LOD
- [x] Implement `render-connection-entity` with energy beams

#### 8.3: Camera System
- [x] Implement `orbit-camera` class with spherical coordinates
- [x] Implement `fly-camera` class with velocity-based movement
- [x] Implement smooth camera transitions with easing
- [x] Implement `focus-on-snapshot`, `focus-on-agent`, `camera-overview`
- [x] Handle orbit (right-drag) and zoom (scroll) input

#### 8.4: HUD System
- [x] Create HUD panel system with position, agent, timeline, hints panels
- [x] Implement `update-hud` from current state
- [x] Implement `render-hud` with transparency and borders
- [x] Add timeline scrubber at bottom

#### 8.5: Input Handling
- [x] Define holodeck key bindings (WASD fly, []/step, F/fork, etc.)
- [x] Implement ray picking for entity selection
- [x] Implement `screen-to-world-ray` for mouse interaction
- [x] Handle keyboard and mouse events

#### 8.6: Main Loop
- [x] Implement `launch-holodeck` entry point
- [x] Implement render loop (systems → camera → entities → connections → HUD)
- [x] Implement `sync-live-agents` for real-time updates
- [x] Add grid rendering for spatial reference

### Phase 9: Self-Extension
- Depends on: Phase 8 complete (can start 8.3+ in parallel)
- **Estimated effort: 4-5 weeks**

#### 9.1: Extension Compiler
- [x] Define sandbox rules (*allowed-packages*, *forbidden-symbols*, *allowed-special-forms*)
- [x] Implement `validate-extension-code` walker
- [x] Implement `compile-extension` with error handling
- [x] Create extension registry and `extension` class
- [x] Implement `register-extension` and `invoke-extension`

#### 9.2: Agent-Written Capabilities
- [x] Create `agent-capability` class extending `capability`
- [x] Implement `agent-define-capability` with validation
- [x] Implement `test-agent-capability` with test cases
- [x] Implement `promote-capability` workflow

#### 9.3: Learning System
- [x] Define `experience` and `heuristic` classes
- [x] Implement `extract-patterns` from experiences
- [x] Implement `extract-action-sequences` (n-gram analysis)
- [x] Implement `generate-heuristic` from patterns
- [x] Implement `apply-heuristics` to decisions
- [x] Implement `update-heuristic-confidence` feedback loop

### Phase 10: Production
- Depends on: Phase 9 complete
- **Estimated effort: 4-6 weeks**

#### 10.1: Performance Optimization
- [x] Implement LRU cache for hot snapshots
- [x] Implement `parallel-ecs-update` for independent systems
- [x] Implement `compact-thought-stream` for memory reduction
- [x] Profile and optimize critical paths
- [x] Implement lazy loading for large DAGs

#### 10.2: Security Hardening
- [x] Define permission system (resource × action matrix)
- [x] Implement `check-permission` and `with-permission-check`
- [x] Implement audit logging with rotation
- [x] Implement input validation framework
- [x] Security test sandbox escape attempts

#### 10.3: Reliability
- [x] Implement error recovery with restarts
- [x] Add state consistency checks
- [x] Implement backup/restore functionality
- [x] Add graceful degradation on failures

#### 10.4: Deployment
- [x] Create Dockerfile with SBCL and dependencies
- [ ] Implement configuration management (load/merge)
- [ ] Implement health check endpoints
- [ ] Implement metrics collection
- [ ] Create docker-compose for full stack
- [ ] Write deployment documentation

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
