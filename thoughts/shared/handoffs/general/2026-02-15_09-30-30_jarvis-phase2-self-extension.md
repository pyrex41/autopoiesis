---
date: 2026-02-15T15:30:30Z
researcher: Claude Code
git_commit: 3a1a30a
branch: main
repository: autopoiesis
topic: "Jarvis Phase 2: Self-Extension Tools Implementation"
tags: [implementation, jarvis, self-extension, phase2, agentic-loop]
status: complete
last_updated: 2026-02-15
last_updated_by: Claude Code
type: implementation_strategy
---

# Handoff: Jarvis Phase 2 Self-Extension Tools

## Task(s)

### Completed: Phase 1 - CL Agentic Tool Loop
Phase 1 of the Jarvis implementation plan is **fully complete and tested**. This added:
1. `agentic-loop` — multi-turn tool loop in `claude-bridge.lisp` (calls Claude API → checks tool_use → executes tools → sends results back → repeats)
2. `agentic-agent` — new agent class with cognitive loop specializations (perceive→reason→decide→act→reflect) that runs agentic loops with full thought recording
3. `*claude-complete-function*` — testability hook for mocking API calls
4. 55 new tests across 2 suites, all passing. Full test suite (2,269 checks, 10 suites) passes with 0 regressions.

**Changes are uncommitted.** The next agent should commit these before starting Phase 2.

### Next: Phase 2 - Self-Extension Tools
Wire the extension compiler + capability system as tools the agent can call during its agentic loop. Close the self-modification loop. Detailed spec in plan document.

### Planned: Phases 3-5
Phases 3 (Provider Generalization), 4 (Rich CL-LFE Bridge), and 5 (Meta-Agent Orchestration) are planned but not started.

## Critical References

