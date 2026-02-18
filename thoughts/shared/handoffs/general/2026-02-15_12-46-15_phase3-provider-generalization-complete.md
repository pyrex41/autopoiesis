---
date: 2026-02-15T18:46:14Z
researcher: Claude Code
git_commit: 4e381a3 (uncommitted changes pending)
branch: main
repository: autopoiesis
topic: "Jarvis Phase 3: Provider Generalization — Complete"
tags: [implementation, jarvis, provider, phase3, agentic-loop, openai, inference]
status: complete
last_updated: 2026-02-15
last_updated_by: Claude Code
type: implementation_strategy
---

# Handoff: Phase 3 Provider Generalization — Complete

## Task(s)

### Completed: Phase 3 — Provider Generalization (uncommitted)
- **Bug fix**: `execute-tool-call` cross-package symbol matching — changed from `eql` to `string=` comparison
- **OpenAI bridge** (`openai-bridge.lisp`): Full OpenAI-compatible API client with bidirectional message/tool format conversion and response normalization
- **Inference provider** (`provider-inference.lisp`): `inference-provider` subclass of `provider` for direct API calls (no subprocess), supporting `:anthropic` and `:openai` API formats
- **Agentic agent update**: `agentic-agent` now accepts any `inference-provider` via `:provider` kwarg, fully backward compatible
- **104 new test checks** across 4 new sub-suites, all passing. Total: 2,409 checks, 0 failures

### Prior Completed: Phase 1 (commit 9c27a59), Phase 2 (commit 4e381a3)
- See `thoughts/shared/handoffs/general/2026-02-15_phase3-provider-generalization.md` for Phase 1+2 details

### Planned: Phase 4 — Rich CL-LFE Bridge
- Expand bridge protocol so LFE can fully orchestrate CL agents
- Trigger agentic loops, navigate snapshots, query capabilities, stream results
- See `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` at "Phase 4: Rich CL-LFE Bridge"

### Planned: Phase 5 — Meta-Agent Orchestration

## Critical References

1. **Implementation Plan**: `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Full 5-phase plan; Phase 4 spec starts at "Phase 4: Rich CL-LFE Bridge"
2. **Phase 3 Input Handoff**: `thoughts/shared/handoffs/general/2026-02-15_phase3-provider-generalization.md` — Context from Phases 1+2
3. **Research**: `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Provider analysis

## Recent Changes

All changes are uncommitted on `main` (base: 4e381a3):

### New Files
- `src/integration/openai-bridge.lisp` — OpenAI-compatible API client (~190 lines): `openai-client` class, `claude-messages-to-openai`, `claude-tools-to-openai`, `openai-complete`, `openai-response-to-claude-format`, `aget` flexible alist accessor
- `src/integration/provider-inference.lisp` — Inference provider (~200 lines): `inference-provider` class, `make-inference-provider`, `make-anthropic-provider`, `make-openai-provider`, `make-ollama-provider`, `provider-invoke` specialization, `sexpr-to-inference-provider`

### Modified Files
- `src/integration/tool-mapping.lisp:221-233` — Bug fix: `execute-tool-call` now uses `string=` for cross-package capability name matching in both hash-table and list lookups
- `src/integration/agentic-agent.lisp` — Added `inference-provider` slot, updated `make-agentic-agent` with `:provider` kwarg, updated `act` to bind correct complete function per API format, updated serialization
- `src/integration/packages.lisp:234-264` — 14 new exports (OpenAI bridge + inference provider)
- `autopoiesis.asd:103-104` — Added `openai-bridge` and `provider-inference` to system definition
- `test/agentic-tests.lisp:676-1162` — 4 new test sub-suites with 32 tests / 104 checks

## Learnings

1. **`cl-json` produces keyword-keyed alists**: When JSON from Claude API goes through `cl-json:decode-json-from-string`, keys become keywords (`:type`, `:content`). But manually constructed alists use string keys (`"type"`, `"content"`). The OpenAI message converter (`claude-messages-to-openai`) must handle both. Solution: the `aget` helper at `openai-bridge.lisp:45-53` tries string=, then direct assoc, then keyword assoc.

2. **`*claude-complete-function*` is the key abstraction point**: Rather than refactoring the entire agentic-loop, the existing `*claude-complete-function*` special variable was the natural extension point. The inference provider binds it to `openai-complete` for OpenAI-format APIs, and to `nil` (default `claude-complete`) for Anthropic. This kept `agentic-loop` unchanged.

