# Autopoiesis

A self-configuring, self-extending agent platform built on Common Lisp's homoiconic foundation.

> *"What if an AI agent had the same relationship to its own cognition that a Lisp developer has to their running system via SWANK?"*

## What Is This?

Autopoiesis is a platform where AI agents think, act, and evolve using S-expressions as the universal representation for everything: their thoughts, their decisions, their state, their configuration, even their own code.

Because Lisp is homoiconic — code and data are the same thing — you get properties for free that are hard to build in other languages:

- **Every agent state is serializable.** It's just an S-expression, so you can hash it, diff it, persist it, send it over the wire.
- **Time-travel is structural.** Snapshot any state, branch from it, diff two states, patch one into another — all with generic S-expression operations.
- **Self-modification is natural.** An agent can inspect its own capabilities, write new ones, compile them in a sandbox, test them, and promote them into its own runtime.
- **Human intervention slots in anywhere.** The cognitive loop is data, so a human can pause it, inspect any thought, reject a decision, inject an observation, or fork reality and try a different path.

## Status

**All phases (0–10) complete.** 2,400+ assertions across 600+ tests, all passing.

## Quick Start

### Prerequisites

- [SBCL](http://www.sbcl.org/) (Steel Bank Common Lisp)
- [Quicklisp](https://www.quicklisp.org/beta/)

### Repository Layout

```
ap/
├── platform/          # Common Lisp agent platform
│   ├── autopoiesis.asd
│   ├── substrate.asd
│   ├── src/
│   ├── test/
│   ├── scripts/
│   ├── docs/
│   └── Dockerfile
├── holodeck/          # Bevy/Rust 3D visualization frontend
│   ├── Cargo.toml
│   └── src/
├── sdk/               # Client SDKs
│   └── go/            # Go SDK
├── thoughts/          # Research & planning docs
└── CLAUDE.md
```

### Install and Test

```bash
git clone <repo-url> autopoiesis
cd autopoiesis
./platform/scripts/test.sh
```

### Hello World

```lisp
;; Load the system
(ql:quickload :autopoiesis)

;; Create an agent
(defvar *agent*
  (autopoiesis.agent:make-agent
    :name "my-agent"
    :capabilities '(read-file analyze-code)))

;; Start an interactive CLI session
(autopoiesis.interface:cli-interact *agent*)
```

```
========================================================================
  AUTOPOIESIS CLI - Agent: my-agent (a3f28c91)
  Status: INITIALIZED | Session: 7bc4d2e8
========================================================================

Commands:
  help, h, ?     - Show this help
  status, s      - Show agent status
  start          - Start the agent
  step           - Single cognitive cycle
  thoughts       - List thought stream
  inject <text>  - Inject observation
  pending        - Show pending human requests
  respond <id>   - Respond to agent request
  viz, v         - Launch visualization
  quit, q        - End session

>
```

## What Can You Do With It?

### Time-Travel Debugging

An agent makes a bad decision 200 steps ago. Check out that snapshot, see exactly what it was thinking, fork a branch, inject a different observation, and watch it take a different path. Then diff the two branches to see how the outcomes diverged.

```lisp
;; Go back in time
(autopoiesis.snapshot:checkout-snapshot "abc123")

;; Fork reality
(autopoiesis.snapshot:create-branch "what-if"
  :from-snapshot "abc123")
(autopoiesis.snapshot:switch-branch "what-if")

;; Inject a different observation and let the agent run
(autopoiesis.interface:human-override *agent*
  '(:redirect :action :archive-to-s3 :target "logs/*"))

;; Compare the two timelines
(autopoiesis.snapshot:snapshot-diff main-head what-if-head)
```

### Human-in-the-Loop with Blocking

An agent is about to do something destructive. It blocks on a condition variable until a human responds. No hallucinating past the gate.

```lisp
;; Agent code — blocks until human answers
(multiple-value-bind (response status)
    (autopoiesis.interface:blocking-human-input
      "About to delete 15 files. Proceed?"
      :options '("yes" "no" "show-list")
      :timeout 300)
  (when (and (eq status :responded) (string-equal response "yes"))
    (delete-files files)))
```

```
;; Human sees in CLI:
[AWAITING INPUT] About to delete 15 files. Proceed?
  Options: yes, no, show-list
  Request ID: 8a2b3c4d

> respond 8a2b no
Response provided to request 8a2b3c4d
```

### Agent Self-Extension

Agents write their own capabilities. Code is sandboxed, tested, and promoted only if tests pass.

```lisp
;; Agent defines a new capability at runtime
;; Extension compiler validates: no eval, no file I/O, no global defs
;; Tests run automatically — promoted only on success
;; Workflow: :draft → :testing → :promoted
```

### Step-Through Cognition

Single-step through an AI's five-phase cognitive cycle — perceive, reason, decide, act, reflect — one step at a time.

```
> start
Agent started.

> pause
Agent paused.

> step
Executed one cognitive cycle.

> thoughts
  [:observation] (:human-input "Review auth module...")
  [:reasoning ] (analyzing "Checking for SQL injection patterns...")
  [:decision  ] (next-action :read-file "auth/login.py")

> step
Executed one cognitive cycle.

> thoughts
  ...
  [:action    ] (:invoke read-file "auth/login.py" :success t)
  [:reflection] (learned "File contains parameterized queries, no injection risk")
```

### Spawn and Coordinate

Agents spawn specialized children with parent-child lineage, inter-agent messaging, and independent thought streams.

```lisp
;; Coordinator spawns a child
(let ((analyzer (autopoiesis.agent:capability-spawn
                  "security-analyzer"
                  :capabilities '(code-read pattern-match))))

  ;; Send work
  (autopoiesis.agent:capability-communicate
    analyzer
    '(:task :analyze-file "auth/login.py" :focus :sql-injection))

  ;; Collect results
  (autopoiesis.agent:capability-receive :clear t))
```

### The Holodeck

The entire snapshot DAG rendered as a 3D scene. Snapshots are holographic nodes — spheres for normal states, octahedra for decisions, branching-nodes with prongs for forks — connected by energy beams with animated flow. Fly through your agent's cognitive history.

```lisp
;; Launch the holodeck
(ql:quickload :autopoiesis/holodeck)
(autopoiesis.holodeck:launch-holodeck :store *my-store*)
```

- **WASD/QE** — Fly camera or orbit
- **Mouse** — Right-drag orbits, middle-drag pans, scroll zooms
- **Click** — Select snapshot, HUD shows details
- **[/]** — Step backward/forward through time
- **Home/End** — Jump to first/last snapshot
- **F** — Fork branch at selection
- **Tab** — Cycle focus between agents
- **1-4** — Switch view modes
- **Space** — Toggle overview

### Claude + MCP Integration

Connect to Claude and MCP servers. Agent capabilities become Claude tools. MCP tools become agent capabilities. Everything is bidirectional.

```lisp
;; Connect to Claude
(let* ((session (autopoiesis.integration:create-claude-session-for-agent *agent*))
       (client  (autopoiesis.integration:make-claude-client)))

  ;; Agent capabilities auto-convert to Claude tool format
  ;; Claude calls tools → capabilities execute → results flow back
  (autopoiesis.integration:claude-complete client
    (autopoiesis.integration:claude-session-messages session)
    :tools (autopoiesis.integration:claude-session-tools session)))

;; Connect an MCP server — its tools become capabilities
(autopoiesis.integration:connect-mcp-server-config
  '(:name "filesystem" :command "npx"
    :args ("-y" "@modelcontextprotocol/server-filesystem" "/tmp")))
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Cross-Cutting         Security (permissions, audit, validation)     │
│                        Monitoring (metrics, health, HTTP endpoints)  │
├──────────────────────────────────────────────────────────────────────┤
│  Integration Layer     Claude API  •  MCP Servers  •  Tool Mapping  │
│                        Built-in Tools  •  Event Bus                  │
├──────────────────────────────────────────────────────────────────────┤
│  Holodeck Layer        3D ECS Visualization  •  Shaders  •  Meshes  │
│                        Dual Camera  •  HUD  •  Ray Picking           │
├──────────────────────────────────────────────────────────────────────┤
│  Visualization Layer   2D ANSI Timeline  •  256-Color Rendering     │
│                        hjkl Navigation  •  Detail Panel              │
├──────────────────────────────────────────────────────────────────────┤
│  Interface Layer       Navigator  •  Viewport  •  Annotator         │
│                        Blocking Input  •  CLI Session                │
├──────────────────────────────────────────────────────────────────────┤
│  Snapshot Layer        Content-Addressable Store  •  Branch Manager  │
│                        Diff Engine  •  Time-Travel  •  Backup        │
├──────────────────────────────────────────────────────────────────────┤
│  Agent Layer           Cognitive Loop  •  Capabilities  •  Learning  │
│                        Context Window  •  Spawner  •  Messaging      │
├──────────────────────────────────────────────────────────────────────┤
│  Core Layer            S-Expression Utilities  •  Cognitive Prims    │
│                        Extension Compiler  •  Recovery  •  Profiling │
└──────────────────────────────────────────────────────────────────────┘
```

### Core Layer (`platform/src/core/`)

The homoiconic foundation. S-expression diff/patch/hash, five cognitive primitives (Thought, Decision, Action, Observation, Reflection), append-only thought streams, a sandboxed extension compiler for agent-written code, condition/restart error recovery with graceful degradation, and nanosecond profiling.

### Agent Layer (`platform/src/agent/`)

Autonomous runtime. Five-phase cognitive loop (perceive → reason → decide → act → reflect). Capability system with `defcapability` macro. Priority-queue context window for working memory (default 100K tokens). Learning system that extracts patterns from experience into heuristics. Parent-child agent spawning with mailbox messaging.

### Snapshot Layer (`platform/src/snapshot/`)

Content-addressable DAG persistence. SHA256 hashing for deduplication. LRU-cached filesystem storage. Lightweight branches as named pointers. Structural diffing via S-expression edit operations. Time-travel with common ancestor finding, path discovery, and DAG traversal. Lazy loading with batch iterators. Consistency checking with repair. Full and incremental backups.

### Interface Layer (`platform/src/interface/`)

Human-in-the-loop infrastructure. Thread-safe blocking requests using Bordeaux threads condition variables. CLI REPL session with 15 commands. Navigator with history stack. Viewport with focus path, filter predicates, and detail levels. Annotator for human commentary. Human override/approve/reject of agent decisions.

### Visualization Layer (`platform/src/viz/`)

ANSI terminal timeline explorer. 256-color rendering with Unicode box drawing and node glyphs. Chronological snapshot layout with branch connections. Detail panel with word-aware line breaking. hjkl navigation, Tab for branch cycling, / for search. Help overlay. Automatic terminal resize.

### Holodeck Layer (`platform/src/holodeck/`)

3D ECS visualization using `cl-fast-ecs`. Three mesh generators (sphere, octahedron, branching-node) at 4 LOD levels. Shader system with Fresnel glow, animated scanlines, energy beam flow — plus CPU-side simulation for headless testing. Orbit and fly cameras with 7 easing functions and smooth transitions. HUD with 4 panels and timeline scrubber. Ray picking via screen-to-world unprojection. 32 key bindings across 5 categories. 60fps main loop with live agent sync.

### Integration Layer (`platform/src/integration/`)

Claude API client via Dexador. MCP client speaking JSON-RPC over stdio. Bidirectional tool mapping: kebab-case Lisp capabilities ↔ snake_case Claude tools, Lisp types ↔ JSON Schema types. Built-in tools for filesystem, web, and shell. Pub/sub event bus with 1000-event history.

### Security (`platform/src/security/`)

Permission system with resource × action matrix. Audit logging with thread-safe 10MB rotation. Input validation framework with 17 types and combinators (`:and`, `:or`, `:not`, `:nullable`). HTML sanitization.

### Monitoring (`platform/src/monitoring/`)

Prometheus-compatible `/metrics` endpoint. Kubernetes-style probes: `/healthz`, `/readyz`, `/health`. Thread-safe counters, gauges, histograms. Hunchentoot HTTP server.

## Implementation Phases

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

## Tests

```
Core tests:         35 assertions    S-expression ops, cognitive primitives, compiler, recovery
Agent tests:        94 assertions    Lifecycle, capabilities, context window, learning, spawning
Snapshot tests:     83 assertions    Persistence, DAG traversal, compaction, branches
Interface tests:    40 assertions    Blocking requests, sessions
Integration tests: 404 assertions    Claude API, MCP, tools, events
E2E tests:         134 assertions    All 15 user stories end-to-end
Viz tests:          92 assertions    Timeline rendering, navigation, filters, help
Holodeck tests:  1,193 assertions    ECS, shaders, meshes, camera, HUD, input, ray picking
Security tests:    321 assertions    Permissions, audit, validation, 65 sandbox escape tests
Monitoring tests:   48 assertions    Metrics, health checks, HTTP endpoints
─────────────────────────────────
Total:           2,444 assertions    All passing
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `bordeaux-threads` | Concurrency (blocking input, thread-safe registries) |
| `cl-json` | JSON serialization (Claude API, MCP protocol) |
| `dexador` | HTTP client (Claude API, web tools) |
| `ironclad` | SHA256 hashing (content-addressable storage) |
| `babel` | UTF-8 encoding |
| `local-time` | Timestamps |
| `alexandria` | Utilities |
| `fiveam` | Testing |
| `uiop` | System utilities (process execution, environment) |
| `hunchentoot` | HTTP server (monitoring endpoints) |
| `cl-ppcre` | Regex (input validation) |
| `cl-charms` | ncurses terminal UI (2D visualization) |
| `log4cl` | Logging |
| `3d-vectors` | Vector math (holodeck) |
| `3d-matrices` | Matrix math (holodeck) |
| `cl-fast-ecs` | Entity-Component-System (holodeck) |

The holodeck is a separate ASDF system (`autopoiesis/holodeck`) to avoid requiring 3D dependencies for core usage.

## Documentation

- **[User Stories](platform/docs/user-stories.md)** — 15 practical examples with code
- **[Specifications](platform/docs/specs/)** — Detailed architecture documents
  - [00 Overview](platform/docs/specs/00-overview.md) — Vision and key differentiators
  - [01 Core Architecture](platform/docs/specs/01-core-architecture.md) — S-expression foundation
  - [02 Cognitive Model](platform/docs/specs/02-cognitive-model.md) — Agent architecture and thought representation
  - [03 Snapshot System](platform/docs/specs/03-snapshot-system.md) — DAG model, branching, diffing
  - [04 Human Interface](platform/docs/specs/04-human-interface.md) — Human-in-the-loop protocol
  - [05 Visualization](platform/docs/specs/05-visualization.md) — ECS architecture, holodeck design
  - [06 Integration](platform/docs/specs/06-integration.md) — Claude bridge, MCP integration
  - [07 Implementation Roadmap](platform/docs/specs/07-implementation-roadmap.md) — Phased plan
  - [08 Addendum](platform/docs/specs/08-specification-addendum.md) — Event sourcing, security, resources
  - [08 Remaining Phases](platform/docs/specs/08-remaining-phases.md) — Phase 7–10 specifications
- **[Deployment](platform/docs/DEPLOYMENT.md)** — Docker deployment
- **[CLAUDE.md](CLAUDE.md)** — Development guidelines and code conventions

## Code Conventions

- Package hierarchy: `autopoiesis.core`, `autopoiesis.agent`, `autopoiesis.snapshot`, etc., with top-level `autopoiesis` reexporting public APIs
- CLOS classes with `:initarg`, `:accessor`, `:initform`, and `:documentation` on slots
- Condition hierarchy with restarts for error handling
- Pure functions preferred — `sexpr-diff`, `sexpr-patch` are non-mutating
- Content-addressable storage using structural hashing
- FiveAM for testing with descriptive test names

## License

MIT
