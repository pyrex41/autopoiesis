---
date: 2026-02-06T13:30:00-06:00
researcher: claude
git_commit: 9e0717ccdf45665723e8fee4f245d5d46e69080f
branch: main
repository: ap
topic: "LFE Implementation Status - Where are we at, does it work?"
tags: [research, codebase, lfe, beam, conductor, agent-worker, http]
status: complete
last_updated: 2026-02-06
last_updated_by: claude
---

# Research: LFE Implementation Status

**Date**: 2026-02-06T13:30:00-06:00
**Researcher**: claude
**Git Commit**: 9e0717c
**Branch**: main
**Repository**: ap

## Research Question
Where are we at with the LFE implementation? Does it work?

## Summary

The LFE implementation is a fully functional OTP application at `lfe/apps/autopoiesis/`. It compiles cleanly, all **59 tests pass** (0 failures), and the system runs as a supervised Erlang application with HTTP endpoints, timer-based scheduling, event processing, and CL subprocess agent workers.

The implementation was consolidated on 2026-02-06 by merging the best patterns from two parallel implementations (main + scud-lfe45 worktree). The worktrees have been cleaned up and deleted.

## What Exists

### Source: 9 LFE modules (~730 LOC) + 1 CL script (~150 LOC)

| Module | LOC | Purpose |
|--------|-----|---------|
| `conductor.lfe` | 313 | Core orchestrator: timer heap, event queue, metrics, agent spawning |
| `agent-worker.lfe` | 228 | Gen_server managing CL subprocess via Erlang port |
| `webhook-server.lfe` | 60 | Cowboy HTTP listener with retry on port conflicts |
| `webhook-handler.lfe` | 39 | POST /webhook endpoint with body-size limits |
| `health-handler.lfe` | 39 | GET /health endpoint with degradation logic |
| `autopoiesis-sup.lfe` | 39 | Top-level one_for_one supervisor |
| `agent-sup.lfe` | 42 | simple_one_for_one supervisor for agent workers |
| `connector-sup.lfe` | 21 | one_for_one supervisor for webhook-server |
| `autopoiesis-app.lfe` | 10 | OTP application callback |
| `agent-worker.lisp` | 154 | SBCL script: S-expression protocol, cognitive cycles |

### Tests: 4 modules, 59 tests, 0 failures

| Module | Tests | Coverage |
|--------|-------|----------|
| `boot-tests` | 11 | App lifecycle, supervisor tree, metadata, restart |
| `conductor-tests` | 25 | Event classification, timer scheduling/cancel, tick processing, metrics |
| `agent-worker-tests` | 18 | CL command construction, S-expression response parsing |
| `connector-tests` | 6 | HTTP health and webhook endpoints (real HTTP requests) |

### Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `lfe` | 2.2.0 | Lisp Flavoured Erlang |
| `cowboy` | 2.14.2 | HTTP server |
| `jsx` | 3.1.0 | JSON codec |
| `ranch` | 2.2.0 | TCP acceptor pool (transitive) |
| `cowlib` | 2.16.0 | Cowboy support (transitive) |

## Architecture

### Supervision Tree

```
autopoiesis-app
  └── autopoiesis-sup (one_for_one, 5/10s)
        ├── conductor (gen_server worker)
        ├── agent-sup (simple_one_for_one, 3/60s)
        │     └── agent-worker instances (transient)
        └── connector-sup (one_for_one, 5/10s)
              └── webhook-server (gen_server)
                    └── cowboy http_listener :4007
                          ├── /webhook → webhook-handler
                          └── /health  → health-handler
```

### Key Flows

**Webhook → Event Processing:**
HTTP POST /webhook → webhook-handler parses JSON → conductor:queue-event → next tick (~100ms) → classify-event → fast-path (inline) or slow-path (spawn agent)

**Timer Scheduling:**
conductor:schedule/1,2,3 → gb_trees insert with monotonic_time key → tick pops due timers → execute action → maybe-reschedule if recurring

**Agent Worker Lifecycle:**
conductor spawns async → agent-sup:spawn-agent → agent-worker:start_link → opens Erlang port to SBCL → S-expression protocol over stdio → 10s init timeout

### Key Design Decisions

- **defrecord** for conductor state (not plain maps) — compile-time field accessors
- **gb_trees** timer heap with composite `#(monotonic-time unique-ref)` keys — O(log n), collision-free
- **erlang:monotonic_time** for all timer calculations — immune to clock adjustments
- **Fast-path vs slow-path** routing via `requires-llm` flag — keeps conductor responsive
- **Async agent spawning** via bare `spawn` — prevents 10s agent-worker init from blocking tick loop
- **Flat status map** with 7 top-level keys — no nested metrics map
- **Body-size limit** on webhooks (1MB → 413) and **503** on conductor failure in health endpoint

## How to Run

```bash
# Compile
cd lfe && rebar3 compile

# Run all tests
cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests

# Start in shell
cd lfe && rebar3 lfe repl
> (application:ensure_all_started 'autopoiesis)

# Test endpoints
curl http://localhost:4007/health
curl -X POST http://localhost:4007/webhook -d '{"type":"test"}' -H 'Content-Type: application/json'
```

## What's Not Wired Up Yet

- **Agent worker CL side**: `scripts/agent-worker.lisp` tries to load `:autopoiesis` ASDF system which may not be available, causing SBCL to crash on agent spawn. This is expected — the CL autopoiesis system is the parent project, not packaged for the LFE worker yet.
- **Heartbeat handling**: agent-worker receives heartbeats but just logs them (comment: "conductor will use these in Phase 3")
- **Blocking requests**: agent-worker recognizes `:blocking-request` messages but has a TODO to route them to human interface
- **Real slow-path work**: Events classified as slow-path spawn agents, but without the CL system available, the agents fail on init (gracefully — conductor continues running)

## Historical Context

The implementation evolved through several phases documented in `thoughts/shared/plans/`:
1. **Feb 3**: Codebase overview and use case research
2. **Feb 4**: BEAM/LFE research → master implementation plan → unified platform plan
3. **Feb 5**: Phase 2 (skeleton) → Phase 3 (conductor) → Phase 3+4 (conductor + HTTP)
4. **Feb 6**: Combined best of two parallel implementations, cleaned up worktrees

Key documents:
- `thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md` — Master plan
- `thoughts/shared/plans/2026-02-06-combine-lfe-implementations.md` — Combination plan (most recent)
- `thoughts/shared/research/2026-02-04-lfe-beam-agent-supervision.md` — Why LFE/BEAM

## Code References

- `lfe/apps/autopoiesis/src/conductor.lfe:14-17` — defrecord state definition
- `lfe/apps/autopoiesis/src/conductor.lfe:128-147` — Timer heap processing loop
- `lfe/apps/autopoiesis/src/conductor.lfe:237-262` — Event classification and fast/slow path
- `lfe/apps/autopoiesis/src/conductor.lfe:268-287` — Async agent spawning
- `lfe/apps/autopoiesis/src/agent-worker.lfe:41-61` — Port init with 10s timeout
- `lfe/apps/autopoiesis/src/agent-worker.lfe:191-209` — S-expression response parser
- `lfe/apps/autopoiesis/src/webhook-handler.lfe:9-21` — Body size check and JSON parsing
- `lfe/apps/autopoiesis/src/health-handler.lfe:9-27` — Health check with degradation logic
