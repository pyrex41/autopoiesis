---
date: 2026-02-14
author: Claude Code
status: draft
branch: main
repository: autopoiesis
topic: "Jarvis Implementation Plan: From Almost There to Fucking Awesome"
tags: [plan, jarvis, meta-agent, implementation, architecture]
depends_on:
  - thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md
---

> **Superseded**: Phases 1-4 complete. Remaining work (Phase 5 meta-agent, LFE removal, conversation storage) has been consolidated into the substrate-first architecture plan at `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md`.

# Jarvis Implementation Plan

## Vision

An **operating system for cognition** — a meta-agent with full compute capabilities that can spin up other compute/agents to do whatever is needed. Supports multiple backends (Pi, Codex, Claude Code, direct model inference), allows endless flexibility, composability, time travel, forking, and maintains clear historical records with visualizations.

## Architectural Principle

**CL runs agents. LFE supervises processes.**

Common Lisp is the primary agent runtime — it runs cognitive loops, makes LLM calls, executes tools, self-extends, and manages agentic cycles. All the unique IP (snapshot DAG, extension compiler, learning system, homoiconic state) lives here.

LFE/BEAM is the supervisor and scheduler — it spawns CL agent processes, monitors health, restarts on failure, manages concurrency, routes work, and provides the entry point. This is what BEAM was built for.

The bridge between them must be rich enough for LFE to orchestrate CL's full capabilities, not just 5 of dozens.

---

## Phase 1: CL Agentic Tool Loop

**Goal**: Make CL a real agent runtime that can have multi-turn conversations with LLMs, execute tools, and loop until done.

**Why first**: Nothing else works without this. The self-extension tools need a loop to call them. The provider generalization needs a loop to wrap. The bridge needs something worth bridging to.

### 1.1 Multi-Turn Tool Loop (`agentic-loop`)

**File**: `src/integration/claude-bridge.lisp`

Add the missing agentic loop that ties together the existing pieces:

```lisp
(defun agentic-loop (client messages capabilities &key system max-turns on-thought)
  "Run a multi-turn agentic loop with Claude.

   Calls Claude, checks if stop_reason is tool_use, executes tools,
   sends results back, repeats until end_turn or max-turns reached.

   CLIENT - A claude-client instance
   MESSAGES - Initial message list
   CAPABILITIES - Hash table or list of capabilities for tool execution
   SYSTEM - System prompt
   MAX-TURNS - Maximum iterations (default 25)
   ON-THOUGHT - Optional callback (type content) for observing the loop

   Returns (values final-response all-messages turn-count)."
  ...)
```

This function connects the existing pieces:
- `claude-complete` (claude-bridge.lisp:97) — makes API call
- `response-tool-calls` (claude-bridge.lisp:138) — extracts tool_use blocks
- `response-stop-reason` (claude-bridge.lisp:148) — checks end_turn vs tool_use
- `execute-all-tool-calls` (tool-mapping.lisp:283) — runs tools
- `format-tool-results` (tool-mapping.lisp:263) — formats results for next call
- `capabilities-to-claude-tools` (tool-mapping.lisp:156) — converts caps to JSON Schema

**Implementation**: ~60-80 lines. The hard parts (HTTP client, tool execution, result formatting) all exist. This is glue code.

### 1.2 Agentic Cognitive Loop Specialization

**File**: `src/integration/provider-agent.lisp` (new specialization) or new file `src/integration/agentic-agent.lisp`

A new agent class `agentic-agent` that uses `agentic-loop` directly (not via CLI subprocess):

```lisp
(defclass agentic-agent (autopoiesis.agent:agent)
  ((client :initarg :client :accessor agent-client)
   (system-prompt :initarg :system-prompt :accessor agent-system-prompt)
   (max-turns :initarg :max-turns :accessor agent-max-turns :initform 25)
   (capabilities :initarg :tool-capabilities :accessor agent-tool-capabilities))
  (:documentation "Agent that runs agentic loops via direct API calls."))
```

Specializes the cognitive loop generics:
- `perceive` — builds messages from environment + conversation history
- `reason` — gathers tools, builds system prompt with context
- `decide` — records delegation decision in thought stream
- `act` — calls `agentic-loop`, records each exchange as thoughts
- `reflect` — analyzes success/failure, updates learning system

