---
date: 2026-02-16T18:00:00-08:00
researcher: Claude Code
git_commit: 8a80e4d
branch: main
repository: autopoiesis
topic: "Substrate plan revision: 11 changes from handoff with thinking-repo design context"
tags: [research, substrate, programming-model, define-entity-type, defsystem, conditions, codebase-patterns]
status: complete
last_updated: 2026-02-16
last_updated_by: Claude Code
---

# Research: Substrate Plan Revision Context

**Date**: 2026-02-16T18:00:00-08:00
**Researcher**: Claude Code
**Git Commit**: 8a80e4d
**Branch**: main
**Repository**: autopoiesis

## Research Question

Gather all context needed to apply 11 changes from the handoff document (`thoughts/shared/handoffs/2026-02-16-substrate-plan-iteration.md`) to the consolidated CL architecture plan (`thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md`). Document the thinking-repo designs and AP codebase patterns that inform each change.

## Summary

The consolidated plan has 8 phases across 3 tracks. It builds a substrate kernel (datom + transact! + hooks) but defers the programming model (define-entity-type, defsystem, MOP, scoped indexes). The user explicitly wants the full programming model IN the plan, not deferred. This research documents the designs and patterns that inform all 11 changes.

## Detailed Findings

### Change 1: `define-entity-type` Macro

**Thinking-repo design**: `ecs-relevance.md` shows the structural equivalence between cl-fast-ecs `defcomponent` and substrate `define-entity-type`. The macro should generate: schema metadata as datoms, validation function, CLOS class with MOP `slot-unbound` loading from entity cache.

**AP codebase pattern**: `src/agent/capability.lisp:138-171` — `defcapability` is the closest macro pattern. It parses `body-and-options` into (docstring, options, body), wraps body in a lambda, calls `make-capability` + `register-capability` into a global hash-table registry.

**Extension points design**: `substrate-extension-points.md` — `define-entity-type` is one of the 8 declared extension points: "Declare an entity type and its expected attributes. Used for validation, documentation, and MOP specialization hints."

**MOP slot-unbound pattern**: `substrate-extension-points.md` lines 43-65 — Full working code for `specialized-entity` class with `slot-unbound` method that loads from LMDB on cache miss, plus `register-hook :mop-invalidator` for cache invalidation via `slot-makunbound`.

### Change 2: `defsystem` Macro

**Thinking-repo design**: `ecs-relevance.md` lines 77-92 and 223-253 — cl-fast-ecs `defsystem` declares component access patterns (`:components-rw`, `:components-ro`, `:after`). The substrate equivalent declares `(:entity-type :k8s/pod :watches (:k8s.pod/phase :k8s.pod/restarts) :access :read-only)` and the framework builds a dispatch table: attribute -> list of systems.

**AP codebase pattern**: `src/holodeck/systems.lisp:47-88` — Three ECS systems (`movement-system`, `pulse-system`, `lod-system`) show the declaration-first pattern. `pulse-system` and `lod-system` both declare `:after (movement-system)` for ordering. Body uses implicit `entity` binding with typed accessors.

**Key design decision**: The substrate's `defsystem` is NOT a frame-tick system. It's a declaration-filtered reactive dispatch. Systems run when relevant datoms change (via hooks), not on a clock. The `:watches` declaration narrows which hook firings reach which systems.

### Change 3: Scoped Indexes

**Thinking-repo design**: `performance-analysis.md` lines 349-396 — Full analysis of scoped indexes as "the single most impactful performance optimization for the module architecture." Implementation is a single `(when (or (null scope) (funcall scope datom)) ...)` guard in `write-to-index`. Scope check is ~5-10ns vs. B+ tree insertion at ~1-5us.

**Impact numbers**: Without scoped indexes, Cortex writes to Bubble's SPO/POS/OSP indexes unnecessarily (5 puts). With scoped indexes, Cortex writes 2-3 puts (SPO/POS/OSP skipped). OTEL writes go from 5 puts to 1-2 puts.

### Change 4: Index Strategy

**Thinking-repo design**: `performance-analysis.md` lines 130-146 — EA-CURRENT should use `:replace` strategy (overwrite on write, not append). Without it, full entity reconstruction is O(attributes x history) cursor steps vs O(attributes). "EA-CURRENT should be a default substrate index, not a module concern."

**Current plan gap**: The plan defines EA-CURRENT in `register-default-indexes` but doesn't formally distinguish `:append` vs `:replace` strategies in the `define-index` API.

### Change 5: Fix `take!`

**Current plan problem**: `take!` in `src/substrate/linda.lisp` scans entire `*entity-cache*` hash table — O(n) in total entities. It iterates every key in the cache checking `(= (cdr key) aid)`.

