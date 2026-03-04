---
date: 2026-03-03T22:15:00Z
researcher: Claude
git_commit: 4375973
branch: main
repository: autopoiesis
topic: "Using Datomic/Datalog directly vs. as inspiration"
tags: [research, codebase, substrate, datalog, datomic, query-engine]
status: complete
last_updated: 2026-03-03
last_updated_by: Claude
---

# Research: Using Datomic/Datalog Directly

## Research Question

Can we use Datomic or Datalog directly, rather than just as inspiration for the substrate?

## Summary

Three key findings:

1. **There is already a Datalog query engine in the substrate** (`platform/src/substrate/datalog.lisp`, 257 lines) that supports variable binding, multi-clause joins, and negation. It is not used by any code outside the substrate's own test suite.

2. **The codebase is full of multi-attribute read patterns** that would be more naturally expressed as Datalog queries — `query-agent` reads 4 attrs, `load-prompts-from-substrate` reads 10 attrs per entity, `workspace-list-tasks` reads 4 attrs per entity, all as sequential `entity-attr` calls.

3. **The CL Datalog library ecosystem is thin** — `cl-datalog` and `cl-grph` exist but are minimal/unmaintained. The most promising paths are: (a) use the existing engine that's already in the codebase, (b) AP5 (actively maintained CL deductive database), or (c) run Datalevin/XTDB as an external process.

## Detailed Findings

### 1. The Existing Datalog Engine Nobody Uses

`platform/src/substrate/datalog.lisp` implements an interpreted Datalog with:

- **Variable binding**: `?e`, `?name` etc. (symbols starting with `?`)
- **Multi-clause joins**: shared variables across clauses do the join
- **Negation**: `(not (?e :attr :val))` filters out matching bindings
- **Compiled queries**: `compile-query` macro wraps `query` in a `defun`
- **Index-aware**: first clause uses `find-entities` when both attr and value are concrete; join clauses use direct `gethash` on the entity cache when entity+attribute are resolved

```lisp
;; This works today:
(query '((?e :agent/status :running) (?e :agent/name ?name)))
;; => ((:?E . 42) (:?NAME . "researcher")) ...)

;; Compiled named query:
(compile-query running-agents
  ((?e :agent/status :running) (?e :agent/name ?name)))
```

**But nobody calls it.** Grep across the entire `platform/src/` tree (excluding `substrate/datalog.lisp` itself and test files) finds zero call sites. Every multi-attribute read is expressed as sequential `entity-attr` calls.

### 2. Query Patterns That Would Benefit from Datalog

| Call site | Current pattern | Equivalent Datalog |
|-----------|----------------|-------------------|
| `builtin-tools.lisp:592-596` (query-agent) | 4 sequential `entity-attr` calls | `((?e :agent/status ?s) (?e :agent/task ?t) (?e :agent/started-at ?st) (?e :agent/result ?r))` |
| `prompt-registry.lisp:240-253` | `find-entities` + 10 `entity-attr` per EID in loop | `((?e :entity/type :prompt) (?e :prompt/name ?n) (?e :prompt/body ?b) ...)` |
| `team-coordination.lisp:57-65` (claim-task) | `find-entities` + status filter + `take!` | `((?e :task/workspace-id ?ws) (?e :task/status :pending))` then `take!` on result |
| `team-coordination.lisp:90-100` (list-tasks) | `find-entities` + 4 `entity-attr` per EID | `((?e :task/workspace-id ?ws) (?e :task/status ?s) (?e :task/content ?c) (?e :task/claimed-by ?cb))` |
| `conductor.lisp:202-203` (active-workers) | `find-entities` + `mapcar entity-attr` | `((?e :worker/status :running) (?e :worker/task-id ?tid))` |
| `context.lisp:44-48` (context-history) | Iterative `entity-attr :turn/parent` walk | Recursive Datalog (not currently supported) |

### 3. CL Datalog Ecosystem

**Native CL libraries:**

