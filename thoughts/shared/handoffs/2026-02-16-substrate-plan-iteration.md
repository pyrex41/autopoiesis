# Handoff: Iterate Consolidated CL Architecture Plan

**Date**: 2026-02-16
**From**: Claude Code session (context exhausted)
**To**: Next session
**Status**: Research complete, edits not yet made

---

## Task

Update `/Users/reuben/projects/ap/thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` to incorporate 11 improvements identified during review. The user explicitly wants the full programming model (define-entity-type, defsystem, MOP, scoped indexes) built into the plan, NOT deferred.

## Context

The user has a `~/projects/thinking/` repo with ~15 documents designing a shared "substrate" that merges Bubble (knowledge graph), Cortex (infrastructure), and Autopoiesis (agent cognition) through a datom-based data model on LMDB. The consolidated plan already exists and is well-structured (8 phases, 3 tracks), but it punts on the programming model — building only plumbing (datom, transact!, hooks) without the API surface you'd write domain code against.

The user pushed back hard on deferring `defsystem`, MOP specialization, `define-entity-type`, and scoped indexes. Their argument: these aren't optimizations for later, they're the programming model. Without them, all domain code is raw `(entity-attr eid :turn/role)` calls instead of CLOS slot access.

## The 11 Required Changes

### Programming Model (add to implementation phases)

1. **`define-entity-type` macro** — Generates: schema metadata stored as datoms, validation function, CLOS class with MOP `slot-unbound` loading from entity cache. Pre-define types: `:turn`, `:context`, `:event`, `:worker`, `:agent`, `:session`, `:snapshot`.

2. **`defsystem` macro** — Declaration-filtered reactive dispatch. Declares `(:entity-type :turn :watches (:turn/role :turn/content-hash) :access :read-only)` and the framework builds a dispatch table: attribute → list of systems. Only matching systems invoked on datom arrival. Pattern from `design-improvements.md` Improvement 1.

3. **Scoped indexes** — Add `:scope` predicate to `define-index`. Essential when Bubble triples share the store (SPO/POS/OSP only fire for knowledge entities). Implementation: single `(when (or (null scope) (funcall scope datom)) ...)` guard in `write-to-index`.

4. **Index strategy** — Add `:strategy` to `define-index` (`:append` for EAVT/AEVT, `:replace` for EA-CURRENT). Clarify entity cache as write-through cache over EA-CURRENT, not a separate data structure.

### Implementation Fixes

5. **Fix `take!`** — Current plan scans entire `*entity-cache*` hash table (O(n) in total entities). Should use AEVT index for attribute+value lookup, or maintain a secondary index `attribute → {value → entity-ids}` for in-memory Phase 1.

6. **Fix `intern-id`** — Current plan truncates SHA-256 to u64/u32 (birthday paradox: 50% collision at ~2^32 entities for u64, ~65K for u32 attributes). Should use monotonic counter like Bubble: SHA-256 is the lookup key, `(incf *next-id*)` produces the actual ID. Persist counter + tables to LMDB in Phase 2.

7. **Fix hook firing** — Current plan fires hooks INSIDE `bt:with-lock-held`. Hooks that call `transact!` (common — e.g., `defsystem` callbacks) will deadlock. Fix: accumulate datoms under lock, release lock, then fire hooks. Or use recursive lock + careful re-entrancy.

8. **Fix `append-turn`** — Current plan calls `transact!` twice (once for turn datoms, once for context head update). Window for orphaned turns on crash. Fix: single `transact!` with all datoms in one list.

9. **Add query functions** — `find-entities` (attribute+value → entity IDs via AEVT scan) and `find-entities-by-type` (scan for entities with `:entity/type` attribute). Building blocks for `defsystem` dispatch and REPL.

10. **Add substrate conditions** — `substrate-condition` base, `validation-error` (with `:coerce`, `:store-raw`, `:skip` restarts), `unknown-entity-type` (with `:classify`, `:store-generic`, `:skip` restarts). ~30 lines of `define-condition` forms. Extend AP's existing hierarchy at `src/core/conditions.lisp:12-62`.

11. **Update "What We're NOT Doing"** — Remove: MOP schema specialization, defsystem/standing queries, define-entity-type, scoped indexes. These are now IN the plan. Keep deferred: Datalog, SoA columns, bitemporal, Rete, full multi-tenant.

## Suggested Plan Structure After Changes

The current plan has 8 phases. The recommended restructure:

