---
date: "2026-02-17T14:51:54Z"
researcher: claude-opus-4-6
git_commit: 12a7db1988380a90d9353647d0177966c8d7cf10
branch: main
repository: autopoiesis
topic: "Unimplemented ideas from ~/projects/thinking worth pursuing"
tags: [research, codebase, substrate, thinking-repo, ideas, roadmap]
status: complete
last_updated: "2026-02-17"
last_updated_by: claude-opus-4-6
---

# Research: Unimplemented Ideas from ~/projects/thinking

**Date**: 2026-02-17T14:51:54Z
**Researcher**: claude-opus-4-6
**Git Commit**: 12a7db1988380a90d9353647d0177966c8d7cf10
**Branch**: main
**Repository**: autopoiesis

## Research Question
Review ~/projects/thinking, especially the most recent documents (by creation date). Any ideas we haven't implemented worth looking at?

## Summary

Many of the highest-value ideas from the thinking repo have **already been implemented** during the CL consolidation (Phases 1-7). The substrate layer now has EA-CURRENT indexes, scoped indexes, content-addressed blobs, MOP entity types via `define-entity-type`, reactive `defsystem`, Linda `take!`, a conversation DAG, and self-extension tools. This is a significant achievement — the consolidation absorbed the best ideas from weeks of research.

The remaining unimplemented ideas fall into two tiers: **high-value / moderate effort** items that would meaningfully extend the platform's capabilities, and **performance / storage optimizations** that matter at scale but aren't blocking current use.

## What's Already Implemented (No Action Needed)

These ideas appeared prominently across the thinking docs but are already working:

| Idea | Where Described | Implementation |
|------|----------------|----------------|
| EA-CURRENT index | substrate-decomposition.md | `src/substrate/store.lisp` - `*ea-current*` hash table |
| Scoped indexes | substrate-extension-points.md | `define-index` macro with `:scope` and `:strategy` |
| Content-addressed blobs | substrate-decomposition.md | `src/substrate/blob.lisp` - SHA-256 + optional zstd |
| Conversation turn DAG | design-improvements.md | `src/conversation/turn.lisp` - parent-pointer DAG |
| MOP entity types | substrate-extension-points.md | `src/substrate/entity-type.lisp` - `define-entity-type` with `slot-unbound` |
| Reactive defsystem | substrate-extension-points.md | `src/substrate/system.lisp` - declaration-filtered dispatch |
| Linda take! | design-improvements.md | `src/substrate/linda.lisp` - `take!` with value index |
| Agentic loop integration | design-improvements.md | `src/integration/agentic-agent.lisp` - conversation-context slot |
| Extension compiler | research-synthesis.md | `src/core/extension-compiler.lisp` |
| Self-extension tools | research-synthesis.md | `src/integration/builtin-tools.lisp` - define-tool, extend-capability |

## Tier 1: High-Value Unimplemented Ideas

### 1. Datalog Query Language (~200 LOC)
**Source**: substrate-decomposition.md, research-synthesis.md, hpc-lisp-optimization-ideas.md

The datom store's EAVT/AEVT layout is inherently Datalog-shaped. A query compiler that translates Datalog-style patterns into index walks would enable expressive queries without hand-coding hash table lookups. The thinking docs propose:

```lisp
(query '((?e :agent/name ?name)
         (?e :agent/status :running)))
```

This would compile to an AEVT walk on `:agent/status` intersected with EAVT lookups. The substrate already has the indexes — this is a query language layer on top.

**Value**: Replaces ad-hoc `find-entities` calls with declarative, composable queries. Essential for complex conversation queries ("find all turns from agent X in context Y that mention topic Z").

**Effort**: ~200 LOC. Pattern matching + index selection + join execution.

### 2. Standing Queries with Subscriber Notification (~150 LOC)
**Source**: substrate-extension-points.md, convo/archil-convo.md

Beyond the current `defsystem` hooks (which fire on every transaction), standing queries would maintain incrementally-updated result sets. When a transaction changes a standing query's results, subscribers get notified with the delta.

```lisp
(define-standing-query running-agents
  '((?e :agent/status :running))
  :on-add (lambda (bindings) ...)
  :on-remove (lambda (bindings) ...)
```

**Value**: Enables reactive UIs, monitoring dashboards, and self-healing behaviors without polling. The `defsystem` hooks handle simple per-attribute reactions; standing queries handle multi-pattern joins.

**Effort**: ~150 LOC. Leverage existing defsystem infrastructure + incremental re-evaluation.

### 3. Batched Write Channel (~80 LOC)
**Source**: hpc-lisp-optimization-ideas.md, performance-analysis.md

Current `transact!` is single-datom, lock-per-write. A batched channel would accept datom vectors and apply them atomically, amortizing lock overhead.

```lisp
(with-batch-transaction ()
  (transact! e1 :status :running)
  (transact! e1 :started-at (get-universal-time))
  (transact! e2 :status :waiting))
;; all three applied atomically with one lock acquisition
```

