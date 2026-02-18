---
date: 2026-02-16T18:00:00-06:00
researcher: Claude
git_commit: 8a80e4d4027b6cd9827b3006adea064a081e225e
branch: main
repository: autopoiesis
topic: "Evaluation of HPC, CS Theory, and Lisp History Ideas Against Consolidated CL Architecture Plan"
tags: [research, codebase, optimization, lmdb, conductor, hpc, lisp-history]
status: complete
last_updated: 2026-02-16
last_updated_by: Claude
---

# Research: HPC/CS Theory/Lisp History Ideas Evaluated Against Consolidated CL Architecture

**Date**: 2026-02-16T18:00:00-06:00
**Researcher**: Claude
**Git Commit**: 8a80e4d4027b6cd9827b3006adea064a081e225e
**Branch**: main
**Repository**: autopoiesis

## Research Question

Evaluate the 20 ideas in `~/projects/thinking/hpc-lisp-optimization-ideas.md` for applicability to the consolidated CL architecture plan at `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md`. Determine which ideas align with or enhance the 7-phase plan (conductor, LFE removal, LMDB storage, blob store, conversation DAG, wiring), and which represent separate future work.

## Summary

The HPC/Lisp ideas document contains 20 proposals organized into three categories: Lisp history (8 ideas), CS theory (6 ideas), and HPC (6 ideas). Many of these ideas were originally designed for a substrate/datom architecture (Cortex-like EAV store with standing queries). The consolidated CL plan is a different architecture: a single-process agent platform with LMDB-backed snapshots, conversation branching, and an agentic loop. This creates an important gap between what the ideas target and what the plan actually builds.

**Directly applicable to the 7-phase plan:** 5 ideas
**Applicable with adaptation:** 5 ideas
**Future work (not current plan scope):** 8 ideas
**Not applicable to this architecture:** 2 ideas

## Detailed Findings

### Category A: Directly Applicable to the 7-Phase Plan

These ideas align with specific phases and can be incorporated during implementation.

---

#### Idea #5: Lisp Machine Ephemeral GC / Arena Allocation — Applicable to Phases 4-7

**What it proposes:** Tune SBCL's nursery size for transaction patterns, use `dynamic-extent` for stack allocation of temporaries, and use SBCL arenas to eliminate GC pressure on write paths.

**Current codebase state:** Zero type declarations (`declare (type ...)`) or optimization declarations (`declare (optimize ...)`) anywhere in the 27,496 lines of source code. Only two structs (`profile-metric` in `src/core/profiling.lisp:30-37` and `sexpr-edit` in `src/core/s-expr.lisp:156-161`) have any `:type` slot declarations. Hash tables have no `:size` hints. Arrays use `(make-array 0 :adjustable t :fill-pointer 0)` universally — starting at zero size and growing.

**Alignment with plan:** Phases 4-7 introduce LMDB as the storage layer. Every `store-snapshot`, `store-blob`, `append-turn`, and `store-context` call will create temporary S-expression serialization structures, key encodings, and byte vectors that become garbage immediately after the LMDB write completes. This is exactly the pattern arena allocation addresses.

**Concrete integration points:**
- Phase 4 (`src/storage/lmdb-store.lisp`): `store-snapshot` serializes an agent-state S-expression to bytes, computes SHA-256 hash, encodes LMDB keys, writes, then all temporaries are garbage. Arena allocation for this path means zero GC contribution from writes.
- Phase 5 (`src/storage/blob-store.lisp`): `store-blob` compresses content via Zstd, computes hash, writes. The uncompressed buffer and hash intermediates are short-lived.
- Phase 6 (`src/conversation/turn.lisp`): `append-turn` serializes turn metadata, creates blob for content, updates context. All temporaries are ephemeral.
- Phase 1 (`src/orchestration/conductor.lisp`): The 100ms tick loop creates temporary plists for timer processing and event classification. These could live in an arena scoped to the tick.