**Key difference from `provider-backed-agent`**: The provider-backed agent delegates the entire loop to an external CLI tool (Claude Code, Codex). The agentic-agent runs the loop itself in CL, giving us full observability and control over each turn.

### 1.3 Thought Recording for Tool Loops

**File**: `src/integration/claude-bridge.lisp` or new `src/integration/agentic-thoughts.lisp`

The `on-thought` callback from `agentic-loop` should create cognitive primitives:

- Each LLM call → `make-observation` (what the LLM said)
- Each tool execution → `make-action` (what we did)
- Each tool result → `make-observation` (what happened)
- Final response → `make-reflection` (outcome assessment)

This connects the agentic loop to the snapshot/time-travel system — every turn is a thought that can be inspected, diffed, replayed.

### Success Criteria

- [ ] Can create an `agentic-agent` with an API key and capabilities
- [ ] Agent runs multi-turn tool loops against the real Claude API
- [ ] Each turn is recorded as thoughts in the agent's thought stream
- [ ] Agent can be snapshotted mid-conversation and restored
- [ ] `max-turns` limit is respected
- [ ] Error handling for API failures, tool errors, timeouts

### Files Modified

| File | Change |
|------|--------|
| `src/integration/claude-bridge.lisp` | Add `agentic-loop` function (~80 lines) |
| `src/integration/agentic-agent.lisp` | New file: `agentic-agent` class + cognitive loop specializations (~150 lines) |
| `src/integration/package.lisp` | Export new symbols |
| `autopoiesis.asd` | Add new file to system definition |
| Tests | New test file for agentic loop (mock HTTP for unit tests, optional live test) |

### Estimated Size

~250-300 lines of new code. No changes to existing code except exports.

---

## Phase 2: Self-Extension Tools

**Goal**: Wire the extension compiler + capability system as tools the agent can call during its agentic loop. Close the self-modification loop.

**Why second**: The agentic loop from Phase 1 gives us a runtime. Now we give it the ability to modify itself.

### 2.1 Three New Built-in Tools

**File**: `src/integration/builtin-tools.lisp`

Add 3 new `defcapability` definitions that expose the existing infrastructure:

#### `define-capability`

```lisp
(defcapability define-capability (&key name description parameters code test-cases)
  "Define a new capability from S-expression code.

   NAME - Capability name (string, will be interned)
   DESCRIPTION - Human-readable description
   PARAMETERS - Parameter spec as JSON: [{name, type, required, doc}, ...]
   CODE - S-expression code as a string (will be READ and validated)
   TEST-CASES - Optional list of {input: {...}, expected: ...} test cases

   The code is validated by the extension compiler's AST-walking sandbox
   (~170 allowed symbols) and compiled. If test-cases are provided,
   they are run immediately.

   Returns success/failure with details."
  :permissions (:self-extend)
  :body ...)
```

Calls: `validate-extension-source` (extension-compiler.lisp:232), `compile-extension` (extension-compiler.lisp:389), `agent-define-capability` (agent-capability.lisp:72)

#### `test-capability`

```lisp
(defcapability test-capability (&key name test-cases)
  "Run test cases against a defined capability.

   NAME - Capability name
   TEST-CASES - List of {input: {...}, expected: ...} objects

   Returns pass/fail for each test case."
  :permissions (:self-extend)
  :body ...)
```

Calls: `test-agent-capability` (agent-capability.lisp:128)

#### `promote-capability`

```lisp
(defcapability promote-capability (&key name)
  "Promote a tested capability to the global registry.

   NAME - Capability name to promote

   Requires all tests to have passed. Once promoted, the capability
   is available to all agents and persists across sessions.

   Returns success/failure."
  :permissions (:self-extend)
  :body ...)
```

Calls: `promote-capability` (agent-capability.lisp:199)

### 2.2 Wire `extension-provides` Slot

**File**: `src/core/extension-compiler.lisp`

The Extension class has an `extension-provides` slot (line 38-41) that is "Capabilities this extension provides" but is **never read by any code**. Wire it so that when an extension is registered, its provided capabilities are auto-registered.

### 2.3 Introspection Tools

Add tools for the agent to inspect its own state:

#### `list-capabilities`

