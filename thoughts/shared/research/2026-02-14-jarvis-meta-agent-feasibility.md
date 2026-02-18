---
date: 2026-02-14T19:13:06Z
researcher: Claude Code
git_commit: 3a1a30a5a08372e6255875f771f35da89dc17ab5
branch: main
repository: autopoiesis
topic: "Jarvis Meta-Agent Feasibility: Current State, Gaps, and Path Forward"
tags: [research, codebase, jarvis, meta-agent, feasibility, architecture, critique]
status: complete
last_updated: 2026-02-14
last_updated_by: Claude Code
last_updated_note: "Added follow-up research: self-extension loop analysis, nanoclaw/openclaw comparison, CL-LFE bridge mapping"
---

# Research: Jarvis Meta-Agent Feasibility

**Date**: 2026-02-14T19:13:06Z
**Researcher**: Claude Code
**Git Commit**: 3a1a30a
**Branch**: main
**Repository**: autopoiesis

## Research Question

"This project is super ambitious, but I don't know its current state. I'm not sure how to get it from being here to being super fucking useful. I'd like to kind of build a Jarvis meta agent on top of it. What would that take and how are we uniquely staged to do that? And perhaps more soberly, what are the critiques or things that we really are missing?"

## Summary

Autopoiesis has two substantial codebases: a Common Lisp platform (~6,000+ LOC across 77 source files, 2,400+ test assertions all passing) and an LFE/BEAM "Super Agent" orchestration layer (~1,200 LOC, 75 tests passing). The CL platform provides real implementations of snapshot persistence, content-addressable storage, a learning system with genuine pattern mining, a self-extension compiler with AST-walking sandbox, and a full tool/capability registry. The LFE layer provides OTP supervision, a conductor tick loop, and Claude CLI integration via Erlang ports.

**The honest picture**: The infrastructure layers are genuinely impressive and substantially complete. But there is no product layer. No user has ever done anything useful with this system beyond running the test suite. The gap between "all tests pass" and "I can ask Jarvis to do something" is the gap between a well-tested engine and a car you can drive.

**What makes this uniquely positioned for Jarvis**: Homoiconicity (agent thoughts are data you can inspect/modify/replay), the snapshot DAG (time-travel for agent cognition), self-extension (agents writing validated Lisp code), and BEAM fault tolerance. No other agent framework has this combination.

**What's missing**: A command-line entry point that does something, real Claude API calls (all mocked in tests), a way to connect CL capabilities to the LFE orchestrator, and concrete use-case workflows.

## Detailed Findings

### 1. The Common Lisp Platform (What Exists)

**Core Layer** (`src/core/`, ~1,200 LOC):
- `s-expr.lisp` (202 lines): SHA256 structural hashing, s-expression diff/patch. Real content-addressable foundation.
- `cognitive-primitives.lisp` (204 lines): CLOS classes for thought, observation, decision, action, reflection. These are the atomic units of agent cognition.
- `thought-stream.lisp` (213 lines): Dual-indexed stream (vector for sequential access, hash for ID lookup). Compaction and archival support.
- `extension-compiler.lisp` (570 lines): AST-walking code validator. Whitelist of ~170 allowed symbols. This is a real sandbox - not a toy. Validates, transforms, and compiles agent-written Lisp.
- `recovery.lisp`: Condition/restart system for graceful error handling.
- `profiling.lisp`: Performance measurement infrastructure.

**Agent Layer** (`src/agent/`, ~1,500 LOC):
- `agent.lisp`: CLOS agent class with capabilities, context window, thought stream.
- `cognitive-loop.lisp` (59 lines): Generic function protocol: perceive → reason → decide → act → reflect. **Intentionally a scaffold** - default methods are no-ops. This is by design; concrete cognitive loops are meant to be specialized per agent type.
- `learning.lisp` (1,032 lines): This is surprisingly substantial. N-gram pattern extraction, frequency-based heuristic generation, confidence scoring, online reinforcement learning with reward integration. Not a stub.
- `spawner.lisp`: Dynamic agent creation from specifications.
- `registry.lisp`: Agent lifecycle management.
- `builtin-capabilities.lisp`: Pre-defined capability set.

