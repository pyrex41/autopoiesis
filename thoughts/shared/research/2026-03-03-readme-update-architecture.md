---
date: 2026-03-03T21:44:42Z
researcher: Claude
git_commit: 5d5c3a6
branch: main
repository: autopoiesis
topic: "README update to reflect architectural features — Linda coordination, snapshot DAG, conductor, multi-provider loops"
tags: [research, codebase, readme, architecture, substrate, snapshot, conductor, integration]
status: complete
last_updated: 2026-03-03
last_updated_by: Claude
---

# Research: README Update — Architectural Features

**Date**: 2026-03-03T21:44:42Z
**Researcher**: Claude
**Git Commit**: 5d5c3a6
**Branch**: main
**Repository**: autopoiesis

## Research Question

Update the README to reflect the current state of the project, covering the architectural features that make it interesting under the hood: the Linda coordination model, the snapshot DAG, the conductor pattern, multi-provider agentic loops, and the self-extension pipeline.

## Summary

The existing README covered the high-level pitch and usage examples well but treated the architecture section as a flat list of layer descriptions. The updated README adds a new "Under the Hood" section that explains six key architectural features with code examples and design rationale:

1. **Substrate with Linda `take!`** — the datom store's inverted value index enables O(1) atomic coordination
2. **Snapshot DAG** — content-addressable S-expression hashing, structural diffing, lazy loading
3. **Cognitive loop as data** — five-phase cycle producing S-expression primitives
4. **Self-extension pipeline** — draft/testing/promoted workflow with code walking sandbox
5. **Conductor** — substrate-backed orchestration with no in-memory queues
6. **Multi-provider agentic loops** — `define-cli-provider` macro, bidirectional tool mapping

## Detailed Findings

### Substrate Layer
- Datom struct: 5 fields (entity u64, attribute u32, value any, tx u64, added bool)
- Three indexes: EAVT, AEVT (both append), EA-CURRENT (replace)
- Inverted value index: `(attribute-id . value)` → hash-set of entity IDs
- `take!` holds store lock for entire find-and-update — structural atomicity
- `defsystem` reactive dispatch with topological sort via Kahn's algorithm
- `with-batch-transaction` accumulates writes, flushes atomically at outermost level
- Single `substrate-context` struct replaces 7+ special variables

### Snapshot Layer
- SHA-256 hashing with type-tagged digesting (S→symbol, I→integer, "("→cons, etc.)
- Content store: reference-counted deduplication
- Filesystem: two-char prefix sharding for directory distribution
- Branch = named mutable pointer to snapshot ID
- Diff: recursive descent on cons tree, emits `:replace` edits with `:car`/`:cdr` paths
- Patch: `copy-tree` + structural reconstruction without mutation
- Lazy loading: `lazy-snapshot` proxy uses `slot-unbound` MOP method
- Consistency: 6 checks (DAG integrity, hash verification, branch, index, states, timestamps)

### Cognitive Architecture
- Five CLOS generic functions: perceive, reason, decide, act, reflect
- Each primitive's `content` slot holds an S-expression
- Thought stream: adjustable vector + hash-table index for O(1) lookup
- Context window: priority queue with `sexpr-size` estimation (4 chars/token)

### Self-Extension
- Code walker validates operator positions only (not value references)
- Handles lambda, let/let*, flet/labels, quote, function, loop
- ~100 whitelisted safe symbols, explicit forbidden list
- Auto-reject after 3 runtime errors
- Checkpoint hook for snapshot-and-revert around extension execution

### Conductor
- 100ms tick loop: process-due-timers then process-events
- No in-memory queues — all state as substrate datoms
- Timer heap: sorted list with CL `merge` for O(log n) insert
- Workers: substrate entities with `:worker/status` tracked via value index
- Claude CLI: `sb-ext:run-program` with `/dev/null` stdin redirect, SIGTERM+SIGKILL timeout

