---
date: 2026-02-06T14:00:00-06:00
researcher: claude
git_commit: 9e0717ccdf45665723e8fee4f245d5d46e69080f
branch: main
repository: ap
topic: "Next Steps: From Not-Working to Working to Product"
tags: [research, roadmap, lfe, conductor, agent-worker, cortex, product]
status: complete
last_updated: 2026-02-06
last_updated_by: claude
---

# Next Steps: From Not-Working to Working to Product

**Date**: 2026-02-06T14:00:00-06:00
**Git Commit**: 9e0717c
**Branch**: main

## The Big Picture

Three layers exist at different levels of completion:

```
┌─────────────────────────────────────────────────────────┐
│  PRODUCT LAYER (Use Cases)                    0% done   │
│  Actual agents doing useful work                        │
│  Infrastructure Healer, Codebase Archaeologist, etc.    │
├─────────────────────────────────────────────────────────┤
│  ORCHESTRATION LAYER (LFE/BEAM)              ~70% done  │
│  Supervisor tree, conductor, HTTP, agent spawning       │
│  ✅ Compiles, 59/59 tests pass                          │
│  ❌ Agent workers can't load CL engine                   │
│  ❌ No Cortex integration                                │
│  ❌ No project config system                             │
├─────────────────────────────────────────────────────────┤
│  COGNITIVE LAYER (Common Lisp)              ~95% done   │
│  Agent class, cognitive loop, snapshots, learning       │
│  ✅ 2,400+ assertions, all tests passing                │
│  ✅ agent-to-sexpr / sexpr-to-agent exist               │
│  ✅ restore-agent-from-snapshot exists                   │
│  ✅ Extension compiler, security, monitoring             │
│  ❌ CL worker script can't find :autopoiesis system     │
└─────────────────────────────────────────────────────────┘
```

## The One Blocker: CL Worker Can't Load

The **single critical blocker** preventing the system from working end-to-end:

`scripts/agent-worker.lisp` line 4: `(asdf:load-system :autopoiesis)`

This fails because:
1. The script doesn't add the project to ASDF's source registry
2. The script doesn't load Quicklisp for dependency resolution
3. `scripts/build.sh` does both of these but the worker script doesn't

**The fix** (add before line 4):
```lisp
(load (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname)))
(push (truename "../") asdf:*central-registry*)
```

Or make the script path-aware relative to where it's invoked from.

Once this works: LFE spawns SBCL → SBCL loads :autopoiesis → worker sends `:ok` → LFE agent-worker init completes → conductor can dispatch real work to CL agents.

## Phase Map: What to Build, In What Order

### Phase A: Make It Work (1-2 sessions)

**Goal**: End-to-end flow where LFE conductor dispatches work to a CL cognitive agent.

1. **Fix agent-worker.lisp startup** — Add Quicklisp loading and ASDF registry push
2. **Verify port protocol** — Send `:init`, get `:ok` back, send `:cognitive-cycle`, get result
3. **Test supervisor restart** — Kill SBCL process, verify LFE restarts it, verify snapshot restore
4. **Smoke test full flow** — POST webhook event → conductor classifies → spawns agent → CL cognitive cycle runs → result

**Success**: `curl -X POST localhost:4007/webhook -d '{"type":"analyze","target":"src/"}' ` triggers a real cognitive cycle.

### Phase B: Make It Useful (3-5 sessions)

**Goal**: First real use case working — an agent that does something valuable.

**B1: Project Config System**
- `project-loader.lfe` module that reads S-expression project configs
- Defines which agents, triggers, and capabilities a project uses
- Agent profiles with CORE.md system prompts, capability sets

**B2: Cortex Bridge**
- Two options (pick one):
  - **HTTP polling**: Scheduled timer in conductor polls Cortex HTTP API every N seconds
  - **MCP tool**: Use existing Cortex MCP server (already running!) — agent calls Cortex tools during cognitive cycle
- The MCP approach is simpler since Cortex MCP tools already exist in the current environment

**B3: First Agent — Infrastructure Watcher**
- Project config defining an agent profile
- Agent boots, connects to Cortex via MCP, watches for anomalies
- Conductor schedules periodic health checks
- Agent spawned on-demand for complex alerts

**OR B3 Alternative: Codebase Archaeologist**
- Simpler (no Cortex needed), uses existing file tools
- Agent explores codebase, builds understanding, creates documentation
- Demonstrates core value: inspectable cognitive model + time-travel

### Phase C: Make It Awesome (ongoing)

**Goal**: The platform differentiators that make this better than LangGraph/CrewAI/AutoGen.

**C1: Self-Extension Loop**
- Agent uses extension compiler to define new capabilities
- Capabilities persist across restarts via snapshots
- Human approves capability promotions
- *This is the thesis statement of the platform*

