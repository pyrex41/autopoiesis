---
date: 2026-02-05T12:00:00-08:00
researcher: claude
git_commit: ce02d6e563435d408a5eef84ebe465937f443d97
branch: main
repository: ap
topic: "Plans Status Review: What's Done and What Remains"
tags: [research, plans, status, lfe, conductor, agent-platform]
status: complete
last_updated: 2026-02-05
last_updated_by: claude
---

# Research: Plans Status Review — What's Done and What Remains

**Date**: 2026-02-05T12:00:00-08:00
**Researcher**: claude
**Git Commit**: ce02d6e
**Branch**: main
**Repository**: ap

## Research Question

Review all plans in `thoughts/shared/plans/` and determine what has been implemented and what remains.

## Summary

There are **5 plan documents** covering an evolution from the original Common Lisp framework toward a hybrid LFE/BEAM + CL agent platform. Two earlier plans were superseded by a unified plan, and a separate LFE-focused implementation plan was later detailed for Phase 2. The CL-side work (Phase 1 of the LFE plan) is **complete**. Phase 2 (LFE project skeleton) is **code-complete but not verified**. Everything else (Phases 3-5 of the LFE plan, and all phases of the Unified Platform Plan) **remains unimplemented**.

---

## Plan Inventory and Relationships

### 1. Autopoiesis + Cortex Synthesis Plan
- **File**: `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md`
- **Status**: Draft, **superseded** by Unified Platform Plan
- **Content**: Original vision for the Conductor pattern — a dual-mode meta-agent combining fast programmatic execution with slow LLM reasoning. Defines conductor struct, work-item classification, agent spawner, timer heap, event queue, blackboard, trigger system, agent profiles, and Cortex bridge.
- **Superseded by**: Unified Platform Plan absorbed and refined all of these concepts.

### 2. Workspace Architecture & Agent Projects Plan
- **File**: `thoughts/shared/plans/2026-02-04-workspace-architecture-plan.md`
- **Status**: Draft, **superseded** by Unified Platform Plan
- **Content**: Monorepo structure, runtime extension loading, per-project Archil/S3 storage, project manifest schema, MCP server SDK, shared capabilities directory, and initial agent projects (compliance-agent, infra-healer). 7 implementation phases over 9 weeks.
- **Superseded by**: Unified Platform Plan merged this with the Cortex Synthesis Plan.

### 3. Unified Platform Plan
- **File**: `thoughts/shared/plans/2026-02-04-unified-platform-plan.md`
- **Status**: Draft, **authoritative plan** (supersedes both above)
- **Content**: Synthesized plan combining conductor pattern + workspace architecture. Per-project SBCL processes with conductors, ZMQ bridge to Cortex, Archil-backed storage, capabilities library, project manifests. 7 phases.
- **Implementation status**: **Nothing implemented** — no `src/conductor/`, no `capabilities/`, no `projects/`, no `src/core/project-loader.lisp`, no `src/core/project-storage.lisp`, no `src/integration/cortex-bridge.lisp`, no `scripts/run-project.sh`.

### 4. LFE-Supervised Agent Platform Plan
- **File**: `thoughts/shared/plans/2026-02-04-lfe-supervised-agent-platform.md`
- **Status**: Draft, **actively being implemented**
- **Content**: Shifts the architectural approach — instead of CL-only with bordeaux-threads, uses LFE/BEAM for OTP supervision and the conductor, with CL as the cognitive engine communicating via ports. 5 phases.
- **Relationship to Unified Plan**: Replaces the CL-only conductor and threading approach with LFE/BEAM supervision. The CL cognitive engine stays the same.

### 5. Phase 2 LFE Project Skeleton (Detailed)
- **File**: `thoughts/shared/plans/2026-02-05-phase2-lfe-project-skeleton.md`
- **Status**: Draft, **detailed breakdown of Phase 2 from plan #4**
- **Content**: Corrects inaccuracies in the master plan (port message format, logger vs lager, dependency versions, map syntax, `mref` usage), provides task-by-task breakdown with dependency graph.

---

## What Is Done

### Phase 1 (CL Worker Script) — COMPLETE

All Phase 1 deliverables from the LFE-Supervised Agent Platform Plan are implemented:

