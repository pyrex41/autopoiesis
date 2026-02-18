# Handoff: Continue Jarvis Phase 4 (Rich CL-LFE Bridge)

**Date**: 2026-02-16
**From**: PR review/merge session
**Priority**: Recover dangling commits, then implement Phase 4

---

## Critical Context: Git State Recovery Needed

### Dangling Commit Chain

The Jarvis Phase 1-3 work AND the LFE super agent source files exist as **dangling commits** not reachable from any branch. This happened because the PR#1 branch was rebased during the review session, orphaning the commits that were previously ancestors.

**Recovery chain** (oldest to newest):
```
44a1d90 [lfe] Add LFE implementation with combined best-of upgrades      ← LFE SOURCE FILES
c0c1558 [lfe] Add Claude worker subsystem
9d0c65f [super-agent] Fix Claude CLI port communication
477982f [super-agent] Handle binary strings in claude-worker
688b94b [docs] Add SCUD task management workflow
368a715 [cl] Add agent serialization and snapshot-based restoration
912b7a9 [docs] Add comprehensive Super Agent implementation record
c3c8290 [docs] Add accumulated research and planning documents
51bf950 [cl] Add agentic loop and agentic-agent                          ← JARVIS PHASE 1
56104e3 [cl] Add self-extension tools                                     ← JARVIS PHASE 2
6459816 [cl] Fix execute-tool-call cross-package capability name matching ← PHASE 2 FIX
6bdbb41 [cl] Add provider generalization with OpenAI bridge              ← JARVIS PHASE 3
```