```lisp
(defcapability list-capabilities (&key filter)
  "List all available capabilities with descriptions.
   FILTER - Optional substring to filter by name."
  :permissions (:introspect)
  :body ...)
```

#### `inspect-thoughts`

```lisp
(defcapability inspect-thoughts (&key agent-id last-n)
  "Inspect recent thoughts from the agent's thought stream.
   Returns the last N thoughts as S-expressions."
  :permissions (:introspect)
  :body ...)
```

### Success Criteria

- [ ] An agentic-agent can call `define-capability` to write new Lisp code
- [ ] The extension compiler validates and rejects unsafe code
- [ ] The agent can run tests on its new capability
- [ ] Promoted capabilities appear in the global registry
- [ ] New capabilities are immediately available as tools in subsequent turns
- [ ] Agent can list its own capabilities and inspect its thought stream

### Files Modified

| File | Change |
|------|--------|
| `src/integration/builtin-tools.lisp` | Add 5 new `defcapability` definitions (~100 lines) |
| `src/core/extension-compiler.lisp` | Wire `extension-provides` slot (~10 lines) |
| Tests | Test self-extension workflow end-to-end |

### Estimated Size

~120-150 lines of new code.

---

## Phase 3: Provider Generalization (Multi-Backend)

**Goal**: Unified interface for direct model inference (Anthropic, OpenAI, local), CLI agents (Claude Code, Codex, Pi), and the new CL agentic loop.

**Why third**: Phases 1-2 gave us a working CL agent. Now we make the backend pluggable so "Jarvis" can use any LLM or agent tool.

### 3.1 Inference Provider (Direct API)

**File**: New `src/integration/provider-inference.lisp`

A provider that makes direct HTTP API calls instead of spawning CLI subprocesses:

```lisp
(defclass inference-provider (provider)
  ((api-client :initarg :api-client :accessor provider-api-client)
   (api-format :initarg :api-format :accessor provider-api-format
               :initform :anthropic
               :documentation "API format: :anthropic, :openai, :ollama"))
  (:documentation "Provider that calls LLM APIs directly."))
```

Specializes:
- `provider-invoke` → runs `agentic-loop` from Phase 1
- `provider-build-command` → N/A (no subprocess)
- `provider-parse-output` → N/A (direct API response)
- `provider-supported-modes` → `(:one-shot :streaming :agentic)`

Supports:
- **Anthropic API** (claude-bridge.lisp already has HTTP client)
- **OpenAI-compatible API** (new HTTP client, similar shape — just different message format)
- **Ollama / local models** (OpenAI-compatible endpoint at localhost)

### 3.2 OpenAI-Compatible Client

**File**: New `src/integration/openai-bridge.lisp`

Minimal HTTP client for OpenAI-format APIs:

```lisp
(defun openai-complete (client messages &key system tools)
  "Send a completion request to an OpenAI-compatible API.")
```

This covers: OpenAI, Groq, Together, Fireworks, Ollama, vLLM, and any other OpenAI-compatible endpoint. Different from Claude API in message format (system is a message, not a parameter) and tool call format.

### 3.3 Provider Configuration from S-expressions

Extend `provider-to-sexpr` / `sexpr-to-provider` so provider configurations can be saved in snapshots and restored. An agent that discovers it needs a different model can reconfigure its own provider.

### 3.4 Pi-Style Minimal Agent

Reference implementation of a Pi-like agent within the provider framework:

```lisp
(defun make-pi-agent (&key model working-directory system-prompt)
  "Create a minimal Pi-style agent: LLM API + tool loop + context management.
   Uses inference-provider with file/shell tools. No learning, no snapshots."
  ...)
```

This demonstrates the framework's flexibility — you can build a Pi-equivalent in ~20 lines by assembling existing components.

### Success Criteria

- [ ] Can create an inference-provider for Anthropic API
- [ ] Can create an inference-provider for OpenAI-compatible APIs
- [ ] Can point inference-provider at local Ollama
- [ ] Provider registry holds both CLI providers (Claude Code) and API providers (direct inference)
- [ ] Agent can switch providers mid-session
- [ ] Provider configuration round-trips through S-expression serialization

### Files Modified