**Phase 1: Substrate Kernel** (expand to include):
- Datom struct, key encoding (as now)
- Monotonic-counter interning (fix #6)
- `transact!` with hooks firing OUTSIDE lock (fix #7)
- `define-index` with `:scope` and `:strategy` (changes #3, #4)
- `find-entities`, `find-entities-by-type` (change #9)
- Substrate condition hierarchy (change #10)
- `take!` using AEVT index (fix #5)
- `register-hook` (low-level, still useful)

**Phase 1.5: Programming Model** (NEW PHASE):
- `define-entity-type` macro → schema + validation + CLOS class + MOP `slot-unbound`
- `defsystem` macro → declaration-filtered dispatch table over hooks
- Pre-define entity types: `:turn`, `:context`, `:event`, `:worker`, `:agent`, `:session`, `:snapshot`
- Tests for MOP loading, validation signaling conditions, defsystem dispatch

**Phases 2-8**: Mostly unchanged, but:
- Phase 6 `append-turn` uses single `transact!` (fix #8)
- Phase 3 conductor uses `define-entity-type :event` and `define-entity-type :worker`
- Phase 6-7 conversation code uses CLOS turn/context objects, not raw `entity-attr`

## Key Source References in AP Codebase

### Existing patterns to model after:

| Pattern | Location | Relevance |
|---------|----------|-----------|
| `defcapability` macro | `src/agent/capability.lisp:138-171` | Model for `define-entity-type` macro structure |
| `cl-fast-ecs:defsystem` | `src/holodeck/systems.lisp:47-88` | Model for substrate `defsystem` macro |
| Content-addressable store | `src/snapshot/content-store.lisp:11-55` | Pattern for blob store |
| Condition hierarchy | `src/core/conditions.lisp:12-62` | Base to extend for substrate conditions |
| 6 standard restarts | `src/core/recovery.lisp:159-199` | Pattern for substrate restart design |
| ECS components | `src/holodeck/packages.lisp:13` | `cl-fast-ecs` usage reference |

### Key thinking-repo documents:

| Document | Key Content |
|----------|-------------|
| `~/projects/thinking/substrate-decomposition.md` | Full substrate design, datom struct, transact!, module decomposition |
| `~/projects/thinking/substrate-extension-points.md` | 8 extension point APIs (define-index, register-hook, define-tool, etc.) |
| `~/projects/thinking/design-improvements.md` | Improvement 1 (defsystem), 2 (EA-CURRENT), 3 (scoped indexes), 4 (define-entity-type), 7 (conditions), 8 (blobs), 9 (conversation branching) |
| `~/projects/thinking/cxdb-comparison.md` | Turn/Context DAG model |
| `~/projects/thinking/ecs-relevance.md` | Datom ≈ ECS equivalence, defsystem as standing query declaration |
| `~/projects/thinking/performance-analysis.md` | EA-CURRENT justification, scoped index math, write amplification analysis |

### Existing research in AP:

| Document | Content |
|----------|---------|
| `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` | Evaluation of all thinking-repo ideas (551 lines) — OUTDATED re: deferrals, user wants full programming model |
| `thoughts/shared/research/2026-02-16-substrate-extension-points-gap-analysis.md` | Gap analysis of 8 extension points vs current AP |

## How to Execute

Use `/cl:iterate_plan` with the plan path and the 11 changes listed above. Or manually:

1. Read the plan (already fully in this handoff's context)
2. The changes are surgical — expand Phase 1, insert Phase 1.5, fix code snippets in Phases 1/6, update "What We're NOT Doing"
3. No new codebase research needed — all patterns are documented above
4. Use Edit tool for focused changes to the plan file

## User Preferences

- The user is the architect of all three projects (Bubble, Cortex, AP) and the thinking-repo designs
- They want the FULL programming model, not a watered-down "add LMDB and blobs" version
- They pushed back explicitly on deferring defsystem, MOP, define-entity-type — "Why don't you want to do defsystem? Why don't you want the MOP specializations?"
- They value ergonomics (CLOS slot access) and correctness (conditions/restarts) over premature simplification
- They're comfortable with CL metaprogramming (macros, MOP, conditions)

## What NOT to Do

- Don't re-evaluate whether these features are "premature" — the user has decided they want them
- Don't add new phases for SoA columns, Datalog, bitemporal, Rete — those remain deferred
- Don't rewrite the entire plan — make surgical edits to the existing structure
- Don't research the codebase further — all needed references are in this handoff
