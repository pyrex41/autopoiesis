---
date: 2026-02-17T19:17:35Z
researcher: Claude
git_commit: HEAD (main)
branch: main
repository: ap
topic: "What is Autopoiesis, how do you use it, and how does it relate to Claude Code?"
tags: [research, architecture, usage, claude-code, interaction-model, overview]
status: complete
last_updated: 2026-02-17
last_updated_by: Claude
---

# Research: What Is Autopoiesis, How Do You Use It, and How Does It Relate to Claude Code?

**Date**: 2026-02-17T19:17:35Z
**Researcher**: Claude
**Branch**: main
**Repository**: ap

## Research Question

> I want to figure out how to actually use this. I use Claude Code to run just about everything and my idea is that I can use Autopoiesis and the agents that it spins up instead. But how will I interact with them? Ideally, they can run as sort of a back end and spin up Claude Code and interact. I give them directions, I chat with them and it can do everything — whether I'm using Claude Code, whether I want to use some other agent system, whether I want to have remote OpenClaw setups, all kinds of stuff like that. But what is it?

## Summary

**Autopoiesis is a self-configuring agent platform written in Common Lisp.** It is a running SBCL process that manages AI agents, their cognitive state, their conversation history, and their tool use — all represented as S-expressions (Lisp data structures). It can talk to Claude's API directly, spawn Claude Code as a subprocess, connect to OpenAI-compatible APIs, or use any MCP server. It exposes a WebSocket API (port 8080), a REST API (port 8081), and an MCP server endpoint (`/mcp`) that any external system can use to control agents.

**Today, here's how you'd actually use it:**

1. Start the SBCL process with `(ql:quickload :autopoiesis)` then `(start-system)` — this boots the substrate store, conductor tick loop, and HTTP monitoring.
2. Optionally start the API servers: `(start-api-server)` for WebSocket on 8080, `(start-rest-server)` for REST+MCP on 8081.
3. Create agents via the REST API (`POST /api/agents`), WebSocket messages, MCP tool calls, the Go CLI (`apcli create-agent`), or directly in the REPL.
4. Interact with agents: inject context, run cognitive cycles, invoke capabilities, pause/step/resume, respond to blocking requests.
5. All agent state is introspectable: thoughts, decisions, snapshots, branches, diffs — via any of those interfaces.

**The relationship to Claude Code:** Autopoiesis treats Claude Code as one of several "providers" — an external subprocess it can spawn for coding tasks. But it can also call the Claude API directly (bypassing Claude Code entirely) via its built-in `agentic-loop`. The vision is that Autopoiesis is the orchestrator: you talk to it, it decides whether to use Claude Code, OpenAI, Ollama, or its own CL-native capabilities to fulfill your request.

---

## Detailed Findings

### 1. What Autopoiesis Actually Is

Autopoiesis is a **single SBCL (Common Lisp) process** that runs as a server. Inside that process:

- A **substrate** (datom store) holds all mutable state as Entity-Attribute-Value triples. Events, workers, agents, sessions, conversation turns — all are substrate entities.
- A **conductor** runs a 100ms tick loop in a background thread. Each tick fires due timers and drains the event queue.
- **Agents** are CLOS objects with a five-phase cognitive loop: perceive → reason → decide → act → reflect. The base agent does nothing; concrete subclasses (like `agentic-agent`) specialize each phase.
- A **snapshot layer** provides content-addressable storage, branching, time-travel, and diffing of agent cognitive state.
- A **conversation layer** stores turns as substrate entities with content-addressed blob storage.
- Built-in **capabilities** (tools) include: file I/O, shell commands, web fetch, git operations, agent spawning, session management, self-extension (agents writing new capabilities).

Key files:
- Substrate: `platform/src/substrate/` (store, linda coordination, entity types, interning, LMDB)
- Conductor: `platform/src/orchestration/conductor.lisp` (tick loop, timer heap, event queue)
- Claude CLI worker: `platform/src/orchestration/claude-worker.lisp` (spawns `claude` subprocess)
- Agent runtime: `platform/src/agent/agent.lisp`, `cognitive-loop.lisp`, `capability.lisp`
- Agentic loop: `platform/src/integration/claude-bridge.lisp:163` (multi-turn tool use)
- API servers: `platform/src/api/server.lisp` (WebSocket), `rest-server.lisp` (REST+MCP)

