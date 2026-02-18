---
date: 2026-02-16T17:00:00-06:00
researcher: reuben
git_commit: 8a80e4d4027b6cd9827b3006adea064a081e225e
branch: main
repository: autopoiesis
topic: "Substrate Extension Points: What's Implemented vs What's Proposed"
tags: [research, substrate, extension-points, datom, hooks, cortex, architecture]
status: complete
last_updated: 2026-02-16
last_updated_by: reuben
---

# Research: Substrate Extension Points — Implemented vs Proposed

**Date**: 2026-02-16T17:00:00-06:00
**Researcher**: reuben
**Git Commit**: 8a80e4d
**Branch**: main
**Repository**: autopoiesis

## Research Question

Review `~/projects/thinking/substrate-extension-points.md` — what extension points from the proposed substrate design have we implemented, and what should we implement?

## Summary

The substrate extension points document proposes 8 extension points for a small-kernel datom-based system. **Autopoiesis has implemented functional equivalents for 3 of them** (`define-tool`, `register-hook`, `define-condition`), **has partial coverage for 2** (`define-adapter`, `define-repl-command`), and **has not implemented 3** (`define-index`, `define-entity-type`, `define-query-operator`). Critically, the foundational substrate primitives — datom struct, `transact!`, LMDB indexes, EAVT/AEVT — **do not exist in Autopoiesis**. They exist in Cortex (a separate codebase). The gap is not in individual extension points but in the substrate itself.

## Extension Point Status Matrix

| Extension Point | Proposed Role | AP Implementation | Status |
|---|---|---|---|
| **define-index** | Register LMDB named databases with custom key encoding | No LMDB, no indexes, no datoms | **Not implemented** |
| **register-hook** | on-transact callbacks receiving datoms | Event bus with `subscribe-to-event` / `emit-integration-event` | **Partial analog** |
| **define-tool** | Register tools for Claude/MCP | `defcapability` macro + `*capability-registry*` + MCP bridge | **Implemented** (different name) |
| **define-entity-type** | Declare entity types and expected attributes | No schema/type declaration system | **Not implemented** |
| **define-query-operator** | Register custom query operators | No query compiler or operator registration | **Not implemented** |
| **define-adapter** | Register adapters with lifecycle management | Provider protocol (`provider-invoke`, `provider-alive-p`, etc.) | **Partial analog** |
| **define-condition** | Register condition types and standard restarts | Full condition hierarchy with 6 standard restarts | **Implemented** |
| **define-repl-command** | Register REPL commands and reader macros | CLI command dispatch via `parse-cli-command` / `execute-cli-command` | **Partial analog** |

## Detailed Findings

### 1. The Missing Substrate: No Datoms, No `transact!`, No LMDB

The extension points document assumes a substrate with:
- A `datom` struct with `(entity, attribute, value, tx, valid-time, added)` fields
- A `transact!` function that atomically writes to all registered indexes
- EAVT/AEVT indexes backed by LMDB
- Hooks that fire after transaction commit with full datom lists

**None of this exists in Autopoiesis.** The codebase has no `datom` struct, no `transact!` function, no LMDB integration, and no EAVT/AEVT indexes. Persistence is file-based S-expression snapshots (`src/snapshot/persistence.lisp:98`), with an in-memory SHA-256 content-addressable store (`src/snapshot/content-store.lisp`) and in-memory LRU cache (`src/snapshot/lru-cache.lisp`).

**Cortex** (a separate CL codebase, available as `cortex-code.xml`) *does* have these primitives:
- `trace-event` struct with id, timestamp, source, entity-type, entity-id, content
- `trace-store` for in-memory event storage with temporal/entity indexes
- LMDB persistence via `lmdb-schemas.lisp`, `lmdb-persistence.lisp`, `lmdb-ops.lisp`
- `image-store-event` that writes to store + updates temporal-index + entity-index

But Cortex's event model (`trace-event`) is not the same as the proposed datom model. It's closer to a document store than EAV.

### 2. `register-hook` → Event Bus (Partial)

**Proposed**: `register-hook` receives `(datoms tx-id)` after every transaction.

**What exists**: `src/integration/events.lisp` provides a typed event bus:
- `subscribe-to-event` (type, handler-fn) — `events.lisp:120-168`
- `emit-integration-event` — fires all handlers for event type
- `subscribe-to-all-events` — global handlers
- `with-event-handler` — scoped temporary subscription macro (`events.lisp:270`)
- `*event-handlers*` — hash table of type → handler-list
- `*global-event-handlers*` — list of handlers for all events
- Event types: `:thought-created`, `:decision-made`, `:action-executed`, `:snapshot-created`, `:agent-spawned`, `:capability-registered`, etc.

