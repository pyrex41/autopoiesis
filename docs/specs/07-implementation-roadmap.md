# Autopoiesis: Implementation Roadmap

## Specification Document 07: Implementation Plan

**Version:** 0.1.0-draft
**Status:** Specification
**Last Updated:** 2026-02-02

---

## Overview

This document outlines a phased approach to implementing Autopoiesis, from foundational primitives to the full 3D visualization. Each phase builds on the previous, with clear milestones and deliverables.

---

## Phase Summary

| Phase | Name | Focus | Deliverable |
|-------|------|-------|-------------|
| 0 | Foundation | Project setup, dependencies | Building environment |
| 1 | Core Primitives | S-expressions, cognitive primitives | Basic thought representation |
| 2 | Agent Runtime | Agent class, capabilities, execution | Runnable agents |
| 3 | Snapshot System | Persistence, branching, navigation | Time-travel debugging |
| 4 | Human Interface | Entry points, viewport, actions | CLI human-in-the-loop |
| 5 | Claude Integration | Claude bridge, tool mapping | AI-powered agents |
| 6 | MCP Integration | Server connections, tool registry | Extensible tools |
| 7 | 2D Visualization | Terminal/web timeline view | Visual navigation |
| 8 | 3D Holodeck | ECS, rendering, spatial navigation | Full Jarvis interface |
| 9 | Self-Extension | Agent-written code, macro system | Self-modifying agents |
| 10 | Production | Performance, security, deployment | Production-ready system |

---

## Phase 0: Foundation

### Goals
- Set up project structure
- Configure Common Lisp environment
- Establish dependencies
- Create build system

### Tasks

```
□ Create project structure
  ├── autopoiesis.asd (ASDF system definition)
  ├── src/
  │   ├── core/
  │   ├── agent/
  │   ├── snapshot/
  │   ├── interface/
  │   ├── viz/
  │   └── integration/
  ├── test/
  ├── docs/
  └── examples/

□ Set up ASDF system definition
  - Core system
  - Test system
  - Visualization system (optional dependency)

□ Configure dependencies
  - cl-fast-ecs (visualization)
  - bordeaux-threads (concurrency)
  - cl-json (serialization)
  - dexador (HTTP client)
  - local-time (timestamps)
  - alexandria (utilities)
  - cl-ppcre (regex)
  - log4cl (logging)
  - fiveam (testing)

□ Set up development environment
  - SBCL recommended
  - Quicklisp for dependency management
  - SLIME/SLY for IDE integration
```

### Deliverable
```lisp
;; Working REPL with:
(ql:quickload :autopoiesis)
(autopoiesis:initialize)
;; => Autopoiesis initialized.
```

---

## Phase 1: Core Primitives

### Goals
- Implement S-expression utilities
- Create cognitive primitive types
- Build thought stream

### Tasks

```
□ S-expression utilities (src/core/s-expr.lisp)
  - sexpr-equal: Deep structural equality
  - sexpr-hash: Content-addressable hashing
  - sexpr-serialize / sexpr-deserialize
  - sexpr-diff / sexpr-patch

□ Cognitive primitives (src/core/cognitive-primitives.lisp)
  - thought class
  - decision class (with alternatives)
  - action class
  - observation class
  - reflection class

□ Thought stream (src/core/thought-stream.lisp)
  - Ordered thought storage
  - Lookup by ID
  - Filtering by type/time
  - Serialization

□ Condition hierarchy (src/core/conditions.lisp)
  - autopoiesis-error base
  - Agent-specific conditions
  - Snapshot conditions
  - Restarts

□ Tests
  - S-expression operations
  - Thought creation and serialization
  - Stream operations
```

### Deliverable
```lisp
(let ((thought (make-thought '(analyze file "auth.py")
                             :type :reasoning
                             :confidence 0.85)))
  (thought-to-sexpr thought))
;; => (thought :id "abc123" :type :reasoning :content (analyze file "auth.py") ...)
```

---

## Phase 2: Agent Runtime

### Goals
- Implement base agent class
- Create capability system
- Build cognitive loop

### Tasks

