---
date: 2026-02-06T15:30:00-06:00
researcher: claude
git_commit: ce02d6e
branch: main
repository: ap
topic: "Super Agent Synthesis: Ralph Loops, Back Pressure, and Claude Agent Teams"
tags: [research, architecture, ralph, agent-teams, cortex, infrastructure, super-agent]
status: complete
last_updated: 2026-02-06
last_updated_by: claude
---

# Super Agent Synthesis: Ralph Loops, Back Pressure, and Claude Agent Teams

**Date**: 2026-02-06T15:30:00-06:00
**Branch**: main

## Sources Analyzed

1. **ghuntley.com/pressure/** — Back pressure for AI agents
2. **ghuntley.com/loop/** and **/ralph/** — Ralph loop pattern
3. **code.claude.com/docs/en/agent-teams** — Claude Code agent teams documentation
4. **Autopoiesis codebase** — LFE conductor, CL cognitive engine, Cortex MCP tools

## The Three Patterns

### 1. Ralph Loop

The core insight: `while :; do cat PROMPT.md | claude-code ; done`

- Progress lives in **files and git**, not in any agent's context window
- Each iteration reads the current state from disk, does work, writes results back
- The loop doesn't need to be smart — it just needs to be **relentless**
- "Allocate the array with specs, then loop the goal"
- Deterministic loop, progressive refinement, eventual consistency

Key properties:
- **Stateless iterations**: Each loop pass starts fresh, reads state from files
- **Git as memory**: Commits are checkpoints, diffs show progress
- **Spec-driven**: A PROMPT.md or spec file defines what "done" looks like
- **Infinite patience**: The loop runs until the goal is met or a human intervenes

### 2. Back Pressure

Automated feedback mechanisms that catch errors in agent loops:

- **Tests**: Does the code compile? Do tests pass?
- **Linting**: Is the output well-formed?
- **Type checking**: Are contracts respected?
- **Pre-commit hooks**: Gate quality before persistence
- **Health checks**: Is the system still functioning?

Back pressure transforms an open loop into a **closed loop** with error correction. Without it, Ralph drifts. With it, Ralph converges.

### 3. Claude Code Agent Teams

Team coordination primitives:

- **Team Lead**: Orchestrates work, creates tasks, assigns teammates
- **Teammates**: Autonomous agents spawned via `Task` tool with `team_name`
- **Shared Task List**: `TaskCreate`, `TaskUpdate`, `TaskList` — structured work items with dependencies
- **Mailbox Messaging**: `SendMessage` for DMs, broadcasts, shutdown requests
- **Delegate Mode**: Teammates work without requiring user permission per action
- **Split Panes**: Parallel visible execution
- **Background Agents**: `run_in_background: true` for fire-and-forget work

Key capabilities:
- Teams persist via `~/.claude/teams/{name}/config.json`
- Tasks have dependencies (`blocks`/`blockedBy`)
- Teammates go idle between turns, wake on message
- Team lead can spawn multiple agents of different types (Bash, general-purpose, Explore, Plan)

## The Insight: The Conductor IS a Ralph Loop

The LFE conductor already implements the Ralph loop pattern:

```
┌────────────────────────────────────────────────────┐
│  Ralph Loop                 LFE Conductor          │
│  ──────────                 ──────────────          │
│  while :; do                tick every 100ms        │
│    cat PROMPT.md            read event-queue        │
│    | claude-code            classify → dispatch     │
│    ; done                   reschedule tick         │
│                                                     │
│  Progress in files/git      Progress in snapshots   │
│  Spec defines "done"        Timer actions define    │
│  Back pressure = tests      Back pressure = health  │
│  Infinite patience          OTP supervision         │
└────────────────────────────────────────────────────┘
```

But the conductor currently dispatches to **CL subprocess workers** via Erlang ports. The CL worker script is broken (can't load `:autopoiesis`), and even when fixed, CL cognitive cycles are limited to what we've hand-built.

**The pivot**: Instead of (or in addition to) CL workers, the conductor could dispatch to **Claude Code agent teams**. Claude brings general intelligence. The conductor brings persistence, scheduling, supervision, and coordination.

## Architecture: The Super Agent

### Layer Diagram

```
┌─────────────────────────────────────────────────────────┐
│  PERCEPTION (Cortex)                                     │
│  ECS, K8s, Git, MongoDB, Redis, OTEL adapters           │
│  Pattern detection, anomaly alerting                     │
│  Accessed via MCP tools (cortex_query, cortex_schema)    │
├─────────────────────────────────────────────────────────┤
│  ORCHESTRATION (LFE Conductor)                           │
│  Timer heap: periodic health checks, polling             │
│  Event queue: alerts, webhooks, human requests           │
│  Agent lifecycle: spawn, monitor, restart, snapshot      │
│  Back pressure: health endpoint, metrics, degradation    │
├─────────────────────────────────────────────────────────┤
│  EXECUTION (Claude Code Agent Teams)                     │
│  Team lead: spawned by conductor for complex tasks       │
│  Teammates: specialized agents (researcher, implementer) │
│  Shared task list: structured work tracking              │
│  Result persistence: writes to files/git, not context    │
├─────────────────────────────────────────────────────────┤
│  MEMORY (Snapshot DAG + Git)                             │
│  Content-addressable agent state                         │
│  Branch, diff, time-travel, fork                         │
│  Git commits as durable checkpoints                      │
│  Learning system: pattern extraction, heuristics         │
└─────────────────────────────────────────────────────────┘
```

### How It Works

**Steady state (the Ralph loop):**

1. Conductor tick fires every 100ms
2. Check timer heap — any periodic tasks due?
3. Drain event queue — any alerts from Cortex? Any webhook events?
4. For each work item:
   - **Fast path** (health checks, metrics): handle inline, ~0ms
   - **Slow path** (investigation, remediation): spawn Claude agent team

**Spawning a Claude agent team:**

1. Conductor calls out to a **bridge process** (new component)
2. Bridge process invokes `claude` CLI with a structured prompt
3. Prompt includes: task description, Cortex MCP context, project specs, back pressure rules
4. Claude agent operates autonomously:
   - Reads Cortex state via MCP tools
   - Investigates the issue (reads logs, checks config, queries infra)
   - Spawns teammates if needed (researcher + implementer)
   - Writes findings/actions to result files
   - Commits to git
5. Bridge process reads results from disk/git
6. Conductor processes results, updates state, maybe schedules follow-up

**Back pressure integration:**

```
Conductor tick
  → Spawn Claude agent team for investigation
  → Agent writes diagnosis to results/
  → Agent proposes remediation
  → Pre-commit hook: validate proposed changes
  → Tests run: verify no regression
  → Health check: verify system still healthy
  → If all pass: commit, report success
  → If any fail: agent retries with error context (Ralph loop)
  → If stuck: escalate to human (blocking request)
```

### The Bridge: LFE → Claude Code

The existing `agent-worker.lfe` manages CL subprocesses via Erlang ports. A new `claude-worker.lfe` would manage Claude Code instances:

```
agent-worker.lfe (existing)         claude-worker.lfe (new)
─────────────────                   ─────────────────────
open_port → sbcl --script           open_port → claude --dangerously-skip-permissions
S-expr over stdio                   Structured files for I/O
10s init timeout                    Configurable long timeout
CL cognitive loop                   Claude agent team with MCP tools
Snapshot via CL API                 Snapshot via git commits
```

Key differences from CL worker:
- **Much longer timeouts** — Claude agent teams can run for minutes or hours
- **File-based I/O** — Instead of S-expressions over stdio, use structured files:
  - `work/tasks/{task-id}/prompt.md` — What to do
  - `work/tasks/{task-id}/result.md` — What was done
  - `work/tasks/{task-id}/status` — pending/running/complete/failed
- **Git as checkpoint** — Each completed task is a commit
- **MCP for perception** — Claude accesses Cortex directly via MCP tools

### Infrastructure Watcher: Concrete Use Case

```
Project config (S-expression):

(:agent infra-watcher
  :type :periodic
  :interval 300  ; every 5 minutes
  :capabilities (:cortex-query :cortex-entity-detail :k8s-read)
  :prompt "You are an infrastructure monitoring agent.
           Query Cortex for recent events. Look for:
           - ECS task failures or restarts
           - K8s pod CrashLoopBackOff
           - Deployment rollback events
           - Anomalous metric patterns
           Report findings. If critical, propose remediation."
  :back-pressure
    (:health-check "/health returns 200"
     :no-destructive "never delete or force-restart without human approval"
     :audit-trail "all actions logged to cortex event store"))
```

**Flow:**

1. Conductor timer fires every 5 minutes
2. Spawns Claude with infra-watcher prompt + Cortex MCP tools
3. Claude queries `cortex_query` for recent events
4. Claude queries `cortex_entity_detail` for concerning entities
5. Claude writes report to `work/infra-watcher/{timestamp}/report.md`
6. If nothing critical: "All clear, 47 events reviewed, no anomalies"
7. If something found: detailed diagnosis with proposed remediation
8. If critical: conductor routes to human via blocking request
9. Report committed to git → snapshot DAG updated → next iteration in 5 min

**What makes this better than a cron + script:**

- Claude **reasons** about the events, not just pattern-matches
- Agent teams can **investigate** (spawn teammate to dig into logs)
- Snapshot DAG preserves **cognitive history** (what did the agent think last time?)
- OTP supervision ensures the loop **never stops**
- Back pressure via health checks ensures the loop **never drifts**
- Human-in-the-loop for anything destructive

### Long-Running Super Agent: The Vision

The ultimate form is a **self-improving infrastructure guardian**:

```
Day 1: Agent runs, queries Cortex, finds nothing, reports "all clear"
Day 2: Agent notices a pattern — certain pods restart every 8 hours
Day 3: Agent investigates, finds memory leak in service X
Day 4: Agent proposes fix, human approves, agent creates PR
Day 5: Agent monitors fix, confirms restarts stopped
Day 7: Agent writes a new heuristic: "watch for 8-hour restart cycles"
         (self-extension via extension compiler)
Day 14: Agent detects a DIFFERENT 8-hour cycle using its own heuristic
         (learned behavior)
Day 30: Agent has built a library of infrastructure patterns
         specific to THIS environment
```

This is the thesis: an agent that gets **smarter about YOUR infrastructure** over time, with full inspectability via the snapshot DAG and human-in-the-loop via blocking requests.

## What Needs to Be Built

### Immediate (enables the pattern)

1. **`claude-worker.lfe`** — Gen_server managing Claude Code subprocess
   - Similar structure to `agent-worker.lfe` but file-based I/O instead of port protocol
   - Longer timeouts, configurable per task type
   - Result parsing from structured files

2. **Work directory structure** — Convention for task I/O
   ```
   work/
     tasks/
       {task-id}/
         prompt.md       — Input for Claude
         context/        — Additional context files
         result.md       — Output from Claude
         status          — pending|running|complete|failed
         artifacts/      — Any files Claude creates
   ```

3. **Conductor timer actions for Claude** — New action type
   ```lfe
   `#M(id infra-check
       interval 300
       recurring true
       requires-llm true
       action-type claude-team    ; NEW: dispatch to claude-worker
       prompt "..."
       mcp-servers (cortex)
       back-pressure (...))
   ```

### Next (makes it useful)

4. **Project config loader** — Read S-expression agent definitions
5. **Cortex MCP integration** — Claude accesses Cortex directly (already works! MCP tools exist)
6. **Result processor** — Conductor reads and acts on Claude agent results
7. **Escalation path** — Route findings to human via existing blocking request protocol

### Later (makes it awesome)

8. **Self-extension loop** — Agent writes new heuristics, extension compiler validates
9. **Multi-agent infra team** — Watcher spawns investigators, investigators spawn fixers
10. **Snapshot-aware context** — Include relevant past observations in prompts
11. **Cortex audit trail** — Agent actions stored back in Cortex event store

## Key Insight: Don't Replace CL, Augment It

The CL cognitive engine and Claude agent teams serve different roles:

| | CL Cognitive Engine | Claude Agent Teams |
|---|---|---|
| **Strength** | Deterministic, inspectable, fast | General intelligence, reasoning |
| **State** | CLOS objects, snapshot DAG | Files, git commits |
| **Latency** | Milliseconds | Seconds to minutes |
| **Cost** | CPU only | API calls |
| **Best for** | Heuristics, pattern matching, state management | Investigation, diagnosis, remediation |

The ideal flow uses BOTH:

1. CL heuristics run continuously (fast, cheap, deterministic)
2. When CL detects something it can't handle → escalate to Claude team
3. Claude investigates, proposes fix
4. Fix goes through back pressure (tests, health checks)
5. If Claude discovers a new pattern → writes it as CL heuristic (self-extension)
6. Next time, CL handles it directly (learning loop closes)

## Implementation Priority

1. **`claude-worker.lfe`** + work directory structure — enables the core loop
2. **One infra-watcher timer** with Cortex MCP — proves the concept
3. **Result processing** in conductor — closes the loop
4. **Fix CL worker loading** — enables the CL↔Claude hybrid
5. **Self-extension** — the differentiator

The first demo: `conductor:schedule` an infra-watcher that queries Cortex every 5 minutes via a Claude agent team, writes reports, and escalates anomalies.
