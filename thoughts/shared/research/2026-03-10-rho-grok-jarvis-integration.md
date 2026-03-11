---
date: "2026-03-10T23:28:23Z"
researcher: reuben
git_commit: f36eef05aef4a233452ef5c3b6df9bcd971faf0e
branch: main
repository: autopoiesis
topic: "Integrating rho with Grok 4.2 as Jarvis top-level agent"
tags: [research, codebase, rho, grok, jarvis, provider, integration, nexus, holodeck]
status: complete
last_updated: "2026-03-10"
last_updated_by: reuben
---

# Research: Integrating rho + Grok 4.2 as the Top-Level Interactive Agent

**Date**: 2026-03-10T23:28:23Z
**Researcher**: reuben
**Git Commit**: f36eef0
**Branch**: main
**Repository**: autopoiesis

## Research Question

How to wire ~/projects/rho (a Rust AI coding agent) running Grok 4.2 as the Jarvis-style top-level interactive agent for autopoiesis, and eventually surface it in Nexus TUI and Holodeck UIs.

## Summary

rho is a Rust agentic loop with built-in Grok support (via OpenAI-compatible API at `api.x.ai/v1`). Autopoiesis has a `define-cli-provider` macro that wraps CLI tools as subprocess providers. The integration path is: define a `rho-provider` using that macro (like the existing `claude-code-provider`), wire it into Jarvis, and extend the Nexus WebSocket protocol to support conversational chat. The key pieces all exist — they just need to be connected.

## Detailed Findings

### 1. rho — What It Is and How It Works

**Location:** `~/projects/rho/`

rho is a Rust workspace producing a `rho-cli` binary. It runs an autonomous agentic loop: send prompt to LLM, dispatch tool calls, feed results back, repeat until done.

**Provider architecture:** rho uses `ProviderType::OpenAi` for Grok/xAI, pointing at `https://api.x.ai/v1` with `XAI_API_KEY`. Built-in model configs include `grok-4.20-reasoning`, `grok-4.20-non-reasoning`, `grok-4.20-multi-agent`. No separate Grok provider — it's OpenAI-compatible.

**Invocation patterns:**
```bash
# One-shot
rho-cli --model grok-4.20-reasoning "do something"

# Stream JSON (machine-readable output)
rho-cli --model grok-4.20-reasoning --output-format stream-json "do something"

# Resume session
rho-cli --resume <session-id> "follow up"
```

**stream-json output format** (newline-delimited JSON on stdout):
```json
{"type":"session","session_id":"..."}
{"type":"text_delta","text":"..."}
{"type":"tool_start","tool_name":"...","tool_id":"...","input_summary":"..."}
{"type":"tool_result","tool_name":"...","tool_id":"...","success":true}
{"type":"complete","success":true,"session_id":"..."}
```

**Key files:**
- `crates/rho-core/src/agent_loop.rs` — main loop entry point
- `crates/rho-core/src/types.rs` — Message, Content, AgentEvent types
- `crates/rho-provider/src/openai.rs` — OpenAI-compat provider (used by Grok)
- `crates/rho-core/src/models.rs` — ModelRegistry with Grok configs
- `src/main.rs` — CLI wiring, stream-json renderer

### 2. Autopoiesis Provider Architecture

**Location:** `platform/src/integration/`

The provider system has two pathways:

**CLI subprocess pathway** (for Jarvis):
- `provider` base class (`provider.lisp:13`) with generic functions: `provider-invoke`, `provider-build-command`, `provider-parse-output`, `provider-start-session`, `provider-send`, `provider-stop-session`
- `define-cli-provider` macro (`provider-macro.lisp:103`) generates a provider class from declarative specs
- `claude-code-provider` (`provider-claude-code.lisp`) — wraps `claude` CLI, one-shot JSON output
- `pi-provider` (`provider-pi.lisp`) — wraps `pi` CLI in RPC streaming mode (stdin/stdout JSON lines)

**Direct API pathway** (for agentic-agent):
- `llm-client.lisp` — `llm-complete` generic, `claude-client`, `openai-client`
- `claude-bridge.lisp` — `agentic-loop` function (multi-turn tool dispatch)
- `provider-inference.lisp` — `inference-provider` wraps `agentic-loop` as a provider
- `agentic-agent.lisp` — `agentic-agent` wires inference-provider into the cognitive cycle

**The existing pattern for adding a new CLI provider** is `define-cli-provider` with `:command`, `:modes`, `:build-command`, `:parse-output` clauses. The Pi provider adds manual `defmethod` overrides for RPC/streaming session mode.

### 3. Jarvis Loop — How It Connects to Providers

