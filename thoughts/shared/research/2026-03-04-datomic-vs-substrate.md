---
date: "2026-03-04T05:33:31Z"
researcher: Claude
git_commit: f2b2f48
branch: main
repository: autopoiesis
topic: "Should Autopoiesis use actual Datomic instead of the custom substrate?"
tags: [research, codebase, substrate, datomic, database, architecture]
status: complete
last_updated: "2026-03-04"
last_updated_by: Claude
---

# Research: Actual Datomic vs. Custom Substrate — Pros and Cons

**Date**: 2026-03-04T05:33:31Z
**Researcher**: Claude
**Git Commit**: f2b2f48
**Branch**: main
**Repository**: autopoiesis

## Research Question

Should Autopoiesis use actual Datomic (or a Datomic-alternative like XTDB/Datalevin) instead of the custom Common Lisp substrate? What are the concrete pros and cons?

## Summary

The substrate is a ~2,000 LOC in-process EAV datom store modeled on Datomic's concepts but implemented natively in Common Lisp. It stores all system state (agents, events, conversations, tasks, prompts, workspaces, sandboxes) as datoms, with LMDB persistence, Linda coordination, reactive hooks, and a Datalog query engine. Replacing it with actual Datomic (or an alternative) would require bridging the JVM/CL gap, giving up Linda coordination and the hook system, and accepting network latency on every query — while gaining immutable history, MVCC reads, speculative transactions, distributed scaling, and a battle-tested query optimizer.

---

## PROS: Using Actual Datomic

### 1. Immutable History Across All Time

Datomic preserves every datom ever asserted or retracted. The substrate's `entity-cache` is mutable — `transact!` overwrites the previous value in the hash table. The substrate stores historical datoms in EAVT/AEVT LMDB indexes, but the query engine (`query`, `q`, `pull`) only reads from the current-value `entity-cache`, not from historical indexes.

Datomic gives you `(d/as-of db t)`, `(d/since db t)`, and `(d/history db)` as first-class database values. The substrate's `entity-as-of` (`entity.lisp:87-166`) does reconstruct state at a given tx, but it works by scanning the in-memory EAVT index via `maphash` — O(entire index) per query.

### 2. MVCC / Snapshot Isolation for Reads

Datomic peers read against immutable database values — no locking required. The substrate serializes ALL reads and writes through a single `bt:make-lock` (`store.lisp:154`). Every `entity-attr` call that resolves through the entity cache races with `transact!` calls that mutate it. The lock prevents data corruption but means reads block on writes and vice versa.

### 3. Speculative Transactions (`d/with`)

`(d/with db tx-data)` returns a new database value without any I/O. You can query `db-after` as if the transaction happened. This enables what-if analysis, test fixtures, and application-level staging. The substrate has no equivalent — `transact!` always mutates the global cache.

### 4. Battle-Tested Schema System

Datomic's schema provides 15 value types, cardinality constraints, uniqueness (identity/value), component cascading, attribute-level predicates, and entity-level specs. The substrate is completely schemaless — values are arbitrary Lisp objects serialized via `prin1-to-string`. There is no type checking, no cardinality enforcement, and no referential integrity.

### 5. Query Optimizer

Datomic's query engine selects optimal join orders, uses all five indexes (EAVT, AEVT, AVET, VAET, Log), and supports aggregates, predicates, function clauses, `or`/`or-join`, and multi-database queries. The substrate's Datalog engine executes clauses left-to-right with no optimization — the caller must order clauses most-selective-first. There are no aggregates, no predicates, no disjunction.

### 6. Rich Pull API

Datomic's Pull supports nested patterns (`{:person/friends [:person/name]}`), reverse navigation (`[:release/_artists]`), recursion with depth limits, attribute renaming, value transformation, and defaults. The substrate's `pull` does flat attribute reads only — no nesting, no reverse refs, no recursion.

### 7. Transaction Functions

