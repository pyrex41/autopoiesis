---
date: 2026-02-17T19:45:00Z
researcher: Claude
branch: main
repository: ap
topic: "Interaction Surfaces: Rho, Holodeck, OpenCode, and the Sci-Fi TUI Vision"
tags: [research, rho, holodeck, opencode, tui, interaction, vision, jarvis]
status: complete
last_updated: 2026-02-17
last_updated_by: Claude
---

# Research: Interaction Surfaces — Rho, Holodeck, OpenCode, and the Sci-Fi TUI Vision

## Research Question

How do rho (~/projects/rho), the holodeck (Rust/Bevy), and OpenCode relate to Autopoiesis? Can they serve as interaction layers? What would a purpose-built sci-fi TUI look like — one that feels different from everything else?

## Summary

Three existing projects each cover a piece of the puzzle:

- **Rho** is a Rust coding agent with CLI + native GUI (Iced). It talks to Claude API directly, has 9 built-in tools, hashline editing, session persistence, and a task/subagent system. No MCP support. It's a good reference but architecturally designed as a standalone agent, not a frontend for an external orchestrator.

- **The Holodeck** is a Rust/Bevy 3D frontend that already connects to Autopoiesis over WebSocket. Agents appear as glowing icospheres, thoughts produce particle bursts, the snapshot DAG is rendered as a 3D tree, blocking requests are spinning cubes. It has egui panels (HUD, command bar, agent detail, thought inspector). Phase 1 is complete and functional.

- **OpenCode** (sst/opencode) is a TypeScript/Bun TUI with full MCP support, 75+ providers, MIT license. It uses a client/server architecture (REST+SSE). Its TUI is built on @opentui/solid. Already partially integrated into the ap repo via .opencode/ directory.

None of these alone is the "Jarvis cockpit" you're describing, but together they map the design space.

## Detailed Findings

### Rho (~/projects/rho)

**What it is:** A Rust workspace of 9 crates implementing a coding agent. Two binaries: `rho` (CLI) and `rho-gui` (native Iced desktop app).

**Key architecture:**
- Agent loop in `rho-core`: stream Claude API → extract tool calls → execute → loop
- Provider: Anthropic SSE only (no MCP, no OpenAI)
- Auth: reads Claude Code's OAuth token from macOS Keychain, or env vars
- Tools: read, write, edit (hashline), bash (PTY), grep, find, web_fetch, web_search, task (subagent)
- Hashline system: `LINE:HASH|content` format gives LLM stable edit anchors
- Config: `RHO.md` with YAML frontmatter, also reads `CLAUDE.md`
- Session persistence: SQLite at `~/.rho/sessions.db`
- GUI: Iced 0.14 (Elm architecture), autocomplete on `/` `@` `!`, shell mode, session sidebar

**As an Autopoiesis frontend:** Rho is designed as a self-contained agent — it has its own agent loop, its own tool execution, its own session management. To use it as an Autopoiesis frontend, you'd need to gut its agent loop and replace it with calls to the Autopoiesis API. The GUI framework (Iced) and the tool suite are useful references, but it's probably easier to build a purpose-built TUI than to refactor Rho.

### Holodeck (~/projects/ap/holodeck)

**What it is:** A Rust/Bevy 0.15 3D spatial operating environment, already wired to Autopoiesis.

**Current state (Phase 1 complete):**
- Connects to `ws://localhost:8080/ws` on startup with auto-reconnect
- Agents → icospheres with state-colored emissive materials (blue/green/amber/red)
- Thoughts → 6-particle bursts (observation=blue, decision=gold, action=green, reflection=purple)
- Snapshots → 3D DAG tree at world offset (+25,0,0)
- Blocking requests → spinning orange cubes
- Animations: breathing pulse, glow spikes on thought arrival, selection rings
- Force-directed layout keeps agent nodes separated
- egui panels: HUD, command bar, agent detail, thought inspector, minimap, notifications
- Picking: click to select agent, auto-subscribes to thoughts
- Command bar: `/` to focus, `create agent <name>`, `step`, `snapshot`, or freetext → inject thought
- HDR + bloom post-processing for the Tron aesthetic

**What's missing:**
- No text chat / conversation rendering
- No voice input/output
- No terminal embedding
- Custom shaders (hologram, energy beam) flagged as Phase 2
- GPU particles (`bevy_hanabi`) imported but not wired
- No persistent state (restarts lose selection, layout)

### OpenCode (sst/opencode)

**What it is:** MIT-licensed TypeScript/Bun TUI for AI coding. 106k+ GitHub stars.

**Key architecture:**
- Client/server: Hono HTTP backend + SSE streaming to TUI clients
- TUI built on `@opentui/solid` (SolidJS for terminals)
- Full MCP support (local stdio + remote HTTP/SSE)
- 75+ LLM providers via Vercel AI SDK
- Session persistence (SQLite), undo/redo, auto-compact
- Leader-key keybinds (`ctrl+x` combos), vim philosophy
- Theme system, plan/build modes

**As an Autopoiesis frontend:** OpenCode's architecture is interesting because its client/server split means you could theoretically point its backend at Autopoiesis's API instead of (or in addition to) its own LLM calls. Its MCP support means Autopoiesis could surface as an MCP server that OpenCode connects to. The TUI framework (@opentui/solid) is purpose-built for rich terminal rendering.

**Forking considerations:** MIT license allows full fork/refactor. The TypeScript/Bun stack is different from the Rust ecosystem of rho/holodeck. The TUI framework is custom (not ncurses/crossterm) — it's a SolidJS reactive UI rendered to terminal escape codes.

---

## The Vision: What "Feels Different" Means