**SBCL-specific details:**
- `sb-vm:with-arena` is available in SBCL 2.3+ and allows arena-scoped allocation where all objects are freed wholesale when the arena scope exits. No GC involvement.
- `dynamic-extent` on `let` bindings with `mapcar`/`loop` can stack-allocate list spines — relevant for the serialize-then-write pattern.
- Nursery tuning via `(setf (sb-ext:bytes-consed-between-gcs) ...)` is a one-line change with measurable impact on GC frequency.

**Effort:** Low (nursery tuning: 1 line; `dynamic-extent`: ~10 annotations; arena: ~20 lines wrapping write paths)
**Impact on plan:** Medium. Doesn't change the architecture but makes the LMDB write path allocation-free.

---

#### Idea #10: Bloom Filters for LMDB Index Acceleration — Applicable to Phase 4

**What it proposes:** Layer Bloom or Cuckoo filters in front of LMDB B+ tree lookups to eliminate negative lookups without touching disk.

**Current codebase state:** The existing `snapshot-exists-p` (`src/snapshot/persistence.lisp:167-170`) already does a two-tier check: LRU cache hash table first, then filesystem `probe-file`. This is the same pattern a Bloom filter would accelerate — but at the LMDB level, where `probe-file` becomes `lmdb-get`.

**Alignment with plan:** Phase 4 creates `lmdb-store.lisp` with 6 named databases. Key lookup patterns:
- `load-snapshot-by-id`: Checks if a snapshot exists, loads it. Bloom filter on snapshot-id space eliminates misses.
- `blob-exists-p` (Phase 5): Content-addressed lookup — most lookups will be for hashes that exist (deduplication check), but some won't. Bloom filter avoids B+ tree traversal for misses.
- `find-latest-for-agent` currently scans the entire `by-id` index (`src/snapshot/persistence.lisp:403-417`). With LMDB, this becomes an index scan that a Bloom filter won't help — but a Bloom filter over `(agent-id, snapshot-id)` pairs could fast-path the existence check.

**Concrete integration point:** In `open-storage` (Phase 4), after opening the LMDB environment, build Bloom filters from existing data by scanning each database. Maintain filters via hooks on `store-snapshot`, `store-blob`, etc. Cost: ~234KB for 200K entities at 1% FPR.