```
□ Agent class (src/agent/agent.lisp)
  - Core slots: id, name, capabilities, state
  - Thought stream integration
  - Context window
  - Agent protocol methods

□ Capability system (src/agent/capability.lisp)
  - defcapability macro
  - Capability registry
  - Parameter handling
  - Cost/latency metadata
  - Composition rules

□ Agent spawner (src/agent/spawner.lisp)
  - Agent specifications
  - spawn-agent function
  - Agent registry
  - fork-agent / merge-agents

□ Cognitive loop (src/agent/cognition.lisp)
  - Context window management
  - Cognitive phases: perceive, reason, decide, act, reflect
  - Hooks system
  - Phase customization via MOP

□ Built-in capabilities
  - introspect
  - spawn
  - communicate
  - request-human-input

□ Tests
  - Agent creation
  - Capability invocation
  - Cognitive loop execution
```

### Deliverable
```lisp
(let ((agent (spawn-agent '(:name "researcher"
                            :capabilities (read-file web-fetch)))))
  (run-agent agent '(task "Find security issues in auth.py"))
  (agent-thought-stream agent))
;; => Stream of thoughts showing agent's reasoning
```

---

## Phase 3: Snapshot System

### Goals
- Implement snapshot persistence
- Create branching system
- Build time-travel navigation

### Tasks

```
□ Snapshot structure (src/snapshot/snapshot.lisp)
  - Snapshot class with all fields
  - Content-addressable IDs
  - Parent/children links
  - Serialization

□ Snapshot store (src/snapshot/store.lisp)
  - SQLite backend
  - LRU cache
  - Index for fast queries
  - CRUD operations

□ Branch system (src/snapshot/branch.lisp)
  - Branch class
  - create-branch / switch-branch
  - fork-from-snapshot
  - merge-branches
  - Conflict detection and resolution

□ Navigation (src/snapshot/navigation.lisp)
  - Navigator class
  - jump-to / step-forward / step-backward
  - Semantic navigation (goto decision, etc.)
  - Bookmarks

□ Diffing (src/snapshot/diff.lisp)
  - Snapshot comparison
  - Change tracking
  - Visual diff output

□ Agent integration
  - create-snapshot in cognitive loop
  - restore-agent-to-snapshot
  - Snapshot frequency configuration

□ Tests
  - Snapshot creation and retrieval
  - Branching and merging
  - Navigation
  - Diff accuracy
```

### Deliverable
```lisp
;; After agent runs
(let ((decision-point (find-decision-points (agent-id agent))))
  (fork-from-snapshot (first decision-point)
                      :explore-alternative 1)
  (run-agent agent))
;; => Agent explores alternative path
```

---

## Phase 4: Human Interface

### Goals
- Create entry point system
- Build viewport for human viewing
- Implement action handling

### Tasks

```
□ Entry points (src/interface/entry-points.lisp)
  - Entry point types
  - Interrupt handling
  - Breakpoint system
  - Agent-initiated requests

□ Viewport (src/interface/viewport.lisp)
  - Viewport class
  - Context rendering
  - Thought rendering
  - State rendering
  - Terminal display

□ Human actions (src/interface/actions.lisp)
  - Action types enum
  - Action parsing
  - Action execution
  - Result handling

□ Human loop (src/interface/loop.lisp)
  - enter-human-loop
  - Action dispatch
  - Viewport updates
  - Session management

□ Watch system (src/interface/watch.lisp)
  - Watch definitions
  - Condition evaluation
  - Trigger handling

□ Notifications (src/interface/notifications.lisp)
  - Notification queue
  - Handlers
  - Display

□ Tests
  - Entry point triggering
  - Action parsing
  - Human loop flow
```

### Deliverable
```lisp
;; Human can now:
(set-breakpoint '(> (agent-cost agent) 0.1))
;; ... agent runs until breakpoint ...
;; Human sees viewport, can:
;;   - Navigate history
;;   - Fork and explore
;;   - Inject context
;;   - Continue or abort
```

---

## Phase 5: Claude Integration

### Goals
- Connect to Claude API
- Map capabilities to tools
- Enable Claude-powered reasoning

### Tasks