### 2. How You Interact with It

There are **six interaction surfaces** today:

#### a) SBCL REPL (Direct Lisp)

The most powerful interface. You're inside the running image:

```lisp
(ql:quickload :autopoiesis)
(autopoiesis.orchestration:start-system)

;; Create an agent
(defvar *agent* (autopoiesis.agent:make-agent :name "my-agent"))

;; Start a CLI session (terminal REPL with agent)
(autopoiesis.interface:cli-interact *agent*)
```

The CLI session gives you commands: `start`, `stop`, `pause`, `step`, `thoughts`, `inject <text>`, `pending`, `respond <id> <value>`, `viz` (launches 2D terminal visualization), `back`, `quit`.

#### b) REST API (Port 8081)

Start with `(autopoiesis.api:start-rest-server)`. Full CRUD on agents, snapshots, branches, blocking requests:

```bash
# List agents
curl http://localhost:8081/api/agents

# Create an agent
curl -X POST http://localhost:8081/api/agents -d '{"name":"coder"}'

# Run one cognitive cycle
curl -X POST http://localhost:8081/api/agents/<id>/cycle -d '{"environment":"Analyze auth.py"}'

# Get thoughts
curl http://localhost:8081/api/agents/<id>/thoughts?limit=10

# Respond to a blocking request
curl -X POST http://localhost:8081/api/pending/<id>/respond -d '{"response":"yes"}'

# SSE event stream
curl -H "Accept: text/event-stream" http://localhost:8081/api/events
```

Auth: API keys stored as SHA-256 hashes. When no keys are configured, read-only access is open by default.

#### c) WebSocket API (Port 8080)

Start with `(autopoiesis.api:start-api-server)`. JSON text frames for control, MessagePack binary frames for push streams:

```json
{"type": "create_agent", "name": "researcher", "capabilities": ["read-file", "web-fetch"]}
{"type": "step_agent", "agentId": "abc123", "environment": "Find all TODO comments"}
{"type": "subscribe", "channel": "events"}
{"type": "inject_thought", "agentId": "abc123", "content": "Focus on security", "thoughtType": "observation"}
```

Supports subscriptions to channels like `"events"`, `"agent:<id>"`, `"thoughts:<id>"`.

#### d) MCP Server Endpoint (`/mcp` on Port 8081)

The REST server exposes an MCP endpoint using Streamable HTTP transport (JSON-RPC 2.0). Any MCP-compatible client (including Claude Code itself) can connect and use 21 tools: `list_agents`, `create_agent`, `cognitive_cycle`, `get_thoughts`, `invoke_capability`, `take_snapshot`, `diff_snapshots`, `respond_to_request`, etc.

This means **Claude Code could use Autopoiesis as an MCP server** — managing agents, running cognitive cycles, and getting results back through the standard MCP protocol.

#### e) Go SDK + CLI (`sdk/go/`)

A Go client library (`apclient`) and CLI tool (`apcli`) that wrap the REST API:

```bash
apcli -url http://localhost:8081 list-agents
apcli create-agent coder
apcli cognitive-cycle <agent-id> "Review the auth module"
apcli get-thoughts <agent-id> 10
```

#### f) Conductor Webhook (`POST /conductor/webhook`)

An HTTP endpoint that accepts JSON events and queues them into the substrate for the next conductor tick to process. Any external system can push events this way.

### 3. How It Relates to Claude Code

Autopoiesis has **three distinct paths** to use LLM intelligence:

#### Path 1: Direct API (the `agentic-loop`)

The `agentic-loop` in `platform/src/integration/claude-bridge.lisp:163` calls the Claude HTTP API directly via `dexador`. It handles multi-turn tool use: sends messages + tool definitions → gets response → if tool_use, executes tools locally → sends results back → loops until done.

This is what `agentic-agent` uses. No Claude Code subprocess involved.

```lisp
;; Create an agent that uses Claude API directly
(autopoiesis.integration:make-agentic-agent
  :name "direct-agent"
  :model "claude-sonnet-4-20250514"
  :capabilities '(read-file write-file run-command))
```

#### Path 2: Claude Code as a CLI Provider

`platform/src/integration/provider-claude-code.lisp` defines Claude Code as a subprocess provider. The conductor can spawn `claude -p <prompt> --output-format json --max-turns N --dangerously-skip-permissions` as a child process, read its JSON output, and integrate results.