| Deliverable | Status | Location |
|-------------|--------|----------|
| Worker entry point | Done | `scripts/agent-worker.lisp` |
| S-expr stdin/stdout protocol | Done | `scripts/agent-worker.lisp:37-41` (send-response) |
| `:init` handler with snapshot restore | Done | `scripts/agent-worker.lisp:50-71` |
| `:cognitive-cycle` handler | Done | `scripts/agent-worker.lisp:73-87` |
| `:snapshot` handler | Done | `scripts/agent-worker.lisp:89-96` |
| `:inject-observation` handler | Done | `scripts/agent-worker.lisp:43-48` |
| `:shutdown` handler with final snapshot | Done | `scripts/agent-worker.lisp:98-109` |
| EOF handling with snapshot | Done | `scripts/agent-worker.lisp:139-153` |
| Heartbeat thread | Done | `scripts/agent-worker.lisp:111-125` |
| Error recovery (parse errors) | Done | `scripts/agent-worker.lisp:140-153` |
| Agent serialization (`agent-to-sexpr`) | Done | `src/agent/agent.lisp:83-94` |
| Agent deserialization (`sexpr-to-agent`) | Done | `src/agent/agent.lisp:96-112` |
| Snapshot restoration (`restore-agent-from-snapshot`) | Done | `src/snapshot/persistence.lisp:420-431` |
| Find latest snapshot (`find-latest-snapshot-for-agent`) | Done | `src/snapshot/persistence.lisp:403-418` |
| Agent serialization tests | Done | `test/agent-tests.lisp:40-115` (5 tests) |
| Snapshot restoration tests | Done | `test/snapshot-tests.lisp:204-331` (5 tests) |
| Init workflow tests | Done | `test/agent-tests.lisp:134-210` (3 tests) |
| Package exports | Done | `src/agent/packages.lisp:21-23`, `src/snapshot/packages.lisp:51-52` |

### Phase 2 (LFE Project Skeleton) — CODE COMPLETE, VERIFICATION PENDING

All Phase 2 source files exist and match the detailed plan:

| File | Status | Notes |
|------|--------|-------|
| `lfe/rebar.config` | Done | Minimal deps (lfe only, no cowboy/jsx yet per plan) |
| `lfe/config/sys.config` | Done | cl_worker_script and sbcl_path configured |
| `lfe/config/vm.args` | Done | |
| `lfe/apps/autopoiesis/src/autopoiesis.app.src` | Done | OTP app descriptor |
| `lfe/apps/autopoiesis/src/autopoiesis-app.lfe` | Done | Application callback, uses `logger` |
| `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe` | Done | Top-level supervisor, `one_for_one`, map-based child specs |
| `lfe/apps/autopoiesis/src/agent-sup.lfe` | Done | `simple_one_for_one`, transient restart, 3/60s limits |
| `lfe/apps/autopoiesis/src/connector-sup.lfe` | Done | Placeholder with no children |
| `lfe/apps/autopoiesis/src/agent-worker.lfe` | Done | Full gen_server with port communication |
| `lfe/apps/autopoiesis/test/agent-worker-tests.lfe` | Done | 20 EUnit tests for `build-cl-command` and `parse-cl-response` |
| `lfe/apps/autopoiesis/test/boot-tests.lfe` | Done | 8 EUnit tests for application boot and supervisor hierarchy |
| `lfe/_build/` | Exists | Build artifacts present, suggesting compilation was attempted |
| `lfe/rebar.lock` | Exists | Dependencies resolved |
| `lfe/erl_crash.dump` | Exists | Indicates at least one crash occurred during development/testing |

**Corrections from Phase 2 detailed plan applied in code:**
- Port message format: `handle_info` correctly matches `#(eol ,line)` / `#(noeol ,line)` wrappers
- Uses `logger` instead of `lager`
- Uses `maps:get` with 2 and 3 arg forms instead of `mref`
- `parse-cl-response` handles `lfe_io:read_string` returning list of forms
- Guard on port identity in `port-receive`

**Verification status unknown** — the plan's verification checklist has not been confirmed:
- [ ] `rebar3 lfe compile` succeeds
- [ ] `rebar3 lfe repl` starts
- [ ] `application:ensure_all_started` works
- [ ] Supervisor hierarchy correct
- [ ] Agent spawning works with SBCL
- [ ] Supervisor restart on crash
- [ ] EUnit tests pass

The presence of `erl_crash.dump` suggests testing was attempted but may have hit issues.

---

## What Remains

### From the LFE-Supervised Agent Platform Plan

#### Phase 3: Conductor Gen_Server — NOT STARTED
- `lfe/apps/autopoiesis/src/conductor.lfe` — not created
- Event loop gen_server with timer heap, event routing, work dispatch
- Tick processing every 100ms
- Fast-path vs slow-path classification
- Agent spawn for complex work
- Health check and metric update handling