```
□ Claude bridge (src/integration/claude-bridge.lisp)
  - API configuration
  - Session management
  - Message conversion
  - Error handling

□ Tool mapping (src/integration/claude-tools.lisp)
  - Capability → Claude tool conversion
  - JSON schema generation
  - Result handling

□ Claude-powered cognition (src/integration/claude-cognition.lisp)
  - claude-think function
  - Response → thought conversion
  - Tool call execution
  - Multi-turn handling

□ Session sync
  - Context → messages
  - Messages → context
  - Import/export sessions

□ Tests
  - API communication (mocked)
  - Tool conversion
  - Multi-turn conversations
```

### Deliverable
```lisp
;; Agent uses Claude for reasoning
(let ((agent (spawn-agent '(:name "claude-agent"
                            :cognition-engine :claude))))
  (run-agent agent '(task "Review this code for security issues"))
  ;; Agent uses Claude to reason, tools to act
  )
```

---

## Phase 6: MCP Integration

### Goals
- Connect to MCP servers
- Register external tools
- Handle resources

### Tasks

```
□ MCP server management (src/integration/mcp.lisp)
  - Server connection
  - Process management
  - Protocol implementation

□ Tool discovery
  - tools/list
  - Capability registration
  - Invocation

□ Resource handling
  - resources/list
  - resources/read
  - Caching

□ Built-in tools (src/integration/tools.lisp)
  - File system tools
  - Web tools
  - Shell tools

□ Event system (src/integration/events.lisp)
  - Event types
  - Event bus
  - Handlers

□ Tests
  - Server connection (mocked)
  - Tool invocation
  - Error handling
```

### Deliverable
```lisp
;; Connect to filesystem MCP server
(connect-mcp-server '(:name "filesystem"
                      :command "npx"
                      :args ("-y" "@anthropic/mcp-server-filesystem")))
;; Tools automatically available to agents
```

---

## Phase 7: 2D Visualization

### Goals
- Create terminal-based timeline view
- Build web-based viewer (optional)
- Enable visual navigation

### Tasks

```
□ Terminal timeline (src/viz/terminal.lisp)
  - ASCII timeline rendering
  - Branch visualization
  - Interactive navigation
  - ncurses or similar

□ Web viewer (optional)
  - Simple HTML/JS frontend
  - WebSocket connection
  - Timeline component
  - Snapshot detail panel

□ Snapshot rendering
  - Type-based styling
  - Truncation
  - Expand/collapse

□ Navigation integration
  - Keyboard shortcuts
  - Click-to-jump
  - Search

□ Tests
  - Rendering output
  - Navigation
```

### Deliverable
```
┌─────────────────────────────────────────────────────────────┐
│ AUTOPOIESIS TIMELINE                               Branch: main  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ○──○──○──◆──○──○                                          │
│              │                                              │
│              └──○──○──○                    (exploring-alt)  │
│                                                             │
│  ◆ = current   ○ = snapshot   ─ = temporal   │ = fork     │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 8: 3D Holodeck

### Goals
- Implement ECS architecture
- Build 3D rendering
- Create Jarvis-style interface

### Tasks

```
□ ECS setup (src/viz/ecs/)
  - Component definitions
  - System definitions
  - Entity management

□ Rendering (src/viz/render.lisp)
  - Window initialization (Trial/Raylib)
  - Shader loading
  - Mesh rendering
  - Glow effects

□ Scene management (src/viz/scene.lisp)
  - Snapshot → entity sync
  - Connection rendering
  - Layout calculation

□ Camera system (src/viz/camera.lisp)
  - Orbit/fly modes
  - Smooth transitions
  - Follow mode

□ Input handling (src/viz/input.lisp)
  - Keyboard/mouse
  - Entity picking
  - Gesture recognition

□ HUD (src/viz/hud.lisp)
  - Position panel
  - Agent status
  - Timeline scrubber
  - Action hints

□ Visual effects
  - Holographic shaders
  - Energy beams
  - Particle trails
  - Post-processing

□ Tests
  - Entity creation
  - System execution
  - Rendering (visual inspection)
```

### Deliverable
```
[3D view of cognitive space with floating nodes, glowing connections,
 camera flying through, HUD showing status, Jarvis aesthetic]
```

---

## Phase 9: Self-Extension

### Goals
- Enable agents to write code
- Implement safe compilation
- Create learning system

### Tasks

```
□ Extension compiler (src/core/extension-compiler.lisp)
  - Validation/sandboxing
  - Safe compilation
  - Extension registry