**Current main HEAD**: `6d98ce2` (Merge PR#1)

**The problem**: Main diverged from these commits at `7f4a189`. Commits `44a1d90..6bdbb41` need to be cherry-picked or rebased onto current main.

### Recovery Steps (Do This First)

```bash
# 1. Create a rescue branch from the dangling tip
git branch jarvis-rescue 6bdbb41

# 2. Rebase it onto current main
git rebase main jarvis-rescue

# 3. Resolve any conflicts (likely in autopoiesis.asd, packages files)
#    The API layer files (src/api/) were already merged via PRs,
#    so conflicts will be in the parts these commits ALSO touch.

# 4. Fast-forward main
git checkout main
git merge jarvis-rescue

# 5. Push
git push origin main
```

**Expected conflicts**: `autopoiesis.asd` (module lists), possibly `src/autopoiesis.lisp` (exports), `CLAUDE.md`. The LFE files (lfe/apps/autopoiesis/src/*.lfe) should apply cleanly since they're new files.

---

## What's Been Completed

### Jarvis Phases 1-3 (in dangling commits, need recovery)

| Phase | Commit | Key Files | Tests |
|-------|--------|-----------|-------|
| Phase 1: Agentic Loop | `51bf950` | `src/integration/claude-bridge.lisp` (+agentic-loop), `src/agent/agentic-agent.lisp` (new) | 55 new checks |
| Phase 2: Self-Extension | `56104e3`, `6459816` | `src/integration/builtin-tools.lisp` (+define/test/promote capabilities) | 16 new checks |
| Phase 3: Providers | `6bdbb41` | `src/integration/openai-bridge.lisp` (new), `src/integration/provider-inference.lisp` (new) | 104 new checks |

**Total**: 2,409 test assertions passing, 0 failures (as of Phase 3 completion)

### LFE Super Agent (in dangling commits, need recovery)

75 LFE tests passing across 5 modules:
- `boot-tests` - Application startup verification
- `conductor-tests` - Timer heap, event dispatch, metrics
- `agent-worker-tests` - Port communication, S-expression protocol
- `connector-tests` - Webhook server, health endpoint
- `claude-worker-tests` - Claude CLI integration

**Supervisor tree**: `autopoiesis-sup` → conductor + agent-sup + connector-sup + claude-sup

### API Layer (already on main)

Both PRs reviewed, fixed, and merged in previous session:
- PR#2: WebSocket API (Clack/Woo) with JSON/MessagePack wire format
- PR#1: REST API (Hunchentoot) + MCP server + Go SDK
- Security fixes: SHA-256 key hashing, timing-safe comparison, intern DoS prevention, path traversal fix, session validation

---

## Phase 4: Rich CL-LFE Bridge

**Detailed plan**: `thoughts/shared/plans/2026-02-15-phase4-rich-cl-lfe-bridge.md`

### Goal

Expand the CL-LFE bridge so LFE can fully orchestrate CL agents: trigger agentic loops, query thoughts/capabilities, navigate snapshots, stream results in real-time, and route human-in-the-loop requests.

### Current Bridge State

**CL side** (`scripts/agent-worker.lisp`): 5 message types — `:init`, `:cognitive-cycle`, `:snapshot`, `:inject-observation`, `:shutdown`

**LFE side** (`lfe/apps/autopoiesis/src/agent-worker.lfe`): gen_server with line-based S-expression protocol over SBCL port

**Gap**: CL has agentic-loop, self-extension, providers, snapshot branches, thought queries — but none of these are exposed through the bridge protocol.

### What Phase 4 Adds

8 new message types:
1. `:agentic-prompt` — Trigger multi-turn agentic loop from LFE
2. `:query-thoughts` — Query thought stream (last N, by type, since timestamp)
3. `:list-capabilities` — List agent's registered capabilities
4. `:invoke-capability` — Invoke a specific capability
5. `:checkout` — Restore agent from snapshot
6. `:diff` — Diff two snapshots
7. `:create-branch` / `:switch-branch` — Branch navigation
8. `:blocking-request` routing — Wire human-in-the-loop from CL through LFE

Plus: activate heartbeat thread, add conductor `agentic` dispatch type, streaming thought messages during agentic loop execution.

### Implementation Sub-phases

| Sub-phase | Scope | Est. Lines |
|-----------|-------|-----------|
| 4.1 Activate Heartbeat | CL heartbeat thread + LFE timeout detection | ~30 |
| 4.2 Expand CL Bridge | 8 new handlers in `scripts/agent-worker.lisp` | ~200 |
| 4.3 Expand LFE Client | 8 new `handle_call` clauses in `agent-worker.lfe` | ~150 |
| 4.4 Conductor Dispatch | `agentic` action type + async spawning | ~60 |
| 4.5 Human-in-the-Loop | `:blocking-request` routing through conductor | ~80 |
| 4.6 Tests | CL + LFE test suites | ~120 |
| **Total** | | **~640** |

### Key Files to Modify

| File | Changes |
|------|---------|
| `scripts/agent-worker.lisp` | +8 message handlers, activate heartbeat |
| `lfe/apps/autopoiesis/src/agent-worker.lfe` | +8 client API functions, streaming collection |
| `lfe/apps/autopoiesis/src/conductor.lfe` | +agentic dispatch, rate limiting |
| `test/bridge-protocol-tests.lisp` | New test file (~120 lines) |
| `lfe/apps/autopoiesis/test/*-tests.lfe` | +17 new test cases |

---

## Known Gotchas (from MEMORY.md)

- **LFE `#M()` map literals** don't evaluate expressions — use backtick-unquote: `` `#M(key ,variable) ``
- **LFE `when` guards** only work in function heads, not bodies — use `if`/`case` instead
- **LFE strings**: `"hello"` = charlist, `#"hello"` = binary. At API boundaries use `ensure-string/1`
- **Claude CLI via Erlang Port**: Must use `{spawn, ShellCmd}` with `</dev/null` — stdin pipe causes hangs
- **`--output-format stream-json`** requires `--verbose` when used with `-p`
- **Agent-worker init**: 10-second port_receive timeout; spawn async to avoid blocking tick loops
- **LFE test running**: `rebar3 eunit --module=boot-tests,conductor-tests,agent-worker-tests,connector-tests,claude-worker-tests`
- **cl-json dash convention**: `stop_reason` → `:STOP--REASON` (double hyphen for underscores)

---

## Recommended Execution Order

1. **Recover dangling commits** → get all Phases 1-3 + LFE code onto main
2. **Verify tests pass** → `./scripts/test.sh` (CL) + `cd lfe && rebar3 eunit --module=...` (LFE)
3. **Implement Phase 4.1** (heartbeat) — small, tests the full CL↔LFE roundtrip
4. **Implement Phase 4.2-4.3** (bridge protocol expansion) — the bulk of the work
5. **Implement Phase 4.4** (conductor agentic dispatch)
6. **Implement Phase 4.5** (human-in-the-loop routing)
7. **Run full test suite**, commit, push

---

## File Locations Quick Reference

```
# CL core system
src/core/           — S-expression utilities, cognitive primitives
src/agent/          — Agent runtime, capabilities, cognitive loop
src/snapshot/       — Content-addressable storage, branches, diff
src/interface/      — Human-in-the-loop blocking requests
src/integration/    — Claude bridge, MCP, tools, agentic loop, providers
src/api/            — WebSocket + REST + MCP servers
scripts/agent-worker.lisp  — CL side of the bridge (what Phase 4 expands)

# LFE super agent
lfe/apps/autopoiesis/src/  — Source (currently MISSING, in dangling commit 44a1d90)
lfe/apps/autopoiesis/test/ — Tests (also in dangling commits)
lfe/rebar.config           — Build config

# Planning & docs
thoughts/shared/plans/2026-02-15-phase4-rich-cl-lfe-bridge.md  — Detailed Phase 4 spec
thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md — Master 5-phase plan
thoughts/shared/handoffs/  — Previous session handoffs
```