1. **Implementation Plan**: `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — The full 5-phase plan with exact file paths, function signatures, success criteria, and estimated sizes for each phase.
2. **Research Document**: `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Contains detailed analysis of the self-extension loop gap (3 subsystems that work independently but aren't wired together), competitive landscape, and CL↔LFE bridge mapping.
3. **Architecture Principle**: CL runs agents, LFE supervises processes. CL is the primary agent runtime; LFE provides OTP supervision and scheduling.

## Recent Changes

All changes are uncommitted on `main` branch:

- `src/integration/claude-bridge.lisp:165-231` — Added `*claude-complete-function*` dynamic var, `agentic-loop` function (~60 lines), and `agentic-complete` convenience wrapper
- `src/integration/agentic-agent.lisp` — **New file** (183 lines): `agentic-agent` class, `make-agentic-agent` constructor, 5 cognitive loop specializations, `agentic-agent-prompt` convenience, `agentic-agent-to-sexpr` serialization
- `src/integration/packages.lisp:218-231` — Added 10 new exports for agentic loop and agentic agent
- `autopoiesis.asd:102` — Added `(:file "agentic-agent")` to integration module
- `autopoiesis.asd:192` — Added `(:file "agentic-tests")` to test system
- `test/agentic-tests.lisp` — **New file** (389 lines): 17 tests across 2 suites with mock infrastructure (`with-mock-claude` macro, mock response builders, test capabilities)

## Learnings

1. **SBCL `flet` cannot override compiled functions across packages.** Tests initially used `cl:flet` to mock `claude-complete` but SBCL ignores the shadowing. Solution: `*claude-complete-function*` dynamic variable in `agentic-loop` that tests bind with `let`. See the `with-mock-claude` test macro at `test/agentic-tests.lisp:83-95`.

2. **cl-json dash handling**: Claude API's `stop_reason` field gets decoded as `:stop--reason` (double dash) by cl-json. The existing `response-stop-reason` function handles this at `src/integration/claude-bridge.lisp:148-150`.

3. **The self-extension gap is small**: Three subsystems (extension compiler, agent capabilities, tool mapping) all work independently but nothing connects them. Phase 2 needs only ~3 new `defcapability` definitions (~100-150 lines) to close the loop. See the detailed analysis in the research document under "The Self-Extension Loop: What's Connected and What's Not".

4. **Team agents hit permission blocks**: When spawning team agents with `bypassPermissions` mode, the agents still got blocked on file writes and sent permission requests to the team lead inbox. I had to extract the code from their inbox messages and write files manually. For Phase 2, either use a single agent or handle this differently.

5. **Loading the system**: SBCL + ASDF, not Quicklisp. Use `(push #p"/Users/reuben/projects/ap/" asdf:*central-registry*)` then `(asdf:load-system :autopoiesis/test)`. Run tests with `(autopoiesis.test:run-all-tests)` or specific suites like `(fiveam:run! 'autopoiesis.test::agentic-loop-tests)`.

## Artifacts

- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Full 5-phase plan (Phase 2 spec starts at the "Phase 2: Self-Extension Tools" section)
- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — Codebase analysis with self-extension loop details
- `src/integration/claude-bridge.lisp:165-231` — New agentic loop implementation
- `src/integration/agentic-agent.lisp` — New agentic agent class
- `test/agentic-tests.lisp` — New test suite with mock infrastructure
- `src/integration/packages.lisp:218-231` — New exports

## Action Items & Next Steps

### Immediate: Commit Phase 1
1. Commit the uncommitted Phase 1 changes (5 files modified/created)

### Phase 2: Self-Extension Tools (~150 lines new code)
Per the plan at `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md`:

1. **Add 3 new `defcapability` tools** to `src/integration/builtin-tools.lisp`:
   - `define-capability` — takes name, description, parameters, code (S-expression string), optional test-cases. Calls `validate-extension-source` (extension-compiler.lisp:232), `compile-extension` (extension-compiler.lisp:389), `agent-define-capability` (agent-capability.lisp:72)
   - `test-capability` — takes name and test-cases. Calls `test-agent-capability` (agent-capability.lisp:128)
   - `promote-capability` — takes name. Calls `promote-capability` (agent-capability.lisp:199)

2. **Add 2 introspection tools** to `src/integration/builtin-tools.lisp`:
   - `list-capabilities` — lists all available capabilities with descriptions
   - `inspect-thoughts` — shows recent thoughts from the agent's thought stream

3. **Wire `extension-provides` slot** in `src/core/extension-compiler.lisp` (line 38-41) — currently documented but never read by any code. Make extensions auto-register as capabilities.

4. **Write tests** for the self-extension workflow end-to-end

5. **Update exports** in packages.lisp and ASDF definition

### Success Criteria for Phase 2
- An agentic-agent can call `define-capability` to write new Lisp code
- The extension compiler validates and rejects unsafe code
- The agent can run tests on its new capability
- Promoted capabilities appear in the global registry
- New capabilities are immediately available as tools in subsequent turns

## Other Notes

### Key File Locations for Phase 2
- Extension compiler: `src/core/extension-compiler.lisp` (570 lines) — `register-extension` at line 474, `validate-extension-source` at line 232, `compile-extension` at line 389, `invoke-extension` at line 517
- Capability system: `src/agent/agent-capability.lisp` — `agent-define-capability` at line 72, `test-agent-capability` at line 128, `promote-capability` at line 199
- Built-in tools: `src/integration/builtin-tools.lisp` (314 lines) — 13 existing tools defined with `defcapability` macro. New tools follow the same pattern.
- Tool mapping: `src/integration/tool-mapping.lisp` — `execute-tool-call` at line 209 handles tool dispatch

### Sandbox Whitelist
The extension compiler allows ~170 symbols (`*sandbox-allowed-symbols*`). Agent-written code can only use these. The `*forbidden-symbols*` list blocks ~30+ dangerous operations. Extensions auto-disable after 3 errors.

### Existing Test Patterns
The `with-mock-claude` macro in `test/agentic-tests.lisp:83-95` provides the mocking pattern for any test that needs to mock Claude API calls. Use `*claude-complete-function*` for custom mock behaviors.
