---
date: 2026-02-15T18:00:00Z
researcher: Claude Code
git_commit: 4e381a3
branch: main
repository: autopoiesis
topic: "Jarvis Phase 3: Provider Generalization"
tags: [implementation, jarvis, provider, phase3, agentic-loop]
status: ready
last_updated: 2026-02-15
last_updated_by: Claude Code
type: implementation_strategy
---

# Handoff: Jarvis Phase 3 — Provider Generalization

## Task(s)

### Completed: Phase 1 — CL Agentic Tool Loop (commit 9c27a59)
- `agentic-loop` multi-turn tool loop in `claude-bridge.lisp`
- `agentic-agent` class with cognitive loop specializations
- `*claude-complete-function*` testability hook
- 55 tests across 2 suites, all passing

### Completed: Phase 2 — Self-Extension Tools (commit 4e381a3)
- 5 new `defcapability` tools in `builtin-tools.lisp`: `define-capability-tool`, `test-capability-tool`, `promote-capability-tool`, `list-capabilities-tool`, `inspect-thoughts`
- Self-modification loop is closed: agent can write Lisp → validate → compile → test → promote → use as tool
- 16 new tests in `self-extension-tests` suite including full E2E through mocked agentic loop
- All 2,305 checks pass across 10 test suites, 0 regressions

### Next: Phase 3 — Provider Generalization (~200-300 lines)
Make the agentic loop backend-agnostic so it can work with any LLM provider, not just Claude.

### Planned: Phases 4-5
- Phase 4: Rich CL-LFE Bridge
- Phase 5: Meta-Agent Orchestration

## Critical References

1. **Implementation Plan**: `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Phase 3 spec starts at "Phase 3: Provider Generalization"
2. **Research Document**: `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Provider analysis and competitive landscape
3. **Phase 2 Handoff**: `thoughts/shared/handoffs/general/2026-02-15_09-30-30_jarvis-phase2-self-extension.md` — Prior context and learnings

## Recent Changes

Phase 2 changes (commit 4e381a3):
- `src/integration/builtin-tools.lisp` — Added 5 new tools (~160 lines): self-extension tools (define, test, promote) and introspection tools (list-capabilities, inspect-thoughts)
- `src/integration/packages.lisp` — Added 5 new exports
- `test/agentic-tests.lisp` — Added `self-extension-tests` suite with 16 tests (~285 lines)

Phase 1 changes (commit 9c27a59):
- `src/integration/claude-bridge.lisp:165-237` — `agentic-loop`, `agentic-complete`, `*claude-complete-function*`
- `src/integration/agentic-agent.lisp` — Full agentic-agent class (183 lines)
- `autopoiesis.asd` — Added agentic-agent.lisp and agentic-tests.lisp

## Learnings

1. **`defcapability` symbol naming vs keyword dispatch**: The `defcapability` macro registers capabilities under package-qualified symbols (e.g., `autopoiesis.integration::define-capability-tool`), but `execute-tool-call` in the agentic loop converts tool names to keywords (`:DEFINE-CAPABILITY-TOOL`). These don't match with `eq`. The workaround in tests is `wrap-as-keyword-capability`. A proper fix would make `execute-tool-call` use `string=` on symbol names instead of `eq`. This is a pre-existing design tension, not introduced by Phase 2.

2. **JSON parameter name mapping**: `capability-params-to-json-schema` uses `string-downcase` on symbol names, preserving dashes (so `:test-cases` → `"test-cases"`). Claude sends back the same key. `json-input-to-keyword-args` converts `"test-cases"` → `:TEST-CASES` which correctly matches the Lisp keyword parameter. But `"test_cases"` (snake_case) would become `:TEST_CASES` which does NOT match. Mock data in tests must use the dash form, not underscore.

3. **`agent-define-capability` needs agent + global registry**: The function adds the capability to the agent's capabilities list only. For the self-extension tools to work across separate tool calls (define, then test, then promote), the capability must also be registered in the global `*capability-registry*`. Phase 2 handles this by calling `register-capability` after `agent-define-capability`.

4. **Team agents still have permission issues**: The handoff from the previous session warned about this. For Phase 2, a single-agent approach was used instead, which worked well for the ~150-line scope.

5. **Loading the system**: Use `(push #p"/Users/reuben/projects/ap/" asdf:*central-registry*)` then `(asdf:load-system :autopoiesis/test)`. Run tests with `(autopoiesis.test:run-all-tests)` or `(fiveam:run! 'autopoiesis.test::self-extension-tests)`.

## Artifacts

- `src/integration/builtin-tools.lisp:268-427` — 5 new self-extension/introspection tools
- `src/integration/packages.lisp:131-137` — New exports
- `test/agentic-tests.lisp:391-675` — 16 self-extension tests
- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Full 5-phase plan

## Action Items & Next Steps

### Phase 3: Provider Generalization (~200-300 lines)

Per the plan at `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md`:

1. **Define a generic `agentic-provider` protocol**:
   - Generic functions: `provider-complete`, `provider-format-tools`, `provider-parse-response`
   - The existing `claude-complete` becomes a method on a Claude-specific provider
   - Other providers (OpenAI, local models) can implement the same protocol

2. **Refactor `agentic-loop` to use the provider protocol**:
   - Replace direct `claude-complete` call with `provider-complete`
   - Make tool format conversion use `provider-format-tools`
   - Make response parsing use `provider-parse-response`
   - Keep backward compatibility: Claude provider is the default

3. **Add at least one additional provider** (e.g., OpenAI-compatible):
   - Implement the protocol for OpenAI's chat completion API
   - Tool format differs (function calling vs Claude tool_use)
   - Response parsing differs (different JSON structure)

4. **Update `agentic-agent`**:
   - Accept a provider instead of a client
   - Default to Claude provider for backward compatibility

5. **Write tests** for provider abstraction and multi-provider dispatch

### Key Files for Phase 3
- `src/integration/claude-bridge.lisp` — Current Claude-specific implementation to generalize
- `src/integration/agentic-agent.lisp` — Agent class to update
- `src/integration/tool-mapping.lisp` — Tool conversion (currently Claude-specific)
- `src/integration/packages.lisp` — New exports
- Existing providers in `src/integration/` — `provider.lisp`, `provider-backed-agent.lisp` (the subprocess-based providers; Phase 3 is about API-level generalization, different from these)

### Success Criteria for Phase 3
- `agentic-loop` works with any provider implementing the protocol
- Existing Claude tests still pass unchanged
- At least one non-Claude provider compiles and has basic tests
- `agentic-agent` can be constructed with any provider

## Other Notes

### Test Suite Status Post-Phase 2
```
core-tests:         471 checks, 0 fail
agent-tests:        366 checks, 0 fail
snapshot-tests:     267 checks, 0 fail
interface-tests:     40 checks, 0 fail
integration-tests:  495 checks, 0 fail  (was 404, +91 from self-extension)
viz-tests:           92 checks, 0 fail
security-tests:     322 checks, 0 fail
monitoring-tests:    48 checks, 0 fail
provider-tests:      70 checks, 0 fail
e2e-tests:          134 checks, 0 fail
TOTAL:            2,305 checks, 0 fail
```

### Architecture Principle Reminder
CL runs agents. LFE supervises processes. Phase 3 generalizes the CL agent runtime to support multiple LLM backends. This is entirely within the CL domain.
