---
date: 2026-02-16T20:30:00-08:00
researcher: Claude Code
git_commit: 783cd02
branch: main
repository: autopoiesis
topic: "Evaluation of ~/projects/thinking Ideas Against Current Autopoiesis + Cortex Codebase"
tags: [research, architecture, evaluation, substrate, lmdb, eav, cortex, bubble, mop, clock-code, defsystem, rete, datalog]
status: complete
last_updated: 2026-02-16
last_updated_by: Claude Code
last_updated_note: "Complete rewrite with deep evaluation of all 9 design-improvements, 20 HPC/CS/Lisp-history ideas, and architectural synthesis"
---

# Evaluation: ~/projects/thinking Ideas for Autopoiesis

**Date**: 2026-02-16T20:30:00-08:00
**Researcher**: Claude Code
**Git Commit**: 783cd02
**Branch**: main
**Repository**: autopoiesis

## Research Question

The `~/projects/thinking` repository contains 13 documents (9 analysis docs + 5 conversation docs) exploring ideas for a "Substrate" — a unified data foundation merging infrastructure introspection (Cortex), knowledge management (Bubble CL), and agent cognition (Autopoiesis). Evaluate each idea against the current codebase state and determine what's worth pursuing.

---

## Executive Summary

The thinking repo describes a **coherent and ambitious vision**: extract common patterns from three CL projects into a shared "Substrate" layer based on LMDB-backed EAV datoms, with declarative reactive systems (`defsystem`), scoped indexes, content-addressed blobs, and CL's condition/restart system for self-healing. It draws deep inspiration from ECS architecture, 1980s Lisp AI (Rete, TMS, frame systems), and modern HPC techniques.

**The core tension**: Autopoiesis is a cognitive agent framework. The thinking repo designs primarily for infrastructure introspection. Most ideas are solutions to Cortex's problems, not AP's. But several ideas are genuinely cross-cutting and would improve AP directly.

### Tier 1: Do Now (High Value, Feasible)

| Idea | Source | Why |
|------|--------|-----|
| **LMDB snapshot storage** | `performance-analysis.md`, `lmdb-storage-analysis.md` | Eliminates GC pressure, crash-safe, persistent event log, enables time-travel queries |
| **CL-native conductor** | `lisp-and-beam-architecture-analysis.md`, `lfe-control-plane-analysis.md` | Eliminates polyglot tax, activates dormant CL cognitive engine |
| **Content-addressed blob storage** | `design-improvements.md` (Improvement 8) | Store full LLM responses/tool outputs as blobs, metadata as datoms. 10x fewer writes for large payloads |
| **Conversation branching (Turn/Context DAG)** | `design-improvements.md` (Improvement 9), `cxdb-comparison.md` | O(1) conversation forking, cross-domain queryable, reactive. This IS AP's use case |

### Tier 2: Do When Needed (Medium Value, Defer)

| Idea | Source | Why |
|------|--------|-----|
| **EA-CURRENT index** | `design-improvements.md` (Improvement 2) | Only matters if LMDB EAV is adopted; 100x faster entity state reconstruction |
| **Scoped indexes** | `design-improvements.md` (Improvement 3) | Only matters with multi-domain store; prevents cross-module write penalty |
| **Condition/restart vocabulary** | `design-improvements.md` (Improvement 7) | AP already has 6 restarts + recovery system; extend when needed for adapter error handling |
| **Batched write channel** | `design-improvements.md` (Improvement 5) | Only matters at high write volumes; AP's cognitive pace is slow |

### Tier 3: Skip (Solutions to Wrong Problem)

| Idea | Source | Why |
|------|--------|-----|
| **Bitemporal EAV** | `infrastructure-introspection-architecture.md` | Valid-time vs tx-time matters for infra discovery lag, not agent cognition |
| **MOP schema specialization** | `substrate-extension-points.md` | Solves unknown-entity-type problem (Cortex), not AP's fixed cognitive primitives |
| **defadapter macro** | `lisp-and-beam-architecture-analysis.md` | AP doesn't watch external infrastructure |
| **SoA columns** | `ecs-relevance.md` | Optimization for standing queries over 10K+ entities; AP has dozens, not thousands |
| **Cortex+AP+Bubble unification** | `substrate-decomposition.md` | MCP bridge provides sufficient integration. Full unification is a product decision |