```lisp
;; The conductor's timer can schedule Claude Code runs
(schedule-action *conductor* 0
  '(:action-type :claude
    :prompt "Fix the bug in auth.py"
    :max-turns 10))
```

#### Path 3: OpenAI-Compatible APIs (Ollama, etc.)

`platform/src/integration/openai-bridge.lisp` normalizes OpenAI-format responses to Claude format, so the same `agentic-loop` works with any OpenAI-compatible API:

```lisp
;; Use Ollama locally
(autopoiesis.integration:make-ollama-provider :model "llama3" :port 11434)

;; Use OpenAI
(autopoiesis.integration:make-openai-provider :model "gpt-4o")
```

### 4. The "Jarvis" Vision — Where This Is Going

The recent work (documented in `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` and the consolidated plan at `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md`) describes the end-state:

```
User → Chat Interface (CLI / API / MCP)
    ↓
Jarvis Conductor (CL orchestration)
- Maintains session state in substrate
- Routes to specialist agents
- Manages cognitive budget
    ↓
Specialist Agents (dynamic)
- Code Agent (spawns Claude Code)
- Research Agent (web/MCP tools)
- Analysis Agent (CL primitives)
- Extension Agent (self-modifying)
    ↓
Snapshot Layer (automatic time-travel)
    ↓
Learning Layer (n-gram patterns, heuristics)
```

The key insight: **Autopoiesis is the orchestration layer above Claude Code, not a replacement for it.** You'd talk to Autopoiesis, and it decides what tools to use — maybe Claude Code for coding, maybe a direct API call for reasoning, maybe an MCP server for specialized tasks.

### 5. What's Unique (What Claude Code Can't Do Alone)

Things Autopoiesis provides that you don't get from Claude Code by itself:

- **Persistent agent state**: Agents have thought streams, conversation history, and cognitive state stored in the substrate. Sessions survive restarts.
- **Time travel**: Content-addressable snapshot DAG. You can `checkout-snapshot`, `fork-from-snapshot`, `diff-snapshots`, `find-common-ancestor`. Git-like branching of agent cognitive state.
- **Self-extension**: Agents can write new capabilities at runtime via `define-capability-tool`, which passes through a sandboxed extension compiler (~570 LOC AST-walking validator). Capabilities go through a draft → testing → promoted lifecycle.
- **Learning system**: N-gram pattern extraction from experience sequences, heuristic generation, automatic weight adjustment on agent decisions. `platform/src/agent/learning.lisp` (1,032 lines).
- **Multi-provider orchestration**: Same agent can use Claude API, OpenAI, Ollama, Claude Code subprocess, or any MCP server.
- **Human-in-the-loop at any point**: Blocking input system where agents pause and wait for human responses. Breakpoints, watches, confidence-triggered pauses.
- **Conversation branching**: Fork a conversation at any point, explore alternatives, compare results, merge insights.

### 6. Current Gaps — What's Not Wired Up Yet

Based on the codebase:

- **No web UI**: Everything is terminal-based (CLI session, 2D viz) or API-based. No browser frontend exists.
- **The "Jarvis" conversational interface isn't complete**: There's no single "chat with Jarvis and it does everything" entry point yet. The pieces exist (agentic loop, tool execution, blocking input, API servers) but they're not composed into a unified conversational agent that routes to sub-agents.
- **The learning system is implemented but passive**: Pattern extraction and heuristic generation exist in code, but there's no automatic feedback loop from completed tasks into the learning system during normal operation.
- **The 3D holodeck is ECS-only**: The entity-component-system and rendering descriptions are built (442 tests), but there's no actual rendering backend (no GPU, no window).

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    HOW YOU INTERACT                              │
│                                                                 │
│  REPL        REST API     WebSocket    MCP Server   Go CLI      │
│  (direct)    :8081        :8080        /mcp         apcli       │
│  cli-interact /api/*      JSON/MsgPack JSON-RPC     REST wrapper│
└──────┬────────┬────────────┬────────────┬────────────┬──────────┘
       │        │            │            │            │
       ▼        ▼            ▼            ▼            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AGENT LAYER                                   │
│  make-agent, cognitive-cycle, capabilities, thought-stream       │
│  perceive → reason → decide → act → reflect                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Claude API   │ │ Claude Code  │ │ OpenAI/Ollama│
│ (direct      │ │ (subprocess  │ │ (API compat) │
│  agentic-    │ │  provider)   │ │              │
│  loop)       │ │              │ │              │
└──────────────┘ └──────────────┘ └──────────────┘
              │            │            │
              └────────────┼────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SUBSTRATE                                     │
│  Datom store (EAV), transact!, take! (Linda), intern/resolve    │
│  Events, workers, agents, conversations — all as entities       │
└─────────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────┐
│  SNAPSHOT LAYER              │  CONVERSATION LAYER               │
│  Content-addressable DAG     │  Turns as substrate entities      │
│  Branch/fork/merge/diff      │  Content-addressed blob store     │
│  Time travel                 │  O(1) fork (shared history)       │
└──────────────────────────────┴──────────────────────────────────┘
```

## Code References

- System entry: `platform/src/orchestration/endpoints.lisp:45` (`start-system`)
- Conductor tick loop: `platform/src/orchestration/conductor.lisp:234`
- Claude CLI worker: `platform/src/orchestration/claude-worker.lisp:64` (`run-claude-cli`)
- Agentic loop (direct API): `platform/src/integration/claude-bridge.lisp:163`
- Agentic agent class: `platform/src/integration/agentic-agent.lisp:13`
- Claude Code provider: `platform/src/integration/provider-claude-code.lisp:8`
- OpenAI bridge: `platform/src/integration/openai-bridge.lisp:14`
- CLI session: `platform/src/interface/session.lisp:404` (`cli-interact`)
- Blocking input: `platform/src/interface/blocking.lisp:176` (`blocking-human-input`)
- REST API routes: `platform/src/api/routes.lisp:597`
- WebSocket handlers: `platform/src/api/handlers.lisp`
- MCP server: `platform/src/api/mcp-server.lisp`
- Go SDK client: `sdk/go/apclient/client.go`
- Go CLI: `sdk/go/cmd/apcli/main.go`
- Extension compiler sandbox: `platform/src/core/extension-compiler.lisp:232`
- Learning system: `platform/src/agent/learning.lisp`
- Built-in tools (including self-extension): `platform/src/integration/builtin-tools.lisp`
- 2D terminal viz: `platform/src/viz/terminal-ui.lisp:295`

## Architecture Documentation

### Test Coverage
2,775+ assertions across 14 test suites plus 1,193 holodeck assertions. Key suites:
- `substrate-tests` (112 checks)
- `orchestration-tests` (91 checks)
- `integration-tests` (649 checks)
- `e2e-tests` (134 checks covering all 15 user stories)

### Configuration
- Claude model: `AUTOPOIESIS_MODEL` env var or `"claude-sonnet-4-20250514"` default
- API keys: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` env vars
- Ports: 8080 (WebSocket), 8081 (REST+MCP+monitoring)
- Docker deployment documented in `platform/docs/DEPLOYMENT.md`

## Related Research

- `thoughts/shared/research/2026-02-14-jarvis-meta-agent-feasibility.md` — The Jarvis vision and feasibility analysis
- `thoughts/shared/plans/2026-02-16-consolidated-cl-architecture.md` — The current master plan (substrate-first)
- `thoughts/shared/research/2026-02-16-thinking-repo-ideas-evaluation.md` — Evaluation of related ideas

## Open Questions

1. **What would the "talk to Jarvis" entry point look like?** The pieces exist but aren't composed into a single conversational agent that intelligently routes to sub-agents. Is this a new `jarvis-agent` class that specializes the cognitive loop? A special CLI mode? An always-running conductor policy?

2. **How would Claude Code sessions be managed?** The `run-claude-cli` function spawns one-shot Claude Code processes. For an interactive experience, would you want persistent Claude Code sessions that the Autopoiesis agent maintains? Or is the one-shot model sufficient?

3. **What's the primary interaction surface?** The REST API + MCP server are fully featured. But should there be a purpose-built chat TUI? A web UI? Or is the plan to interact via Claude Code itself (with Autopoiesis as an MCP server)?

4. **How does the learning system get feedback?** The pattern extraction and heuristic generation code is thorough (~1000 lines), but there's no automatic pipeline from "task completed" → "record experience" → "extract patterns" → "apply heuristics to future decisions" during normal agent operation.
