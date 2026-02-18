# Handoff: Remove LFE Control Plane, Consolidate to CL

**Date**: 2026-02-16
**From**: Research/Planning Session
**To**: Implementation Agent
**Status**: Ready for implementation

## Context

The user has decided to remove the LFE/BEAM control plane and consolidate all orchestration into Common Lisp. The LFE layer was architecturally sound but practically disconnected — it orchestrated Claude CLI subprocesses but never used the CL cognitive engine. The polyglot overhead (two runtimes, subprocess IPC, S-expression bridging) wasn't justified for a solo-user system.

## Implementation Plan

**Plan file**: `thoughts/shared/plans/2026-02-16-remove-lfe-consolidate-cl.md`

Read this file completely before starting. It has 5 phases with detailed code snippets and success criteria.

## Quick Summary of Phases

1. **CL Conductor** — New `src/orchestration/` module with timer heap + tick loop + event queue (~250 LOC)
2. **CL Claude Worker** — Spawn `claude` CLI as subprocess, parse stream-json (~120 LOC)
3. **HTTP Endpoints** — Add /conductor/status and /conductor/webhook to existing Hunchentoot (~40 LOC)
4. **ASDF Wiring** — Add orchestration module to system definition, create start-system/stop-system
5. **Delete LFE** — Remove `lfe/` directory, `scripts/agent-worker.lisp`, update CLAUDE.md

## Critical Files to Read First

Before implementing, read these to understand what you're porting FROM and building ON:

### What you're porting from (LFE sources):
- `lfe/apps/autopoiesis/src/conductor.lfe` — The main logic to port (timer heap, tick loop, event queue, metrics)
- `lfe/apps/autopoiesis/src/claude-worker.lfe` — Claude CLI subprocess driver to port

### What you're building on (existing CL infrastructure):
- `src/integration/provider.lisp:237-318` — `run-provider-subprocess` pattern for subprocess management
- `src/monitoring/endpoints.lisp` — Existing Hunchentoot server (add new endpoints here)
- `src/integration/claude-bridge.lisp:174-226` — `agentic-loop` for direct API calls (the `:agentic` action type uses this)
- `autopoiesis.asd` — System definition to update

### What you're deleting:
- `lfe/` — Entire directory (11 source files, 5 test files, configs)
- `scripts/agent-worker.lisp` — CL-side bridge script (no longer needed)
- `test/bridge-protocol-tests.lisp` — Tests for the deleted bridge

## Key Decisions Already Made

1. **No OTP supervision trees in CL** — Simple thread + retry loops. The conductor catches errors in its tick loop and continues.
2. **Sorted list for timer heap** — Not gb_trees. CL doesn't have an equivalent built-in. A sorted list is fine for the expected number of timers (single digits).
3. **Reuse existing Hunchentoot** — Don't create a separate HTTP server. Add dispatcher entries to the running monitoring server.
4. **Move config files** — `lfe/config/cortex-mcp.json` and `lfe/config/infra-watcher-prompt.md` move to `config/` at project root.
5. **Keep `scripts/test.sh` working** — Just remove any LFE-specific test commands from it.

## Known Gotchas

- **`cl-json` key format**: cl-json converts JSON keys to keywords with hyphens. `"type"` becomes `:TYPE`. Snake_case like `"cost_usd"` becomes `:COST--USD` or `:COST-USD`. The LFE code used binary keys (#"type"). The CL code uses keyword symbols.
- **Shell quoting**: The LFE `shell-escape-single-quotes` replaces `'` with `'\''`. The CL version should do the same via `cl-ppcre:regex-replace-all`.
- **`sb-ext:run-program` vs `uiop:run-program`**: Use `sb-ext:run-program` for long-running subprocesses (streaming output). Use `uiop:run-program` for one-shot commands (returns string).
- **Thread cleanup**: When stopping the conductor, set `running` to nil and `bt:join-thread` the tick thread. Don't force-kill threads.

## Verification Command

After each phase:
```bash
./scripts/test.sh
```

After all phases:
```lisp
(ql:quickload :autopoiesis)
(autopoiesis.orchestration:start-system)
;; curl localhost:8081/conductor/status
(autopoiesis.orchestration:stop-system)
```

## What Success Looks Like

- `lfe/` directory is gone
- `scripts/agent-worker.lisp` is gone
- All existing CL tests pass (~2,400+ assertions)
- New orchestration tests pass (~25 tests, ~60 assertions)
- `(autopoiesis.orchestration:start-system)` boots conductor + monitoring server
- `(autopoiesis.orchestration:schedule-infra-watcher)` works
- CLAUDE.md reflects the new architecture