Datomic transaction functions run inside the transactor with access to `db-before`, enabling CAS, conditional writes, and computed assertions. The substrate's `transact!` accepts a static list of datoms — there is no way to condition a write on the current database state within the same atomic operation (except `take!`, which is specific to Linda coordination).

### 8. Distributed Read Scaling

Datomic's Peer model gives each client an in-process cache of immutable index segments. Reads scale horizontally without coordination. The substrate is single-process only — all reads go through one entity-cache hash table protected by one lock.

### 9. Excision (GDPR Compliance)

Datomic can physically remove datoms from all history. The substrate has no equivalent — once a datom is written to LMDB, it persists in the EAVT/AEVT indexes permanently. Retraction only updates the `ea-current` and entity-cache.

### 10. Mature Ecosystem

Datomic has extensive documentation, a Jepsen-verified consistency model, 10+ years of production use at Nubank (hundreds of millions of customers), and active development. The substrate is ~2,000 LOC with 187 test assertions.

---

## CONS: Using Actual Datomic

### 1. JVM Dependency — Fundamental Architecture Mismatch

Datomic is a JVM library. Common Lisp cannot embed a Datomic Peer. The only option is the REST Peer Service, which means:
- Every query becomes an HTTP request with EDN serialization/deserialization
- No in-process peer caching (the key Datomic performance advantage is lost)
- Need a CL EDN parser (none mature exists)
- The only CL Datomic wrapper (`cl-datomic`) was abandoned in 2015

This is the single biggest obstacle. You would be using Datomic through its worst-performing interface while giving up its best feature (the Peer cache).

### 2. Loss of Linda Coordination (`take!`)

The substrate's `take!` primitive is used for two critical patterns:
- **Event queue draining** (`conductor.lisp:133`): the conductor tick loop atomically claims pending events
- **Task claiming** (`team-coordination.lisp:64`): agents atomically claim tasks from a shared queue

Datomic has no equivalent of `take!`. You would need to implement distributed coordination via CAS transaction functions (`db/cas`), which requires JVM code running inside the Datomic transactor — not callable from CL.

### 3. Loss of Reactive Hook System

The substrate's `register-hook` fires callbacks after every transaction, used for:
- `defsystem` reactive dispatch (attribute → system routing, topologically sorted)
- Condition-variable wakeup for agent-await patterns (single and batch)

Datomic has no post-transaction callback mechanism from the peer side. You would need to poll the transaction log or use Datomic's tx-report-queue (JVM API only, not available via REST).

### 4. Loss of In-Process Performance

Current substrate operations are sub-microsecond:
- `entity-attr`: one `gethash` (O(1), ~50ns)
- `pull`: N `gethash` calls
- `transact!`: lock + hash table mutations + optional LMDB write

With Datomic via REST: minimum ~1ms per HTTP round-trip, plus EDN serialization overhead. For the conversation system (which does `entity-attr` on every turn traversal in `context-history`), this would be orders of magnitude slower.

### 5. Operational Complexity

Running Datomic requires:
- A JVM process for the transactor
- A JVM process for the REST peer service
- A storage backend (DynamoDB, PostgreSQL, etc.)
- Monitoring, backup, and lifecycle management for all of these

The substrate is zero-ops: it's a library loaded into the SBCL image with optional LMDB file persistence.

### 6. Loss of Homoiconic Integration

The substrate is deeply integrated with the CL image:
- Values can be arbitrary Lisp objects (functions, CLOS instances, symbols)
- `prin1`/`read` serialization preserves CL data types natively
- `defsystem` handlers are lambdas
- `define-entity-type` generates CLOS classes with `slot-unbound` lazy loading
- The blob store uses `ironclad` directly for SHA-256

With Datomic, values are restricted to Datomic's 15 types. Lisp objects would need explicit serialization to strings/bytes, losing the seamless CL integration.

### 7. No Common Lisp Ecosystem