**Snapshot Layer** (`src/snapshot/`, ~1,800 LOC):
- `content-store.lisp`: Content-addressable storage using SHA256. Real disk persistence to `~/.autopoiesis/`.
- `snapshot.lisp`: Full agent state capture as S-expressions.
- `branch.lisp`: Git-like DAG with create-branch, list-branches, branch history. **Branch merging is a placeholder** - only fast-forward implemented.
- `time-travel.lisp`: Jump to any snapshot, replay forward with modifications. Real implementation.
- `diff-engine.lisp`: Structural diff between any two cognitive states.
- `lru-cache.lisp`: LRU eviction for memory management.
- `lazy-loading.lisp`: On-demand content retrieval.
- `backup.lisp`: Snapshot export/import.
- `persistence.lisp`: Disk I/O with journaling.

**Integration Layer** (`src/integration/`, ~2,000+ LOC):
- `claude-bridge.lisp` (164 lines): Real HTTP calls via `dex:post` to Claude API. Handles message formatting, system prompts, tool results. **Claude streaming is NOT implemented** (placeholder only).
- `mcp-client.lisp` (481 lines): Real subprocess management via `sb-ext:run-program`. JSON-RPC 2.0 over stdio pipes. Server lifecycle management.
- `tool-mapping.lisp` (308 lines): Bidirectional name conversion (kebab-case ↔ snake_case). Capability → JSON Schema translation for Claude's tool_use format.
- `builtin-tools.lisp` (314 lines): 13 real capabilities (file read/write/list, shell exec, web fetch, search, grep, directory tree, clipboard, env vars).
- `provider.lisp` + provider-*.lisp: Abstraction layer wrapping CLI tools (Claude Code, Codex, OpenCode, Cursor) as cognitive backends. Each provider spawns external processes.
- `events.lisp`: Event bus for inter-component communication.

**Visualization** (`src/viz/`, ~800 LOC):
- Full 2D terminal timeline with ANSI rendering, scrolling, filtering, help overlay.
- Interactive navigation through snapshot history.

**Holodeck** (`src/holodeck/`, ~1,500 LOC):
- ECS architecture, shader definitions, mesh generation, dual camera, HUD, ray picking, key bindings.
- **No actual OpenGL rendering** - the architecture and data structures are complete, but there's no windowing system integration. Tests verify the ECS and math, not pixels on screen.

**Security** (`src/security/`, ~500 LOC):
- Permission system with agent-level access control.
- Audit logging with tamper detection.
- Input validation with regex patterns.
- Sandbox escape prevention in extension compiler.

**Monitoring** (`src/monitoring/`):
- Hunchentoot HTTP server for health/metrics endpoints.
- `/health`, `/metrics`, `/agents` endpoints.

### 2. The LFE/BEAM Super Agent (What Exists)

A complete OTP application (`lfe/apps/autopoiesis/`):

- **Supervisor tree**: `autopoiesis-sup` → conductor + agent-sup + connector-sup + claude-sup
- **Conductor** (`conductor.lfe`): Gen_server with 100ms tick loop, timer-based scheduling, event queue, task result handling with failure tracking. Implements the "Ralph Loop" pattern: tick → check tasks → spawn claude worker → parse result → reschedule.
- **Claude Worker** (`claude-worker.lfe`, 257 LOC): Port-based gen_server spawning Claude CLI (`claude -p "prompt" --output-format stream-json --verbose`). Handles binary/list string normalization, shell escaping, stream-json parsing.
- **Claude Supervisor** (`claude-sup.lfe`): `simple_one_for_one` for dynamic worker spawning.
- **Agent Worker** (`agent-worker.lfe`): Spawns SBCL subprocess loading `:autopoiesis` system. S-expression protocol over stdio. **10-second init timeout** - must be spawned asynchronously.
- **Boot** (`boot.lfe`): Application startup and environment config.

