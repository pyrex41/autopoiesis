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

**All phases (0-10) complete.** 2,775+ assertions across 14 test suites, all passing.

---

**Start here** -> [`platform/docs/QUICKSTART.md`](platform/docs/QUICKSTART.md) — Full setup guide, first agent swarm, TUI cockpit, self-extension walkthrough, scaling guidance, and multi-language navigation.

---

## Quick Start

### Prerequisites

- [SBCL](http://www.sbcl.org/) (Steel Bank Common Lisp)
- [Quicklisp](https://www.quicklisp.org/beta/)

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

---

## Under the Hood

### The Substrate: A Datom Store with Linda Coordination

At the bottom of the stack is a datom store whose data model comes directly from [Datomic](https://www.datomic.com/), which is itself built on Datalog. The five-tuple datom `(entity, attribute, value, tx, added)`, the EAVT/AEVT index naming, immutable facts with monotonic transaction stamping, and EAV triples as the universal schema are all Datomic's design carried over. What's *not* here is Datomic's Datalog query engine — instead of declarative `[:find ?e :where [?e :status :running]]` queries, the substrate uses direct index access: `entity-attr` for O(1) point lookups, `find-entities` via an inverted value index, and `take!` for atomic claim-and-update. The trade-off is less expressive queries in exchange for predictable constant-time operations and the Linda coordination primitive.

All mutable state — events, workers, agents, sessions, conversation turns — is stored as EAV triples:

```lisp
;; A datom: (entity, attribute, value, tx, added?)
;; Symbolic names auto-intern to compact integers
(transact!
 (list (make-datom "my-agent" :agent/status :running)
       (make-datom "my-agent" :agent/started-at (get-universal-time))))
```

Three indexes are maintained in lockstep on every write: `:eavt` and `:aevt` for history scans, `:ea-current` for O(1) current-value lookup. An inverted value index maps `(attribute . value)` pairs to entity sets, enabling O(1) queries by value.

The signature feature is **`take!`** — a Linda-style atomic coordination primitive:

```lisp
;; Atomically find a pending event and claim it
;; Only one caller can ever win — the entire find-and-update
;; runs under a single lock
(take! :event/status :pending :new-value :processing)
```

`take!` uses the inverted value index for O(1) lookup, then performs the retract-and-assert within the lock it already holds. No locks are released between finding the entity and updating it — the atomicity is structural, not transactional. This is how the conductor's event queue, worker claiming, and task assignment all achieve safe concurrent access without external coordination infrastructure.

**Reactive dispatch** via `defsystem` lets you declare systems that fire when specific attributes change. A single store hook dispatches to affected systems using a pre-indexed lookup table, topologically sorted by declared ordering constraints:

```lisp
(defsystem :derived-status
  (:entity-type :agent
   :watches (:agent/error-count :agent/uptime)
   :after (:cache-invalidation))
  (format t "Agent state changed: ~A~%" entity))
```

### The Snapshot DAG: Content-Addressable Time-Travel

Agent state snapshots form a directed acyclic graph where each node holds a complete serialized agent as an S-expression, linked by parent pointers. SHA-256 hashes of the S-expression content serve as both deduplication keys and integrity tokens.

```lisp
;; Every S-expression gets a deterministic hash via type-tagged digesting:
;; symbols get "S" prefix, integers "I", cons cells "(" + car + "." + cdr + ")"
(sexpr-hash '(:agent :name "scout" :state :running))
;; => "a3f28c91..."  (same structure always produces the same hash)
```

The hash function is structural: two `sexpr-equal` trees always produce identical hashes regardless of object identity. This is the foundation for content-addressable storage — `store-put` only writes when the hash is absent, and `store-delete` is reference-counted.

**Branches are named mutable pointers** into the DAG. Creating a branch is just `(setf (branch-head branch) snapshot-id)` — the DAG itself is immutable. Forking is O(1): both branches share the same history, diverging only from new snapshots onward.

**Structural diffing** operates on the S-expression tree directly:

```lisp
;; Diff two agent states — returns a list of edit operations
;; with paths like (:car :cdr :cdr :car) navigating the cons tree
(sexpr-diff old-state new-state)
;; => (#S(SEXPR-EDIT :TYPE :REPLACE :PATH (:CDR :CDR :CAR)
;;                   :OLD :paused :NEW :running))

;; Apply edits non-destructively (copy-tree + structural reconstruction)
(sexpr-patch old-state edits)
```

**DAG traversal** includes common ancestor finding (hash-set of A's ancestors, walk B upward until hit), path discovery, branch-point detection, and both depth-first and breadth-first walks. For large DAGs, `lazy-snapshot` proxies load metadata from the index but defer disk I/O for agent-state until accessed — the `slot-unbound` MOP method triggers the load transparently.

```lisp
;; Time-travel: go back, fork, inject a different observation, compare
(checkout-snapshot "abc123")
(create-branch "what-if" :from-snapshot "abc123")
(snapshot-diff main-head what-if-head)
```

### The Cognitive Loop: Five Phases as Data

Every agent runs a five-phase cognitive cycle where each phase produces S-expression primitives that flow into the next:

```
perceive(environment) → observations
  reason(observations) → understanding
    decide(understanding) → decision
      act(decision) → result
        reflect(result) → insight
```

Each cognitive primitive is a CLOS object whose `content` slot holds an S-expression:

| Primitive | Content Form |
|-----------|-------------|
| Observation | `(or interpreted raw)` — the agent's interpretation of input |
| Decision | `(:decided chosen :from (alt1 alt2 ...))` — with confidence from scores |
| Action | `(:invoke capability arg1 arg2 ...)` — the capability invocation |
| Reflection | `(:reflect-on target :insight insight)` — with optional self-modification |

Everything is appended to a `thought-stream` — an adjustable vector with a parallel hash-table index for O(1) lookup by thought ID. At any point, `agent-to-sexpr` serializes the complete agent (including full thought history) to a plist that can be hashed, diffed, snapshotted, or sent over the wire.

### Self-Extension: The Draft-Testing-Promoted Pipeline

Agents write their own capabilities as S-expressions. The extension compiler validates, compiles, and promotes agent-written code without leaving the Lisp runtime:

1. **Draft**: The agent provides `name`, `params`, and `body` as S-expressions. A code walker validates the source against a sandbox — checking operators against `*forbidden-symbols*` (no `eval`, `load`, `open`, `run-program`, `setf`, `defclass`, etc.) and verifying all packages are in `*allowed-packages*`. If valid, `(compile nil (lambda ...))` produces a live function.

2. **Testing**: The agent provides `(input expected-output)` test cases. Each is run against the compiled function; results are recorded as structured plists.

3. **Promoted**: Only from `:testing` status, and only if every test result has `(:status :pass)`. The capability joins the global `*capability-registry*` alongside built-in capabilities — indistinguishable at the call site.

The code walker handles `lambda`, `let`/`let*`, `flet`/`labels` (tracking locally defined functions), `quote` (stops recursion — quoted forms are data), `#'` (function references), and `loop` (skips keyword clauses). After 3 runtime errors, an extension is auto-rejected.

### The Conductor: Substrate-Backed Orchestration

A single background thread running a 100ms heartbeat loop. On each tick it fires due timers and drains pending events. The key design: **the conductor holds no queues or worker lists in memory**. Everything is datoms:

```lisp
;; Queue an event — writes 4 datoms to the substrate
(queue-event :deploy '(:service "api" :version "2.1"))

;; On the next tick, the conductor claims it atomically:
(take! :event/status :pending :new-value :processing)
;;                    ↑ O(1) via inverted value index
```

Workers are also substrate entities: `register-worker` writes `:worker/status :running`, and any thread can query `(find-entities :worker/status :running)` to see what's active. Timer actions are stored in a sorted list maintained with CL's `merge` — `schedule-action` inserts in one pass.

Claude CLI workers are spawned as independent threads with subprocess management: `sb-ext:run-program` with merged stderr, streaming JSON line parsing, SIGTERM/SIGKILL timeout handling, and exponential backoff (2^N seconds, capped at 5 minutes) on failure.

### Multi-Provider Agentic Loops

The integration layer supports both **direct API providers** (Anthropic, OpenAI, Ollama) and **CLI subprocess providers** (Claude Code, Codex, OpenCode) through a shared provider protocol:

```lisp
;; Direct API — uses the in-process agentic loop
(make-anthropic-provider :model "claude-sonnet-4-20250514")
(make-openai-provider :model "gpt-4")
(make-ollama-provider :port 11434 :model "llama3")

;; CLI subprocess — wraps external tools
(make-claude-code-provider :max-turns 25)
(make-codex-provider :model "codex-mini")
```

The `define-cli-provider` macro generates an entire provider from a declarative spec — CLOS class, constructor, command builder, output parser (JSON object or JSONL event stream), and serializer — in a single form.

**Bidirectional tool mapping** converts between Lisp's kebab-case capabilities and the snake_case tools that LLMs expect:

```lisp
(lisp-name-to-tool-name :read-file)  ;=> "read_file"
(tool-name-to-lisp-name "read_file") ;=> :READ-FILE
```

Capability parameter specs (`((path string :required t))`) convert to JSON Schema. MCP tool definitions convert to capabilities. The result: built-in tools, agent-written capabilities, and external MCP tools are all first-class capabilities that can surface to any LLM provider through the same mapping.

### Conversations as a Turn DAG

Conversation turns are stored as substrate datoms linked by `:turn/parent` pointers, forming a DAG. Turn content is stored as content-addressed blobs (only the hash lives in the datom). Contexts are mutable pointers to branch heads.

**Forking is O(1)**: `fork-context` creates a new context entity pointing to the same head turn — both contexts share history, diverging only from subsequent `append-turn` calls. All datoms for a new turn (role, content hash, parent, timestamp, context head update) are written in a single `transact!` call to prevent orphaned turns on crash.

### Evolutionary Swarm

The swarm module implements genome-based evolutionary optimization of agent configurations:

- **Genomes** encode capabilities, heuristic weights, and tunable parameters as S-expressions
- **Uniform crossover** blends two parent genomes — capabilities at 50% inclusion, numeric parameters averaged, non-numeric randomly selected
- **Mutation** stochastically adds/removes capabilities and perturbs weights (rate-controlled, default 10%)
- **Selection**: tournament (sample K, take best), roulette (fitness-proportionate), elitism (top N unchanged)
- **Production rules** convert learned heuristics into conditional genome transformations, bridging the learning system with evolution

The learning system extracts patterns from agent experience using n-gram analysis on action sequences and frequency-based context key extraction, generating heuristics with confidence scores that decay on failed applications.

---

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
  ;; Claude calls tools -> capabilities execute -> results flow back
  (autopoiesis.integration:claude-complete client
    (autopoiesis.integration:claude-session-messages session)
    :tools (autopoiesis.integration:claude-session-tools session)))

;; Connect an MCP server — its tools become capabilities
(autopoiesis.integration:connect-mcp-server-config
  '(:name "filesystem" :command "npx"
    :args ("-y" "@modelcontextprotocol/server-filesystem" "/tmp")))
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Cross-Cutting         Security (permissions, audit, validation)     │
│                        Monitoring (metrics, health, HTTP endpoints)  │
├──────────────────────────────────────────────────────────────────────┤
│  Orchestration Layer   Conductor Tick Loop  •  Timer Heap            │
│                        Substrate-Backed Event Queue  •  Workers      │
├──────────────────────────────────────────────────────────────────────┤
│  Integration Layer     Claude API  •  MCP Servers  •  Tool Mapping  │
│                        Multi-Provider Agentic Loops  •  Event Bus   │
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
│  Conversation Layer    Turn DAG  •  Content-Addressed Blobs         │
│                        Fork/Merge  •  Dual-Track History             │
├──────────────────────────────────────────────────────────────────────┤
│  Snapshot Layer        Content-Addressable DAG  •  Branch Manager   │
│                        Structural Diff/Patch  •  Lazy Loading        │
├──────────────────────────────────────────────────────────────────────┤
│  Swarm Layer           Genome Evolution  •  Crossover/Mutation       │
│                        Tournament/Roulette Selection  •  Fitness     │
├──────────────────────────────────────────────────────────────────────┤
│  Agent Layer           Cognitive Loop  •  Capabilities  •  Learning  │
│                        Context Window  •  Spawner  •  Messaging      │
├──────────────────────────────────────────────────────────────────────┤
│  Core Layer            S-Expression Utilities  •  Cognitive Prims    │
│                        Extension Compiler  •  Recovery  •  Profiling │
├──────────────────────────────────────────────────────────────────────┤
│  Substrate Layer       Datom Store (EAV)  •  Linda take!             │
│                        Value Index  •  Interning  •  defsystem       │
└──────────────────────────────────────────────────────────────────────┘
```

### Substrate Layer (`platform/src/substrate/`)

Datom store with EAV triples, three synchronized indexes (EAVT, AEVT, EA-CURRENT), and an inverted value index for O(1) queries. Linda coordination via `take!` for atomic state transitions. Monotonic-counter interning maps symbolic names to compact integers (no hash collisions). Reactive `defsystem` dispatch with topological ordering. Batch transactions via `with-batch-transaction`. LMDB persistence optional.

### Core Layer (`platform/src/core/`)

The homoiconic foundation. S-expression diff/patch/hash with type-tagged SHA-256 digesting. Five cognitive primitives (Thought, Decision, Action, Observation, Reflection) as CLOS classes with S-expression content. Append-only thought streams with O(1) ID lookup. Sandboxed extension compiler with code walking, forbidden-symbol checking, and package restrictions. Condition/restart error recovery. Nanosecond profiling.

### Agent Layer (`platform/src/agent/`)

Five-phase cognitive loop (perceive -> reason -> decide -> act -> reflect) as CLOS generic functions. `defcapability` macro for declaring capabilities with parameter specs and permissions. Priority-queue context window for working memory (default 100K tokens). Learning system: n-gram action sequence analysis, frequency-based context patterns, heuristic generation with confidence decay. Parent-child agent spawning with mailbox messaging.

### Swarm Layer (`platform/src/swarm/`)

Evolutionary optimization of agent configurations. Genomes encode capabilities, heuristic weights, and parameters. Uniform crossover, stochastic mutation, tournament/roulette/elitism selection. Production rules bridge learned heuristics to genome transformations. Optional parallel fitness evaluation.

### Snapshot Layer (`platform/src/snapshot/`)

Content-addressable DAG persistence. SHA-256 structural hashing for deduplication. LRU-cached filesystem storage with two-character prefix sharding. Lightweight branches as named pointers. Structural diffing via S-expression edit operations with `:car`/`:cdr` path navigation. Time-travel with common ancestor finding, path discovery, and DAG traversal. Lazy-loading proxies via `slot-unbound` MOP method. Six-check consistency verification with repair.

### Conversation Layer (`platform/src/conversation/`)

Turns stored as substrate datoms linked by `:turn/parent` pointers. Content stored as content-addressed blobs. O(1) context forking via shared head pointers. Single-transaction turn writes for crash safety. Dual-track: in-memory message list for API calls, substrate entities for durable history.

### Interface Layer (`platform/src/interface/`)

Thread-safe blocking requests using Bordeaux threads condition variables. CLI REPL session with 15 commands. Navigator with history stack. Viewport with focus path, filter predicates, and detail levels. Annotator for human commentary. Human override/approve/reject of agent decisions.

### Visualization Layer (`platform/src/viz/`)

ANSI terminal timeline explorer. 256-color rendering with Unicode box drawing and node glyphs. hjkl navigation, Tab for branch cycling, / for search. Help overlay. Automatic terminal resize.

### Holodeck Layer (`platform/src/holodeck/`)

3D ECS visualization using `cl-fast-ecs`. Three mesh generators (sphere, octahedron, branching-node) at 4 LOD levels. Shader system with Fresnel glow, animated scanlines, energy beam flow. Orbit and fly cameras with 7 easing functions. HUD with 4 panels and timeline scrubber. Ray picking. 32 key bindings. 60fps main loop with live agent sync.

### Integration Layer (`platform/src/integration/`)

Multi-provider agentic loops: direct API (Anthropic, OpenAI, Ollama) and CLI subprocess (Claude Code, Codex, OpenCode). `define-cli-provider` macro generates providers from declarative specs. Bidirectional tool mapping: kebab-case capabilities <-> snake_case tools, Lisp types <-> JSON Schema. MCP client speaking JSON-RPC 2.0 over stdio. Built-in tools for filesystem, web, shell, and git. Pub/sub event bus with 1000-event history.

### Orchestration Layer (`platform/src/orchestration/`)

Conductor tick loop (100ms heartbeat) with substrate-backed event queue. Linda `take!` for atomic event claiming. Timer heap for scheduled actions. Worker management as substrate entities. Claude CLI subprocess spawning with streaming JSON, timeout handling, and exponential backoff. HTTP webhook endpoint.

### Security (`platform/src/security/`)

Permission system with resource x action matrix. Audit logging with thread-safe 10MB rotation. Input validation framework with 17 types and combinators (`:and`, `:or`, `:not`, `:nullable`). HTML sanitization.

### Monitoring (`platform/src/monitoring/`)

Prometheus-compatible `/metrics` endpoint. Kubernetes-style probes: `/healthz`, `/readyz`, `/health`. Thread-safe counters, gauges, histograms. Hunchentoot HTTP server.

---

## Repository Layout

```
ap/
├── platform/          # Common Lisp agent platform
│   ├── autopoiesis.asd
│   ├── substrate.asd
│   ├── src/
│   │   ├── substrate/     # Datom store, Linda, interning, defsystem
│   │   ├── core/          # S-expr utils, cognitive primitives, compiler
│   │   ├── agent/         # Cognitive loop, capabilities, learning
│   │   ├── swarm/         # Evolutionary optimization
│   │   ├── snapshot/      # Content-addressable DAG, branches, diff
│   │   ├── conversation/  # Turn DAG, context forking
│   │   ├── interface/     # CLI, blocking input, viewport
│   │   ├── viz/           # 2D terminal timeline
│   │   ├── holodeck/      # 3D ECS visualization
│   │   ├── integration/   # LLM providers, MCP, tools, agentic loops
│   │   ├── orchestration/ # Conductor, event queue, workers
│   │   ├── security/      # Permissions, audit, validation
│   │   └── monitoring/    # Metrics, health checks
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

## Tests

```
Substrate tests:      112 assertions    Datom store, interning, transact!, hooks, take!, entity types
Orchestration tests:   91 assertions    Conductor, timer heap, event queue, workers, Claude CLI
Conversation tests:    45 assertions    Turn creation, context management, forking, history
Core tests:           470 assertions    S-expression ops, cognitive primitives, compiler, recovery
Agent tests:          363 assertions    Lifecycle, capabilities, context window, learning, spawning
Snapshot tests:       267 assertions    Persistence, DAG traversal, compaction, branches
Interface tests:       40 assertions    Blocking requests, sessions
Integration tests:    649 assertions    Claude API, MCP, tools, events, agentic loops
Provider tests:        70 assertions    Multi-provider subprocess management
REST API tests:        73 assertions    REST API serialization and dispatch
Viz tests:             92 assertions    Timeline rendering, navigation, filters, help
Holodeck tests:     1,193 assertions    ECS, shaders, meshes, camera, HUD, input, ray picking
Security tests:       322 assertions    Permissions, audit, validation, 65 sandbox escape tests
Monitoring tests:      48 assertions    Metrics, health checks, HTTP endpoints
E2E tests:            134 assertions    All 15 user stories end-to-end
───────────────────────────────────
Total:              2,775+ assertions   All passing
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `bordeaux-threads` | Concurrency (blocking input, thread-safe registries, conductor) |
| `cl-json` | JSON serialization (Claude API, MCP protocol, providers) |
| `dexador` | HTTP client (Claude API, OpenAI API, web tools) |
| `ironclad` | SHA256 hashing (content-addressable storage, snapshot DAG) |
| `babel` | UTF-8 encoding |
| `local-time` | Timestamps |
| `alexandria` | Utilities |
| `fiveam` | Testing |
| `uiop` | System utilities (process execution, environment) |
| `hunchentoot` | HTTP server (monitoring endpoints, conductor webhook) |
| `cl-ppcre` | Regex (input validation) |
| `cl-charms` | ncurses terminal UI (2D visualization) |
| `log4cl` | Logging |
| `3d-vectors` | Vector math (holodeck) |
| `3d-matrices` | Matrix math (holodeck) |
| `cl-fast-ecs` | Entity-Component-System (holodeck) |

The holodeck is a separate ASDF system (`autopoiesis/holodeck`) to avoid requiring 3D dependencies for core usage.

## Documentation

- **[Quick Start](platform/docs/QUICKSTART.md)** — Setup, first agent, walkthrough
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
  - [08 Remaining Phases](platform/docs/specs/08-remaining-phases.md) — Phase 7-10 specifications
- **[Deployment](platform/docs/DEPLOYMENT.md)** — Docker deployment
- **[CLAUDE.md](CLAUDE.md)** — Development guidelines and code conventions

## License

MIT