**Fix**: Use AEVT index for attribute+value lookup. For in-memory Phase 1, maintain a secondary index `attribute-id -> {value -> entity-ids}` (inverted index). This makes `take!` O(1) for the common case.

### Change 6: Fix `intern-id`

**Current plan problem**: SHA-256 truncated to u64 has birthday paradox collision at ~2^32 entities (~4 billion). u32 attributes collide at ~65K. This is acceptable for entities but dangerous for attributes.

**Thinking-repo design**: `substrate-decomposition.md` lines 66-75 — Bubble's intern uses SHA-256 as the lookup KEY, but the actual ID is `(incf *next-id*)` — a monotonic counter. This is collision-free. Persist counter + tables to LMDB in Phase 2.

### Change 7: Fix Hook Firing

**Current plan problem**: `transact!` fires hooks INSIDE `bt:with-lock-held`. Any hook that calls `transact!` (common for `defsystem` callbacks) will deadlock on the lock.

**Thinking-repo design**: `substrate-decomposition.md` line 101 — "Hooks fire OUTSIDE the transaction (like Bubble does)." `substrate-extension-points.md` line 291 — "Hooks fire AFTER the transaction commits, with the FULL datom list."

**Fix**: Accumulate datoms under lock, release lock, then fire hooks. The plan already has a `:after` method attempting this but it's mixed with the lock-holding `transact!` defun.

### Change 8: Fix `append-turn`

**Current plan problem**: `append-turn` in Phase 6 calls `transact!` twice — once for turn datoms, once for context head update. Window for orphaned turns on crash between the two calls.

**Fix**: Single `transact!` with all datoms (turn datoms + context head update) in one list.

### Change 9: Add Query Functions

**Current plan gap**: No `find-entities` (attribute+value -> entity IDs) or `find-entities-by-type`. These are building blocks for `defsystem` dispatch and REPL exploration.

**Implementation**: `find-entities` scans AEVT index for attribute, filters by value. `find-entities-by-type` is sugar for `(find-entities :entity/type type-keyword)`.

### Change 10: Substrate Conditions

**AP codebase pattern**: `src/core/conditions.lisp:12-62` — Three-level hierarchy: `autopoiesis-condition` (base, no superclass), `autopoiesis-error` (+ CL `error`), `autopoiesis-warning` (+ CL `warning`), then leaf conditions with domain slots.

**AP recovery pattern**: `src/core/recovery.lisp:159-199` — Six standard restarts in `establish-recovery-restarts`: `continue-with-default`, `retry-operation`, `retry-with-delay`, `use-fallback`, `skip-operation`, `abort-operation`.

**Substrate conditions needed**: `substrate-condition` base, `validation-error` (with `:coerce`, `:store-raw`, `:skip` restarts), `unknown-entity-type` (with `:classify`, `:store-generic`, `:skip` restarts). ~30 lines of `define-condition` forms.

### Change 11: Update "What We're NOT Doing"

Remove from "NOT Doing": MOP schema specialization, defsystem/standing queries, define-entity-type, scoped indexes. These are now IN the plan.

Keep deferred: Datalog, SoA columns, bitemporal, full Rete incremental maintenance, multi-tenant.

## Code References

- `src/agent/capability.lisp:138-171` — `defcapability` macro (model for `define-entity-type`)
- `src/holodeck/systems.lisp:47-88` — cl-fast-ecs `defsystem` usage (model for substrate `defsystem`)
- `src/snapshot/content-store.lisp:11-55` — Content-addressable store (model for blob store)
- `src/core/conditions.lisp:12-62` — Condition hierarchy (base for substrate conditions)
- `src/core/recovery.lisp:159-199` — Six standard restarts (pattern for substrate restarts)
- `src/holodeck/packages.lisp:13` — cl-fast-ecs package integration

## Architecture Documentation

### Thinking-Repo Source Documents

| Document | Key Content |
|----------|-------------|
| `~/projects/thinking/substrate-decomposition.md` | Full substrate design, datom struct, transact!, module decomposition, monotonic counter interning |
| `~/projects/thinking/substrate-extension-points.md` | 8 extension point APIs, MOP slot-unbound pattern, standing query dispatch table |
| `~/projects/thinking/ecs-relevance.md` | Datom = ECS equivalence, defsystem as standing query declaration, SoA columns |
| `~/projects/thinking/performance-analysis.md` | EA-CURRENT justification, scoped index math, write amplification analysis |
| `~/projects/thinking/cxdb-comparison.md` | Turn/Context DAG model, blob deduplication |

## Related Research

- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Prior evaluation (outdated re: deferrals)
- `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` — Extension points gap analysis
- `thoughts/shared/research/2026-02-16-linda-tuple-spaces-substrate-evaluation.md` — Linda mapping
- `thoughts/shared/handoffs/2026-02-16-substrate-plan-iteration.md` — The handoff document with all 11 changes