3. **OpenAI response normalization pattern**: The `openai-response-to-claude-format` function at `openai-bridge.lisp:166-198` normalizes OpenAI responses to Claude's format so the agentic loop works unchanged. Key mappings: `finish_reason "stop"` → `stop_reason "end_turn"`, `finish_reason "tool_calls"` → `stop_reason "tool_use"`, `tool_calls[].function` → inline `tool_use` content blocks.

4. **Inference provider vs CLI provider**: The existing `provider` base class was designed for CLI subprocess providers. `inference-provider` subclasses it but overrides `provider-invoke` to run `agentic-loop` directly instead of spawning a subprocess. `provider-alive-p` always returns T. `provider-build-command` returns `"direct-api"` (no-op).

5. **Test mocking via `provider-complete-function` slot**: Each `inference-provider` has a `complete-function` slot for testing. Set it to a lambda to mock API calls without touching the global `*claude-complete-function*`. See `test/agentic-tests.lisp:878-882` for the pattern.

## Artifacts

- `src/integration/openai-bridge.lisp` — New file: OpenAI-compatible API client
- `src/integration/provider-inference.lisp` — New file: Inference provider
- `src/integration/tool-mapping.lisp:221-233` — Bug fix for cross-package name matching
- `src/integration/agentic-agent.lisp:13-40` — Updated class definition with `inference-provider` slot
- `src/integration/agentic-agent.lisp:42-67` — Updated constructor accepting `:provider`
- `src/integration/agentic-agent.lisp:109-150` — Updated `act` method with provider dispatch
- `src/integration/agentic-agent.lisp:177-192` — Updated serialization
- `src/integration/packages.lisp:234-264` — New exports
- `autopoiesis.asd:103-104` — New file entries
- `test/agentic-tests.lisp:676-1162` — 4 new test suites (openai-bridge, inference-provider, agentic-agent-provider, tool-name-matching)
- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Master plan (read Phase 4+5)

## Action Items & Next Steps

### Immediate: Commit Phase 3
All changes are tested and passing but uncommitted. Commit with something like `[cl] Add provider generalization with OpenAI bridge and inference provider`.

### Phase 4: Rich CL-LFE Bridge (~300-400 lines estimated)
Per the plan at `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md`:

1. **Expand bridge protocol** — LFE needs to trigger agentic loops, navigate snapshots, query capabilities, and stream results from CL agents
2. **Bridge message format** — Define S-expression protocol messages between BEAM (LFE) and CL processes
3. **Streaming support** — Allow LFE to receive intermediate results from agentic loops in progress
4. **Capability discovery** — LFE should query what tools/capabilities a CL agent has available

### Phase 5: Meta-Agent Orchestration
- Agent that can spin up other agents, assign tasks, collect results
- Uses the full provider registry (CLI providers + inference providers)

## Other Notes

### Test Suite Status Post-Phase 3
```
core-tests:         471 checks, 0 fail
agent-tests:        366 checks, 0 fail
snapshot-tests:     267 checks, 0 fail
interface-tests:     40 checks, 0 fail
integration-tests:  599 checks, 0 fail  (was 495, +104)
viz-tests:           92 checks, 0 fail
security-tests:     322 checks, 0 fail
monitoring-tests:    48 checks, 0 fail
provider-tests:      70 checks, 0 fail
e2e-tests:          134 checks, 0 fail
TOTAL:            2,409 checks, 0 fail
```

### Architecture After Phase 3
The provider hierarchy now has two branches:
- **CLI providers** (existing): `provider` → `claude-code-provider`, `codex-provider`, `opencode-provider`, `cursor-provider` — spawn subprocesses
- **Inference providers** (new): `provider` → `inference-provider` — direct API calls via `agentic-loop`

Both are registered in `*provider-registry*` and usable via `provider-invoke`. An `agentic-agent` can use either path — pass a provider via `:provider` or fall back to direct `claude-client` for backward compatibility.

### Key Design Decision
The `agentic-loop` itself was NOT generalized — it still calls a single complete function. Instead, the API format differences are handled at the edges:
- **Input**: `claude-messages-to-openai` / `claude-tools-to-openai` convert formats before the call
- **Output**: `openai-response-to-claude-format` normalizes responses after the call
- **Dispatch**: `*claude-complete-function*` binding selects which API to call

This keeps the loop simple and avoids a complex strategy pattern inside it.