**75 tests across 5 modules, 0 failures.**

### 3. Research Documents and Evolution

19 documents in `thoughts/shared/` trace the project's evolution:

- Started as pure CL platform with all 10 phases.
- Evolved to recognize BEAM/OTP as better fit for supervision and orchestration.
- "Super Agent" concept: LFE conductor orchestrates, CL provides cognitive primitives.
- Key insight from `super-agent-synthesis.md`: "Conductor = Ralph Loop" - the conductor's tick loop IS the existing ralph automation pattern, formalized as OTP.
- `Autopoiesis + Cortex Synthesis Plan.md`: Dual-mode execution design (fast programmatic path for known patterns, slow LLM path for novel situations).

### 4. What's Actually Runnable

**Things that work today:**
1. `(ql:quickload :autopoiesis)` in SBCL - loads the full system
2. `(asdf:test-system :autopoiesis)` - runs 600+ tests, all pass
3. `(autopoiesis.interface:start-session ...)` - interactive CLI session
4. LFE supervisor tree boots: `application:start 'autopoiesis`
5. Claude CLI integration via LFE ports (tested E2E)
6. Docker deployment (`docs/DEPLOYMENT.md`)
7. 2D timeline visualization in terminal

**Things that don't work or don't exist:**
1. No standalone binary or simple CLI command to "just use it"
2. No `examples/` directory showing real usage
3. Holodeck: architecture complete, no actual rendering
4. Claude API: real HTTP code exists but never tested against live API (all mocked)
5. MCP: real subprocess code exists but never tested against live servers (all mocked)
6. Branch merging: placeholder only
7. Claude streaming: not implemented
8. CL↔LFE bridge: agent-worker.lfe tries to load SBCL but this path is fragile

## The Jarvis Question: What Would It Take?

### What "Jarvis" Means Here

A Jarvis meta-agent would be: a persistent, conversational AI assistant that can orchestrate multiple specialized sub-agents, maintain context across sessions, learn from interactions, time-travel through its own history, and extend its own capabilities - all with human oversight at any point.

### Unique Advantages (Why This Platform)

1. **Homoiconicity is real power**: In most frameworks, agent state is opaque Python objects. Here, every thought, decision, and action is an S-expression. You can `diff` two cognitive states like you diff code. You can `eval` a thought. You can `macroexpand` a strategy. No other framework offers this.

2. **Snapshot DAG enables cognitive time-travel**: Not just "undo" - full branching of agent cognition. "What would have happened if the agent chose differently at step 47?" is a real operation, not a thought experiment.

3. **Self-extension compiler is production-quality**: The 570-line AST-walking validator with ~170 whitelisted symbols is not a toy. Agents can safely write, validate, and compile new Lisp code. This is the path to agents that genuinely extend themselves.

4. **Learning system has real teeth**: 1,032 lines of actual pattern mining, heuristic generation, and reinforcement learning. This isn't "append to a prompt" learning - it's structural.

5. **BEAM supervision is the right orchestration model**: OTP supervisors provide exactly the fault-tolerance semantics you want for agent orchestration. Agents crash? Supervisor restarts them. This is what Erlang was designed for.

6. **Provider abstraction already wraps Claude Code**: The integration layer can already drive Claude Code as a subprocess. The pipe from "conductor decides to do X" to "Claude Code executes X" exists.

### What's Missing (The Gap to Jarvis)

#### Critical Path (Must Have)

1. **A CLI entry point**: Something like `autopoiesis chat` or `jarvis "do the thing"`. Currently requires REPL knowledge. The LFE boot.lfe is closest to this but it's still developer-facing.

2. **Real Claude API integration**: The bridge code exists but has never been tested against the actual API. Need to: validate message format, handle streaming responses, manage token limits, deal with rate limits.