□ Agent macros (src/agent/macros.lisp)
  - defagent-macro
  - Macro expansion
  - Shared macro propagation

□ Self-modification (src/agent/self-modification.lisp)
  - Modification types
  - Validation
  - Rollback support

□ Learning system
  - Pattern extraction
  - Heuristic generation
  - Experience accumulation

□ Capability generation
  - Agent-written capabilities
  - Testing integration
  - Promotion to permanent

□ Tests
  - Extension validation
  - Safe execution
  - Self-modification
```

### Deliverable
```lisp
;; Agent learns from experience
(let ((agent (spawn-agent '(:class learner-agent))))
  (run-agent agent task-1)
  (run-agent agent task-2)
  ;; Agent has now created its own heuristics
  (agent-extensions agent))
;; => List of self-created extensions
```

---

## Phase 10: Production

### Goals
- Performance optimization
- Security hardening
- Deployment preparation

### Tasks

```
□ Performance
  - Profile critical paths
  - Optimize snapshot store
  - Reduce memory usage
  - Parallel system execution

□ Security
  - Input validation
  - Sandbox hardening
  - Capability permissions
  - Audit logging

□ Reliability
  - Error recovery
  - State consistency
  - Backup/restore

□ Deployment
  - Docker container
  - Configuration management
  - Monitoring integration
  - Documentation

□ Testing
  - Load testing
  - Security testing
  - Integration testing
  - User acceptance
```

### Deliverable
```bash
# Deployable Autopoiesis instance
docker run -d \
  -e ANTHROPIC_API_KEY=... \
  -v /data:/autopoiesis/data \
  -p 8080:8080 \
  autopoiesis:latest
```

---

## Milestone Checkpoints

### M1: Core Complete (Phases 0-2)
- [ ] Project compiles and loads
- [ ] Agents can be spawned and run
- [ ] Capabilities work
- [ ] Basic thoughts are recorded

### M2: Time Travel (Phase 3)
- [ ] Snapshots are persisted
- [ ] Branching works
- [ ] Can navigate history
- [ ] Can fork and explore

### M3: Human in Loop (Phase 4)
- [ ] Can interrupt agents
- [ ] Viewport shows state
- [ ] Can take actions
- [ ] Sessions are recorded

### M4: AI Connected (Phases 5-6)
- [ ] Claude powers reasoning
- [ ] MCP tools work
- [ ] Built-in tools function
- [ ] Events are tracked

### M5: Visual (Phases 7-8)
- [ ] 2D timeline works
- [ ] 3D visualization renders
- [ ] Navigation is fluid
- [ ] Jarvis aesthetic achieved

### M6: Self-Extending (Phase 9)
- [ ] Agents write extensions
- [ ] Learning improves performance
- [ ] Modifications are safe
- [ ] System is metacircular

### M7: Production Ready (Phase 10)
- [ ] Performance acceptable
- [ ] Security audited
- [ ] Documentation complete
- [ ] Deployment automated

---

## Technology Stack Summary

| Component | Technology | Why |
|-----------|------------|-----|
| Language | Common Lisp (SBCL) | Homoiconicity, performance, REPL |
| ECS | cl-fast-ecs | Fast, Lisp-native |
| 3D Engine | Trial or Raylib | Modern OpenGL, CL bindings |
| Storage | SQLite | Simple, reliable, embedded |
| HTTP | Dexador | Fast, modern |
| JSON | cl-json | Standard |
| Testing | FiveAM | Flexible |
| Logging | log4cl | Configurable |

---

## Getting Started

```bash
# Clone repository
git clone <repo-url>
cd autopoiesis

# Start SBCL with Quicklisp
sbcl --load quicklisp/setup.lisp

# Load Autopoiesis
(ql:quickload :autopoiesis)

# Initialize
(autopoiesis:initialize)

# Run tests
(asdf:test-system :autopoiesis)

# Start an agent
(autopoiesis:spawn-agent '(:name "test-agent"))
```

---

## Contributing

See CONTRIBUTING.md for:
- Code style guidelines
- PR process
- Issue templates
- Development workflow

---

## Next Steps

1. Complete Phase 0 setup
2. Begin Phase 1 implementation
3. Set up CI/CD
4. Create initial test suite
5. Write developer documentation