Based on the conversation, the goal is something like:

```
┌──────────────────────────────────────────────────────────────────┐
│ AUTOPOIESIS COMMAND                           ▲ 3 agents active │
│ ─────────────────────────────────────────────────────────────────│
│                                                                  │
│ ┌─ Agent: researcher ─── running ─── 47 thoughts ─────────────┐│
│ │ > Analyzing auth.py for SQL injection patterns...            ││
│ │   Found 3 potential injection points in login_handler()      ││
│ │   ◆ Decision: Investigate parameterized query migration      ││
│ │                                                              ││
│ │ [snapshot tree]  main ──○──○──◆──○──● HEAD                  ││
│ │                              └──○──○  experiment/sqli-fix    ││
│ └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│ ┌─ Agent: coder ─── paused ─── awaiting input ────────────────┐│
│ │ ❓ Should I refactor to use prepared statements or an ORM?   ││
│ │    [1] Prepared statements  [2] SQLAlchemy ORM  [3] Both     ││
│ └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│ ┌─ Holodeck ──────────────────────────────────────────────────┐│
│ │  [3D viewport — agents as glowing spheres, thought particles]││
│ └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│ ▶ _                                              [Tab: agents] │
│ ctrl+x: menu  /: command  @: file  !: shell      [?: help]     │
└──────────────────────────────────────────────────────────────────┘
```

What makes it feel sci-fi and different:
1. **Multiple agents visible simultaneously** — not one conversation, a cockpit
2. **Inline 3D viewport** — the holodeck rendered as a panel (or fullscreen toggle)
3. **Snapshot timeline visible** — always see where you are in the branch DAG
4. **Blocking requests surface as interactive prompts** — not just text, structured choices
5. **Voice** — speech-to-text input, text-to-speech output (TTS for agent responses)
6. **Terminal-native but graphically rich** — ANSI art, Unicode box drawing, 256-color, sixel/kitty graphics protocol for inline images
7. **MCP as the integration point** — other tools (Claude Code, OpenCode, anything) plug in as MCP servers/clients

---

## Architecture Options

### Option A: Fork OpenCode + Embed Holodeck

- Fork `sst/opencode`, strip its agent loop, replace with Autopoiesis REST/WS client
- Keep the TUI framework (@opentui/solid) for the text interface
- Embed holodeck as a subprocess, render to a panel via kitty graphics protocol or sixel
- Add voice via a separate module (whisper for STT, TTS engine)
- TypeScript/Bun for TUI + Rust for 3D = two processes

**Pro:** Rich existing TUI, MCP support comes free, massive community
**Con:** Two language ecosystems, custom TUI framework is poorly documented

### Option B: Purpose-Built Rust TUI (ratatui)

- Build from scratch using `ratatui` (Rust TUI framework, very active ecosystem)
- Directly embed Bevy holodeck rendering via shared GPU context or offscreen + sixel
- Use rho's tool implementations as a library (hashline, grep, etc.)
- WebSocket client to Autopoiesis backend (like holodeck already does)
- Single Rust binary, single process

**Pro:** One language, one binary, tight integration with holodeck
**Con:** More from-scratch work, no existing MCP client in Rust TUI

### Option C: OpenCode as MCP Client + Autopoiesis as MCP Server (No Fork)

- Use OpenCode as-is, configure Autopoiesis's `/mcp` endpoint as an MCP server
- OpenCode's LLM calls go to Claude, but tools route through Autopoiesis
- Holodeck runs as a separate window
- Voice added as a separate layer (e.g., whisper daemon + TTS)

**Pro:** Zero custom TUI work, leverage existing tools, incrementally adoptable
**Con:** Doesn't "feel different" — it's just OpenCode with extra MCP tools. No multi-agent cockpit, no inline 3D, no unified experience.

### Option D: Hybrid — Ratatui Shell + OpenCode Protocol + Bevy 3D

- Ratatui TUI as the outer shell (Rust, single binary with holodeck)
- Implement OpenCode's REST+SSE protocol for compatibility
- Autopoiesis WS connection for agent state
- Bevy holodeck as an embedded panel (offscreen render → terminal graphics)
- Voice module (whisper + TTS)
- MCP client support for plugging in external tools

**Pro:** Maximum "feels different", single cohesive experience
**Con:** Most engineering work

---

## Code References

- Rho entry point: `~/projects/rho/src/main.rs:253`
- Rho agent loop: `~/projects/rho/crates/rho-core/src/agent_loop.rs:26`
- Rho GUI: `~/projects/rho/crates/rho-gui/src/app.rs`
- Holodeck entry: `~/projects/ap/holodeck/src/main.rs`
- Holodeck WS client: `~/projects/ap/holodeck/src/protocol/client.rs:36`
- Holodeck command bar: `~/projects/ap/holodeck/src/ui/command_bar.rs`
- Holodeck agent rendering: `~/projects/ap/holodeck/src/systems/agents.rs`
- Autopoiesis WS API: `platform/src/api/server.lisp:215`
- Autopoiesis REST API: `platform/src/api/rest-server.lisp:36`
- Autopoiesis MCP server: `platform/src/api/mcp-server.lisp`
- OpenCode local config: `.opencode/package.json`

## Open Questions

1. Which terminal graphics protocol to target — sixel (broad support), kitty (best quality), or iTerm2 inline images?
2. How to embed Bevy rendering in a terminal panel — offscreen render to texture then encode as graphics protocol frames? Or separate window with synchronized state?
3. Voice: local whisper.cpp for STT vs cloud API? Which TTS engine gives the "Jarvis" feel?
4. Should the TUI implement the OpenCode protocol for backwards compatibility, or is a clean break acceptable?