3. **Conductor ↔ Cognitive Loop binding**: The LFE conductor ticks. The CL cognitive loop defines perceive/reason/decide/act/reflect. These two aren't connected. The conductor needs to invoke the CL cognitive cycle (or re-implement it in LFE/Erlang).

4. **Task decomposition and delegation**: The conductor has a task queue and can spawn Claude workers. But there's no intelligence in how tasks are decomposed or routed. Need: task analysis, capability matching, sub-agent specialization.

5. **Persistent state across sessions**: Snapshots exist. Disk persistence exists. But there's no "resume where I left off" workflow. Need: session save/restore, context reconstruction from snapshot DAG.

#### Important But Not Blocking

6. **Streaming responses**: Claude streaming is not implemented. For interactive use, streaming is important for UX.

7. **Branch merging**: Only fast-forward exists. For "try two approaches and merge the better one," need real three-way merge of cognitive states.

8. **MCP integration testing**: The client code is real, but untested against live servers. MCP is how Jarvis would access external tools beyond the 13 builtins.

9. **Observability**: The monitoring endpoints exist but need connection to the conductor loop. "What is Jarvis doing right now?" should be answerable.

#### Nice to Have

10. **Holodeck rendering**: The ECS architecture is there. Connecting it to an actual rendering backend would give the "Jarvis visualization" aspect.

11. **Multi-agent collaboration**: Agent spawner exists, but no protocol for agents to collaborate on shared goals, communicate intermediate results, or negotiate resources.

12. **Knowledge persistence**: Learning system extracts patterns, but where are they stored between sessions? Need durable heuristic storage.

### Rough Architecture of Jarvis

```
User → CLI/Chat Interface
         ↓
    Jarvis Conductor (LFE gen_server)
    - Maintains session state
    - Routes to specialist agents
    - Manages cognitive budget
         ↓
    ┌────────────────────────────────┐
    │  Specialist Agents (dynamic)   │
    │  - Code Agent (Claude Code)    │
    │  - Research Agent (web/MCP)    │
    │  - Analysis Agent (CL prims)   │
    │  - Extension Agent (compiler)  │
    └────────────────────────────────┘
         ↓
    Snapshot Layer (automatic)
    - Every significant action snapshots
    - User can time-travel, branch, diff
         ↓
    Learning Layer (background)
    - Pattern extraction from sessions
    - Heuristic refinement
    - Self-extension proposals
```

## Honest Critiques

### 1. The "All Tests Pass" Illusion

CLAUDE.md says "All phases (0-10) complete" and "2,400+ assertions across 600+ tests." This is technically true. But the tests verify internal data structures and mocked integrations. No test verifies that you can actually talk to Claude, connect to an MCP server, or accomplish a real-world task. The test suite proves the engine works; it does not prove the car drives.

### 2. Two Systems, Loosely Coupled

The CL platform and LFE layer are essentially independent codebases that happen to be in the same repo. The CL system has a sophisticated cognitive model. The LFE system has a practical orchestration loop. But the bridge between them (`agent-worker.lfe` spawning SBCL) is fragile - it requires Quicklisp, correct ASDF paths, and a 10-second init timeout. In practice, the LFE conductor talks to Claude CLI, not to the CL cognitive primitives.

### 3. No User-Facing Workflow

There is no `examples/` directory. No quickstart guide that ends with something useful happening. No demo script. The closest thing to a user experience is `(autopoiesis.interface:start-session ...)` in a SLIME REPL. A Jarvis needs to be something someone can *use*, not something they can *load*.

### 4. Spec-Driven Development Debt

The 10-phase spec was ambitious and drove comprehensive implementation. But the spec sometimes drove features before their prerequisites. For example: the 3D holodeck has complete ECS and shader infrastructure but no rendering backend. The branch system has full DAG management but only fast-forward merge. The cognitive loop defines the protocol but all methods are no-ops. These are architecturally sound but practically incomplete.