There is no maintained CL Datomic client, no CL EDN library, and no CL implementation of Datomic-like semantics beyond what the substrate already provides. Building the bridge would be a significant project itself.

### 8. Closed Source

Datomic binaries are free (Apache 2.0 for the compiled JARs), but the source is closed. You cannot fork, patch, or inspect the internals. If you hit a bug or need a feature, you're dependent on Nubank's priorities.

### 9. `take!` Bypasses Would Need Rearchitecting

The substrate's `take!` intentionally bypasses hooks and EAVT/AEVT indexes for performance — it only updates the entity-cache and value-index. This is a design choice specific to the Linda coordination model. In Datomic, all writes go through the transactor and are fully indexed. You would need to rethink the event queue and task claiming patterns entirely.

### 10. Schema Rigidity vs. Flexibility

The substrate's schemalessness is a feature for the current use case: agents dynamically add attributes (`update-sub-agent` constructs attribute keywords from plist keys at runtime, `builtin-tools.lisp:525-531`). Datomic requires every attribute to be declared with a value type before use. This would constrain the self-modifying agent architecture.

---

## Alternatives Worth Considering

### XTDB via Postgres Wire Protocol

XTDB v2 exposes a Postgres-compatible wire protocol, meaning CL can connect using `cl-postgres` (a mature, maintained library). This gives:
- Bitemporality (system-time + valid-time)
- SQL queries (no EDN needed)
- No JVM embedding required from CL side
- Open source (Apache 2.0 with source)

**But**: no `take!`, no hooks, no in-process performance, still requires running a JVM.

### Datalevin (Embedded LMDB-Based Datomic)

Datalevin runs on LMDB (same as the substrate), supports Datalog, and has a cost-based query optimizer reportedly faster than PostgreSQL on complex joins. It positions itself as "an agent's memory model" for AI systems.

**But**: JVM/Clojure only, no CL bindings, no transaction-time history (deletes are permanent).

### Keep Substrate, Steal Ideas

The substrate already implements Datomic's core model. The most valuable Datomic features that could be added to the substrate without changing the architecture:

| Feature | Difficulty | Value |
|---------|-----------|-------|
| MVCC reads (snapshot isolation) | Medium — copy entity-cache per "db value" | High |
| `d/with` speculative transactions | Medium — apply to snapshot, don't persist | High |
| Schema with value types | Low — add to `define-entity-type` | Medium |
| Aggregates in Datalog | Low — post-process bindings | Medium |
| Nested Pull patterns | Medium — recursive pull with ref following | Medium |
| Query optimizer (join reordering) | Hard — selectivity estimation | Medium |
| Full as-of via Datalog | Medium — route queries through EAVT index | Medium |

---

## Architecture Comparison

```
SUBSTRATE (current)                    DATOMIC (hypothetical)
┌───────────────────┐                  ┌───────────────────┐
│   SBCL Process    │                  │   SBCL Process    │
│                   │                  │                   │
│  entity-cache ────┤ O(1) reads       │  HTTP client ─────┤ ~1ms per query
│  value-index      │                  │  EDN parser       │
│  intern-tables    │                  │                   │
│  query/q/pull     │                  └───────┬───────────┘
│  take!            │                          │ REST API
│  hooks/defsystem  │                          │
│  blob store       │                  ┌───────┴───────────┐
│                   │                  │  REST Peer (JVM)  │
│  LMDB ────────────┤ persistence      │  Peer cache       │
└───────────────────┘                  │  Query engine     │
                                       └───────┬───────────┘
                                               │
                                       ┌───────┴───────────┐
                                       │  Transactor (JVM) │
                                       │  Write serializer │
                                       └───────┬───────────┘
                                               │
                                       ┌───────┴───────────┐
                                       │  Storage Backend  │
                                       │  (DynamoDB/PG/...)│
                                       └───────────────────┘
```

---

## Verdict Framework