### Tier 4: Fascinating But Premature

| Idea | Source | Why |
|------|--------|-----|
| **Rete algorithm for defsystem** | `hpc-lisp-optimization-ideas.md` (#1) | Multi-entity join rules are powerful but AP has no standing query infrastructure to optimize |
| **Truth Maintenance System** | `hpc-lisp-optimization-ideas.md` (#2) | Derived-fact tracking is genuinely novel for infrastructure but AP's facts are direct observations |
| **Datalog query language** | `hpc-lisp-optimization-ideas.md` (#9) | Beautiful and native to EAV, but requires the EAV store first |
| **SERIES query fusion** | `hpc-lisp-optimization-ideas.md` (#3) | Eliminates intermediate allocation; only matters at scale |
| **Partial evaluation (Futamura)** | `hpc-lisp-optimization-ideas.md` (#11) | Compiled queries are fast but CL `compile` makes this easy when needed |

---

## Detailed Evaluations

### 1. Design Improvements (design-improvements.md)

#### Improvement 1: Declaration-Driven Dispatch (`defsystem`)

**The idea**: Replace imperative `register-hook` callbacks with declarative `defsystem` forms that specify entity types, watched attributes, and access patterns. The framework builds a dispatch table for O(1) routing.

**Current AP state**: `src/integration/events.lisp:120-168` has a pub/sub event bus with type-specific handler lists. Handlers are plain lambdas. No filtering by attribute or entity type — all handlers of a given event type receive all events.

**Evaluation**: The `defsystem` concept is architecturally superior to plain hooks. The dispatch table optimization (attribute → system lookup) is real. But AP's event bus handles ~13 event types at cognitive-loop frequency (not thousands of events/second). The overhead of plain handler dispatch is negligible.

**However**: If AP adopts LMDB and conversation branching (Tier 1 items), a `defsystem`-like declaration for "watch this conversation for tool failures" or "monitor agent learning patterns" becomes natural. The macro could be a thin layer over the existing event bus.

**Verdict**: **Defer, but keep the design.** If the conversation model is adopted, `defsystem` is the right API for reactive conversation monitoring.

---

#### Improvement 2: EA-CURRENT Index

**The idea**: A substrate-level index storing only the latest value per (entity, attribute), using LMDB's `:replace` strategy. Turns full entity reconstruction from O(attributes × history_depth) to O(attributes).

**Current AP state**: Snapshots are full state captures (`snapshot/snapshot.lisp:11-36`). Entity state reconstruction doesn't traverse history — you just load the snapshot. Time-travel uses parent-pointer walks, not EAV scans.

**Evaluation**: This optimization matters when you decompose entity state into EAV datoms and need to reconstruct "current state" frequently. AP's snapshot model avoids this entirely. But if cognitive state is stored as datoms (individual thoughts, decisions, observations as separate entities with attributes), the EA-CURRENT index becomes essential for "what is the agent's current belief about X?"

**Verdict**: **Adopt if EAV datoms are used for cognitive state.** If snapshots remain as blobs, this is irrelevant.

---

#### Improvement 3: Scoped Indexes

**The idea**: `define-index` with a `:scope` predicate. Only matching datoms are written to the index, avoiding cross-module write penalty.

**Current AP state**: No LMDB indexes. The single "index" is the in-memory hash table in `snapshot/persistence.lisp:176-189`.

**Evaluation**: Only relevant in a multi-domain scenario (infrastructure + knowledge + cognition in one store). AP standalone has one domain. But the design is elegant and the implementation cost is trivial (one predicate check per datom per index).

**Verdict**: **Include in any LMDB design as a forward-looking capability.** Zero cost to implement; significant value if AP ever shares a store with Cortex.

---

#### Improvement 4: `define-entity-type`

**The idea**: A single macro that generates schema metadata, AVET index entries, column arrays, MOP class definitions, and validation functions from a type declaration.

**Current AP state**: Entity types are plain `defclass` definitions with fixed slots. `agent.lisp:11-40`, `snapshot/snapshot.lisp:11-36`, `core/cognitive-primitives.lisp:14-130`.

**Evaluation**: This is the ECS-inspired idea (from `ecs-relevance.md`) applied to the data layer. It's powerful for infrastructure entities with dozens of attributes, but AP's cognitive primitives are well-defined and don't need runtime schema generation.

**Where it DOES apply**: If AP represents conversation turns as entities (Improvement 9), `define-entity-type :turn` would generate validation, MOP caching, and queryable indexes for turn metadata (role, model, tokens, tool calls). This is genuinely useful.

**Verdict**: **Adopt for conversation entities.** Skip for existing cognitive primitives.

---

#### Improvement 5: Batched Write Channel (`submit!`)

**The idea**: Buffer datoms and flush as batch transactions for throughput.

**Current AP state**: No write batching. Event log appends are synchronous (`snapshot/event-log.lisp:40-43`). Snapshot saves are individual file writes (`snapshot/persistence.lisp:98-124`).

**Evaluation**: At cognitive pace (1-2 thoughts/second), batching is irrelevant. At Claude API response speed (seconds per turn), even more irrelevant. This matters for Cortex's K8s polling (hundreds of events/second) or OTEL spans (100K/second).

**Verdict**: **Skip.** Synchronous `transact!` is fine for AP's throughput profile.

---

#### Improvement 6: Entity State Cache

**The idea**: In-memory write-through cache (entity-id → hash-table of attributes) for 100ns lookups.

**Current AP state**: LRU cache for snapshots (`snapshot/lru-cache.lisp:12-124`, 1000-entry capacity with hit/miss stats). No per-attribute caching.

**Evaluation**: The existing LRU cache serves the same purpose — hot snapshots are in memory. The per-attribute cache is more granular and better for `defsystem` callbacks that need one attribute. But AP's access patterns are "load full snapshot" not "check one attribute of one entity."

**Verdict**: **Skip.** The existing LRU cache is appropriate for AP's access patterns.

---

#### Improvement 7: Condition/Restart Vocabulary

**The idea**: Standard condition hierarchy: `unknown-entity-type`, `validation-error`, `adapter-error`, `authentication-expired`, `rate-limited`.

**Current AP state**: Already rich. `src/core/recovery.lisp` defines 4 condition tiers, 6 standard restarts, recovery strategies with priority, graceful degradation levels (`:minimal`, `:offline`, `:read-only`), component health tracking, and automatic degradation triggers. 853 lines.

**Evaluation**: AP already has the most complete condition/restart system of the three projects. The thinking repo's vocabulary adds infrastructure-specific conditions (adapter errors, authentication, rate limiting) that don't apply to cognitive agents. But the pattern — conditions as a composable error vocabulary — is exactly what AP already does.

**Possible extension**: `authentication-expired` and `rate-limited` would apply to Claude API calls. AP could define:
```lisp
(define-condition claude-rate-limited (transient-error)
  ((retry-after :initarg :retry-after))
  (:restarts
    (wait-and-retry () "Wait and retry")
    (use-cached-response () "Use last known response")
    (reduce-context () "Retry with smaller context window")))
```

**Verdict**: **Extend existing system with Claude-specific conditions.** Don't replace what exists.

---

#### Improvement 8: Content-Addressed Blob Storage

**The idea**: Store large payloads (LLM responses, YAML manifests, tool outputs) as content-addressed blobs (BLAKE3 hash → compressed bytes). Reference from datoms via hash.

**Current AP state**: Content-addressable hashing exists (`core/s-expr.lisp:81-113`, SHA-256 via ironclad). But it hashes entire S-expression trees, not individual payloads. No blob store separate from snapshot store.

**Evaluation**: **This is directly applicable to AP.** Claude responses are 1-8KB of text. Tool outputs can be larger. Storing these as blobs with queryable metadata as datoms is dramatically more efficient than embedding them in S-expression snapshots.

The current snapshot model serializes everything inline:
```lisp
;; Current: full response embedded in snapshot
(agent-state
  (last-response "Here is a 4KB analysis of your codebase..."))

;; Better: blob reference in snapshot, content-addressed
(agent-state
  (last-response-hash "blake3:abc123"))  ; → blob store
```

**With LMDB**: Blob store is a dedicated LMDB database. Zstd compression at level 3 gives 3-4x compression on LLM responses. Content addressing deduplicates identical tool outputs (e.g., same `git status` run multiple times).

**Verdict**: **Do this.** Natural complement to LMDB adoption (Tier 1). Directly reduces storage for the most voluminous data AP produces.

---

#### Improvement 9: Conversation Branching (Turn/Context DAG)

**The idea**: Represent conversations as entities. Turns have parent pointers forming a DAG. Contexts are mutable pointers to branch heads. Fork = create new Context pointing to existing Turn. O(1), no data copying.

**Current AP state**: The snapshot DAG (`snapshot/branch.lisp:11-69`) provides conceptually similar branching at the cognitive-state level. But it captures **all** agent state, not individual conversation turns. There's no way to say "fork this conversation at turn 5 and try a different approach" — you'd fork the entire agent state.

**Evaluation**: **This is the highest-value idea in the entire thinking repo for AP specifically.** The Turn/Context model IS the agent cognition use case:

1. Agent has a conversation with Claude. Turn 10 goes wrong. Fork at Turn 9, try different prompt.
2. Agent is exploring a problem. Branch the conversation: one branch investigates approach A, another investigates approach B. Compare results.
3. Human reviews agent work. "Go back to Turn 5 and redo from there with this additional context."

The datom representation is clean:
- Turn entity: `:turn/parent`, `:turn/role`, `:turn/content` (blob ref), `:turn/model`, `:turn/tokens`, `:turn/tool-use` (blob ref)
- Context entity: `:context/head` (turn ref), `:context/name`, `:context/agent`

Cross-domain queries are free if Cortex is accessible:
```lisp
;; "Show me conversations where the agent discussed the pod failure"
(query '(:find ?turn :where
         [?turn :turn/role :assistant]
         [?turn :turn/created-at ?t]
         [?pod :k8s.pod/phase :failed]
         [(temporal-overlap ?t ?pod-time)]))
```

**Standing queries on conversations** enable reactive cognition:
```lisp
(defsystem :learning-extractor
  (:entity-type :turn
   :watches (:turn/role :turn/content))
  (:on-change (entity datoms)
    (when (eq (entity-attr entity :turn/role) :assistant)
      (extract-patterns entity))))
```

**Verdict**: **Do this.** This is what makes AP a *conversational* agent framework, not just a cognitive state machine. It directly enables the Jarvis use case (branching strategies, replaying with modifications, learning from conversation history).

---

### 2. Performance Analysis (performance-analysis.md)

This document provides the rigorous performance math for the datom model vs. blob model. Key findings relevant to AP:

**Full entity state reconstruction**: O(attributes × history_depth) for datoms vs O(1) for blobs. AP's snapshot model is blobs. If AP decomposes state into datoms, the EA-CURRENT index (Improvement 2) is essential.

**GC wins**: "Data outside the CL heap" is the biggest win. LMDB's mmap keeps entity data out of GC. AP's current snapshot store loads S-expression trees onto the CL heap. With 1000 cached snapshots × ~2KB each = 2MB of GC-traced data. Not huge, but it grows with agent activity.

**Single-writer throughput**: At 1000 tx/sec, LMDB has 100,000x headroom for AP's cognitive pace (~1 tx/sec). No contention concerns.

**Verdict**: The performance analysis confirms LMDB is appropriate for AP. The datom model's costs (write amplification, entity reconstruction) are bounded and manageable at AP's scale. The GC benefit is real even for small workloads.

---

### 3. ECS Relevance (ecs-relevance.md)

Establishes the structural equivalence: Datom ≈ ECS with time. Entity = Entity. Component = Attribute. System = Standing Query. Both decompose state into entity-attribute-value triples.

**Key insight for AP**: The `defsystem` macro from cl-fast-ecs (already used in `src/holodeck/systems.lisp:47-88`) captures data access patterns declaratively. AP already uses this for 3D visualization. The same pattern applied to conversation monitoring would be natural:

```lisp
;; Already exists in holodeck:
(defsystem movement-system
  (:components-rw (position3d velocity3d))
  (incf position3d-x (* velocity3d-dx *delta-time*)))

;; Proposed for conversation monitoring:
(defsystem tool-failure-monitor
  (:entity-type :turn
   :watches (:turn/tool-use :turn/role)
   :access :read-only)
  (:on-change (entity datoms)
    (when (tool-failed-p entity)
      (flag-for-retry entity))))
```

**SoA columns**: Irrelevant for AP (tens of entities, not thousands). The "three tiers of access" model (LMDB → entity cache → CLOS slots) is the right mental model even if AP only uses the first two tiers.

**Verdict**: The `defsystem`-as-standing-query idea is the actionable takeaway. SoA/SIMD is for Cortex-scale workloads.

---

### 4. HPC/CS Theory/Lisp History Ideas (hpc-lisp-optimization-ideas.md)

This is the most creative document, drawing from Rete (1979), TMS (1979), SERIES (1989), frame systems (1980s), Lisp Machines, Connection Machine, Linda tuple spaces, CLIM, Datalog, Bloom filters, Futamura projections, interval trees, Merkle trees, ART, huge pages, NUMA, lock-free queues, vectorized predicates, work stealing, and temporal compression.

**Evaluated per-idea for AP relevance:**

| # | Idea | AP Relevance | Notes |
|---|------|-------------|-------|
| 1 | **Rete algorithm** | Low | Multi-entity join rules require standing query infra AP doesn't have |
| 2 | **Truth Maintenance (TMS)** | Medium | Derived facts with dependency tracking could track agent beliefs ("I believe X because I observed Y"). But AP doesn't currently model belief justification chains |
| 3 | **SERIES fusion** | Low | Query volumes too small to benefit from zero-allocation pipelines |
| 4 | **Frame systems / auto-classification** | Medium | Automatic entity classification (port 6379 → Redis) is Cortex's problem. But declarative classifiers for cognitive primitives could be useful: "this thought pattern looks like a decision" |
| 5 | **Lisp Machine GC / arena allocation** | Low | AP's GC pressure is minimal. Arena allocation for `transact!` only matters at high throughput |
| 6 | **Connection Machine / data-parallel** | Low | AP has dozens of entities, not millions |
| 7 | **Linda tuple spaces** | Medium | The work-queue pattern (`take-task!`) maps to conductor work distribution. Datom store as coordination medium between cognitive workers is genuinely useful |
| 8 | **CLIM presentation types** | Medium | Enriched entity rendering (commands, related entities) would make the SSE/web layer more useful. Low effort to add to `define-entity-type` |
| 9 | **Datalog** | High (if EAV adopted) | The natural query language for EAV datoms. Homoiconic in CL. Guaranteed termination. Recursive queries enable "find all conversations that influenced this decision" |
| 10 | **Bloom filters** | Low | 200K entities needed before useful. AP has dozens |
| 11 | **Partial evaluation (Futamura)** | Medium | Compiled standing queries via CL `compile`. Easy to implement, meaningful for hot queries |
| 12 | **Interval trees** | Low | Temporal range queries over conversation history. LMDB prefix scans are sufficient |
| 13 | **Merkle trees** | Low | State sync between instances. AP is single-node |
| 14 | **Adaptive Radix Trees** | Low | Hash tables are fine for AP's attribute vocabulary (~50 distinct attributes) |
| 15 | **Huge pages** | Low | AP's LMDB will be <100MB for years |
| 16 | **NUMA** | Low | Single-socket machines for AP |
| 17 | **Lock-free write channel** | Low | One writer (cognitive loop) at AP's pace |
| 18 | **Vectorized predicates** | Low | SoA columns needed first; AP volumes too small |
| 19 | **Work stealing** | Low | Parallel query evaluation overkill for AP |
| 20 | **Temporal compression** | Low | AP data volumes are tiny |

**The winners for AP**: Datalog (#9) if EAV is adopted, TMS (#2) for belief justification, Linda (#7) for work coordination, CLIM (#8) for presentation enrichment.

**The meta-observation is accurate**: The substrate unconsciously recapitulates 1980s Lisp AI. Datoms = frames/slots. Hooks = slot daemons. Standing queries = production rules. Classification = frame classification. The lineage is real and the patterns are proven.

---

### 5. Substrate Decomposition (substrate-decomposition.md)

**The grand vision**: Extract shared patterns into `:substrate` (~1,500-2,000 LOC), with `:cortex`, `:bubble`, and `:apiosis` as modules.

**Current reality check**:

| Proposed Substrate Component | Exists in AP? | Exists in Cortex? | Shared? |
|-----|-----|-----|-----|
| LMDB store | No (file-based) | Yes (`lmdb-env.lisp`) | Could share |
| Term interning | No | No (string keys) | New code |
| Key encoding | No | Partial (`encode-u64-be`) | New code |
| Datom struct | No | `trace-event` (similar) | Redesign |
| `transact!` | No | `persist-event` (similar) | Redesign |
| Query DSL | No | Yes (`query/parser.lisp`) | Could share |
| Entity state | Snapshot-based | Event replay | Different models |
| Hooks | Event bus | Alerting detector | Different patterns |
| Actors | No (explicit locks) | Write buffer (producer-consumer) | Different patterns |
| Scheduler | No | Adapter polling | Cortex-specific |
| Sandbox | Yes (extension-compiler) | No | AP-unique |
| Claude client | Yes (claude-bridge) | Via MCP | Different approaches |
| Tools | Yes (builtin-tools) | Yes (MCP tools) | Could share framework |
| MCP | Yes (mcp-client) | Yes (mcp-server.py) | Complementary |
| SSE/web | No | Yes (dashboard) | Cortex-specific |
| REPL | SWANK | SWANK | Already shared |

**Assessment**: About 30% of the proposed substrate would be genuinely shared code (LMDB, query DSL, tool framework, REPL extensions). The other 70% would be new code serving the unified vision. The "extract from three projects" framing understates the new design work needed.

**The honest question**: Is it worth building the shared substrate, or should AP and Cortex evolve independently and integrate via MCP?

**My assessment**: MCP integration is sufficient for the current use case (agent queries infrastructure). The substrate is the right answer if you want cross-domain queries ("show me conversations about pods that were failing") — but that requires both systems to share a data model, which is a larger commitment.

---

### 6. CXDB Comparison (cxdb-comparison.md)

The most directly relevant document for AP. CXDB is a purpose-built AI context store with:
- **Turn DAG**: Parent pointers, O(1) branching — exactly what AP needs
- **Content-addressed blobs**: BLAKE3 + Zstd compression — applicable
- **Binary protocol**: Purpose-built for high-throughput turn appending — overkill for AP
- **Type registry**: Schema evolution via numeric tags — different approach from CL macros

**What AP should steal** (and the doc says the same):
1. **Context/Turn branching model** as datom entities (Improvement 9)
2. **Content-addressed blob storage** with compression (Improvement 8)
3. **The hybrid approach**: queryable metadata as datoms, bulk content as blobs

**What AP doesn't need**:
- Binary wire protocol (in-process is fine)
- Multi-language SDKs (CL-only)
- React visualization (HTMX or terminal timeline is appropriate)

---

## Synthesis: What the Thinking Repo Gets Right

### 1. The Simplification Trajectory

The 5-conversation arc (Rust → CL → LMDB → Archil) is a genuine insight path. Each step removes complexity while preserving capability. The endpoint — "CL + LMDB on a mount point" — is elegant and practical.

### 2. LMDB as the Right Storage Layer

The performance math holds up. LMDB gives: crash safety, zero-copy reads, MVCC concurrent readers, data outside GC, and the full B+ tree for ordered queries. The `lmdb` Quicklisp package exists. The migration from file-based snapshots is straightforward.

### 3. Content-Addressed Blobs as Complement to Datoms

Not everything should be decomposed into attributes. LLM responses, tool outputs, and YAML manifests should be blobs. The hybrid (queryable metadata as datoms + bulk content as blobs) is the correct design.

### 4. Conversation Branching as First-Class Primitive

This is the killer feature for AP. CXDB's Turn/Context model mapped to datoms gives AP conversation-level time-travel, branching, and cross-domain querying. No other agent framework has this.

### 5. The Condition System as Composable Error Vocabulary

AP already implements this well. The thinking repo's vocabulary extensions (infrastructure-specific conditions) validate AP's approach and suggest domain-specific extensions for Claude API error handling.

---

## What the Thinking Repo Gets Wrong (for AP)

### 1. Infrastructure-Centric Framing

The substrate design optimizes for infrastructure introspection: high event throughput, unknown entity types, standing queries over streaming data, MOP specialization for runtime-discovered schemas. AP's domain is different: low event throughput, known entity types, retrospective queries, fixed cognitive primitives.

### 2. "Three Projects Into One" Overestimates Code Reuse

The decomposition document claims ~30% overlap between AP, Cortex, and Bubble. In practice, the data models are fundamentally different (S-expression trees vs flat events vs RDF triples). A unified datom model would require redesigning all three, not extracting shared code.

### 3. Premature Optimization

Many ideas (SoA columns, SIMD vectorization, NUMA pinning, huge pages, lock-free queues) are HPC optimizations for workloads 1000x larger than AP produces. The cognitive pace is 1-2 events/second. The LMDB single-writer has 100,000x headroom.

### 4. Missing the Actual Bottleneck

The thinking repo designs storage, query, and reactive layers. AP's actual bottleneck is that the CL cognitive engine sits dormant while Claude CLI does all the work. The most impactful change isn't a better data model — it's activating the existing CL brain (CL-native conductor).

---

## Recommended Action Plan

### Phase A: CL-Native Conductor (Highest Priority)

Replace LFE orchestration with CL conductor running inside the AP process. This unlocks everything else.

**Key files to leverage**:
- `src/integration/claude-bridge.lisp:174-226` — existing `agentic-loop`
- `src/core/recovery.lisp:159-199` — 6 standard restarts for supervision
- `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md` — CL conductor design

**Estimated scope**: ~300-400 lines of new CL code replacing ~1,600 lines of LFE.

### Phase B: LMDB + Blob Storage

Replace file-based snapshots with LMDB. Add content-addressed blob storage for LLM responses and tool outputs.

**Key design decisions**:
- Store snapshots as blobs (not EAV datoms) initially — preserves S-expression fidelity
- Add blob database for large payloads (Zstd compressed, BLAKE3 addressed)
- Add metadata indexes (by agent-id, by timestamp, by snapshot type)
- Persist event log in LMDB transaction log

**Estimated scope**: ~600-800 lines replacing ~400 lines of file I/O.

### Phase C: Conversation Branching

Implement Turn/Context DAG model on LMDB.

**Design**:
- Turn entity stored as datoms (metadata) + blob (content)
- Context entity with `:context/head` pointer
- `append-turn`, `fork-context`, `conversation-history` operations
- Standing query for conversation monitoring (optional `defsystem`)

**Estimated scope**: ~400-500 lines of new code.

### Phase D: Activate Cognitive Features

With the conductor running in CL and conversation history in LMDB:

1. Every agent action creates a conversation turn (automatic history)
2. Fork conversations to explore alternative approaches
3. Self-extension: agent writes new tools via existing extension compiler
4. Learning: pattern extraction from conversation history across branches
5. Time-travel: replay any conversation branch with modifications

**This is the endgame**: A self-modifying, conversation-branching, time-traveling cognitive agent system in a single CL process.

---

## Architecture: Current vs. Proposed

### Current
```
LFE/BEAM (conductor, supervisors)
    ↓ Erlang ports
Claude CLI (subprocess)
    ↓ MCP
Cortex (infrastructure events)

CL Autopoiesis (cognitive engine) ← DORMANT
```

### After Phase A+B+C+D
```
CL Autopoiesis Process
├── Conductor Loop (bordeaux-threads + timer)
│   ├── Fast: health checks, metrics, status
│   └── Slow: cognitive-cycle → Claude API → tool execution
├── Cognitive Engine
│   ├── Turn/Context conversation model
│   ├── Snapshot DAG (branch, fork, replay)
│   ├── Self-extension compiler (sandboxed)
│   └── Learning system (cross-branch pattern mining)
├── Storage (LMDB)
│   ├── Conversation turns (datoms + blobs)
│   ├── Snapshots (content-addressed blobs)
│   ├── Event log (persistent, temporal)
│   └── Extension registry (compiled functions)
├── Integration
│   ├── Claude API (direct dexador calls)
│   ├── MCP client → Cortex (infrastructure)
│   ├── OpenAI/Ollama bridges
│   └── 22+ built-in tools
├── HTTP (Hunchentoot)
└── SWANK (live REPL)
```

---

## Open Questions

1. **Should the LFE layer be deleted or preserved?** If CL conductor succeeds, LFE is dead code. Keeping it adds confusion. But it's 1,600 LOC of working code with 75 tests.

2. **EAV datoms vs. blobs for cognitive state?** Blobs preserve S-expression tree structure (simpler, lossless). EAV datoms enable per-attribute queries (more powerful, requires schema design). Start with blobs, consider EAV for conversation turns.

3. **Claude API direct vs. CLI?** Direct API is simpler but loses MCP tool routing that Claude CLI provides. The existing `agentic-loop` already uses direct API. Keep both paths.

4. **Datalog for conversation queries?** If conversation turns are datoms, Datalog is the natural query language. But it requires implementing a query compiler. S-expression pattern matching may be sufficient initially.

5. **When to tackle Cortex integration?** MCP bridge is sufficient now. Shared LMDB would enable cross-domain conversation queries but doubles the integration effort.

---

## Code References

### Autopoiesis (existing code to leverage)
- `src/core/extension-compiler.lisp:64-176` — Sandbox configuration (reuse for conversation safety)
- `src/core/recovery.lisp:159-199` — 6 standard restarts (CL conductor supervision)
- `src/core/s-expr.lisp:81-113` — SHA-256 hashing (extend to BLAKE3 for blobs)
- `src/integration/claude-bridge.lisp:174-226` — Existing agentic loop (foundation for conductor)
- `src/integration/events.lisp:120-168` — Event bus (extend with conversation events)
- `src/snapshot/persistence.lisp:176-189` — Snapshot index (replace with LMDB indexes)
- `src/snapshot/lru-cache.lisp:12-124` — LRU cache (keep for LMDB read caching)
- `src/holodeck/systems.lisp:47-88` — ECS `defsystem` usage (pattern for conversation systems)

### Cortex (integration points)
- `src/core/types.lisp:12074-12149` — `trace-event` structure (reference for datom design)
- `src/core/entity-state.lisp:11184-11271` — Event replay (pattern for conversation reconstruction)
- `src/query/parser.lisp:19068-19339` — Query AST (potential reuse for conversation queries)
- `src/storage/lmdb-schemas.lisp` — LMDB database layout (reference for AP's LMDB design)

### Thinking Repo (key documents)
- `design-improvements.md` — 9 improvements, 3 directly applicable (blob storage, conversation branching, condition vocabulary)
- `performance-analysis.md` — Rigorous perf math confirming LMDB suitability
- `cxdb-comparison.md` — Turn/Context model design and rationale
- `substrate-decomposition.md` — Separation of concerns architecture
- `hpc-lisp-optimization-ideas.md` — 20 ideas, 4 relevant (Datalog, TMS, Linda, CLIM)

### Existing Research
- `thoughts/shared/research/2026-02-16-lfe-control-plane-analysis.md` — Supports CL conductor decision
- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Identifies dormant CL engine as key gap
- `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md` — CL conductor design (reuse)
- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — 5-phase plan (subsume with cleaner architecture)