### 5. The Learning System Is Isolated

The 1,032-line learning system is genuinely impressive, but it's not connected to anything that produces real training data. The n-gram extractor, heuristic generator, and RL updater need actual agent interactions to learn from. Currently they're exercised only by test fixtures.

### 6. Security Before Users

The security layer (permissions, audit, validation, sandbox) is thorough. But securing a system nobody uses yet is premature. When real users arrive, the threat model will likely be different from what was anticipated.

## Pragmatic Path Forward (Shortest Route to Useful)

If the goal is "Jarvis that does something useful ASAP," here's the shortest path:

**Week 1: Make it talk**
- Create `bin/jarvis` CLI entry point that boots LFE supervisor
- Connect conductor to Claude API (validate the bridge code against real API)
- Implement basic chat loop: user → conductor → claude worker → response → user

**Week 2: Make it remember**
- Wire snapshot layer into conductor loop (snapshot on each significant exchange)
- Implement session save/restore
- Add `jarvis resume` command

**Week 3: Make it smart**
- Implement task decomposition in conductor (use Claude to decompose, then route)
- Add specialist agent types (code, research, analysis)
- Connect provider abstraction so conductor can delegate to Claude Code

**Week 4: Make it learn**
- Wire learning system to real interaction data
- Implement heuristic persistence
- Add self-extension proposals (agent suggests new capabilities, human approves)

This skips holodeck, branch merging, MCP, and multi-agent collaboration. Those are valuable but not on the critical path to "useful Jarvis."

## Code References

- `src/core/extension-compiler.lisp` - Self-extension sandbox validator
- `src/core/cognitive-primitives.lisp` - Agent thought representation
- `src/agent/learning.lisp` - Pattern mining and RL system
- `src/agent/cognitive-loop.lisp` - Cognitive cycle protocol
- `src/integration/claude-bridge.lisp` - Claude API bridge
- `src/integration/mcp-client.lisp` - MCP subprocess client
- `src/integration/provider-claude-code.lisp` - Claude Code CLI provider
- `src/snapshot/content-store.lisp` - Content-addressable persistence
- `src/snapshot/time-travel.lisp` - Cognitive time travel
- `lfe/apps/autopoiesis/src/conductor.lfe` - Orchestration tick loop
- `lfe/apps/autopoiesis/src/claude-worker.lfe` - Claude CLI port driver
- `lfe/apps/autopoiesis/src/autopoiesis-sup.lfe` - OTP supervisor tree
- `scripts/agent-worker.lisp` - CL subprocess worker

## Architecture Documentation

The codebase follows a layered architecture where each layer depends only on layers below it. The CL platform uses CLOS extensively with well-defined generic function protocols. The LFE layer follows standard OTP conventions (gen_server, supervisor, application behaviors). The two systems communicate via subprocess stdio protocols.

Key architectural patterns:
- Content-addressable storage (SHA256 hashing) throughout snapshot layer
- Generic function protocols for extensibility (cognitive loop, capabilities)
- Condition/restart system for error recovery
- Event bus for loose coupling between components
- Provider abstraction for external tool integration

## Related Research

- `thoughts/shared/research/2026-02-06-next-steps-roadmap.md` - Three-layer completion assessment
- `thoughts/shared/research/2026-02-06-super-agent-synthesis.md` - Conductor = Ralph Loop insight
- `thoughts/shared/plans/2026-02-06-super-agent-implementation-record.md` - Complete Super Agent implementation record
- `thoughts/shared/plans/Autopoiesis + Cortex Synthesis Plan.md` - Original conductor design with fast/slow paths
- `thoughts/shared/research/2026-02-03-autopoiesis-codebase-overview.md` - Earlier codebase overview

## Open Questions

1. **CL or LFE for Jarvis brain?** The CL cognitive primitives are richer but the LFE conductor is more practical. Should Jarvis's high-level reasoning happen in CL (via agent-worker subprocess) or LFE (direct Claude CLI)?

