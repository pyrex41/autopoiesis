# Handoff: Continue to Phase 5 (Meta-Agent Orchestration)

**Date**: 2026-02-16
**From**: Phase 4 implementation session
**Priority**: Implement Phase 5 — the final phase of the Jarvis plan

---

## What's Done (Phases 1-4 Complete)

All Jarvis phases 1-4 are committed and on `main`. The branch is 14 commits ahead of origin.

### Phase Summary

| Phase | Commit | Description | Tests Added |
|-------|--------|-------------|-------------|
| Phase 1 | `5dfdf86` | Agentic loop (`agentic-loop` in claude-bridge.lisp), `agentic-agent` class with cognitive specializations | 55 CL checks |
| Phase 2 | `eac0b80`, `d0d5459` | Self-extension tools (define/test/promote capability), introspection tools | 16 CL checks |
| Phase 3 | `3a8b5ca` | Provider generalization — OpenAI bridge, inference provider, multi-backend support | 104 CL checks |
| Phase 4 | `783cd02` | Rich CL-LFE bridge — 10 new message handlers, streaming thoughts, heartbeat, conductor agentic dispatch, human-in-the-loop routing | 12 CL checks, 20 LFE tests |

### Test Baseline

- **CL**: 2,400+ assertions passing. 1 pre-existing failure in REST-API-TESTS (`BRANCH-SERIALIZATION` — `BRANCH-CREATED` function undefined, unrelated to Jarvis work)
- **LFE**: 95 tests, 0 failures (up from 75 pre-Phase 4)

### Verification Commands

```bash
# CL tests
./scripts/test.sh

# LFE tests
cd lfe && rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests
```

---

## Git State

```
main HEAD: 783cd02 [bridge] Implement Phase 4: Rich CL-LFE bridge protocol
main is 14 commits ahead of origin/main (not pushed)
```

Recent history:
```
783cd02 [bridge] Implement Phase 4: Rich CL-LFE bridge protocol
3a8b5ca [cl] Add provider generalization with OpenAI bridge and inference provider
d0d5459 [cl] Fix execute-tool-call cross-package capability name matching
eac0b80 [cl] Add self-extension tools closing the self-modification loop
5dfdf86 [cl] Add agentic loop and agentic-agent for direct Claude API tool loop
1cef61e [docs] Add accumulated research and planning documents
68d1946 [docs] Add comprehensive Super Agent implementation record
9f3a4f7 [cl] Add agent serialization and snapshot-based restoration
5e71e95 [docs] Add SCUD task management workflow to CLAUDE.md
e3aa2ce [super-agent] Handle binary strings in claude-worker command building
93824b2 [super-agent] Fix Claude CLI port communication: shell spawn with /dev/null
381444a [lfe] Add Claude worker subsystem for Super Agent infrastructure monitoring
36270e4 [lfe] Add LFE implementation with combined best-of upgrades
9668b14 [docs] Add real-world agent use cases research and update codebase overview
6d98ce2 Merge pull request #1 from pyrex41/claude/compare-picoclaw-project-lpaW7
```

---

## What Phase 4 Built (Bridge Protocol)

Phase 4 expanded the CL-LFE bridge from 5 to 16 message types. Key files:

### CL Side: `scripts/agent-worker.lisp` (+350 lines)

- **Thread-safe output**: `*output-lock*` mutex for heartbeat thread + main thread stdout serialization
- **Heartbeat thread**: Activated on `:init`, sends periodic heartbeats to LFE
- **10 new command handlers**:
  - `:agentic-prompt` — Runs full multi-turn agentic loop, streams `:thought` messages back
  - `:query-thoughts` — Query thought stream (last N, by type)
  - `:list-capabilities` — List registered capabilities with optional filter
  - `:invoke-capability` — Invoke a specific capability by name
  - `:checkout` — Restore agent state from snapshot
  - `:diff` — Diff two snapshots
  - `:create-branch` — Create snapshot branch
  - `:list-branches` — List all branches
  - `:switch-branch` — Switch to branch and checkout head
  - `:blocking-response` — Receive resolution for human-in-the-loop requests
