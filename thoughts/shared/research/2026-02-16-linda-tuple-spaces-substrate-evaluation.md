---
date: 2026-02-16T18:54:00-06:00
researcher: Claude
git_commit: 8a80e4d4027b6cd9827b3006adea064a081e225e
branch: main
repository: autopoiesis
topic: "Linda Tuple Spaces and the Substrate Datom Model: Mapping and Applicability"
tags: [research, linda, tuple-space, substrate, datom, conductor, coordination, hpc]
status: complete
last_updated: 2026-02-16
last_updated_by: Claude
---

# Research: Linda Tuple Spaces, the Substrate, and the Consolidated CL Architecture

**Date**: 2026-02-16T18:54:00-06:00
**Researcher**: Claude
**Git Commit**: 8a80e4d4027b6cd9827b3006adea064a081e225e
**Branch**: main
**Repository**: autopoiesis

## Research Question

The HPC ideas document (#7: Linda Tuple Spaces) was previously evaluated as "Medium" relevance and categorized as "Future work" for the consolidated CL plan. The user observes that Linda tuple spaces map directly to the datom structure, but this mapping assumes the substrate architecture described in `substrate-decomposition.md` and `substrate-extension-points.md` — not the current plan's blob-based snapshot model. Evaluate this relationship in detail.

## Summary

**The user is correct.** Linda tuple spaces DO map almost perfectly to the datom model proposed in `substrate-decomposition.md`. The prior HPC evaluation (in `2026-02-16-hpc-lisp-optimization-evaluation.md`) dismissed Linda because the consolidated CL plan doesn't build a datom/EAV store. But this dismissal conflated two questions:

1. **Does Linda apply to the 7-phase consolidated CL plan?** No — that plan stores blobs and conversation turns, not datoms.
2. **Does Linda apply to the substrate architecture?** Yes — directly and powerfully. The datom store IS a tuple space.

The critical dependency is whether Autopoiesis evolves toward the substrate architecture (where datoms are the universal data unit) or stays with the consolidated plan (where snapshots are blobs and only conversations use structured entities). The substrate documents in `~/projects/thinking/` describe a path where Linda is not just applicable but emergent — the datom store naturally becomes a coordination medium.

---

## The Linda-Datom Isomorphism

### Linda's Four Operations

Linda (Gelernter, 1985) provides four operations on a shared associative memory:

| Linda Op | Semantics | Datom Equivalent |
|----------|-----------|------------------|
| `out(tuple)` | Write a tuple to the space | `transact!` — assert datoms |
| `rd(pattern)` | Non-destructive read matching pattern | `query` — scan indexes by pattern |
| `in(pattern)` | Destructive read (remove matching tuple) | `transact!` with retraction (`:added nil`) |
| `eval(expr)` | Fork computation, write result as tuple | `spawn` actor that writes result via `transact!` |

### The Datom as Tuple

From `substrate-decomposition.md:80-86`:

```lisp
(defstruct (datom (:conc-name d-))
  (entity   0 :type (unsigned-byte 64))   ; interned entity ID
  (attribute 0 :type (unsigned-byte 32))   ; interned attribute
  (value   nil)                            ; typed value
  (tx      0 :type (unsigned-byte 64))     ; transaction time
  (added   t :type boolean))               ; assert or retract
```

This IS a tuple: `(entity, attribute, value, tx, added)`. The `added` flag gives us retraction semantics — Linda's `in()` operation.

### Pattern Matching via Indexes

Linda's pattern matching works by wildcards: `rd(?, "k8s.pod/phase", "Running")` finds all tuples where attribute is pod-phase and value is Running. The substrate's EAVT/AEVT indexes provide exactly this:

```
EAVT:  Given entity → find all attributes/values (entity-centric lookup)
AEVT:  Given attribute → find all entities with that attribute (attribute-centric scan)
VAET:  Given value → find all entities where some attribute has that value (reverse lookup)
```

These are the three access patterns Linda's `rd()` needs:
- `rd(entity, ?, ?)` → EAVT prefix scan
- `rd(?, attribute, ?)` → AEVT prefix scan
- `rd(?, ?, value)` → VAET prefix scan (if the index exists)

### `in()` as Atomic Claim (Work Queue Pattern)

The HPC document's key insight is the `take-task!` pattern:

```lisp
(defun take-task! (task-type)
  "Atomically find and claim a pending task."
  (let ((task (query-first '(:where (and (= :task/type task-type)
                                         (= :task/status :pending))))))
    (when task
      (transact! (list (make-datom (entity-id task) :task/status :in-progress)))
      task)))
```

This works because:
1. LMDB's single-writer model guarantees atomicity of the `transact!` call
2. The query + transact can be wrapped in a single LMDB write transaction for true atomic claim
3. The `:task/status` change fires hooks, allowing standing queries to react

**This is exactly Linda's `in()` — destructive read that removes the tuple from the matching set (by changing its status from `:pending` to `:in-progress`).** The datom model's retraction semantics make this even cleaner than Linda's original design, because the old value (`:pending`) is retracted and the new value (`:in-progress`) is asserted in the same transaction, with the full history preserved.

---

## Where This Lives in the Architecture Stack

### Three Layers of Architecture Documents

There are three distinct layers being discussed:

```
Layer 3: ~/projects/thinking/ — The Substrate Vision
          substrate-decomposition.md, substrate-extension-points.md
          A shared datom store powering Cortex + Bubble + Apiosis
          Linda maps perfectly HERE

Layer 2: Consolidated CL Plan — The Current Implementation Plan
          thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md
          Single CL process, LMDB for snapshots/blobs/conversations
          Linda maps partially HERE (conductor coordination)

Layer 1: Current Codebase — What Exists Today
          File-based snapshots, in-memory event bus, LFE bridge
          Linda maps poorly HERE (no shared mutable store)
```

### The Gap Between Layer 2 and Layer 3

The consolidated CL plan (Layer 2) explicitly defers several substrate capabilities:

From the plan (lines 99-108):
```
## What We're NOT Doing
- OTP supervision trees in CL
- Datalog query language — Future work if EAV datoms warrant it
- Full EAV decomposition of cognitive state — Snapshots remain as blobs
- Standing query / defsystem reactive layer — Defer until needed
- MOP schema specialization — AP's cognitive types are fixed
- Multi-user / multi-tenant
```

Linda needs the substrate (Layer 3) because:
1. **`out(tuple)` = `transact!`** requires a unified write path with hook dispatch — the plan has LMDB writes but no `transact!` with hooks
2. **`rd(pattern)` = `query`** requires EAV indexes — the plan stores blobs, not decomposed attributes
3. **`in(pattern)` = atomic claim** requires EAV indexes plus retraction — the plan has no retraction semantics
4. **`eval(expr)` = `spawn`** requires the actor system — the plan has threads but no actor/mailbox abstraction

The consolidated plan's Turn/Context DAG (Phases 6-7) is the closest to datom-like structures, but turns are stored as entities with a small fixed schema, not as arbitrary EAV datoms. You can query turns by role, by context, by time — but you can't do arbitrary pattern matching over all attributes like Linda requires.

---

## Concrete Evaluation: What Linda Gives You at Each Layer

### At Layer 3 (Full Substrate) — High Value

With the substrate architecture, every piece of data is a datom. Linda's operations become the universal coordination mechanism:

**1. Work Distribution for Cognitive Tasks:**

```lisp
;; Agent encounters something it can't handle alone
(transact! (list
  (make-datom (new-entity-id) :task/type :deep-analysis
              :task/payload conversation-context
              :task/status :pending
              :task/priority 8
              :task/created-by agent-id)))

;; Conductor's tick loop finds and claims the task
(take-task! :deep-analysis)
;; → Spawns Claude CLI worker with the payload
```

**2. Inter-Agent Coordination:**

```lisp
;; Agent A writes a finding to the shared space
(transact! (list
  (make-datom finding-id :finding/type :security-concern
              :finding/entity pod-123
              :finding/severity :high
              :finding/discoverer agent-a)))

;; Standing query on Agent B fires when it sees high-severity findings
(defsystem :security-responder
  (:entity-type :finding
   :watches (:finding/severity))
  (:on-change (entity datoms)
    (when (eq (entity-attr entity :finding/severity) :high)
      (spawn-response-agent entity))))
```

**3. Conversation Branch as Coordination:**

```lisp
;; Fork a conversation and submit both branches as tasks
(let ((branch-a (fork-context context :name "approach-a"))
      (branch-b (fork-context context :name "approach-b")))
  ;; Write both branches as pending tasks
  (transact! (list
    (make-datom task-a :task/type :explore
                :task/context (context-id branch-a)
                :task/status :pending)
    (make-datom task-b :task/type :explore
                :task/context (context-id branch-b)
                :task/status :pending)))
  ;; Conductor assigns each to different workers
  ;; Results merge back via datom assertions
  )
```

### At Layer 2 (Consolidated CL Plan) — Medium Value

The plan's conductor (Phase 1) already has an event queue and worker management. Linda's patterns can be approximated:

**What the plan already provides:**
- `queue-event` in the conductor → similar to `out()` but not EAV-indexed
- `conductor-active-workers` hash table → worker tracking
- `schedule-action` → deferred execution (like `eval()` for timed tasks)
- `handle-task-result` → result collection

**What's missing for full Linda:**
- No pattern-matching `rd()` over events — events are typed but not attribute-queryable
- No atomic `in()` — work assignment is by the conductor's dispatch logic, not by worker self-selection
- No shared mutable space — each worker gets its task from the conductor, not from a shared tuple space

**The plan's conductor is centralized dispatch, not decentralized coordination.** Linda's value is in enabling workers to self-organize by reading the shared space. The consolidated plan has a central conductor that assigns work. These are fundamentally different coordination models.

**However**, one Linda pattern IS directly applicable to Phase 1: the conductor's event queue could be a tuple space where different event processors claim events based on pattern matching. Instead of the conductor classifying events into "fast" vs "slow" paths and dispatching, events go into a shared space and specialized handlers `take!` the events they know how to handle:

```lisp
;; Instead of:
(defun process-events (conductor)
  (let ((events (drain-event-queue conductor)))
    (dolist (event events)
      (case (getf event :type)
        (:claude-result (handle-claude-result event))
        (:health-check (handle-health-check event))
        ...))))

;; Linda-style:
(defun claim-event (handler-type)
  "Handler self-selects events it can process."
  (take-task! handler-type))
```

But this requires the event queue to be indexed (EAV-style), which the plan doesn't specify.

### At Layer 1 (Current Codebase) — Low Value

The current codebase has:
- `*orchestration-requests*` — a simple list that's pushed/drained. No indexing, no pattern matching.
- `*sub-agents*` — a hash table by agent-id. Only keyed by ID, not queryable by attributes.
- `*event-handlers*` — type-dispatched handler lists. Not a shared space.

None of these are tuple-space-like. They're point-to-point communication channels.

---

## The Path Question: When Does Linda Become Relevant?

### Path A: Consolidated CL Plan Only (Phases 1-7)

Linda remains a theoretical nicety. The conductor is centralized dispatch. Events are typed, not EAV-indexed. Workers don't self-organize. The plan works fine without Linda.

**Linda applicability: Low.** The previous HPC evaluation was correct for this path.

### Path B: Consolidated CL Plan → Substrate Evolution

After the 7 phases complete, the system has:
- LMDB storage (Phase 4-5)
- Conversation turns as entities (Phase 6-7)
- A CL conductor with event queue (Phase 1)
- Content-addressed blob store (Phase 5)

The next natural evolution is:
1. **Upgrade `transact!` with hooks** — the substrate's `register-hook` firing after commits
2. **Add EAV indexes** — EAVT/AEVT over conversation turns (already almost there in Phase 6)
3. **Expose `take!` as a primitive** — atomic claim on the LMDB write path

At this point, the conductor's event queue becomes an LMDB-backed tuple space. Events are datoms. Workers claim events via `take!`. Standing queries fire on new datoms. **Linda emerges naturally from the substrate.**

The substrate-extension-points document (`substrate-extension-points.md:217-296`) describes exactly this evolution:

```
Extension Point           What Modules Can Do With It
─────────────────────────────────────────────────────
define-index              Register additional LMDB named databases
register-hook             on-transact callbacks receiving datoms
define-tool               Register tools for Claude/MCP
define-entity-type        Declare entity types
define-query-operator     Register custom query operators
define-adapter            Register adapters with lifecycle
```

With `register-hook` + `define-index` + `transact!` retraction semantics, Linda's four operations are all expressible. No special "Linda module" needed — it's just the substrate used a certain way.

### Path C: Direct Substrate Build

Build the substrate first (as `substrate-decomposition.md` Phase 1 proposes: Store + Transact + Query in ~500 LOC), then build the consolidated CL modules on top. In this path, Linda is available from day one because the datom store IS the tuple space.

**This is the most ambitious path** but also the most architecturally clean. The consolidated CL plan's Phases 4-7 (LMDB, blobs, turns, wiring) would be implemented as substrate modules rather than standalone code.

---

## The Specific Mapping: Linda Operations → Substrate Primitives

For completeness, here's the precise mapping assuming the substrate from `substrate-decomposition.md` exists:

### `out(tuple)` → `transact!`

```lisp
;; Linda: out(("task", "classify", pod-data, "pending"))
;; Substrate:
(transact!
  (list (make-datom task-id :task/type :classify)
        (make-datom task-id :task/payload-hash (store-blob pod-data))
        (make-datom task-id :task/status :pending)
        (make-datom task-id :task/created-at (get-universal-time))))
```

The datom form is more expressive than Linda's flat tuple: each attribute is separately indexed and queryable.

### `rd(pattern)` → Index Scan

```lisp
;; Linda: rd(?, "task/type", "classify")
;; Substrate:
(query '(:find ?task
         :where [?task :task/type :classify]))

;; With additional constraints:
;; Linda: rd(?, "task/type", "classify", "pending")
;; Substrate (multi-attribute join):
(query '(:find ?task
         :where [?task :task/type :classify]
                [?task :task/status :pending]))
```

The substrate query is strictly more powerful than Linda's pattern matching because it supports multi-attribute joins, temporal queries, and recursive rules (if Datalog is implemented).

### `in(pattern)` → Atomic Claim via Transact

```lisp
;; Linda: in(?, "task/type", "classify", "pending")
;; Substrate: query + retract/assert in single LMDB write txn

(defun take! (task-type)
  "Atomic Linda in() — find and claim a task."
  (lmdb:with-txn (:write t)
    ;; Read within write txn for isolation
    (let ((task (query-in-txn '(:find ?task
                                :where [?task :task/type ,task-type]
                                       [?task :task/status :pending]
                                :limit 1))))
      (when task
        ;; Retract :pending, assert :in-progress — same txn
        (transact-in-txn!
          (list (make-datom (entity-id task) :task/status :pending
                            :added nil)  ; retract
                (make-datom (entity-id task) :task/status :in-progress
                            :added t)))  ; assert
        task))))
```

This is LMDB's single-writer guarantee providing the atomicity that Linda's `in()` requires. Multiple workers calling `take!` concurrently are serialized by LMDB's write lock — only one succeeds per call, and the rest see the updated status.

### `eval(expr)` → Spawn + Transact

```lisp
;; Linda: eval(classify, pod-data) → writes result tuple when done
;; Substrate:
(spawn "classifier"
  (lambda (actor)
    (let ((result (classify-entity pod-data)))
      (transact!
        (list (make-datom task-id :task/status :complete)
              (make-datom task-id :task/result result)
              (make-datom task-id :task/completed-at (get-universal-time)))))))
```

The `spawn` + `transact!` combination gives Linda's `eval()` plus full audit trail (the result is a datom with temporal history).

---

## What This Means for the Consolidated CL Plan

### No Changes to Phases 1-3 (Conductor, Claude Worker, LFE Removal)

These phases don't need Linda. The conductor is centralized dispatch, which is simpler and sufficient for the current workload (1-10 concurrent workers).

### Phases 4-5 (LMDB, Blob Store): Lay the Foundation

When implementing LMDB storage, two design choices affect future Linda capability:

1. **Include retraction in the data model.** Even if Phase 4 stores snapshots as blobs, the metadata indexes (by-agent, by-timestamp) should support retraction (old metadata replaced when snapshot is superseded). This costs nothing now and enables `in()` later.

2. **Make `transact!` a first-class function with hook dispatch.** Instead of directly calling `lmdb:put`, route all writes through a `transact!` that:
   - Takes a list of write operations
   - Executes them in a single LMDB write txn
   - Fires registered hooks after commit

   This is the substrate's `transact!` pattern. It costs ~20 extra lines and unlocks `register-hook` for free.

### Phases 6-7 (Turns, Contexts): The Linda Threshold

The Turn/Context DAG model stores turns as entities with attributes (`:turn/role`, `:turn/parent`, `:turn/content-hash`, etc.). This IS EAV over a small schema. When you query turns by role, by time range, or by context — you're doing Linda `rd()` over the turn space.

If the conductor needs to distribute work (e.g., "process all unanalyzed turns for learning patterns"), the `take!` pattern becomes natural:

```lisp
;; Conductor finds turns that need learning analysis
(defun claim-unanalyzed-turn ()
  (take! :unanalyzed-turn))

;; Where:
;; [?turn :turn/analyzed nil]
;; [?turn :turn/role :assistant]
;; becomes the pattern for take!
```

### Post-Phase 7: Substrate Emergence

If the Turn/Context model proves its value, the natural next step is generalizing it: all entities (not just turns) stored as datoms with the same `transact!` / `query` / `take!` interface. At that point, the substrate has emerged bottom-up from the consolidated CL plan — not by building it top-down from the thinking repo's vision, but by generalizing what the plan already built.

---

## Comparison: Prior Evaluations vs This Analysis

### Previous HPC Evaluation (2026-02-16-hpc-lisp-optimization-evaluation.md)

Classified Linda (#7) as:
> "**Future work (not current plan scope).**"
> "The plan's conductor manages a small number of Claude CLI workers (rate-limited). The Linda `take!` pattern for atomic task consumption would be relevant if the system grows to dozens of workers processing classification or analysis tasks. Not needed for the current plan."

**This was correct for the 7-phase plan as written**, but missed the broader point: Linda is not just a coordination optimization — it's an architectural principle that emerges naturally from the substrate's datom model. The evaluation correctly identified the gap (no EAV store in the plan) but didn't trace the path from plan to substrate.

### Previous Thinking-Repo Evaluation (2026-02-16-thinking-repo-ideas-evaluation.md)

Classified Linda (#7) as "Medium" relevance:
> "The work-queue pattern (`take-task!`) maps to conductor work distribution. Datom store as coordination medium between cognitive workers is genuinely useful."

**This was more accurate** — it recognized the mapping to conductor work distribution. But it still evaluated against the current plan rather than the substrate path.

### This Analysis

Linda's value depends entirely on which architectural path is taken:
- **Path A (plan only):** Low value — the conductor handles coordination
- **Path B (plan → substrate):** High value — Linda emerges from the datom model
- **Path C (substrate first):** Built-in — Linda IS the datom store's coordination API

The user's question points to Path B or C. The substrate documents assume it. The consolidated plan doesn't preclude it — it just doesn't build it yet.

---

## The Meta-Point: Substrate as Coordination Medium

The deepest insight from the Linda mapping is not the specific operations (`out`, `rd`, `in`, `eval`) but the **philosophical shift**: the data store becomes a coordination medium, not just a persistence layer.

In the current codebase, coordination is explicit:
- Conductor dispatches to workers via hash table lookup
- Workers report back via `handle-task-result` callback
- Events fire through typed handler dispatch
- Sub-agents are tracked in a separate `*sub-agents*` registry

With the substrate, coordination is implicit:
- Writers put datoms. Readers find datoms. Claimers take datoms.
- The store IS the coordination medium. No separate dispatch logic needed.
- New coordination patterns emerge from new datom schemas, not new code.

This is Gelernter's original insight: the tuple space IS the programming model. Processes don't communicate point-to-point; they communicate through shared associative memory. The substrate's datom store, with its indexes and hooks, IS that shared associative memory.

## Code References

- `src/integration/builtin-tools.lisp:14` — `*orchestration-requests*` list (current coordination primitive)
- `src/integration/builtin-tools.lisp:11-12` — `*sub-agents*` hash table (current worker registry)
- `src/integration/builtin-tools.lisp:443-450` — `queue-orchestration-request` / `drain-orchestration-requests` (current queue-drain pattern — opposite of Linda self-selection)
- `src/integration/events.lisp:120-134` — Event bus globals (type-dispatched, not EAV-indexed)
- `src/integration/events.lisp:136-168` — `emit-integration-event` (fire-and-forget, no `in()` semantics)
- `src/snapshot/event-log.lisp:37-49` — Append-only event log (Linda `out()` without `in()`)
- `src/snapshot/content-store.lisp:30-41` — Content-addressed store (blob `out()`/`rd()`, no `in()`)

## Architecture Documentation

### Current Coordination Model (Centralized Dispatch)

```
Conductor ──dispatch──→ Worker A
           ──dispatch──→ Worker B
           ──dispatch──→ Worker C

Workers report back to conductor via callbacks.
Conductor assigns work. Workers don't self-select.
```

### Linda Coordination Model (Decentralized via Shared Space)

```
                    ┌─────────────────┐
Worker A ──take!──→ │                 │ ←──out──── Producer X
Worker B ──take!──→ │  Datom Space    │ ←──out──── Producer Y
Worker C ──take!──→ │  (LMDB + EAV)  │ ←──out──── Producer Z
                    │                 │
Standing Queries ←──│  (hooks fire)   │
                    └─────────────────┘

Workers self-select work by pattern matching.
Producers don't know about workers.
Coordination is emergent from the shared space.
```

### Hybrid Model (Plan Phase 1 Conductor + Future Linda)

```
Conductor ──schedule──→ Timer Heap
           ──queue────→ Event Space (LMDB-backed)

Event Space:
  ├── Workers take! events by type
  ├── Hooks fire on new events
  └── History preserved as datoms

Conductor handles scheduling (what runs when).
Event Space handles coordination (who handles what).
```

## Related Research

- `thoughts/shared/research/2026-02-16-hpc-lisp-optimization-evaluation.md` — Prior HPC evaluation (Linda classified as "Future work")
- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Prior evaluation (Linda rated "Medium")
- `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` — Gap between substrate vision and current AP
- `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` — The 7-phase plan being implemented
- `~/projects/thinking/substrate-decomposition.md` — Full substrate architecture with datom model
- `~/projects/thinking/substrate-extension-points.md` — Extension points (register-hook, define-index, etc.)
- `~/projects/thinking/hpc-lisp-optimization-ideas.md` — Linda section (#7, lines 293-323)

## Open Questions

1. **Which path is intended?** The consolidated CL plan and the substrate vision are different architectures. The plan is pragmatic (blob storage, centralized conductor). The substrate is ambitious (datom store, decentralized coordination). Are the 7 phases the destination, or a stepping stone toward the substrate?

2. **Can `transact!` be introduced in Phase 4 without full EAV?** A minimal `transact!` that wraps LMDB writes, fires hooks after commit, but doesn't require full datom decomposition would lay the foundation for Linda without the cost of EAV. Writes would still be key-value (snapshot-id → blob), but the hook infrastructure would be in place.

3. **Is centralized dispatch a liability?** The conductor's centralized dispatch is simpler but less resilient. If the conductor thread dies, all coordination stops. With Linda/tuple-space coordination, any worker can claim work independently — the single point of failure is LMDB (which is crash-safe), not a thread.

4. **When does the scale justify Linda?** Linda's value scales with the number of concurrent workers and the diversity of task types. At 1-3 workers doing the same thing (run Claude CLI), centralized dispatch is fine. At 10+ workers doing heterogeneous tasks (classification, analysis, learning, monitoring), Linda's self-selection is dramatically simpler than centralized dispatch logic.