**Gap**: Events are typed (keyword-based dispatch) rather than datom-based. They don't receive raw datoms grouped by transaction. They fire at specific points in application code rather than after a unified `transact!`. This means:
- Modules can't build materialized views from raw writes
- No guarantee of consistency — events fire at emit-time, not commit-time
- Standing queries can't be built because there's no unified write path to hook into

Additionally, `on-thought` callbacks in `agentic-loop` (`claude-bridge.lisp:174`) provide per-step callbacks during agent execution — a separate callback mechanism.

### 3. `define-tool` → `defcapability` (Implemented)

**Proposed**: Register tools for Claude/MCP with schema.

**What exists**: Three-layer tool registration:

**Layer 1 — Capabilities** (`src/agent/capability.lisp`):
- `defcapability` macro (lines 138-171) — declarative tool definition with docstring, permissions, body
- `*capability-registry*` — global hash table
- `register-capability` / `find-capability` / `invoke-capability`
- 22+ built-in tools via `defcapability` (`src/integration/builtin-tools.lisp:26-616`): file ops, web, shell, self-extension, orchestration, branching

**Layer 2 — External Tools** (`src/integration/tool-registry.lisp`):
- `external-tool` class with name, description, JSON schema parameters, handler
- Separate registry from capabilities

**Layer 3 — MCP Bridge** (`src/integration/mcp-client.lisp`):
- `mcp-connect` discovers tools via JSON-RPC `tools/list`
- `mcp-tool-to-capability` bridges MCP tools into the capability registry (lines 398-422)
- Name conversion: `tool-name-to-lisp-name` (snake_case → kebab-case) in `tool-mapping.lisp:19-24`

**Self-extension**: Agents can define new capabilities at runtime:
- `agent-define-capability` validates and compiles source code (`agent-capability.lisp:72-122`)
- `test-agent-capability` runs test cases
- `promote-capability` registers globally after tests pass

This is a fully-realized version of the proposed `define-tool`.

### 4. `define-entity-type` — Not Implemented

**Proposed**: Declare entity types with expected attributes for validation, documentation, and MOP hints.

**What exists**: Nothing. The holodeck uses `defcomponent` from `cl-fast-ecs` for ECS component definitions (`src/holodeck/components.lisp`), but these are compile-time structs for visualization, not runtime entity type declarations. There is no schema validation, no attribute declaration, no entity type registry.

Cortex has entity types (POD, DEPLOYMENT, SERVICE, etc.) but these are implicit in the adapter transformers, not declared via a `define-entity-type` macro.

### 5. `define-query-operator` — Not Implemented

**Proposed**: Register custom query operators that the query compiler recognizes.

**What exists**: No query language or compiler in Autopoiesis. Snapshot navigation uses direct function calls (`find-snapshot-by-timestamp`, `snapshot-children`, `snapshot-ancestors`). The viz layer has `search-snapshots` which does simple string matching.

Cortex has a full S-expression query language with parser (`src/query/parser.lisp`), executor (`src/query/executor.lisp`), and extensions (traversal, join, aggregations). But it doesn't have a `define-query-operator` registration API — operators are baked into the parser.

### 6. `define-adapter` → Provider Protocol (Partial)

**Proposed**: Register adapters with lifecycle management (start/stop/restart/health).

**What exists**: The provider system (`src/integration/provider.lisp`) implements a lifecycle protocol:
- `provider` base class with name, command, process, session state
- `provider-invoke` — one-shot execution
- `provider-start-session` / `provider-stop-session` — streaming lifecycle
- `provider-alive-p` — health check
- `provider-status` — status plist
- `*provider-registry*` — global registry by name
- `register-provider` / `find-provider` / `list-providers`

Concrete implementations: `claude-code-provider`, `codex-provider`, `opencode-provider`, `cursor-provider`, `inference-provider`.

**Gap**: Providers are specifically for AI code assistant subprocess management, not general infrastructure adapters. They don't handle polling, retry, circuit-breaking, or rate limiting. Cortex's adapters (kubernetes, ECS, git, mongodb, redis, otel, crossplane, argocd) are a much closer match to the proposed `define-adapter` but live in a separate codebase.

### 7. `define-condition` — Implemented

**Proposed**: Register condition types and standard restarts.

**What exists**: Full condition hierarchy in `src/core/conditions.lisp`:
- `autopoiesis-error` base condition
- Specific conditions: `capability-not-found`, `permission-denied`, `validation-error`, etc.
- 6 standard restarts in `src/core/recovery.lisp:159-199`
- `with-recovery` macro for structured error handling
- `with-retry` macro for transient error retry
- `with-operation-recovery` combining both

### 8. `define-repl-command` → CLI Command Dispatch (Partial)