### Integration
- `define-cli-provider` macro: generates class, constructor, command builder, parser, serializer
- Two parser modes: `:json-object` and `:jsonl-events`
- `llm-complete` generic function dispatches by CLOS on client type
- MCP: JSON-RPC 2.0 over stdio, `mcp-tool-to-capability` bridges to agent capabilities
- Tool mapping: `lisp-name-to-tool-name` / `tool-name-to-lisp-name` (substitute #\_ #\-)
- 16 event types in pub/sub bus with 1000-event circular history

### Conversation Layer
- Turns as substrate datoms with content-addressed blob storage
- O(1) fork via shared head pointer
- Single-transaction writes for crash safety
- Dual-track: in-memory list for API, substrate for durable history

### Swarm Module
- Genome: capabilities + heuristic weights + parameters
- Crossover: uniform (50% inclusion), numeric averaging
- Mutation: add/remove capabilities, perturb weights (default 10% rate)
- Selection: tournament, roulette, elitism
- Production rules: convert heuristics to conditional genome transforms

## Code References
- `platform/src/substrate/datom.lisp` — Datom struct definition
- `platform/src/substrate/linda.lisp` — `take!` implementation
- `platform/src/substrate/store.lisp` — `transact!`, indexes, batch transactions
- `platform/src/substrate/system.lisp` — `defsystem` reactive dispatch
- `platform/src/substrate/context.lisp` — Single context struct
- `platform/src/core/s-expr.lisp` — Hash, diff, patch, equality
- `platform/src/core/cognitive-primitives.lisp` — Five primitive types
- `platform/src/core/extension-compiler.lisp` — Code walker, sandbox
- `platform/src/core/thought-stream.lisp` — Stream with index
- `platform/src/agent/cognitive-loop.lisp` — Five-phase cycle
- `platform/src/agent/capability.lisp` — defcapability macro
- `platform/src/agent/agent-capability.lisp` — Draft/testing/promoted pipeline
- `platform/src/agent/learning.lisp` — N-gram patterns, heuristics
- `platform/src/snapshot/persistence.lisp` — Filesystem storage, LRU cache
- `platform/src/snapshot/diff-engine.lisp` — Snapshot diff/patch
- `platform/src/snapshot/time-travel.lisp` — DAG traversal, common ancestor
- `platform/src/snapshot/lazy-loading.lisp` — Lazy proxies, batch iterator
- `platform/src/conversation/turn.lisp` — Turn creation with blob storage
- `platform/src/conversation/context.lisp` — Context forking
- `platform/src/integration/claude-bridge.lisp` — Agentic loop
- `platform/src/integration/provider.lisp` — Provider protocol
- `platform/src/integration/provider-macro.lisp` — define-cli-provider
- `platform/src/integration/tool-mapping.lisp` — Bidirectional name conversion
- `platform/src/integration/mcp-client.lisp` — MCP JSON-RPC client
- `platform/src/integration/builtin-tools.lisp` — 20+ built-in tools
- `platform/src/integration/agentic-agent.lisp` — Cognitive cycle + agentic loop bridge
- `platform/src/orchestration/conductor.lisp` — Tick loop, events, workers
- `platform/src/orchestration/claude-worker.lisp` — Claude CLI subprocess
- `platform/src/swarm/genome.lisp` — Genome representation
- `platform/src/swarm/operators.lisp` — Crossover, mutation
- `platform/src/swarm/population.lisp` — Evolution loop

## Architecture Documentation

The README now documents the full 12-layer architecture (substrate through cross-cutting) with emphasis on the design patterns that differentiate the system:
- Linda coordination as the concurrency primitive (vs locks/channels)
- Content-addressable S-expression hashing as the persistence primitive (vs ORM/serialization)
- Substrate datoms as the universal state medium (vs in-memory data structures)
- Homoiconicity enabling self-modification, diffing, and time-travel on the same representation