**Implementation detail for CL:** Ironclad (already a dependency) provides SHA-256. For Bloom filter hash functions, use two SHA-256 halves as independent hashes and derive k hash functions via the Kirsch-Mitzenmacher double-hashing scheme. CL's `(make-array N :element-type 'bit)` provides efficient bit vectors with hardware-accelerated `sbit` access.

**Effort:** Low (~100 LOC for Bloom filter implementation + maintenance hooks)
**Impact on plan:** Medium for read-heavy patterns. Avoids LMDB B+ tree traversal (~500ns) for negative lookups, replacing with ~50ns filter check.

---

#### Idea #15: Huge Pages for LMDB — Applicable to Phase 4

**What it proposes:** Apply `madvise(MADV_HUGEPAGE)` to LMDB's mmap region to reduce TLB misses during B+ tree traversal.

**Current codebase state:** No memory mapping in the existing codebase. The filesystem persistence uses standard CL `open-file`/`read`/`write` without mmap.

**Alignment with plan:** Phase 4 introduces LMDB, which is entirely mmap-based. Every `lmdb-get` traverses B+ tree nodes in mmap'd memory. TLB pressure is proportional to database size divided by page size (4KB default). At 1GB map-size (the plan specifies this), that's 262K 4KB pages vs 512 2MB huge pages.

**Platform consideration:** The plan specifies SBCL on macOS (Darwin 25.2.0 per the environment). macOS does NOT support `madvise(MADV_HUGEPAGE)` — that's Linux-specific. macOS uses `vm_allocate` with `VM_FLAGS_SUPERPAGE_SIZE_2MB` for huge pages, but this applies to `mmap` calls, not retroactively to existing mappings. LMDB's mmap on macOS will use 16KB pages (Apple Silicon default), not 4KB, so TLB pressure is already 4x lower than the document assumes.

**For Linux deployment:** If the system deploys to Linux (Docker containers, servers), this is a trivial one-time optimization. Add `madvise` call after `lmdb:env-open` via CFFI. Requires Transparent Huge Pages enabled on the host.

**Effort:** Trivial (~10 LOC, Linux-only)
**Impact on plan:** Medium on Linux, negligible on macOS. Free performance where available.

---

#### Idea #20: Compression Strategies for Temporal Data — Applicable to Phases 4-5

**What it proposes:** Delta encoding for transaction logs, RLE for column data, dictionary encoding for repeated strings.

**Current codebase state:** The event log (`src/snapshot/event-log.lisp:37`) is an in-memory adjustable vector with no compression. Snapshots are stored as full S-expressions with no delta encoding. The content-store (`src/snapshot/content-store.lisp`) uses SHA-256 for deduplication but stores full content for each unique hash.

**Alignment with plan:**
- Phase 5 already specifies Zstd compression for blobs at level 3. The HPC document's suggestion of compression is already incorporated.
- **Dictionary encoding** is directly relevant to Phase 6 (Turn/Context DAG): turn roles (`:user`, `:assistant`, `:system`, `:tool`) are a tiny vocabulary that repeats across every turn. Model names repeat across all assistant turns. Dictionary encoding for these fields in LMDB reduces per-turn storage.
- **Delta encoding** for the LMDB event database (Phase 4): consecutive transactions to the same entity (e.g., a conversation getting turns appended) share most of their structure. Storing deltas between consecutive events for the same entity reduces storage by 60-80%.

**Concrete integration point:** In `src/storage/lmdb-store.lisp`, implement a `dictionary-encode`/`dictionary-decode` layer for string fields with <256 distinct values. In `src/storage/blob-store.lisp`, implement delta encoding for blobs that share a common prefix (detected by Bloom filter on first N bytes of content).

**Effort:** Medium (~200 LOC for dictionary + delta encoding)
**Impact on plan:** Medium. Reduces LMDB disk usage and improves cache utilization for temporal queries. Zstd compression (already planned) handles the bulk; dictionary/delta encoding adds incremental improvement.

---

#### Idea #17: Lock-Free Write Channel — Applicable to Phase 1

**What it proposes:** Replace locked queues with a Michael-Scott lock-free queue for the write channel, using SBCL's `sb-ext:cas`.

**Current codebase state:** All concurrency uses `bordeaux-threads:make-lock` and `with-lock-held`. No lock-free structures exist. The orchestration request queue (`*orchestration-requests*` in `builtin-tools.lisp:14`) is a simple list manipulated with `push`/`nreverse`. The event bus (`src/integration/events.lisp:136-168`) uses no lock at all — it assumes single-threaded access.

**Alignment with plan:** Phase 1 creates a conductor with an event queue (`conductor-event-queue` as adjustable vector in the plan). Multiple threads will queue events: Claude CLI workers completing tasks, agentic loop threads producing results, the tick loop processing timers. The plan specifies `(make-array 0 :adjustable t :fill-pointer 0)` — which requires locking for thread safety.

**Alternative consideration:** Phase 1 only expects ~1-10 concurrent event producers (the conductor rate-limits workers). At this contention level, a locked `sb-concurrency:queue` (which SBCL provides as a lock-free CAS queue natively) may be sufficient. SBCL's `sb-concurrency:queue` already implements a lock-free algorithm internally.

**Concrete recommendation:** Use `sb-concurrency:queue` for the conductor event queue instead of a locked adjustable vector. This is already lock-free, already part of SBCL, and requires zero custom implementation.

**Effort:** Trivial (change data structure choice in Phase 1)
**Impact on plan:** Low-Medium. Eliminates contention on the event queue without custom code.

---

### Category B: Applicable with Adaptation

These ideas were designed for a different architecture (datom/EAV store with standing queries) but contain principles that can be adapted to the consolidated CL plan.

---

#### Idea #9: Datalog as Query Language — Adaptable to Phase 6-7

**What it proposes:** Use Datalog as the query language for the datom store, with bottom-up evaluation, stratified negation, and recursive queries.

**Current codebase state:** The snapshot layer has ad-hoc query functions: `find-snapshot-by-timestamp` (linear scan of sorted list, `persistence.lisp:343`), `find-latest-snapshot-for-agent` (full scan of `by-id` index, `persistence.lisp:403`), `snapshot-children` (hash table lookup, `persistence.lisp:369`). No query language exists.

**Adaptation for the plan:** The consolidated CL plan doesn't build a datom/EAV store — it stores snapshots as blobs and conversations as turn entities. However, **conversation queries** in Phase 6-7 would benefit from a declarative query interface:

```lisp
;; "Find all assistant turns in context X where the model was opus"
(:find ?turn-id ?content-hash
 :where
 [?turn :turn/context context-x]
 [?turn :turn/role :assistant]
 [?turn :turn/model "claude-opus-4-6"])