**Proposed**: Register REPL commands and reader macros.

**What exists**: `src/interface/session.lisp` provides CLI command parsing:
- `parse-cli-command` — parses user input into command name + args
- `execute-cli-command` — dispatches to handler
- `cli-interact` — REPL loop with prompt/read/eval/print
- Commands: help, status, think, decide, snapshot, branch, diff, etc.

**Gap**: Commands are defined inline in the execution dispatch, not via a `define-repl-command` registration macro. Adding new commands requires editing the dispatch function, not calling a registration API.

### 9. `define-index` — Not Implemented

**Proposed**: Register additional LMDB named databases with custom key-encoding. `transact!` auto-writes to all registered indexes.

**What exists**: Nothing in Autopoiesis. This is the most fundamental missing piece — without a unified write path and index registration, modules can't build custom indexes.

Cortex has `index-add`, `entity-index-add`, and `temporal-index` but these are hardcoded in `image-store-event`, not dynamically registered.

## What Should Be Implemented?

The consolidated architecture plan (`thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md`) already addresses this question. Its 7-phase plan covers:

**Track B (Phases 4-5): LMDB Storage + Blob Store**
- Replaces file-based snapshots with LMDB
- Content-addressed blob storage for LLM responses
- This is the **substrate foundation** the extension points document assumes

**Track C (Phases 6-7): Turn/Context DAG**
- Conversation turns stored as datoms + blobs
- Context entity with head pointer
- This is where **datom-like structures** first appear

The plan explicitly defers several extension points:
- **Standing query / defsystem reactive layer** — "Defer until conversation monitoring is needed"
- **MOP schema specialization** — "AP's cognitive types are fixed"
- **Datalog query language** — "Future work if EAV datoms warrant it"
- **Full EAV decomposition** — "Snapshots remain as blobs; only conversations use datoms"

### Priority Ordering

Based on the consolidated plan and what exists:

1. **LMDB storage** (Phase 4-5) — Foundation for everything. Without persistent indexes, no extension point beyond tools and conditions matters.

2. **`register-hook` upgrade** — When LMDB `transact!` exists, upgrade the event bus to fire after commits with datom lists. This unlocks materialized views, standing queries, and cache invalidation.

3. **`define-index`** — Once `transact!` writes to LMDB, modules should be able to register additional indexes. This enables bitemporal queries without substrate changes.

4. **`define-adapter`** — When the conductor is CL-native (Phase 1), adapt the provider protocol to also handle polling/watching adapters, not just AI subprocess management.

5. **`define-entity-type`** / **`define-query-operator`** / **`define-repl-command`** — These are nice-to-have registration macros that can be added incrementally as needs arise. They don't gate other work.

6. **MOP specialization** / **Standing queries** / **Bitemporal valid-time** — Module-level features that can be built once hooks and indexes exist. As the extension points document correctly argues, these need only `register-hook` and `define-index` from the substrate.

## Code References

- `src/integration/events.lisp:120-270` — Event bus (closest to register-hook)
- `src/agent/capability.lisp:138-171` — defcapability macro (define-tool equivalent)
- `src/integration/builtin-tools.lisp:26-616` — 22+ built-in tools
- `src/integration/tool-registry.lisp:11-87` — External tool registry
- `src/integration/mcp-client.lisp:196-449` — MCP bridge
- `src/integration/tool-mapping.lisp:12-246` — Tool name conversion and schema mapping
- `src/integration/provider.lisp:13-231` — Provider protocol (partial define-adapter)
- `src/core/conditions.lisp` — Condition hierarchy
- `src/core/recovery.lisp:159-199` — 6 standard restarts
- `src/snapshot/persistence.lisp:98` — File-based snapshot persistence (to be replaced by LMDB)
- `src/snapshot/content-store.lisp` — In-memory content-addressable store
- `src/interface/session.lisp` — CLI command dispatch
- `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` — Implementation plan

## Architecture Documentation

Autopoiesis is a monolithic 8-layer CL system with no substrate/module separation. The "substrate" envisioned in the extension points document would need to be extracted or built as a new foundation layer underneath the existing code. The consolidated architecture plan takes a pragmatic approach: build LMDB storage first, then incrementally add extension points as the system evolves toward datom-based storage.

Cortex, while a separate codebase, has many of the primitives the substrate needs (LMDB, trace-events, temporal indexes, adapters, query engine). The synthesis plan (`Autopoiesis + Cortex Synthesis Plan.md`) envisions eventual convergence.

## Related Research

- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Evaluation of thinking repo designs including substrate
- `thoughts/shared/research/2026-02-16-lfe-control-plane-analysis.md` — Analysis supporting CL conductor decision
- `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` — 7-phase implementation plan
- `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md` — CL conductor + convergence design