**Value**: Critical for conversation turn recording (multiple datoms per turn) and bulk imports. The conversation module currently does multiple individual transact! calls per turn.

**Effort**: ~80 LOC. Thread-local accumulator + flush-on-exit.

### 4. Truth Maintenance System (TMS) (~200 LOC)
**Source**: research-synthesis.md, design-improvements.md

Derived facts that automatically update when their premises change. Example: an agent's "health" status derived from error rate + response time + memory usage. When any input changes, the derived value recomputes.

```lisp
(define-derived-fact agent-health (agent)
  (let ((errors (entity-attr agent :error-count))
        (uptime (entity-attr agent :uptime)))
    (if (< (/ errors uptime) 0.01) :healthy :degraded)))
```

**Value**: Eliminates manual cache invalidation and stale derived state. Particularly useful for the monitoring layer.

**Effort**: ~200 LOC. Dependency tracking + invalidation propagation. Could build on `defsystem` hooks.

## Tier 2: Performance & Storage Optimizations

### 5. Dictionary Encoding for Repeated Values (~100 LOC)
**Source**: hpc-lisp-optimization-ideas.md, performance-analysis.md

Status keywords like `:running`, `:idle`, `:error` repeat across thousands of entities. Dictionary encoding replaces repeated values with integer codes in the value index, reducing memory and speeding comparisons.

**Value**: Memory reduction for large stores. Not urgent at current scale.

### 6. Arena Allocation / GC-Free Writes (~150 LOC)
**Source**: hpc-lisp-optimization-ideas.md

Pre-allocate datom pools and reuse them to avoid GC pressure during high-throughput writes. SBCL-specific, using `sb-ext:define-alien-type` or custom allocators.

**Value**: Only matters at >10K writes/sec. Not blocking anything currently.

### 7. Temporal Sharding & Retention Policies (~200 LOC)
**Source**: convo/archil-convo.md

Partition the datom store by time windows. Old datoms migrate to cold storage (LMDB) while recent datoms stay in hot memory. Combined with retention policies that auto-expire stale data.

**Value**: Long-running agents will accumulate unbounded history. Not urgent until production deployment.

## Tier 3: Interesting but Lower Priority

### 8. Prism Pattern (Multi-Perspective Views)
**Source**: convo/archil-convo.md

Same entity viewed through different lenses — developer sees code metrics, manager sees progress metrics, security sees audit events. Implemented via scoped projections over entity state.

**Value**: Interesting for future multi-stakeholder UIs. No current consumer.

### 9. Condition-Based Self-Healing
**Source**: convo/archil-convo.md, design-improvements.md

Leverage CL condition system for autonomous recovery — define restart strategies for known failure modes. The recovery module (`src/core/recovery.lisp`) already has the foundation; this extends it to substrate-level self-repair.

**Value**: Production resilience. Foundation exists, just needs substrate-specific restart definitions.

## Recommended Priority

If implementing, the natural order based on value/effort ratio:

1. **Batched writes** (80 LOC, unblocks conversation efficiency)
2. **Datalog queries** (200 LOC, unlocks expressive substrate querying)
3. **Standing queries** (150 LOC, enables reactive behaviors)
4. **TMS** (200 LOC, eliminates derived-state staleness)

Total: ~630 LOC for items 1-4. Each is independently useful and builds on the existing substrate.

## Code References

- `src/substrate/store.lisp` - Current transact!, find-entities, index infrastructure
- `src/substrate/linda.lisp` - take! implementation (value index based)
- `src/substrate/system.lisp` - defsystem macro, declaration-filtered dispatch
- `src/substrate/entity-type.lisp` - define-entity-type, MOP slot-unbound
- `src/substrate/blob.lisp` - Content-addressed blob store
- `src/conversation/turn.lisp` - Turn DAG with multiple transact! calls per turn
- `src/conversation/context.lisp` - Context management, fork-context

## Source Documents Analyzed

From `~/projects/thinking/` (most recent first):
- `ap-codebase-review.md` (Feb 17) - Codebase review with architecture analysis
- `substrate-extension-points.md` (Feb 16) - Extension point catalog
- `substrate-decomposition.md` (Feb 16) - Full substrate design with encoding/indexes
- `review-coherence-and-gaps.md` (Feb 16) - Gap analysis across all thinking docs
- `performance-analysis.md` (Feb 16) - Performance considerations
- `hpc-lisp-optimization-ideas.md` (Feb 16) - HPC-inspired optimization proposals
- `design-improvements.md` (Feb 16) - Design improvement ideas
- `cxdb-comparison.md` (Feb 16) - Comparison with XTDB/Datomic
- `research-synthesis.md` (Feb 16) - Synthesis of all research
- `convo/archil-convo.md` - Conversation with Archil on storage/retention

## Open Questions

- Should Datalog queries compile to closures at macro-expansion time (fast, static) or remain interpreted (flexible, dynamic)?
- Do standing queries need to survive restart (persist subscriptions in substrate) or are they session-local?
- Is batched write correctness simpler as a thread-local accumulator flushed at scope exit, or as an explicit channel with a dedicated writer thread?
