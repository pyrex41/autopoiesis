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

**All phases (0-11) complete.** 4,300+ assertions across 28 test suites, all passing.

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

At the bottom of the stack is a datom store whose data model comes directly from [Datomic](https://www.datomic.com/), which is itself built on Datalog. The five-tuple datom `(entity, attribute, value, tx, added)`, the EAVT/AEVT index naming, immutable facts with monotonic transaction stamping, and EAV triples as the universal schema are all Datomic's design carried over. The substrate includes a Datalog query engine with Datomic-style `q` queries, Pull API, `:in` parameters, recursive rules, and compiled queries via Futamura's first projection (`compile-query` for static compilation, `compile-query-fn` for runtime JIT) — alongside direct index access (`entity-attr` for O(1) point lookups, `find-entities` via an inverted value index) and `take!` for atomic claim-and-update.

**Why not actual Datomic?** Datomic is JVM-only. From Common Lisp, the only option is Datomic's REST Peer Service — meaning every query becomes an HTTP round-trip (~1ms+), losing the Peer cache that is Datomic's key performance advantage. The substrate's in-process reads are sub-microsecond (~50ns). Beyond latency, the substrate's `take!` (Linda coordination) and reactive hooks have no Datomic equivalent, and arbitrary Lisp objects can be stored as datom values without serialization. Zero-ops deployment (single SBCL binary + LMDB file) vs. running a JVM transactor + REST peer + storage backend seals it. See [`thoughts/shared/research/2026-03-04-datomic-vs-substrate.md`](thoughts/shared/research/2026-03-04-datomic-vs-substrate.md) for the full analysis.

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

### Persistent Agents: O(1) Forking via Structural Sharing

Agents can be represented as persistent (immutable) structs backed by the [FSet](https://common-lisp.net/project/fset/) library's balanced trees. All updates return new structs — old roots are never modified. This enables:

- **O(1) forking**: `persistent-fork` allocates one struct; all data is shared via structural sharing
- **Automatic version history**: The `dual-agent` bridge wraps a mutable CLOS agent with a persistent root, pushing old versions to history on every state change
- **Immutable cognitive loop**: `persistent-perceive`, `persistent-reason`, `persistent-decide`, `persistent-act`, `persistent-reflect` — each returns a new agent struct
- **Append-only merge**: Union of thoughts, union of capabilities, latest-wins for genome/membrane
- **Lineage tracking**: Parent-child relationships, ancestor walking, common ancestor, generation counting
- **Membrane safety**: Boundary rules control what genome modifications are allowed

```lisp
;; Create a persistent agent
(let ((agent (autopoiesis.agent:make-persistent-agent
               :name "scout"
               :capabilities '(:search :analyze :report))))

  ;; Fork — O(1), returns child + updated parent
  (multiple-value-bind (child parent)
      (autopoiesis.agent:persistent-fork agent "scout-alpha")
    ;; child and parent share all data via structural sharing
    ;; Run independent cognitive cycles on each
    (let ((evolved-child (autopoiesis.agent:persistent-cognitive-cycle child env)))
      ;; Original agent is unchanged
      (assert (eq (autopoiesis.agent:persistent-agent-thoughts agent)
                  (autopoiesis.agent:persistent-agent-thoughts parent))))))
```

**Swarm integration** bridges persistent agents to the existing evolutionary infrastructure — extract genomes, run `evolve-generation`, patch results back:

```lisp
;; Evolve a population of persistent agents
(let ((evolved (autopoiesis.swarm:evolve-persistent-agents
                 agents
                 (autopoiesis.swarm:make-standard-pa-evaluator)
                 environment
                 :generations 10)))
  ;; evolved is a list of new persistent-agent structs with evolved traits
  ;; Original agents are unmodified
  evolved)
```

Three built-in fitness functions: `thought-diversity-fitness` (unique thought types / total), `capability-breadth-fitness` (count / max), `genome-efficiency-fitness` (capabilities / genome-size).

---

## Design Lineage

Autopoiesis draws on decades of research in programming languages, AI, and distributed systems. This section makes the intellectual debts explicit.

### Autopoiesis (Maturana & Varela, 1972)

The project name comes from the biological theory of self-producing systems. Chilean biologists Humberto Maturana and Francisco Varela coined "autopoiesis" to describe living systems that continuously produce and maintain themselves — the cell membrane, for instance, is both a product of the cell's internal chemistry and the boundary that makes that chemistry possible. Here, agents produce their own capabilities, evolve their own genomes, and modify their own cognitive architecture. The `membrane` in the persistent agent layer controls what genome modifications are allowed — a direct echo of the biological membrane's selective permeability.

### Linda Tuple Spaces (Gelernter, 1985)

David Gelernter's Linda coordination language introduced four operations on a shared associative memory: `out` (write), `rd` (read), `in` (destructive read), and `eval` (fork computation). The substrate's `take!` primitive is Linda's `in()` — an atomic find-and-remove that enables safe concurrent coordination without point-to-point messaging. The datom `(entity, attribute, value, tx, added)` IS a Linda tuple, and the EAVT/AEVT indexes provide exactly the three access patterns Linda's `rd()` needs. This isn't an analogy — the isomorphism is structural. See [`thoughts/shared/research/2026-02-16-linda-tuple-spaces-substrate-evaluation.md`](thoughts/shared/research/2026-02-16-linda-tuple-spaces-substrate-evaluation.md).

### Datomic & Datalog (Hickey, 2012)

Rich Hickey's Datomic contributes the five-tuple datom model, EAVT/AEVT index naming, immutable facts with monotonic transaction stamping, and EAV triples as a universal schema. The substrate's Datalog query engine implements Datomic-style `q` queries with `:find` projection, Pull API, `:in` parameters, and recursive rules. What's NOT from Datomic: `take!` (Linda), reactive hooks (`defsystem`), schemaless values, and the zero-ops single-process deployment. See [`thoughts/shared/research/2026-03-04-datomic-vs-substrate.md`](thoughts/shared/research/2026-03-04-datomic-vs-substrate.md).

### Homoiconicity & Image-Based Development (Lisp, 1958–present)

The entire architecture rests on Lisp's homoiconicity — code and data are the same S-expression trees. This gives you serializable agent state (it's just a plist), structural diffing (`sexpr-diff` walks cons cells), content-addressable hashing (type-tagged SHA-256 over S-expression structure), and natural self-modification (agents write code as data, compile it with `(compile nil (lambda ...))`, test it, and promote it). The project's epigraph — *"What if an AI agent had the same relationship to its own cognition that a Lisp developer has to their running system via SWANK?"* — makes the debt to image-based development explicit. Like Interlisp's structure editor or connecting to a running Genera system, you can reach into a live agent, inspect its thoughts, inject observations, and modify behavior without stopping it.

### Content-Addressable Storage & Merkle Trees (Git, 2005)

The snapshot DAG uses SHA-256 structural hashing for deduplication and integrity, two-character prefix sharding (matching Git's object store layout), lightweight branches as named mutable pointers into an immutable DAG, and common-ancestor finding for merge operations. Forking is O(1) — both branches share history. The diff engine operates on S-expression trees rather than text, but the operational model (branch, fork, diff, merge, time-travel) is Git's, applied to agent cognition instead of source code.

### CLOS & the Meta-Object Protocol (Kiczales et al., 1991)

*The Art of the Metaobject Protocol* provides the foundation for several key mechanisms. `slot-unbound` MOP methods enable lazy-loading of both snapshot proxies and substrate entities — data loads transparently on first access. `:after` methods on `(setf agent-state)` drive the dual-agent bridge's automatic persistent root updates. `define-entity-type` generates CLOS classes with MOP-driven attribute loading from the entity cache. The cognitive model spec describes an "Agent Metaobject Protocol" (AMOP) where `compute-cognitive-method` customizes per-agent cognition dispatch.

### Persistent Data Structures (Okasaki, 1998; FSet)

Chris Okasaki's *Purely Functional Data Structures* established the theory of persistent collections with structural sharing. The persistent agent layer uses [FSet](https://common-lisp.net/project/fset/) (Scott L. Burson's weight-balanced tree library for Common Lisp) wrapped as `pmap-*`, `pvec-*`, `pset-*` — giving O(1) agent forking where parent and child share all data via structural sharing, and all updates return new structs with the old root unmodified. The planning documents also evaluated HAMTs (Bagwell, 2001) and 32-way branching tries (as in Clojure's PersistentVector) before settling on FSet.

### Condition/Restart System (Common Lisp)

Common Lisp's condition/restart system — where the signaler and the handler are separated, and restarts offer multiple recovery strategies — pervades the error handling. The recovery module defines 4 condition tiers, 6 standard restarts, graceful degradation levels (`:minimal`, `:offline`, `:read-only`), and component health tracking. Substrate conditions provide `:coerce`, `:store-raw`, and `:skip` restarts. This is non-local exit done right: the signaler doesn't choose the recovery strategy, the handler does.

### Cognitive Architecture: OODA Extended (Boyd, 1970s)

John Boyd's OODA loop (Observe → Orient → Decide → Act) was designed for military decision-making under uncertainty. The five-phase cognitive cycle (perceive → reason → decide → act → reflect) extends OODA with a `reflect` phase that feeds insight back into future perception — closing the learning loop. Each phase produces S-expression cognitive primitives that flow to the next. The synthesis plan evaluated six orchestrator patterns — event loop, actor model, blackboard, OODA, workflow/saga, and control theory feedback loops — and the conductor emerged as a synthesis of all six.

### Event Sourcing (2005–present)

The substrate's immutable datoms with `(tx, added)` fields implement event sourcing: every state change is an append-only fact assertion or retraction, and current state is reconstructable by replaying the log. The spec addendum explicitly adopts event sourcing to replace full-state snapshots (which would produce ~25GB/day per active agent). Periodic checkpoints enable efficient replay.

### Entity-Component-System (Game Industry, 2000s)

The ECS pattern — entities as IDs, components as data, systems as behavior — appears in two places. The holodeck 3D visualization uses `cl-fast-ecs` directly for cache-friendly real-time rendering with 32 key bindings and persistent agent embodiment. More subtly, the substrate's `defsystem` macro is ECS-inspired: systems declare entity types they watch, attributes they care about, and ordering constraints (`:after`, `:before`) — the runtime builds a dispatch table for O(1) routing of attribute changes to affected systems.

### Actor Model (Hewitt, 1973; Erlang/OTP)

Thread-safe per-agent mailboxes with condition variables enable concurrent message delivery. The project originally ran on the BEAM (Erlang's VM) via LFE (Lisp Flavoured Erlang) for OTP supervision trees and "let it crash" fault isolation. The LFE layer was removed when the CL substrate absorbed its coordination role, but the actor model's influence persists in the mailbox architecture, the conductor's worker management, and the five team coordination strategies (leader-worker, parallel, pipeline, debate, consensus).

### Blackboard Architecture (Hayes-Roth, 1985)

The AI planning pattern where multiple "knowledge sources" read and write a shared knowledge structure. The substrate's datom store serves this role — agents, the conductor, and team coordination all post events and claim tasks through the same shared associative memory, coordinated by `take!` rather than a centralized scheduler. The synthesis plan explicitly evaluated blackboard architecture as one of six candidate patterns.

### 1980s Lisp AI: Frames, Rete, TMS

A research evaluation noted that *"the substrate unconsciously recapitulates 1980s Lisp AI. Datoms = frames/slots. Hooks = slot daemons. Standing queries = production rules. Classification = frame classification. The lineage is real and the patterns are proven."* Specific systems considered during design:

- **Rete algorithm** (Forgy, 1979) — Efficient pattern matching for production rules. The `defsystem` reactive dispatch is a simplified version; full Rete incremental maintenance is deferred.
- **Truth Maintenance Systems** (de Kleer/Doyle, 1979) — Dependency tracking for derived beliefs. Evaluated as "medium relevance" for agent belief justification chains.
- **Frame systems** (Minsky, 1970s) — Slot-based knowledge representation with inheritance and slot daemons. The structural parallel to EAV datoms with reactive hooks is direct.
- **SERIES** (Waters, 1989) — Lazy fused sequence operations. Evaluated for LMDB cursor pipelines.
- **Futamura projections** (1971) — Partial evaluation of interpreters. `compile-query` implements the first projection: specializing the Datalog interpreter against a known query to produce native compiled code. Static binding analysis selects per-clause strategies (value-index O(1), direct-lookup O(1), cache-scan, full-scan), then code generation emits specialized Lisp that `(compile nil ...)` JIT-compiles to machine code. Attribute IDs are resolved once per call instead of N×M times per binding.

### Genetic Algorithms (Holland, 1975)

The swarm module implements genome-based evolutionary optimization: S-expression genomes encoding capabilities and heuristic weights, uniform crossover, stochastic mutation, tournament/roulette/elitism selection, and production rules that bridge learned heuristics to genome transformations. Applied to persistent agents via the genome bridge — extract, evolve, patch back — with structural sharing preserving history.

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

### Team Coordination

Create teams of agents that work together using configurable strategies. Five coordination patterns are built in:

```lisp
;; Create a team with a leader-worker strategy
(let ((team (autopoiesis.team:create-team "code-review"
              :strategy :leader-worker
              :task "Review authentication module"
              :leader "architect"
              :members '("architect" "security-analyst" "test-writer"))))

  ;; Start the team — initializes strategy, creates shared workspace
  (autopoiesis.team:start-team team)

  ;; Leader decomposes task into subtasks via workspace queue
  ;; Workers claim subtasks atomically via take!
  ;; Results accumulate in shared workspace

  ;; Query team progress
  (autopoiesis.team:query-team-status team)
  ;; => (:ID "team-code-review-..." :STATUS :ACTIVE :MEMBER-COUNT 3 ...)

  ;; Wait for all members to finish
  ;; (uses CV-based substrate hooks, not polling)
  (autopoiesis.team:disband-team team))
```

**Strategies:**
| Strategy | Pattern | Use Case |
|----------|---------|----------|
| `:leader-worker` | Leader decomposes, workers claim via `take!` | Task decomposition, delegation |
| `:parallel` | All agents get same task, best result selected | Competitive drafting, redundancy |
| `:pipeline` | Sequential stages, output flows to next | Multi-step refinement |
| `:debate` | N rounds of argumentation + judge evaluates | Adversarial reasoning |
| `:consensus` | Iterative draft/review/vote until convergence | Collaborative decision-making |

Teams use the substrate for coordination: shared memory via workspace datoms, atomic task claiming via `take!`, and CV-based await (no polling). Thread-safe mailboxes with per-agent locks and condition variables enable concurrent message delivery across team members.

### Safe Operations with Supervisor Checkpoints

Wrap risky operations in `with-checkpoint` — automatic rollback on failure:

```lisp
(autopoiesis.supervisor:with-checkpoint (agent :label "deploy-attempt")
  ;; If anything signals an error, agent reverts to pre-checkpoint state
  (dangerous-deploy-operation agent))
```

### Crystallize Runtime to Source

Emit learned capabilities, evolved genomes, and heuristics as Lisp source files, stored in the snapshot DAG or exported to Git:

```lisp
;; Crystallize capabilities the agent learned at runtime → source files
(autopoiesis.crystallize:crystallize-capabilities agent)

;; Export to a Git repository
(autopoiesis.crystallize:export-to-git agent "/path/to/repo")
```

### Structured LLM Outputs with Skel

Typed function framework for reliable structured outputs from LLMs:

```lisp
;; Define a typed function backed by an LLM
(autopoiesis.skel:define-skel-function extract-entities
  :params ((text string :required t))
  :returns (list-of entity)
  :prompt "Extract named entities from: ~A")
```

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
│  Jarvis Layer          NL→Tool Dispatch  •  Conversational Loop     │
│                        Human-in-the-Loop  •  Pi RPC Provider         │
├──────────────────────────────────────────────────────────────────────┤
│  Team Layer            Coordination Strategies  •  Shared Workspace  │
│                        Task Queue (take!)  •  CV-Based Await         │
├──────────────────────────────────────────────────────────────────────┤
│  Orchestration Layer   Conductor Tick Loop  •  Timer Heap            │
│                        Substrate-Backed Event Queue  •  Workers      │
├──────────────────────────────────────────────────────────────────────┤
│  Integration Layer     Claude API  •  MCP Servers  •  Tool Mapping  │
│                        Multi-Provider Loops  •  Skel Typed LLM Fns  │
├──────────────────────────────────────────────────────────────────────┤
│  API Layer             REST Server  •  WebSocket (Clack/Woo)        │
│                        MCP Server  •  SSE  •  JSON/MessagePack       │
├──────────────────────────────────────────────────────────────────────┤
│  Crystallize Layer     Emit Runtime → Source  •  Git Export          │
│                        Capabilities  •  Heuristics  •  Genomes       │
├──────────────────────────────────────────────────────────────────────┤
│  Supervisor Layer      Checkpoint/Revert  •  Stable State Tracking  │
│                        Dual-Agent Bridge  •  Risk-Wrapped Operations │
├──────────────────────────────────────────────────────────────────────┤
│  Interface Layer       Navigator  •  Viewport  •  Annotator         │
│                        Blocking Input  •  CLI  •  2D Terminal Viz    │
├──────────────────────────────────────────────────────────────────────┤
│  Conversation Layer    Turn DAG  •  Content-Addressed Blobs         │
│                        Fork/Merge  •  Dual-Track History             │
├──────────────────────────────────────────────────────────────────────┤
│  Snapshot Layer        Content-Addressable DAG  •  Branch Manager   │
│                        Structural Diff/Patch  •  Lazy Loading        │
├──────────────────────────────────────────────────────────────────────┤
│  Swarm Layer           Genome Evolution  •  Crossover/Mutation       │
│                        Selection  •  Persistent Agent Evolution      │
├──────────────────────────────────────────────────────────────────────┤
│  Agent Layer           Cognitive Loop  •  Capabilities  •  Learning  │
│                        Persistent Agents (O(1) Fork)  •  Dual-Agent │
├──────────────────────────────────────────────────────────────────────┤
│  Workspace Layer       Ephemeral Contexts  •  Isolation Backends    │
│                        Team Coordination  •  Agent Home Dirs         │
├──────────────────────────────────────────────────────────────────────┤
│  Core Layer            S-Expression Utilities  •  Cognitive Prims    │
│                        Persistent Structs (fset)  •  Ext. Compiler   │
├──────────────────────────────────────────────────────────────────────┤
│  Substrate Layer       Datom Store (EAV)  •  Linda take!             │
│                        Value Index  •  Interning  •  defsystem       │
└──────────────────────────────────────────────────────────────────────┘

Separate ASDF systems: Holodeck (3D ECS viz), Sandbox (squashd containers), Research (parallel campaigns)
```

### Substrate Layer (`platform/src/substrate/`)

Datom store with EAV triples, three synchronized indexes (EAVT, AEVT, EA-CURRENT), and an inverted value index for O(1) queries. Linda coordination via `take!` for atomic state transitions. Monotonic-counter interning maps symbolic names to compact integers (no hash collisions). Reactive `defsystem` dispatch with topological ordering. Batch transactions via `with-batch-transaction`. LMDB persistence optional.

### Core Layer (`platform/src/core/`)

The homoiconic foundation. S-expression diff/patch/hash with type-tagged SHA-256 digesting. Five cognitive primitives (Thought, Decision, Action, Observation, Reflection) as CLOS classes with S-expression content. Append-only thought streams with O(1) ID lookup. Persistent data structures via FSet wrappers: `pmap-*` (maps), `pvec-*` (vectors), `pset-*` (sets) with structural sharing for O(1) forking. Sandboxed extension compiler with code walking, forbidden-symbol checking, and package restrictions. Condition/restart error recovery. Nanosecond profiling.

### Agent Layer (`platform/src/agent/`)

Five-phase cognitive loop (perceive -> reason -> decide -> act -> reflect) as CLOS generic functions. `defcapability` macro for declaring capabilities with parameter specs and permissions. Priority-queue context window for working memory (default 100K tokens). Learning system: n-gram action sequence analysis, frequency-based context patterns, heuristic generation with confidence decay. Parent-child agent spawning with mailbox messaging. Persistent agents: immutable `defstruct` with pvec thoughts, pset capabilities, pmap membrane/metadata — O(1) fork via structural sharing, immutable cognitive cycle, lineage tracking, membrane boundary rules. Dual-agent bridge wraps mutable CLOS agents with thread-safe persistent root + automatic version history.

### Swarm Layer (`platform/src/swarm/`)

Evolutionary optimization of agent configurations. Genomes encode capabilities, heuristic weights, and parameters. Uniform crossover, stochastic mutation, tournament/roulette/elitism selection. Production rules bridge learned heuristics to genome transformations. Optional parallel fitness evaluation. Persistent agent genome bridge: extract genomes from persistent agents, run evolution, patch results back. Three built-in fitness functions (thought diversity, capability breadth, genome efficiency) composable via `make-standard-pa-evaluator`.

### Snapshot Layer (`platform/src/snapshot/`)

Content-addressable DAG persistence. SHA-256 structural hashing for deduplication. LRU-cached filesystem storage with two-character prefix sharding. Lightweight branches as named pointers. Structural diffing via S-expression edit operations with `:car`/`:cdr` path navigation. Time-travel with common ancestor finding, path discovery, and DAG traversal. Lazy-loading proxies via `slot-unbound` MOP method. Six-check consistency verification with repair.

### Conversation Layer (`platform/src/conversation/`)

Turns stored as substrate datoms linked by `:turn/parent` pointers. Content stored as content-addressed blobs. O(1) context forking via shared head pointers. Single-transaction turn writes for crash safety. Dual-track: in-memory message list for API calls, substrate entities for durable history.

### Workspace Layer (`platform/src/workspace/`)

Per-task ephemeral execution contexts with pluggable isolation backends (`:none`, `:directory`, `:sandbox`). Agent home directories with persistent file storage. Team coordination via shared workspace datoms and atomic task claiming.

### Interface Layer (`platform/src/interface/`)

Thread-safe blocking requests using condition variables. CLI REPL session with 15 commands. Navigator with history stack. Viewport with focus path, filter predicates, and detail levels. Annotator for human commentary. Human override/approve/reject of agent decisions. 2D ANSI terminal timeline explorer with 256-color rendering, hjkl navigation, and branch cycling.

### Supervisor Layer (`platform/src/supervisor/`)

Checkpoint-and-revert wrapper for high-risk agent operations. `with-checkpoint` captures agent state before risky operations and automatically reverts on failure. Stable state tracking, promotion, and dual-agent bridge for persistent root checkpointing.

### Crystallize Layer (`platform/src/crystallize/`)

Emits live runtime changes — capabilities, heuristics, genomes — as Lisp source files stored in the snapshot DAG. Capability crystallizer, heuristic crystallizer, genome crystallizer, ASDF fragment generator, and Git export for version-controlled runtime artifacts.

### API Layer (`platform/src/api/`)

Multi-protocol API server: REST endpoints via Hunchentoot, WebSocket via Clack/Woo for real-time frontends, MCP server support, SSE for streaming events. JSON and MessagePack serialization. Authentication middleware.

### Integration Layer (`platform/src/integration/`)

Multi-provider agentic loops: direct API (Anthropic, OpenAI, Ollama) and CLI subprocess (Claude Code, Codex, OpenCode). `define-cli-provider` macro generates providers from declarative specs. Bidirectional tool mapping: kebab-case capabilities <-> snake_case tools, Lisp types <-> JSON Schema. MCP client speaking JSON-RPC 2.0 over stdio. Skel typed LLM function framework with structured types, JSON schema generation, and streaming. Built-in tools for filesystem, web, shell, and git. Pub/sub event bus with 1000-event history.

### Orchestration Layer (`platform/src/orchestration/`)

Conductor tick loop (100ms heartbeat) with substrate-backed event queue. Linda `take!` for atomic event claiming. Timer heap for scheduled actions. Worker management as substrate entities. Claude CLI subprocess spawning with streaming JSON, timeout handling, and exponential backoff. HTTP webhook endpoint.

### Team Layer (`platform/src/team/`)

Multi-agent coordination with five pluggable strategies as CLOS generic function specializations. Teams persist to substrate, maintain thread-safe in-memory registries, and coordinate via shared workspace datoms. Task assignment uses Linda `take!` for atomic claiming. CV-based await for zero-polling agent completion detection. Thread-safe per-agent mailboxes. Strategies: leader-worker, parallel, pipeline, debate, consensus.

### Jarvis Layer (`platform/src/jarvis/`)

Unified conversational loop using Pi RPC provider for NL→tool dispatch. Integrates agent backing, supervisor checkpoints, and human-in-the-loop approval into a single interactive session.

### Holodeck Layer (`platform/src/holodeck/`, separate ASDF system)

3D ECS visualization of the snapshot DAG and persistent agent state. Uses `cl-fast-ecs` for entity management. Persistent agent embodiment with cognitive/metabolic/lineage/genome ECS components. Orbit and fly cameras, HUD panels, ray picking, 32 key bindings.

### Cross-Cutting

**Security** (`platform/src/security/`): Permission matrix, audit logging with thread-safe 10MB rotation, input validation with 17 types and combinators, HTML sanitization.

**Monitoring** (`platform/src/monitoring/`): Prometheus-compatible `/metrics`, Kubernetes-style probes (`/healthz`, `/readyz`), thread-safe counters/gauges/histograms, Hunchentoot HTTP server.

---

## Repository Layout

```
ap/
├── platform/          # Common Lisp agent platform
│   ├── autopoiesis.asd
│   ├── substrate.asd
│   ├── src/
│   │   ├── substrate/     # Datom store, Linda, interning, defsystem
│   │   ├── core/          # S-expr utils, cognitive prims, persistent structs (fset)
│   │   ├── agent/         # Cognitive loop, capabilities, persistent agents, dual-agent
│   │   ├── workspace/     # Ephemeral execution contexts, agent homes, team coordination
│   │   ├── swarm/         # Genome evolution, persistent agent evolution, fitness
│   │   ├── snapshot/      # Content-addressable DAG, branches, diff, time-travel
│   │   ├── supervisor/    # Checkpoint/revert, stable state, risk-wrapped ops
│   │   ├── crystallize/   # Emit runtime → source, Git export
│   │   ├── conversation/  # Turn DAG, context forking
│   │   ├── interface/     # CLI, blocking input, viewport, 2D viz
│   │   ├── integration/   # LLM providers, MCP, tools, skel, agentic loops
│   │   ├── skel/          # Typed LLM functions, BAML parser, SAP preprocessor
│   │   ├── api/           # REST, WebSocket, MCP server, SSE
│   │   ├── team/          # Multi-agent coordination (5 strategies)
│   │   ├── orchestration/ # Conductor, event queue, workers
│   │   ├── jarvis/        # NL→tool conversational loop
│   │   ├── holodeck/      # 3D ECS visualization (separate ASDF system)
│   │   ├── sandbox/       # Squashd container integration (separate ASDF system)
│   │   ├── research/      # Parallel research campaigns (separate ASDF system)
│   │   ├── security/      # Permissions, audit, validation
│   │   └── monitoring/    # Metrics, health checks
│   ├── test/              # 28 test suites, 4,300+ assertions
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
Core tests:           470 assertions    S-expression ops, cognitive primitives, compiler, recovery
Agent tests:          363 assertions    Lifecycle, capabilities, context window, learning, spawning
Snapshot tests:       267 assertions    Persistence, DAG traversal, compaction, branches
Conversation tests:    45 assertions    Turn creation, context management, forking, history
Interface tests:       40 assertions    Blocking requests, sessions, viewport
Viz tests:             92 assertions    Timeline rendering, navigation, filters, help
Integration tests:    649 assertions    Claude API, MCP, tools, events, agentic loops
Agentic tests:        195 assertions    Agentic loop, tool dispatch, provider integration
Provider tests:        70 assertions    Multi-provider subprocess management
Prompt registry:       71 assertions    Prompt templates, registration, retrieval
Skel tests:           523 assertions    Typed LLM functions, BAML parser, SAP, JSON schema
REST API tests:        73 assertions    REST API serialization and dispatch
Swarm tests:          110 assertions    Genome evolution, crossover, mutation, selection
Supervisor tests:      63 assertions    Checkpoint/revert, stable state, promotion
Crystallize tests:     60 assertions    Emit capabilities/heuristics/genomes to source
Git tools tests:       38 assertions    Git read/write tool integration
Jarvis tests:          69 assertions    NL dispatch, tool invocation, session management
Team tests:            30 assertions    Mailbox concurrency, CV-based await, strategies
Workspace tests:       69 assertions    Ephemeral contexts, isolation, team coordination
Persistent agent:      80 assertions    Persistent structs, cognition, fork, lineage, dual-agent
Swarm integration:     23 assertions    Genome bridge, persistent evolution, fitness
Bridge protocol:       14 assertions    Claude bridge protocol, message format
Meta-agent tests:      36 assertions    Meta-agent capabilities, self-inspection
Security tests:       322 assertions    Permissions, audit, validation, 65 sandbox escape tests
Monitoring tests:      48 assertions    Metrics, health checks, HTTP endpoints
E2E tests:            134 assertions    All 15 user stories end-to-end
Holodeck tests:     1,193 assertions    ECS, shaders, meshes, camera, HUD (separate system)
───────────────────────────────────
Total:              4,300+ assertions   All passing
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
| `fset` | Persistent functional collections (structural sharing for agents) |
| `lparallel` | Parallel evaluation (swarm fitness) |
| `3d-vectors` | Vector math (holodeck, separate system) |
| `3d-matrices` | Matrix math (holodeck, separate system) |
| `cl-fast-ecs` | Entity-Component-System (holodeck, separate system) |

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
