---
date: "2026-03-04T05:50:06Z"
researcher: Claude
git_commit: 23867ac
branch: main
repository: autopoiesis
topic: "Common Lisp-compatible Datalog databases"
tags: [research, codebase, substrate, datalog, database, cl-ffi]
status: complete
last_updated: "2026-03-04"
last_updated_by: Claude
---

# Research: Common Lisp-Compatible Datalog Databases

**Date**: 2026-03-04T05:50:06Z
**Researcher**: Claude
**Git Commit**: 23867ac
**Branch**: main
**Repository**: autopoiesis

## Research Question

Are there any Datalog databases that could be used from SBCL Common Lisp, either natively or via FFI?

## Summary

There is no actively maintained, pure Common Lisp Datalog database with persistence and time-travel. The strongest external option is **CozoDB** (Rust, MPL-2.0), which has a clean C API callable via CFFI. However, the serialization overhead (CL → JSON string → C API → JSON string → CL) on every query makes it a hard sell for a system where `entity-attr` is ~50ns. The pragmatic path remains improving the substrate's own Datalog engine.

---

## Options Evaluated

### Tier 1: Realistic from SBCL

#### CozoDB (Rust, C API) — Best External Option

- **Source**: [github.com/cozodb/cozo](https://github.com/cozodb/cozo)
- **License**: MPL-2.0
- **Maturity**: Active, 1,800+ commits, v0.7
- **CL usability**: Clean C API (`cozo_c.h`, 8 functions). Pre-built `.dylib`/`.so` for Mac/Linux. Unofficial CL binding at [pegesund/cozodb-lisp](https://github.com/pegesund/cozodb-lisp) (14 commits, early).
- **Features**: Datalog with recursive rules, aggregations, built-in graph algorithms (BFS, PageRank, Louvain), time-travel (opt-in per relation via `Validity` key), vector search (HNSW), full-text search, multiple storage backends (memory, SQLite, RocksDB, TiKV).
- **C API**: `cozo_open_db`, `cozo_close_db`, `cozo_run_query`, `cozo_import_relations`, `cozo_export_relations`, `cozo_backup`, `cozo_restore`, `cozo_free_str`. All I/O is JSON strings over `char*`.
- **Caveats**: Time-travel is opt-in per relation with explicit `Validity` columns, not Datomic's universal append-only log. All queries go through JSON serialization.

#### Datahike (Clojure, beta C bindings via GraalVM)

- **Source**: [github.com/replikativ/datahike](https://github.com/replikativ/datahike)
- **License**: EPL
- **Maturity**: Active, 1,659+ commits, production use (Swedish government)
- **CL usability**: `libdatahike` provides C/C++ native bindings via GraalVM native-image. Beta quality. Requires GraalVM to build — significant build dependency.
- **Features**: Most Datomic-faithful open-source alternative. Append-only, immutable log, full time-travel, LMDB backend option, GDPR excision.

### Tier 2: Archived or Impractical

| Option | Language | CL Path | Status | Notes |
|--------|----------|---------|--------|-------|
| Mozilla Mentat | Rust | C FFI crate exists | **Archived 2018** | Datomic-inspired EAV + Datalog on SQLite |
| DDlog | Haskell→Rust | `ddlog.h` C API | **Archived** | Incremental Datalog, unique reactive model |
| datom-rs | Rust | `datom-c` subdir | Pre-release | Datomic clone, requires nightly Rust |
| Soufflé | C++ | Needs `extern "C"` wrapper | Active | Batch-only, no persistence, program analysis focus |
| XTDB | Clojure | HTTP/REST only | Active | Bitemporality, but not embeddable from CL |
| Datalevin | Clojure | No C API (issue #37 open) | Active | LMDB backend like our substrate, but JVM-only |
| DataScript | ClojureScript | JS only | Active | In-memory only, no persistence |

### Tier 3: Native CL (All Inadequate)

| Option | Notes |
|--------|-------|
| cl-datalog | MIT, Quicklisp. Toy — 13 commits, no persistence, abandoned |
| AP5 | Public domain, 1989 origins, 2024 update. Relational logic programming, not a database |
| vivace-graph-v3 | ACID graph DB with Prolog queries, SBCL native. Dead since 2016 |
| si-kanren | miniKanren in CL. Logic programming, not a database |
| LambdaLite | ~250 LOC functional in-memory relational DB. No Datalog |
| bknr.datastore | CLOS-based in-RAM DB with tx logging. No Datalog |

---

## Assessment for Autopoiesis

### Why not CozoDB?

CozoDB is genuinely good, but the integration cost is real:

1. **Serialization overhead**: Every query becomes CL → JSON string → CFFI call → Rust parsing → execution → JSON string → CL parsing. Our substrate does `entity-attr` in ~50ns (one `gethash`). CozoDB via CFFI would be 10-100x slower minimum.

2. **Dual state problem**: We'd need to keep the substrate for `take!`, hooks, and in-process entity cache, then sync state to CozoDB for queries. Two sources of truth.

3. **Loss of homoiconic values**: CozoDB values are typed (int, float, string, bool, list, bytes). No arbitrary Lisp objects.

4. **Build dependency**: Pre-built binaries exist but add a native library dependency to what is currently a pure-CL system.

### When CozoDB would make sense

- If we needed graph algorithms (shortest path, PageRank, community detection) over substrate entities
- If we needed vector search / semantic similarity over stored data
- If query complexity grew beyond what our Datalog engine handles well (complex joins, aggregations)
- If we needed a secondary analytical query layer (not replacing the substrate, augmenting it)

### Current recommendation

Keep improving the substrate's Datalog engine. We just added `q`, `pull`, `:in` params, and recursive rules. The next high-value additions would be:

- Aggregates (`count`, `sum`, `min`, `max`) as post-processing on `q` results
- Join optimization (use value index when attribute is known but entity is unbound)
- `d/with`-style speculative transactions (apply to snapshot, don't persist)

These are each ~100-200 LOC additions to `datalog.lisp` and keep everything in-process.

---

## Related Research

- [`thoughts/shared/research/2026-03-04-datomic-vs-substrate.md`](2026-03-04-datomic-vs-substrate.md) — Full Datomic vs substrate analysis
- [`thoughts/shared/research/2026-03-03-datalog-direct-usage.md`](2026-03-03-datalog-direct-usage.md) — Datalog usage in the substrate

## Sources

- [CozoDB GitHub](https://github.com/cozodb/cozo)
- [CozoDB Docs](https://docs.cozodb.org/)
- [CozoDB C Header](https://github.com/cozodb/cozo/blob/main/cozo-lib-c/cozo_c.h)
- [cozodb-lisp unofficial binding](https://github.com/pegesund/cozodb-lisp)
- [Datahike GitHub](https://github.com/replikativ/datahike)
- [Mozilla Mentat GitHub (archived)](https://github.com/mozilla/mentat)
- [DDlog GitHub (archived)](https://github.com/vmware-archive/differential-datalog)
- [Soufflé](https://souffle-lang.github.io/)
- [cl-datalog](https://github.com/thephoeron/cl-datalog)
- [AP5](https://ap5.com/)
- [vivace-graph-v3](https://github.com/kraison/vivace-graph-v3)
- [Datalevin C API issue](https://github.com/juji-io/datalevin/issues/37)