- **Helpers**: `resolve-capabilities`, `thought-to-sexpr`
- **`*pending-responses*`** hash table for blocking request coordination

### LFE Side: `lfe/apps/autopoiesis/src/agent-worker.lfe` (+294 lines)

- **12 new client API functions**: `agentic-prompt/2`, `agentic-prompt/3`, `query-thoughts/2`, `list-capabilities/1`, `invoke-capability/2`, `invoke-capability/3`, `checkout-snapshot/2`, `diff-snapshots/3`, `create-branch/2`, `create-branch/3`, `list-branches/1`, `switch-branch/2`
- **10 new `handle_call` clauses** with appropriate timeouts
- **`collect-agentic-response/3`**: Recursive streaming collector for thought messages
- **Heartbeat monitoring**: `check-heartbeat` timer (30s intervals, 60s timeout → worker kill)
- **`resolve-blocking` handle_cast**: Forwards HITL responses to CL

### LFE Conductor: `lfe/apps/autopoiesis/src/conductor.lfe` (+110 lines)

- **`pending-requests`** field in state record
- **`'agentic` action type** in `execute-timer-action`
- **`dispatch-agentic-agent/1`**: Spawns CL agent and runs agentic prompt asynchronously
- **`blocking-request` / `resolve-request`** handle_cast clauses for HITL routing
- **Helper functions**: `find-pending-request/2`, `remove-pending-request/2`

### Tests: `test/bridge-protocol-tests.lisp` (156 lines, new)

12 CL tests covering thought streams, capabilities, snapshots, diffs, serialization.

### Tests: LFE (220 lines added)

- 12 new agent-worker-tests (response parsing for all new message types)
- 9 new conductor-tests (blocking-request, agentic dispatch, pending-request helpers)

---

## Phase 5: Meta-Agent Orchestration

**Master plan**: `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` (Phase 5 section starts at line 433)

### Goal

CL agents that can spawn other agents (via LFE supervision), compose results, fork/merge cognitive branches. The "Jarvis" layer that makes everything useful.

### What the Plan Specifies

#### 5.1 Agent Spawning from CL

New built-in tools that let an agent manage other agents through the bridge:

```lisp
(defcapability spawn-agent (&key name provider-type system-prompt capabilities task)
  "Spawn a new agent to work on TASK.
   The agent runs under LFE supervision (fault-tolerant).
   Returns an agent-id for monitoring.")

(defcapability query-agent (&key agent-id)
  "Check the status and recent thoughts of a spawned agent.")

(defcapability await-agent (&key agent-id timeout)
  "Wait for a spawned agent to complete its task.")
```

These tools communicate through the CL→LFE bridge to request agent spawning via the supervisor tree.

#### 5.2 Cognitive Branching

```lisp
(defcapability fork-branch (&key name)
  "Create a cognitive branch from the current state.")

(defcapability switch-branch (&key name)
  "Switch to a different cognitive branch.")

(defcapability compare-branches (&key branch-a branch-b)
  "Diff two cognitive branches to see how they diverged.")
```

#### 5.3 Session Management

```lisp
(defcapability save-session (&key name)
  "Save the current session state. Can be resumed later.")

(defcapability resume-session (&key name)
  "Resume a previously saved session, restoring full cognitive state.")
```

#### 5.4 CLI Entry Point

```bash
$ jarvis "deploy the new feature to staging"
$ jarvis --resume  # pick up where you left off
$ jarvis --branch experiment "try a different approach"
```

### Estimated Size

~350-400 lines of new code.

### Files Expected to Change

| File | Change |
|------|--------|
| `src/integration/builtin-tools.lisp` | Add orchestration tools (spawn-agent, query-agent, await-agent, fork/switch/compare-branches) |
| `src/integration/session.lisp` | New file: session save/restore |
| `scripts/agent-worker.lisp` | New bridge messages for agent spawning requests |
| `lfe/apps/autopoiesis/src/agent-worker.lfe` | Handle spawn-agent requests (forward to supervisor) |
| `lfe/apps/autopoiesis/src/conductor.lfe` | Multi-agent coordination, session persistence |
| `lfe/apps/autopoiesis/src/boot.lfe` | CLI entry point |
| Tests | Integration tests for multi-agent workflows |