2. **How fragile is the CL↔LFE bridge?** The agent-worker path requires SBCL + Quicklisp + ASDF + 10s timeout. Is this viable for production or should the CL capabilities be reimplemented in LFE/Erlang?

3. **What's the MVP use case?** "Jarvis, do X" - what is X? The platform is general-purpose, but the first use case defines what gets built first. Code assistance? Research? DevOps? The existing provider abstraction suggests code assistance is the natural fit.

4. **Snapshot granularity for Jarvis?** Every message exchange? Every task completion? Every agent spawn? The performance budget (spec says <5% overhead) depends on this.

5. **Where does Cortex fit?** The Cortex MCP server already provides infrastructure observability. A Jarvis that can also see your infrastructure state via Cortex would be immediately differentiated from generic AI assistants.

---

## Follow-up Research: Self-Extension Loop, Competitive Landscape, Bridge Analysis

### The Self-Extension Loop: What's Connected and What's Not

The self-extension system has three independently working subsystems that are **not wired together**:

#### Subsystem A: Extension Compiler (works, isolated)

```
register-extension(agent-id, code)          ; extension-compiler.lisp:474
  → validate-extension-source(code, :strict) ; extension-compiler.lisp:232 (AST walker)
  → (compile nil `(lambda () ,code))         ; extension-compiler.lisp:501 (real CL compile)
  → store in *extension-registry*            ; extension-compiler.lisp:511
  → invoke-extension(ext-id)                 ; extension-compiler.lisp:517 (funcall compiled fn)
```

**Status**: Fully functional. Tests prove it compiles and executes code safely.

#### Subsystem B: Agent-Defined Capabilities (works, isolated)

```
agent-define-capability(agent, name, desc, params, body)  ; agent-capability.lisp:72
  → validate-extension-code(full-lambda)                   ; validates against sandbox
  → (compile nil full-lambda)                              ; compiles with args
  → make-instance 'agent-capability                        ; wraps in capability
  → push to agent's capabilities list                      ; local only

test-agent-capability(cap, test-cases)                     ; agent-capability.lisp:128
  → runs input/output pairs                                ; tracks pass/fail

promote-capability(cap)                                    ; agent-capability.lisp:199
  → checks all tests passed                               ; requires :testing status
  → register-capability(cap)                               ; adds to GLOBAL registry
```

**Status**: Fully functional. Tests prove define → test → promote workflow works.

#### Subsystem C: Tool Mapping for Claude (works, isolated)

```
Claude returns tool_use blocks
  → response-tool-calls(response)             ; claude-bridge.lisp:138
  → execute-tool-call(call, capabilities)     ; tool-mapping.lisp:209
  → tool-name-to-lisp-name("snake_case")     ; → :KEBAB-CASE
  → find capability in registry               ; capability.lisp:56
  → apply-capability-with-input(cap, input)   ; tool-mapping.lisp:239