| Library | Status | Notes |
|---------|--------|-------|
| [cl-datalog](https://github.com/thephoeron/cl-datalog) | 13 commits, unmaintained | On Quicklisp. Minimal. |
| [cl-grph](https://github.com/inconvergent/cl-grph) | Last commit 2022 | Immutable graph + Datalog with `and`/`or`/`not`/`or-join` and fixed-point iteration |
| [AP5](https://ap5.com/) | Active through 2025 | Deductive database embedded in CL. `defrelation`, views, constraints, triggers. Public domain. |
| [cl-facts](https://github.com/facts-db/cl-facts) | Maintained | Triple store with skip lists. Simple query with `?variable` wildcards. Not Datalog. |
| [fact-base](https://github.com/Inaimathi/fact-base) | Maintained | Append-only triple store. No Datalog. Lisp predicates for selection. |
| [Screamer](https://github.com/nikodemus/screamer) | Maintained | Constraint logic programming. Not Datalog but powerful. |
| [si-kanren](https://quickdocs.org/si-kanren) | On Quicklisp | miniKanren relational programming |

**External engines (reachable via FFI or HTTP):**

| Engine | Language | Access from CL | Notes |
|--------|----------|---------------|-------|
| [Datalevin](https://github.com/juji-io/datalevin) | Clojure/JVM | HTTP API, JSON | LMDB-backed. Most production-ready OSS Datomic alternative. Updated Jan 2026. |
| [XTDB](https://xtdb.com) | Clojure/JVM | HTTP/JSON | Bitemporal. SQL + Datalog. |
| [Soufflé](https://souffle-lang.github.io/) | C++ | CFFI (no existing bindings) | Compiles Datalog to parallel C++. Embeddable via `__EMBEDDED_SOUFFLE__`. |
| [DataScript](https://github.com/tonsky/datascript) | Clojure/JS | None directly | In-memory. The reference design. |
| [AllegroGraph](https://allegrograph.com/) | Allegro CL | Native CL API | Commercial. SPARQL + Prolog over RDF. |

**Academic:**
- [Racket `datalog`](https://docs.racket-lang.org/datalog/) — full Datalog with tabling. Built into Racket.

### 4. What the Existing Engine Lacks

The `datalog.lisp` engine is functional but basic:

- **No aggregation** — no `count`, `sum`, `min`, `max`
- **No recursion / fixed-point** — can't express transitive closure (e.g., ancestor walking)
- **No projection** — returns full binding maps, no `:find` clause to select specific variables
- **No ordering** — results are unordered
- **No rules** — only ground clauses, no derived relations
- **No `or`/disjunction** — only conjunction + negation
- **`compile-query` is trivial** — just wraps `query` in `defun`, doesn't actually compile to optimized code
- **Join strategy is naive** — full cache scan when entity or attribute is unresolved in a join clause

### 5. Paths Forward

**Path A: Adopt the existing `datalog.lisp` engine across the codebase**
- Zero new dependencies
- Replace sequential `entity-attr` call sites with `query` calls
- Add `:find` projection, aggregation, ordering as needed
- Limitation: no recursion (can't replace `context-history` parent-chain walks)

**Path B: Integrate AP5**
- Actively maintained (2025), public domain, embeds in CL
- `defrelation` maps naturally to entity-type declarations
- Has constraints, triggers, computed relations
- Would need an adapter layer to bridge AP5 relations ↔ substrate datoms

**Path C: Run Datalevin as sidecar**
- Most capable engine (cost-based optimizer, vector search, full-text)
- LMDB storage (the substrate already supports LMDB)
- Requires JVM, HTTP/JSON bridge, serialization overhead
- Adds operational complexity

**Path D: Extend `datalog.lisp` into a real engine**
- Add rules (`defrule`), recursion with tabling, aggregation, projection
- Reference: DataScript internals ([tonsky.me/blog/datascript-internals](https://tonsky.me/blog/datascript-internals/))
- Reference: Racket Datalog with tabling ([docs.racket-lang.org/datalog/](https://docs.racket-lang.org/datalog/))
- Fits the homoiconic philosophy (queries as S-expressions, rules as data)

## Code References

- `platform/src/substrate/datalog.lisp` — Existing Datalog engine (257 lines)
- `platform/src/substrate/entity.lisp:41-51` — `entity-attr` O(1) point read
- `platform/src/substrate/linda.lisp:39-81` — `take!` atomic claim
- `platform/src/substrate/query.lisp:16-33` — `find-entities` value-index query
- `platform/src/integration/builtin-tools.lisp:592-596` — 4-attr sequential read (query-agent)
- `platform/src/integration/prompt-registry.lisp:240-253` — 10-attr sequential read
- `platform/src/workspace/team-coordination.lisp:57-100` — find+filter+take pattern
- `platform/src/orchestration/conductor.lisp:202-203` — find+map pattern
- `platform/src/conversation/context.lisp:44-48` — linked-list walk (needs recursion)

## Open Questions

- Should the existing `datalog.lisp` be promoted to a first-class query API? It already works.
- Would rules + recursion (for transitive closure) be worth the complexity?
- Is there value in AP5's constraint/trigger model given that `defsystem` already provides reactive dispatch?