**Location:** `platform/src/jarvis/`

Jarvis uses the Pi provider in RPC mode (stdin/stdout JSON lines). The cycle:

1. `start-jarvis` → spawns `pi --mode rpc` subprocess
2. `jarvis-prompt` → sends JSON `{"type":"prompt","message":"..."}` to stdin
3. Reads one JSON line from stdout
4. `parse-tool-call` — looks for `:tool--use` key in response
5. If tool call found → `dispatch-tool-call` → `find-capability` → `invoke-tool`
6. Sends tool result back to provider, reads follow-up
7. Returns text response

**Key observation:** Jarvis is loosely coupled to Pi. It uses `find-symbol` at runtime to locate provider functions, avoiding compile-time dependency. Swapping the provider means implementing the same three methods: `provider-start-session`, `provider-send`, `provider-stop-session`.

### 4. What's Needed to Wire rho as a Provider

Two integration approaches:

**Approach A: rho as CLI subprocess provider (like Pi)**

Define a `rho-provider` that spawns `rho-cli --model grok-4.20-reasoning --output-format stream-json` in a long-lived RPC-like session. This requires:

1. A new `provider-rho.lisp` using `define-cli-provider` macro for one-shot mode
2. Manual `defmethod` overrides for streaming session mode (like Pi does):
   - `provider-start-session` — spawn `rho-cli` with stdin/stdout streaming
   - `provider-send` — write prompt to stdin, read stream-json events until `{"type":"complete"}`
   - `provider-stop-session` — close stdin, terminate process