```

**Status**: Fully functional. Tests prove tool execution works.

#### The Gap: Nothing Connects Them

**No tool exists for Claude to invoke `register-extension` or `agent-define-capability`.** The 13 built-in tools (`builtin-tools.lisp:275`) are: `read-file`, `write-file`, `list-directory`, `file-exists-p`, `delete-file-tool`, `glob-files`, `grep-files`, `web-fetch`, `web-head`, `run-command`, `git-status`, `git-diff`, `git-log`.

None of these let an LLM:
- Write and compile new code
- Define new capabilities
- Test and promote capabilities
- Invoke extensions

The 4 built-in agent capabilities (`builtin-capabilities.lisp:193-218`) are: `introspect`, `spawn`, `communicate`, `receive`. None relate to self-extension.

**The `extension-provides` slot** on the Extension class (extension-compiler.lisp:38-41) is documented as "Capabilities this extension provides" but **is never read by any code**. Extensions cannot auto-register as capabilities.

#### What Would Close the Loop

The gap is surprisingly small. Three new tools would close it:

1. **`define-extension`** tool: Claude writes S-expression code → `register-extension` validates/compiles it
2. **`test-extension`** tool: Claude provides test cases → `test-agent-capability` runs them
3. **`promote-extension`** tool: After tests pass → `promote-capability` registers globally

These could be `defcapability` definitions in `builtin-tools.lisp`, each ~20 lines. The hard infrastructure (sandbox, compiler, test runner, promotion) already exists.

#### The Multi-Turn Tool Use Loop Is Also Missing

For the direct Claude API path, there is no agentic loop:
- `claude-complete` makes a single HTTP call (claude-bridge.lisp:97)
- `response-tool-calls` extracts tool_use blocks (claude-bridge.lisp:138)
- `execute-tool-call` invokes capabilities (tool-mapping.lisp:209)
- `format-tool-results` formats for next call (tool-mapping.lisp:263)

But **no loop ties these together**. There's no code that:
1. Calls Claude
2. Checks if stop_reason is "tool_use"
3. Executes tools
4. Sends results back
5. Repeats until "end_turn"

The provider-backed agent path sidesteps this by delegating the entire loop to `claude --max-turns N`, which handles its own tool execution internally.

#### The Learning System Doesn't Generate Code

The learning system (learning.lisp, 1,032 lines) generates **heuristics** (decision weight adjustments), not **extensions** (compiled code). Heuristics affect which alternative an agent chooses; they don't add new capabilities. The ideal future: patterns extracted by the learning system trigger extension proposals, which agents write and the compiler validates. This doesn't exist today.

---

### Competitive Landscape: NanoClaw, OpenClaw, and Others

#### NanoClaw
- **Architecture**: 500 lines of TypeScript. Single-process orchestrator with WhatsApp → SQLite → Claude Agent SDK pipeline
- **State**: SQLite + per-group CLAUDE.md files. No snapshot DAG, no branching
- **Self-modification**: "Skills as Transformations" - Claude modifies source files directly when you run `/add-telegram`. No sandbox, no validation
- **Compute isolation**: Apple Container / Docker per agent execution
- **Philosophy**: Intentionally minimal. "AI-native software" designed to be managed through AI interaction

#### OpenClaw
- **Architecture**: ~400K lines TypeScript. Hub-and-spoke with WebSocket Gateway as control plane
- **State**: Append-only event logs with session branching. Closest to Autopoiesis's snapshot DAG concept, but JSON-based, not S-expression
- **Self-modification**: Plugin/tool registration API. Docker-based per-session sandboxing
- **Multi-agent**: Full routing with isolated sessions per channel/group
- **Deployment**: Local, VPS, Fly.io. 10+ messaging platforms

#### How Autopoiesis Differs

| Aspect | NanoClaw | OpenClaw | Autopoiesis |
|--------|----------|----------|-------------|
| State format | SQLite + Markdown | JSON event logs | S-expressions (homoiconic) |
| Branching | None | Session branching | Full DAG with common ancestor |
| Self-modification | Claude rewrites source files | Plugin registration | Sandboxed Lisp compilation |
| State inspection | Read CLAUDE.md | Read JSON logs | `sexpr-diff` two cognitive states |
| Learning | None | None | N-gram pattern mining + RL |
| Code-as-data | No | No | Yes (homoiconic) |
| Fault tolerance | Container restart | Process restart | OTP supervision tree |
| Size | 500 lines | 400K lines | ~8K lines (CL+LFE) |

**What none of them have**: Content-addressable cognitive state, structural diffing of agent thoughts, compiled self-extension with AST-walking sandbox, or a learning system that extracts patterns from agent behavior.

**What they have that Autopoiesis doesn't**: Users. Working CLI. Messaging platform integration. Production deployments.

#### Other Notable Frameworks
- **LangGraph**: Stateful graph-based workflows. Most control/flexibility. 2.2x faster than CrewAI
- **CrewAI**: Role-based team model. Intuitive for business workflows
- **AutoGen** (Microsoft): Conversational agents with dynamic role-playing
- **MetaGPT**: Meta Agent Search - iteratively programs new agents in code. Closest to self-extension concept
- **PicoClaw**: Go-based, <10MB, boots in 1s. Single binary. Extreme efficiency

---

### CL↔LFE Bridge: What's Actually Connected

The bridge operates via S-expression messaging over Unix pipes. Here's the exact protocol:

#### LFE → CL Messages (via `agent-worker.lfe` port-send)

| Message | CL Handler | CL Functions Called |
|---------|-----------|-------------------|
| `(:init :agent-id ID :name NAME)` | `handle-init` (line 67) | `restore-agent-from-snapshot`, `make-agent`, `start-agent` |
| `(:cognitive-cycle :environment ENV)` | `handle-cognitive-cycle` (line 90) | `cognitive-cycle` (perceive→reason→decide→act→reflect) |
| `(:snapshot)` | `handle-snapshot` (line 106) | `make-snapshot`, `save-snapshot` |
| `(:inject-observation :content TEXT)` | `handle-inject-observation` (line 60) | `make-observation`, `stream-append` |
| `(:shutdown)` | `handle-shutdown` (line 115) | `stop-agent`, `make-snapshot`, `sb-ext:exit` |

#### CL → LFE Responses

| Response | Meaning |
|----------|---------|
| `(:ok :type :init :agent-id ID :restored BOOL)` | Init succeeded |
| `(:ok :type :cycle-complete :result R :thoughts-added N)` | Cognitive cycle done |
| `(:ok :type :snapshot-complete :snapshot-id ID :hash H)` | Snapshot saved |
| `(:error :type TYPE :message MSG)` | Operation failed |
| `(:heartbeat :thoughts N :uptime S)` | Status pulse |
| `(:blocking-request :id ID :prompt P :options O)` | Needs human input (not routed) |

#### What's NOT Accessible from LFE

- Extension compilation (`compile-extension`, `register-extension`)
- Capability management (`register-capability`, `find-capability`)
- Snapshot navigation (`checkout-snapshot`, `find-common-ancestor`, `create-branch`)
- Learning system (`extract-patterns`, `generate-heuristic`, `apply-heuristics`)
- Thought stream queries (can inject observations, but cannot query)
- Snapshot diffing (`sexpr-diff`, `sexpr-patch`)

The bridge exposes 5 of the CL system's dozens of capabilities. Expanding it requires adding message handlers to `scripts/agent-worker.lisp`.

#### Conductor Routing Logic

The conductor dispatches based on two flags:

```
requires-llm = false → fast-path (inline funcall, no subprocess)
requires-llm = true, action-type = claude → spawn claude-worker (Claude CLI)
requires-llm = true, action-type != claude → spawn agent-worker (SBCL subprocess)
```

Currently, the infrastructure watcher uses `action-type: claude`. No existing scheduled actions use `action-type: cl` (the CL agent path), though the code supports it.

---

### Sources

- [NanoClaw Architecture Analysis](https://fumics.in/posts/2026-02-02-nanoclaw-agent-architecture)
- [OpenClaw Architecture Overview](https://ppaolo.substack.com/p/openclaw-system-architecture-overview)
- [OpenClaw Documentation](https://docs.openclaw.ai/)
- [NanoClaw vs OpenClaw Security](https://venturebeat.com/orchestration/nanoclaw-solves-one-of-openclaws-biggest-security-issues-and-its-already)
- [Claude Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Agent Orchestration 2026 Guide](https://iterathon.tech/blog/ai-agent-orchestration-frameworks-2026)
- [PicoClaw](https://picoclaw.net/)
- [MetaGPT - IBM](https://www.ibm.com/think/topics/metagpt)