**C2: Multi-Agent Coordination**
- Multiple agents in same project communicating via conductor
- Shared blackboard state in conductor
- Agent spawning other agents for subtasks

**C3: Time-Travel Debugging**
- Snapshot DAG integration with LFE lifecycle events
- "Rewind agent to 2 hours ago and replay with different input"
- Fork agent state to explore alternative strategies

**C4: Visualization**
- 2D terminal timeline of agent cognitive state (already built in CL)
- Connect LFE health metrics to existing monitoring endpoints
- Real-time thought stream display during cognitive cycles

**C5: Cortex Deep Integration**
- Cortex alerts → conductor event queue → agent spawning
- Agent actions → Cortex event log (audit trail)
- Cortex checkpoints cross-linked to agent snapshots

## What Already Exists (Don't Rebuild)

### In CL (fully implemented, tested)

| Component | What It Does | Where |
|-----------|-------------|-------|
| Cognitive Loop | 5-phase perceive→reason→decide→act→reflect | `src/agent/cognitive-loop.lisp` |
| Agent Class | CLOS with serialization, lifecycle, capabilities | `src/agent/agent.lisp` |
| Snapshot DAG | Content-addressable storage, branching, time-travel | `src/snapshot/` |
| Extension Compiler | Sandboxed compilation of agent-written code | `src/core/extension-compiler.lisp` |
| Learning System | Pattern extraction, heuristic generation | `src/agent/learning.lisp` |
| Provider Bridge | Claude Code subprocess management | `src/integration/provider*.lisp` |
| MCP Client | Full MCP protocol, auto-registers as capabilities | `src/integration/mcp-client.lisp` |
| Human Interface | Blocking requests, viewport, annotator | `src/interface/` |
| 14 Built-in Tools | File ops, web fetch, shell, git | `src/integration/builtin-tools.lisp` |
| Event Bus | Pub/sub with 14 event types | `src/integration/events.lisp` |
| Security | Permissions, audit, validation, sandbox | `src/security/` |
| 2D Visualization | Terminal timeline with ANSI rendering | `src/viz/` |
| 3D Holodeck | Full ECS with shaders, camera, HUD | `src/holodeck/` |

### In LFE (implemented, 59/59 tests passing)

| Component | What It Does | Where |
|-----------|-------------|-------|
| Supervision Tree | one_for_one top, simple_one_for_one agents | `lfe/apps/autopoiesis/src/*-sup.lfe` |
| Conductor | Timer heap, event queue, fast/slow dispatch, 7 metrics | `lfe/apps/autopoiesis/src/conductor.lfe` |
| Agent Worker | Port-based gen_server managing CL subprocess | `lfe/apps/autopoiesis/src/agent-worker.lfe` |
| HTTP Server | Cowboy on :4007, webhook + health endpoints | `lfe/apps/autopoiesis/src/webhook-*.lfe` |
| Health Handler | 503 on failure, degradation logic | `lfe/apps/autopoiesis/src/health-handler.lfe` |

### In Cortex (separate system, accessible via MCP)

| Component | What It Does |
|-----------|-------------|
| Event Store | LMDB-based infrastructure event storage |
| Adapters | ECS, K8s, ArgoCD, Crossplane, Git, MongoDB, Redis, OTEL |
| Query Engine | S-expression query language |
| Alerting | Pattern-based detection |
| Checkpoint | Infrastructure state snapshots |

## The Unique Value (Why This Matters)

No competitor has this combination:

1. **Homoiconicity** — Agent thoughts, config, and code are all S-expressions. Agents can inspect and modify their own cognitive processes.

2. **Snapshot DAG** — Full cognitive state captured with content-addressable hashing. Branch, diff, time-travel, fork alternative strategies.

3. **Self-Extension** — Agents write new capabilities via sandboxed extension compiler. Capabilities go through draft→testing→promoted lifecycle.

4. **BEAM Supervision** — Real OTP supervision trees for agent lifecycle. Crash recovery, restart strategies, resource limits — not reimplemented, actual Erlang.

5. **Human-in-the-Loop** — Native blocking request protocol. Agent can pause mid-thought and ask for human input. Multiple modes (approve, choose, freeform).

The first use case that demonstrates ALL five is the thesis statement for the platform.

## Recommended Priority

1. **Fix the CL worker loading** (Phase A) — unblocks everything
2. **Codebase Archaeologist agent** (Phase B3-alt) — fastest path to useful demo, no Cortex dependency
3. **Self-extension demo** (Phase C1) — the "wow" feature that differentiates from every competitor
4. **Cortex integration** (Phase B2/C5) — connects to real infrastructure monitoring
5. **Multi-agent coordination** (Phase C2) — enables complex use cases