#### Phase 4: Connectors (HTTP Webhook, MCP Server) — NOT STARTED
- `lfe/apps/autopoiesis/src/connector-sup.lfe` — exists but is empty placeholder
- `lfe/apps/autopoiesis/src/webhook-server.lfe` — not created
- `lfe/apps/autopoiesis/src/webhook-handler.lfe` — not created
- `lfe/apps/autopoiesis/src/mcp-server.lfe` — not created
- Requires cowboy dependency (not yet in rebar.config)
- HTTP webhook server on configurable port
- Health endpoint

#### Phase 5: Project Definition Format — NOT STARTED
- `lfe/config/project.schema.lfe` — not created
- `lfe/apps/autopoiesis/src/project-loader.lfe` — not created
- Project config parsing and validation
- Trigger registration with conductor
- Agent autostart from config
- Connector startup from config

### From the Unified Platform Plan (CL-side)

All 7 phases remain entirely unimplemented:

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Conductor Core (CL version) | Not started — superseded by LFE conductor approach |
| 2 | Project Infrastructure | Not started — no `src/core/project-loader.lisp`, no `src/core/project-storage.lisp`, no `projects/`, no `capabilities/` |
| 3 | Cortex ZMQ Bridge | Not started — no `src/integration/cortex-bridge.lisp` |
| 4 | Agent Spawning & Profiles | Not started — no `src/conductor/spawner.lisp`, no `profiles/` directory |
| 5 | Compliance Agent | Not started — no `projects/compliance-agent/` |
| 6 | Infrastructure Watcher | Not started — no `projects/infra-watcher/` |
| 7 | Cost Tracking & Polish | Not started |

**Note**: The Unified Plan's Phase 1 (CL conductor) may be moot if the LFE approach is the chosen direction. However, Phases 2-7 contain work that applies regardless of whether the conductor is CL or LFE:
- Per-project storage with Archil/S3
- Project manifest parsing
- Cortex ZMQ bridge
- Agent profiles and CORE.md files
- Capability library
- Agent projects (compliance, infra-watcher)

### From the Workspace Architecture Plan (superseded)

All work here was absorbed into the Unified Plan and also remains unimplemented:
- Extension loader and runtime loading
- MCP server SDK and shared MCP servers (GitHub, K8s, Prometheus, Datadog, Policy Engine)
- Shared capabilities library
- CLI (`ap project new`, `ap project load`, etc.)
- Project templates

---

## Architectural Decision Point

The plans reveal a **fork in approach** that hasn't been explicitly resolved:

1. **Unified Platform Plan**: CL-only with bordeaux-threads for concurrency, conductor as a CL struct with `conductor-loop`, agents spawned as threads within the same SBCL process.

2. **LFE-Supervised Agent Platform Plan**: LFE/BEAM for supervision and the conductor (gen_server), CL as cognitive engine via ports, each agent is an SBCL process managed by OTP.

The LFE plan is the one being actively implemented (Phase 1 complete, Phase 2 code-complete). The Unified Plan's CL-only conductor appears to be superseded by the LFE approach, but the Unified Plan's project infrastructure (storage, capabilities, profiles, agent projects) would still need to be built — either in CL, LFE, or split across both.

## Code References

- `scripts/agent-worker.lisp` — CL worker entry point (Phase 1)
- `src/agent/agent.lisp:83-112` — Agent serialization functions
- `src/agent/packages.lisp:21-23` — Agent serialization exports
- `src/snapshot/persistence.lisp:403-431` — Snapshot restoration functions
- `src/snapshot/packages.lisp:51-52` — Snapshot restoration exports
- `test/agent-tests.lisp:40-210` — Agent serialization and init workflow tests
- `test/snapshot-tests.lisp:204-331` — Snapshot restoration tests
- `lfe/apps/autopoiesis/src/` — All 6 LFE source modules (Phase 2)
- `lfe/apps/autopoiesis/test/` — 2 LFE test files with 28 tests total

## Historical Context

- `thoughts/shared/research/2026-02-04-lfe-beam-agent-supervision.md` — Research on LFE/BEAM supervision that informed the LFE plan
- `thoughts/shared/research/2026-02-04-agent-system-ideas-synthesis.md` — Synthesis of agent system ideas
- `thoughts/shared/research/2026-02-03-autopoiesis-real-agent-use-cases.md` — Use case research that motivated the workspace architecture plan

## Open Questions

1. Is the CL-only conductor approach (Unified Plan Phase 1) officially abandoned in favor of LFE?
2. Has Phase 2 verification been attempted? The `erl_crash.dump` suggests issues.
3. Where should project infrastructure (storage, capabilities, profiles) live — CL, LFE, or split?
4. Is the Cortex ZMQ bridge still planned, or will integration happen differently with LFE in the picture?