**Use actual Datomic if:**
- You need distributed read scaling across multiple processes
- You need GDPR-compliant excision
- You need a battle-tested query optimizer for complex analytical queries
- You're willing to run JVM infrastructure alongside CL
- Your query patterns are request/response (not reactive/streaming)

**Keep the substrate if:**
- In-process, sub-microsecond reads are essential (conversation traversal, cognitive loops)
- Linda coordination (`take!`) is a core architectural pattern
- Reactive hooks drive system behavior (defsystem, agent-await)
- Zero-ops deployment matters (single SBCL binary + LMDB file)
- Homoiconic data (arbitrary CL values as datom values) is used
- The system is single-process (no distributed read scaling needed)

**The pragmatic middle ground:**
Keep the substrate for runtime state (events, agents, tasks, conversations) where in-process performance and Linda coordination are critical. Adopt Datomic-inspired improvements (MVCC snapshots, speculative `with`, schema types) within the CL codebase. Consider XTDB via Postgres wire protocol only if you eventually need cross-process queryable state with bitemporality.

---

## Code References

- `platform/src/substrate/store.lisp` — Store class, `transact!`, lock, hooks
- `platform/src/substrate/entity.lisp` — Entity cache, `entity-attr`, `entity-state`
- `platform/src/substrate/datalog.lisp` — Query engine, `q`, `pull`, rules
- `platform/src/substrate/linda.lisp` — `take!`, value index
- `platform/src/substrate/lmdb-backend.lisp` — LMDB persistence, restore on startup
- `platform/src/substrate/context.lisp` — Substrate context struct
- `platform/src/substrate/encoding.lisp` — EAVT/AEVT/EA key encoding
- `platform/src/substrate/system.lisp` — `defsystem` reactive dispatch
- `platform/src/substrate/entity-type.lisp` — `define-entity-type` CLOS generation
- `platform/src/orchestration/conductor.lisp:133` — `take!` for event draining
- `platform/src/workspace/team-coordination.lisp:64` — `take!` for task claiming
- `platform/src/integration/builtin-tools.lisp:635-646` — Hook-based agent await

## Related Research

- `thoughts/shared/research/2026-03-03-datalog-direct-usage.md` — Prior research on Datalog usage in the substrate

## Sources

- [Unofficial Guide to Datomic Internals (tonsky.me)](https://tonsky.me/blog/unofficial-guide-to-datomic-internals/)
- [The Architecture of Datomic (InfoQ)](https://www.infoq.com/articles/Architecture-Datomic/)
- [Jepsen: Datomic Pro 1.0.7075](https://jepsen.io/analyses/datomic-pro-1.0.7075)
- [Datomic is Free (blog)](https://blog.datomic.com/2023/04/datomic-is-free.html)
- [Datomic Cloud is Free](https://blog.datomic.com/2023/06/datomic-cloud-is-free.html)
- [Datomic Schema Reference](https://docs.datomic.com/schema/schema-reference.html)
- [Datomic Query Reference](https://docs.datomic.com/query/query-data-reference.html)
- [Datomic Pull API](https://docs.datomic.com/query/query-pull.html)
- [Datomic Transaction Functions](https://docs.datomic.com/transactions/transaction-functions.html)
- [Datomic Excision](https://docs.datomic.com/operation/excision.html)
- [Datomic Language Support](https://docs.datomic.com/operation/languages.html)
- [cl-datomic (GitHub)](https://github.com/thephoeron/cl-datomic) — abandoned 2015
- [Datalevin (GitHub)](https://github.com/juji-io/datalevin)
- [Datalevin Jan 2026 Progress](https://yyhh.org/blog/2026/01/triple-store-triple-progress-datalevin-posited-for-the-future/)
- [XTDB Overview](https://docs.xtdb.com/intro/what-is-xtdb.html)
- [Learn Datalog Today](https://www.learndatalogtoday.org/)