| File | Change |
|------|--------|
| `src/integration/provider-inference.lisp` | New file: inference provider (~150 lines) |
| `src/integration/openai-bridge.lisp` | New file: OpenAI-compatible HTTP client (~120 lines) |
| `src/integration/provider.lisp` | Add `sexpr-to-provider` deserializer (~30 lines) |
| `autopoiesis.asd` | Add new files |
| Tests | Provider switching, API format tests |

### Estimated Size

~300-350 lines of new code.

---

## Phase 4: Rich CL-LFE Bridge

**Goal**: Expand the bridge protocol so LFE can fully orchestrate CL agents — trigger agentic loops, navigate snapshots, query capabilities, stream results.

**Why fourth**: Phases 1-3 built the CL agent runtime. Now we connect it to BEAM supervision so the full system works together.

### 4.1 Expanded Bridge Protocol

**File**: `scripts/agent-worker.lisp` (CL side) + `lfe/apps/autopoiesis/src/agent-worker.lfe` (LFE side)

Current protocol (5 messages):
```
:init, :cognitive-cycle, :snapshot, :inject-observation, :shutdown
```

Expanded protocol (adds ~10 new messages):

```
;; Agentic loop management
(:agentic-prompt :prompt "..." :capabilities (:tool1 :tool2) :max-turns 25)
  → runs agentic-loop, streams thoughts back as they happen
(:agentic-abort)
  → cleanly stops a running agentic loop

;; Self-extension
(:define-capability :name "..." :code "..." :tests ...)
(:test-capability :name "..." :test-cases ...)
(:promote-capability :name "...")
(:list-capabilities)

;; Snapshot navigation
(:checkout :snapshot-id "...")
(:diff :from "..." :to "...")
(:create-branch :name "..." :from "...")
(:list-branches)

;; Learning
(:extract-patterns)
(:get-heuristics)

;; Thought stream
(:query-thoughts :last-n 10 :type :decision)
```

### 4.2 Streaming Results

For long-running agentic loops, the CL agent should stream partial results back to LFE rather than blocking until completion:

```
CL → LFE: (:thought :type :observation :content "Claude said..." :turn 3)
CL → LFE: (:thought :type :action :content "Executing read-file..." :turn 3)
CL → LFE: (:thought :type :observation :content "File contents: ..." :turn 3)
...
CL → LFE: (:complete :result "..." :turns 7 :snapshot-id "abc123")
```

### 4.3 Conductor Integration

**File**: `lfe/apps/autopoiesis/src/conductor.lfe`

Update the conductor to use the new bridge capabilities:

- New action type: `agentic` → spawns agent-worker with `:agentic-prompt` message
- Handle streaming thoughts from agent-worker (`:thought` messages)
- Route self-extension requests through the bridge
- Snapshot management integrated with conductor's task lifecycle

### Success Criteria

- [ ] All CL capabilities are accessible from LFE via the bridge
- [ ] Agentic loops stream thoughts back to LFE in real-time
- [ ] Conductor can dispatch tasks to CL agentic agents
- [ ] Snapshot navigation works through the bridge
- [ ] Capability listing/definition works through the bridge
- [ ] LFE can monitor CL agent health via heartbeats

### Files Modified

| File | Change |
|------|--------|
| `scripts/agent-worker.lisp` | Add ~10 new message handlers (~200 lines) |
| `lfe/apps/autopoiesis/src/agent-worker.lfe` | Add matching LFE-side protocol handlers (~150 lines) |
| `lfe/apps/autopoiesis/src/conductor.lfe` | Add `agentic` action type, streaming handler (~80 lines) |
| Tests | Bridge protocol tests (both sides) |

### Estimated Size

~430-500 lines of new code (split CL + LFE).

---

## Phase 5: Meta-Agent Orchestration

**Goal**: CL agents that can spawn other agents (via LFE supervision), compose results, fork/merge cognitive branches. The "Jarvis" layer.

**Why last**: This is the product layer that makes everything useful. It depends on all previous phases.

### 5.1 Agent Spawning from CL

New built-in tools that let an agent manage other agents:

```lisp
(defcapability spawn-agent (&key name provider-type system-prompt capabilities task)
  "Spawn a new agent to work on TASK.
   The agent runs under LFE supervision (fault-tolerant).
   Returns an agent-id for monitoring."
  ...)

(defcapability query-agent (&key agent-id)
  "Check the status and recent thoughts of a spawned agent."
  ...)

(defcapability await-agent (&key agent-id timeout)
  "Wait for a spawned agent to complete its task."
  ...)
```