**Challenge:** rho doesn't have an RPC mode like Pi's `--mode rpc`. Its stream-json output is one-directional (stdout only). For multi-turn, you'd need to either:
- Use `--resume <session-id>` to spawn a new process per turn (simplest, uses rho's SQLite session persistence)
- Add an RPC mode to rho (stdin prompt → stdout stream-json → repeat)

**Approach B: rho as a Rust library (direct integration)**

Since Nexus is already Rust, rho's crates could be used as library dependencies:
- `rho-core` for `agent_loop`, `AgentLoopConfig`, `AgentEvent`
- `rho-provider` for `stream_fn_for_model` (Grok)
- `rho-tools` for the tool implementations

This would bypass the CL Jarvis loop entirely and run the agentic loop in Nexus directly. The CL backend would be the tool target (agents, substrate, snapshots accessible via WebSocket API).

### 5. Nexus/Holodeck WebSocket Protocol — Current Chat Surface

**Location:** `platform/src/api/`, `nexus/crates/nexus-protocol/src/`

The WebSocket protocol has 20+ message types covering agent CRUD, thoughts, snapshots, branches, blocking requests, and events. Key findings for chat integration:

**What exists:**
- `inject_thought` — sends text to an agent's thought stream (observation type)
- `blocking_request` / `respond_blocking` — human-in-the-loop prompts pushed to TUI
- Nexus has a `Chat` widget (`widgets/chat.rs`) with `ChatMessage` rendering
- The chat pane's Enter handler pushes messages to local `state.chat_messages` but does **not** send them over WebSocket

**What's missing:**
- No `"chat"` or `"prompt"` message type in the WebSocket protocol
- No way to send a free-form prompt to an agent and get a streaming response back
- No mechanism to surface the Jarvis provider-backed conversation in the TUI
- The Jarvis session is entirely REPL-side; it has no WebSocket surface

**Subscription channels exist for:** `agents`, `events`, `events:<type>`, `agent:<agentId>`, `thoughts:<agentId>`

**Data types:** `AgentData`, `ThoughtData`, `BlockingRequestData`, `EventData` — all serialized as JSON or MessagePack depending on client preference.

### 6. Integration Path: End-to-End Architecture

```
┌─────────────────────────────────────────────┐
│  User types NL prompt in Nexus TUI Chat     │
│  → ClientMessage::ChatPrompt {agentId, text}│
└──────────────┬──────────────────────────────┘
               │ WebSocket
               ▼
┌──────────────────────────────────────────────┐
│  CL API Server (new handler)                 │
│  → Creates/finds Jarvis session for agent    │
│  → jarvis-prompt session text                │
│    → provider-send rho-provider text         │
│      → writes to rho-cli stdin               │
│      → reads stream-json events              │
│      → dispatches tool calls via capabilities│
│    → returns response text                   │
│  → Broadcasts ChatResponse to subscribers    │
└──────────────┬──────────────────────────────┘
               │ WebSocket push
               ▼
┌──────────────────────────────────────────────┐
│  Nexus TUI receives ChatResponse             │
│  → Appends to Chat widget                    │
│  → Updates thought stream                    │
└──────────────────────────────────────────────┘
```

**The pieces needed:**

| Piece | Where | What |
|-------|-------|------|
| `rho-provider` | `platform/src/integration/provider-rho.lisp` | New CLI provider wrapping `rho-cli` with `--output-format stream-json` |
| RPC mode or per-turn spawn | rho modification or CL workaround | Multi-turn conversation via `--resume` or new rho RPC mode |
| Jarvis rho wiring | `platform/src/jarvis/loop.lisp` | Accept rho-provider in `start-jarvis` (currently hardcoded to Pi) |
| WebSocket chat messages | `platform/src/api/handlers.lisp` + `nexus-protocol/src/types.rs` | New `chat_prompt` / `chat_response` / `chat_stream` message types |
| Chat handler | `platform/src/api/handlers.lisp` | New handler that bridges WebSocket → Jarvis session |
| Nexus chat integration | `nexus/crates/nexus-tui/src/app.rs` | Wire Chat widget Enter to send `ChatPrompt`, receive `ChatResponse` |
| Holodeck chat | `holodeck/src/` | Same protocol, rendered in egui panel |

## Code References

- `platform/src/integration/provider.lisp:13-317` — Provider base class and subprocess execution
- `platform/src/integration/provider-macro.lisp:103` — `define-cli-provider` macro
- `platform/src/integration/provider-claude-code.lisp` — Example CLI provider (claude)
- `platform/src/integration/provider-pi.lisp:56-101` — Example RPC session provider (pi)
- `platform/src/integration/provider-inference.lisp` — Direct API provider
- `platform/src/integration/claude-bridge.lisp:163-214` — `agentic-loop`
- `platform/src/integration/agentic-agent.lisp:53-229` — Full agentic agent wiring
- `platform/src/jarvis/loop.lisp:13-171` — Jarvis lifecycle and NL→tool dispatch
- `platform/src/jarvis/dispatch.lisp:48-90` — Tool call dispatch
- `platform/src/api/handlers.lisp` — WebSocket message handlers
- `platform/src/api/wire-format.lisp` — JSON/MessagePack encoding
- `nexus/crates/nexus-protocol/src/types.rs:131-306` — Client/server message types
- `nexus/crates/nexus-protocol/src/ws.rs` — WebSocket client with init sequence
- `nexus/crates/nexus-tui/src/app.rs:513-523` — Chat widget (local-only currently)
- `~/projects/rho/src/main.rs` — rho CLI entry point, stream-json output
- `~/projects/rho/crates/rho-core/src/agent_loop.rs` — rho's agentic loop
- `~/projects/rho/crates/rho-core/src/models.rs:166-203` — Grok model configs
- `~/projects/rho/crates/rho-provider/src/openai.rs` — OpenAI-compat provider (Grok path)

## Architecture Documentation

### Existing Provider Patterns

The system already supports two CLI providers (Claude Code and Pi) and three direct API providers (Anthropic, OpenAI, Ollama). The `define-cli-provider` macro is the established pattern for CLI subprocess integration. The Pi provider's manual RPC overrides show how to add streaming session support on top of the macro.

### Jarvis Provider Coupling

Jarvis uses runtime `find-symbol` to locate provider methods, making it loosely coupled to any specific provider. The conversation history is a simple `(role . content)` cons list. Tool dispatch goes through the standard capability registry.

### Nexus Protocol Extensibility

The WebSocket protocol is message-type extensible — adding new `ClientMessage` / `ServerMessage` variants in `types.rs` and corresponding `define-handler` entries in `handlers.lisp` is the established pattern. The subscription/broadcast infrastructure already supports channel-based push delivery.

## Open Questions

1. **rho multi-turn strategy:** Should rho get an RPC mode (persistent process, stdin→stdout turns), or should each turn spawn a new `rho-cli --resume <session-id>` process? The former is more efficient; the latter works today without rho changes.
2. **Tool overlap:** rho has its own tools (read, write, edit, bash, grep, find). Should the Jarvis-dispatched tools be rho's native tools, autopoiesis capabilities, or both? The rho tools operate on the filesystem directly; autopoiesis capabilities operate on the substrate.
3. **Streaming:** rho's stream-json emits `text_delta` events. Should these stream through the WebSocket to the Nexus Chat widget in real-time, or should the CL server buffer until the turn completes?
4. **Which agentic loop:** Should the CL `agentic-loop` drive the conversation (using Grok via `openai-client` directly), or should rho's Rust loop drive it (with CL capabilities exposed as rho tools or WebSocket API calls)?