---

## Important Context

### Architecture Principle

> "CL runs agents. LFE supervises processes."

Phase 4 built the rich bridge. Phase 5 uses it — a CL agent calls `spawn-agent` tool → CL sends a bridge message → LFE supervisor spawns a new CL agent worker → the new worker is supervised independently → results flow back.

### The "Dormant Path" Issue

Research at `thoughts/shared/research/2026-02-16-lfe-control-plane-analysis.md` notes that the conductor currently routes ALL work through Claude CLI (`action-type: claude`), not through CL agents (`action-type: agentic`). Phase 4 built the `dispatch-agentic-agent` function but nothing currently invokes it. Phase 5 should activate this path — when a meta-agent spawns sub-agents, they should use the CL agentic path, not the Claude CLI path.

### Key CL Functions Available (from Phases 1-3)

- `agentic-loop` (`src/integration/claude-bridge.lisp:174`) — Multi-turn tool loop
- `agentic-complete` (`src/integration/claude-bridge.lisp:227`) — Convenience wrapper
- `agent-to-sexpr` / `sexpr-to-agent` (`src/agent/agent.lisp`) — Serialization
- `make-snapshot` / `save-snapshot` / `load-snapshot` (`src/snapshot/`) — Persistence
- `create-branch` / `switch-branch` / `list-branches` (`src/snapshot/branch.lisp`) — Branching
- `snapshot-diff` (`src/snapshot/diff-engine.lisp`) — Diffing
- `define-capability-tool` / `test-capability-tool` / `promote-capability-tool` (`src/integration/builtin-tools.lisp`) — Self-extension
- `make-inference-provider` (`src/integration/provider-inference.lisp`) — Provider switching

### Known Gotchas

- **LFE `#M()` map literals** don't evaluate expressions — use backtick-unquote: `` `#M(key ,variable) ``
- **LFE `when` guards** only work in function heads, not bodies
- **LFE binary vs list strings**: `"hello"` = charlist, `#"hello"` = binary. Use `ensure-string/1` at boundaries
- **CL worker boot**: SBCL + Quicklisp = up to 10 seconds. Agent spawning must be async
- **LFE test running**: Must specify modules explicitly: `rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests`
- **Clean rebuild**: `rm -rf _build/default/lib/autopoiesis/ebin _build/test/lib/autopoiesis/ebin`

---

## Bug Fixes Applied During Phase 4

These were pre-existing, fixed opportunistically:

1. **`src/api/routes.lisp`**: `(declare (ignore agent-id))` was placed after `(require-permission :read)` — CL requires declarations at body start. Moved declare before function call.
2. **`src/api/packages.lisp`**: `*api-keys*` was used by `rest-api-tests.lisp` but not exported from the `autopoiesis.api` package. Added to exports.

---

## File Locations Quick Reference

```
# CL core system
src/core/               — S-expression utilities, cognitive primitives, extension compiler
src/agent/              — Agent runtime, capabilities, cognitive loop, learning
src/snapshot/           — Content-addressable storage, branches, diff engine
src/interface/          — Human-in-the-loop blocking requests
src/integration/        — Claude bridge, MCP, tools, agentic loop, providers, OpenAI bridge
src/api/                — WebSocket + REST + MCP servers
scripts/agent-worker.lisp  — CL side of the bridge protocol

# LFE super agent
lfe/apps/autopoiesis/src/  — Source (11 modules, 1,605+ LOC)
lfe/apps/autopoiesis/test/ — Tests (5 modules, 95 tests)
lfe/rebar.config           — Build config

# Planning & docs
thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md    — Master 5-phase plan
thoughts/shared/plans/2026-02-15-phase4-rich-cl-lfe-bridge.md     — Phase 4 spec (complete)
thoughts/shared/research/2026-02-16-lfe-control-plane-analysis.md — Architecture analysis
thoughts/shared/handoffs/                                          — Session handoffs
```