```

This is less ambitious than full Datalog over an EAV store — it's Datalog over a small schema of turn/context entities stored in LMDB. The index structures (by-role, by-timestamp, by-context) already planned for Phase 6 support the scan patterns Datalog would compile to.

**Scope reduction:** Implement a minimal Datalog compiler that handles conversation queries (3 entity types: turn, context, blob) rather than arbitrary EAV queries. This is ~200 LOC vs ~1000 LOC for full Datalog.

**Effort:** Medium for minimal version
**Impact on plan:** Low for current phases, high for future conversation analysis features.

---

#### Idea #11: Partial Evaluation / Query Compilation (Futamura) — Adaptable to Phase 6-7

**What it proposes:** Compile standing queries into native code using CL's `compile`, eliminating interpretation overhead.

**Current codebase state:** No query compilation. All queries are hand-written functions with explicit cursor logic. The extension compiler (`src/core/extension-compiler.lisp:389-431`) already demonstrates the pattern of wrapping code in a lambda and calling `(compile nil ...)`.

**Adaptation for the plan:** If Datalog or any declarative query is introduced in Phase 6-7, the pattern applies: compile conversation queries into direct LMDB cursor operations. CL's `compile` makes this trivial:

```lisp
(compile nil
  `(lambda (storage context-id)
     ;; Direct cursor scan of turns-db for context
     (with-read-txn (storage)
       (cursor-set-range turns-index ,(encode-context-prefix context-id))
       (loop ...))))
```

Even without Datalog, the pattern of "compile a query plan into a function" applies to `find-turns-by-role`, `find-turns-by-time-range`, and `context-history`. These are currently planned as interpreted functions; they could be compiled for frequently-accessed contexts.

**Effort:** Low-Medium (compile wrapper around existing query functions)
**Impact on plan:** Low for initial implementation, medium for repeated queries on hot contexts.

---

#### Idea #3: SERIES for Query Fusion — Adaptable to Phases 4-7

**What it proposes:** Use Richard Waters' SERIES package for lazy, fused query pipelines over entity data, compiling filter/map/join chains into single-pass loops.

**Current codebase state:** Query results are materialized as lists. `list-snapshots` returns a list of IDs. `find-snapshot-by-timestamp` filters a sorted list. `context-history` (in the Phase 6 plan) walks a parent chain collecting turns into a list.

**Adaptation for the plan:** SERIES is most valuable when chaining multiple transformations over large datasets. The conversation model processes a small number of turns per context (typically 10-100). However, **LMDB cursor iteration** is a natural fit for SERIES sources:

```lisp
(collect
  (mapping ((turn (scan-lmdb-cursor storage :turns-db :prefix context-prefix)))
    (when (eq (turn-role turn) :assistant)
      (turn-content-hash turn))))
```

`scan-lmdb-cursor` would be a SERIES source that reads LMDB entries via cursor without materializing them all into a list. For contexts with hundreds of turns, this avoids allocating a full turn list just to filter it.

**Dependency note:** SERIES is in Quicklisp (`(ql:quickload :series)`). It's a stable, mature library.

**Effort:** Low to add dependency, Medium to define SERIES sources for LMDB
**Impact on plan:** Low for small conversations, Medium for bulk operations (migration, export, analytics).

---

#### Idea #2: Truth Maintenance Systems — Adaptable as Future Extension

**What it proposes:** Track dependency chains between derived facts so that when base facts change, derived facts automatically update or retract.

**Current codebase state:** The event bus (`src/integration/events.lisp`) provides fire-and-forget notifications. No dependency tracking between events. The condition/restart system (`src/core/recovery.lisp`) handles error recovery but not fact dependency.

**Adaptation for the plan:** TMS doesn't directly apply to the 7-phase plan, which is about consolidation and storage. However, the **conductor** (Phase 1) could benefit from TMS-like thinking for derived state:
- "Agent X is healthy" derives from "Agent X's last task succeeded" AND "Agent X responded within timeout"
- "Infra-watcher is needed" derives from "more than 30 minutes since last check" AND "conductor is running"

This is a much simpler TMS than the full infrastructure reasoning system the HPC document envisions. It could be added as a conductor extension after Phase 3.

**Effort:** High for full TMS, Low for simple derived-state tracking in conductor
**Impact on plan:** Low for initial plan. High potential for conductor intelligence.

---

#### Idea #4: Frame Systems / Automatic Classification — Adaptable to Agent Model

**What it proposes:** Recognize that the entity model is already a frame system and complete the pattern with automatic classification, slot inheritance, facets, and active values.

**Current codebase state:** The agent class hierarchy (`src/agent/agent.lisp:11-40`) uses standard CLOS with no metaclass. Capabilities are registered in a flat hash table (`src/agent/capability.lisp:45-46`). The agentic-agent specializes generic methods for perceive/reason/decide/act/reflect. No automatic classification or slot inheritance beyond standard CLOS.

**Adaptation for the plan:** The agent model could benefit from:
- **Automatic classification of tool capabilities**: Instead of explicitly registering tools, a classifier could determine tool type from function signatures and docstrings.
- **Slot inheritance for agent hierarchies**: The `parent`/`children` slots on agents already create a tree. Inherited capabilities (child gets parent's tools + its own) would be a natural frame system extension.

This is future work beyond the 7-phase plan, but the awareness that the CLOS-based agent model IS a frame system is valuable context for Phase 3 (refactoring orchestration tools).

**Effort:** Medium
**Impact on plan:** Not directly applicable to current phases. Useful design context.

---

### Category C: Future Work (Not Current Plan Scope)

These ideas target capabilities beyond the 7-phase plan — they're relevant to the platform's evolution but shouldn't be mixed into the consolidation work.

---

#### Idea #1: Rete Algorithm for Production Rules

**Target:** A standing query / reactive dispatch system. The consolidated CL plan explicitly lists "Standing query / defsystem reactive layer" under "What We're NOT Doing" (plan line 104). Rete is the natural implementation of the deferred reactive layer.

**Current relevance:** The event bus (`events.lisp`) handles single-event handlers. The conductor (Phase 1) dispatches timer actions. Neither is a multi-condition join system. Rete would be valuable if the platform evolves to monitor infrastructure state (like Cortex), but that's not the current plan's scope.

#### Idea #6: Connection Machine / Data-Parallel Operations

**Target:** Parallel scanning of large entity collections. The consolidated CL plan manages agents (typically <10 concurrent) and conversation turns (typically <1000 per context). There's no "scan 100K entities" workload in the plan. Relevant for future Cortex-like entity monitoring.

#### Idea #7: Linda Tuple Spaces

**Target:** Work-queue coordination between many worker threads. The plan's conductor manages a small number of Claude CLI workers (rate-limited). The Linda `take!` pattern for atomic task consumption would be relevant if the system grows to dozens of workers processing classification or analysis tasks. Not needed for the current plan.

#### Idea #8: CLIM Presentation Types

**Target:** Rich interactive output for a web dashboard. The plan explicitly states "SSE / web dashboard — Cortex has this; AP uses SWANK" under "What We're NOT Doing" (plan line 107). CLIM presentations would enhance SWANK inspector output, but that's a nice-to-have, not a plan dependency.

#### Idea #12: Interval Trees for Temporal Range Queries

**Target:** Efficient stabbing queries over bitemporal intervals. The plan's conversation model uses a DAG with parent pointers, not bitemporal intervals. The existing `find-snapshot-by-timestamp` (linear scan of sorted list) handles the simple temporal queries the plan needs. Interval trees would matter if conversation turns had validity intervals rather than point-in-time timestamps.

#### Idea #13: Merkle Trees for State Synchronization

**Target:** Multi-node state sync. The plan explicitly states "Multi-user / multi-tenant — Single-user system" under "What We're NOT Doing" (plan line 106). Merkle trees are irrelevant to a single-process, single-user system.

#### Idea #14: Adaptive Radix Trees

**Target:** Replace hash tables with cache-friendly tries for prefix-heavy key spaces. The plan's LMDB key spaces use snapshot IDs (random UUIDs), blob hashes (random SHA-256), and turn IDs (random UUIDs). These have no prefix structure. ART would be valuable for namespaced attribute keys (`:k8s.pod/name`, `:k8s.pod/phase`) in a datom store, but the plan doesn't use datoms.

#### Idea #18: Vectorized Predicate Evaluation on Columns

**Target:** SIMD scanning of typed arrays for bulk entity filtering. No column-oriented storage exists in the plan. Snapshots are stored as blobs. Turns are stored as individual entities. There's no "scan all turns for a predicate" pattern that would benefit from vectorization.

---

### Category D: Not Applicable to This Architecture

#### Idea #16: NUMA-Aware Store Topology

**Target:** Multi-socket server deployments. The development environment is macOS on Apple Silicon (Darwin 25.2.0, ARM64). Apple Silicon is a unified memory architecture — there are no NUMA nodes. Even for Linux deployment, the plan targets a single-process system that wouldn't need NUMA pinning unless running on a multi-socket server, which is unlikely for a personal agent platform.

#### Idea #19: Work-Stealing for Parallel Query Evaluation

**Target:** Distributing standing query evaluation across cores after large transactions. The plan processes conversations sequentially (one turn at a time) and agents in parallel (but only a few concurrent agents). There's no "large transaction triggering many standing queries" workload. The conductor's tick loop is sequential by design (100ms sleep, process timers, process events). Work-stealing would add complexity without benefit.

---

## Synthesis: Integration Recommendations Per Phase

### Phase 1: CL Conductor

| Idea | Integration | Effort |
|------|-------------|--------|
| #17 Lock-free queue | Use `sb-concurrency:queue` for event queue instead of locked vector | Trivial |
| #5 GC tuning | Add nursery sizing hint in conductor startup | 1 line |

### Phase 2: Claude CLI Worker

No HPC ideas directly applicable. The worker is I/O-bound (waiting for Claude CLI subprocess), not compute-bound.

### Phase 3: Refactor + Delete LFE

No HPC ideas directly applicable. This phase is architectural refactoring, not performance work.

### Phase 4: LMDB Storage

| Idea | Integration | Effort |
|------|-------------|--------|
| #10 Bloom filters | Add Bloom filter layer in front of LMDB get operations | ~100 LOC |
| #15 Huge pages | Add `madvise` call after env-open (Linux only) | ~10 LOC |
| #5 Arena allocation | Wrap `store-snapshot` write path in `sb-vm:with-arena` | ~20 LOC |
| #20 Dictionary encoding | Encode repeated string fields as integers in LMDB values | ~100 LOC |

### Phase 5: Blob Store

| Idea | Integration | Effort |
|------|-------------|--------|
| #5 Arena allocation | Wrap `store-blob` compression path in arena | ~10 LOC |
| #20 Delta encoding | Store deltas for blobs that share prefixes | ~100 LOC |

### Phase 6: Turn/Context DAG

| Idea | Integration | Effort |
|------|-------------|--------|
| #9 Mini-Datalog | Declarative query interface for conversation queries | ~200 LOC |
| #3 SERIES sources | LMDB cursor as SERIES source for turn iteration | ~50 LOC |
| #11 Query compilation | Compile hot conversation queries to native code | ~100 LOC |

### Phase 7: Wire to Loop

| Idea | Integration | Effort |
|------|-------------|--------|
| #5 `dynamic-extent` | Annotate turn-recording temporaries | ~10 annotations |

---

## Architecture Documentation

### Current System Profile (Relevant to HPC Evaluation)

- **Source:** 27,496 lines CL across 97 files, 8 modules
- **Type annotations:** Effectively zero (only 2 structs have `:type` slots)
- **Optimization declarations:** Zero (`declare (optimize ...)` not used anywhere)
- **Concurrency model:** Lock-based via `bordeaux-threads`, ~10 lock instances across codebase
- **Memory model:** Fully GC-managed, no manual allocation, no arenas, no dynamic-extent
- **Storage:** Filesystem-based S-expression files with in-memory LRU cache (O(n) eviction)
- **Query patterns:** Ad-hoc functions with hash table lookups and list scans
- **External dependencies:** 17 libraries, all in Quicklisp

### What the HPC Document Gets Right

1. The LMDB write path IS the natural target for arena allocation
2. Bloom filters ARE valuable for content-addressed stores
3. `sb-concurrency:queue` IS the right choice for multi-producer event queues
4. Nursery tuning IS a one-line win for transaction-heavy workloads
5. Query compilation via `(compile nil ...)` IS trivially available in CL

### What the HPC Document Assumes That Doesn't Apply

1. **EAV/datom store** — The plan stores blobs, not datoms. Most ideas assume indexed attribute scanning.
2. **Standing queries** — The plan doesn't implement reactive queries. Ideas #1, #6, #18, #19 target this.
3. **100K+ entities** — The plan manages <100 agents and <10K conversation turns. Scale assumptions are off.
4. **Multi-entity joins** — The Rete and Datalog ideas assume cross-entity query patterns. The plan's queries are single-entity (load snapshot by ID, list turns by context).
5. **Multi-socket deployment** — Ideas #15 (huge pages on Linux) and #16 (NUMA) assume server hardware. Development is on macOS Apple Silicon.

## Code References

- `src/snapshot/persistence.lisp:167-170` — Current two-tier existence check (Bloom filter candidate)
- `src/snapshot/persistence.lisp:403-417` — Full index scan for agent lookup (query compilation candidate)
- `src/snapshot/content-store.lisp:30-39` — SHA-256 content-addressed put/get (Bloom filter candidate)
- `src/core/profiling.lisp:30-37` — Only struct with `:type` declarations (GC tuning baseline)
- `src/core/extension-compiler.lisp:389-431` — Existing `(compile nil ...)` pattern (query compilation precedent)
- `src/integration/events.lisp:136-168` — Event emission without locking (lock-free queue candidate)
- `src/snapshot/lru-cache.lisp:42-82` — O(n) LRU operations (LMDB replaces this)
- `src/core/s-expr.lisp:81-110` — SHA-256 hashing via Ironclad (Bloom filter hash source)
- `src/integration/builtin-tools.lisp:14` — `*orchestration-requests*` as simple list (lock-free queue candidate)

## Related Research

- `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` — The 7-phase plan being evaluated against
- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Prior evaluation of thinking repo ideas (LMDB, conversation branching)
- `~/projects/thinking/hpc-lisp-optimization-ideas.md` — Source document being evaluated
- `~/projects/thinking/performance-analysis.md` — LMDB throughput math
- `~/projects/thinking/cxdb-comparison.md` — Turn/Context DAG design

## Open Questions

1. **SBCL arena availability:** `sb-vm:with-arena` was introduced in SBCL ~2.3.x. What version is deployed? Need to verify compatibility before relying on arenas.
2. **LMDB CL binding quality:** The plan mentions `:lmdb` from Quicklisp or `cl-lmdb` from GitHub. Neither is well-established. Does the CFFI binding expose `mdb_env_info` for the mmap address needed by huge pages and Bloom filter population?
3. **SERIES compatibility:** SERIES uses code walkers that may conflict with other CL macro systems. Test compatibility with the existing codebase before committing to SERIES-based query sources.
4. **Zstd CL binding:** The plan mentions `cl-zstd` with a fallback. If Zstd isn't available, delta encoding becomes more important for storage efficiency.
5. **Is query compilation worth the complexity?** With <10K turns per context, even a linear scan takes <1ms. The benefits of query compilation may not justify the code if the data volumes stay small.