These tools communicate through the CL→LFE bridge to request agent spawning via the supervisor tree.

### 5.2 Cognitive Branching

```lisp
(defcapability fork-branch (&key name)
  "Create a cognitive branch from the current state.
   Enables 'what if' exploration without affecting the main line."
  ...)

(defcapability switch-branch (&key name)
  "Switch to a different cognitive branch."
  ...)

(defcapability compare-branches (&key branch-a branch-b)
  "Diff two cognitive branches to see how they diverged."
  ...)
```

### 5.3 Session Management

```lisp
(defcapability save-session (&key name)
  "Save the current session state. Can be resumed later."
  ...)

(defcapability resume-session (&key name)
  "Resume a previously saved session, restoring full cognitive state."
  ...)
```

### 5.4 CLI Entry Point

**File**: `bin/jarvis` (or integrated into LFE boot)

A simple entry point:

```bash
$ jarvis "deploy the new feature to staging"
$ jarvis --resume  # pick up where you left off
$ jarvis --branch experiment "try a different approach to the auth bug"
```

### Success Criteria

- [ ] An agent can spawn sub-agents and wait for results
- [ ] Sub-agents run under LFE supervision (restart on crash)
- [ ] Cognitive branching works: fork, explore, compare, merge
- [ ] Sessions persist across process restarts
- [ ] CLI entry point works for common workflows
- [ ] A meta-agent can compose results from multiple sub-agents

### Files Modified

| File | Change |
|------|--------|
| `src/integration/builtin-tools.lisp` | Add orchestration tools (~150 lines) |
| `src/integration/session.lisp` | New file: session save/restore (~100 lines) |
| `lfe/apps/autopoiesis/src/boot.lfe` | CLI entry point (~50 lines) |
| Tests | Integration tests for multi-agent workflows |

### Estimated Size

~350-400 lines of new code.

---

## Phase Dependencies

```
Phase 1 ─── Phase 2 ─── Phase 3 ─── Phase 4 ─── Phase 5
(loop)      (self-ext)   (backends)   (bridge)    (meta-agent)
```

Phases 1-2 are strictly sequential (self-extension needs the loop).
Phase 3 (backends) could partially overlap with Phase 2.
Phase 4 (bridge) depends on Phases 1-3 being stable.
Phase 5 (meta-agent) depends on everything.

## Total Estimated New Code

| Phase | Lines | Key Deliverable |
|-------|-------|----------------|
| 1 | ~300 | Multi-turn agentic loop in CL |
| 2 | ~150 | Self-extension tools |
| 3 | ~350 | Multi-backend provider |
| 4 | ~500 | Rich CL-LFE bridge |
| 5 | ~400 | Meta-agent orchestration |
| **Total** | **~1,700** | |

Roughly 1,700 lines of new code on top of ~8,000 existing lines. No rewrites — everything builds on what exists.

## What This Doesn't Cover (Yet)

- **Streaming responses** from Claude API (SSE parsing) — important for UX, not blocking
- **Branch merging** beyond fast-forward — complex, defer until branching is used in practice
- **MCP server integration** testing — the client code exists, needs live testing
- **Holodeck/3D visualization** — separate track, not on critical path
- **AR/VR visualization** — future, depends on holodeck + rendering backend
- **Learning system activation** — the 1,032-line system exists but needs real interaction data; will naturally activate once agents are running real tasks
- **Messaging platform integration** (WhatsApp, Slack, etc.) — product decision, not architecture

## Open Decisions

1. **API key management**: Where does the Anthropic API key come from? Environment variable? Config file? Prompt on first use?

2. **Default model**: Claude Sonnet for speed, Opus for quality? Configurable per-agent?

3. **Snapshot frequency**: Every turn? Every task? Configurable?

4. **Security model for self-extension**: The sandbox is strict (~170 allowed symbols). Should there be a "trusted mode" for experienced agents with proven track records? The learning system could inform this.

5. **CLI UX**: Minimal REPL? Rich TUI? Just pipe to/from stdin/stdout?
