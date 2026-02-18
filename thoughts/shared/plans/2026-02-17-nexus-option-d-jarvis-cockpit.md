# Nexus: The Autopoiesis Cockpit — Option D Implementation Plan

## Overview

Build **Nexus**, a purpose-built Rust TUI that serves as the primary human interface for Autopoiesis. Nexus combines a ratatui terminal shell, embedded Bevy 3D holodeck rendering, voice I/O, and MCP client support into a single binary. The goal: a sci-fi cockpit experience where you see multiple agents simultaneously, interact via keyboard or voice, visualize the snapshot DAG, respond to blocking requests as structured prompts, and plug in external tools (Claude Code, etc.) via MCP.

This is Option D from the interaction surfaces research — the most ambitious path, all-in.

## Current State Analysis

### What Exists Today

**Autopoiesis Backend (Common Lisp):**
- WebSocket API on port 8080: 20+ message types, JSON text + MessagePack binary frames, subscription channels (`agents`, `thoughts:<id>`, `events`, `events:<type>`, `agent:<id>`)
- REST API on port 8081: 25+ routes, Bearer token auth, SSE streaming at `GET /api/events`
- MCP Server at `/mcp` on port 8081: 21 tools, Streamable HTTP transport, session management via `Mcp-Session-Id` header
- Conductor tick loop (100ms), substrate-backed event queue, multi-provider agentic loops
- 2,775+ test assertions across 14 suites

**Holodeck (Rust/Bevy 0.15):**
- 4-plugin architecture: ConnectionPlugin, ScenePlugin, AgentPlugin, UiPlugin
- WebSocket client using tungstenite + crossbeam channels (thread isolation pattern)
- Agent rendering: icospheres with state-colored emissive materials + bloom
- Thought particles: 6 per thought, color-coded by type, 2.5s lifetime with fade
- Snapshot tree: BFS layout at world offset (25,0,0)
- Blocking requests: pulsing orange cubes
- Force-directed layout for agent positioning
- egui panels: HUD, minimap, agent detail, command bar, notifications, thought inspector
- Selection system with Bevy 0.15 picking, subscription auto-follow

**Rho (Rust, ~/projects/rho):**
- 9-crate workspace with reusable components
- `anthropic-auth`: reads Claude Code OAuth from macOS Keychain
- `rho-hashline`: `LINE:HASH|content` stable edit anchors
- `rho-tools`: 9 tools implementing `AgentTool` trait (read, write, edit, bash, grep, find, web_fetch, web_search, task)
- `rho-session`: SQLite session persistence
- Agent loop: stream Claude API → extract tool calls → execute → loop

**OpenCode (TypeScript/Bun, sst/opencode):**
- Reference architecture: Hono HTTP backend + SSE → TUI clients
- @opentui/solid TUI framework (SolidJS reactive rendering to terminal)
- Full MCP client support, 75+ LLM providers
- Leader-key keybinds, vim philosophy, plan/build modes

### What's Missing

- No unified cockpit showing multiple agents simultaneously
- No terminal-based interface that connects to Autopoiesis (only the 3D holodeck window)
- No voice I/O
- No MCP client (Autopoiesis is an MCP *server*, but can't *call* external MCP tools)
- No way to see the holodeck in a terminal panel
- No session/history persistence for the TUI

### Key Discoveries

- WebSocket uses camelCase keys via jzon (`agentId`, `thoughtCount`); REST uses snake_case via cl-json (`agent_id`, `thought_count`) — client must handle both conventions
- WebSocket has NO authentication; REST requires Bearer token or X-Api-Key header
- Binary WS frames are MessagePack (default for push notifications); text frames are JSON
- Holodeck's thread isolation pattern (tungstenite on OS thread, crossbeam channels to Bevy) is the right architecture for a TUI too
- The holodeck's `protocol/types.rs` already defines all message structs — can be extracted as a shared crate
- Bevy supports headless mode (`HeadlessPlugin`) and render-to-texture — key for embedding in terminal
- Kitty graphics protocol supports animation (frame replacement) at ~30fps in modern terminals

## Desired End State

A single `nexus` binary that:

1. **Launches as a full-screen TUI** with multi-pane layout showing:
   - Agent list with state badges and thought counts
   - Selected agent detail with thought stream, capabilities, action buttons
   - Chat/command interface for injecting thoughts, issuing commands
   - Snapshot timeline as a Unicode DAG
   - Blocking request prompts as structured interactive widgets
   - Optional 3D holodeck viewport rendered inline via Kitty/Sixel graphics protocol

2. **Connects to Autopoiesis** via WebSocket (real-time state) and REST (auth, one-shot queries)

3. **Supports MCP client mode** — can connect to external MCP servers (Claude Code, other tools) and route their capabilities through to agents

4. **Has voice I/O** — push-to-talk or voice-activated input via local Moonshine v2 (streaming STT via ONNX Runtime), text-to-speech output via local neural TTS

5. **Feels like a spaceship cockpit** — sci-fi aesthetic with ANSI color, Unicode box drawing, animated status indicators, bloom-like glow effects via terminal colors, sound effects

### Verification

- `cargo build --release` produces a single binary
- Binary connects to a running Autopoiesis backend and renders agent state within 2 seconds
- All 7 phases have individual success criteria below
- Voice module works fully offline (no cloud APIs)
- MCP client can discover and call tools from a connected MCP server

## What We're NOT Doing

- **Web UI** — Nexus is terminal-first; web comes later as a separate project
- **Replacing Autopoiesis backend** — Nexus is a frontend; all orchestration stays in Common Lisp
- **Building a new agent loop** — Nexus delegates to Autopoiesis's conductor for agent execution
- **Supporting Windows** — macOS and Linux only (terminal graphics protocols, voice bindings)
- **Mobile** — Desktop terminal only
- **Replacing the standalone holodeck** — The 3D holodeck remains a separate binary; Nexus embeds a headless version as an optional panel

## Implementation Approach

**Single Rust workspace** with these crates:

```
nexus/
├── Cargo.toml                    # workspace root
├── crates/
│   ├── nexus-protocol/           # shared types, WS/REST/MCP client
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── types.rs          # extracted from holodeck/protocol/types.rs
│   │   │   ├── ws.rs             # async WebSocket client
│   │   │   ├── rest.rs           # REST client with auth
│   │   │   ├── mcp_client.rs     # MCP JSON-RPC client
│   │   │   └── codec.rs          # JSON + MsgPack encode/decode
│   │   └── Cargo.toml
│   ├── nexus-tui/                # ratatui terminal interface
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── app.rs            # main app state + event loop
│   │   │   ├── layout.rs         # pane arrangement + resize
│   │   │   ├── widgets/
│   │   │   │   ├── agent_list.rs
│   │   │   │   ├── agent_detail.rs
│   │   │   │   ├── thought_stream.rs
│   │   │   │   ├── command_bar.rs
│   │   │   │   ├── snapshot_dag.rs
│   │   │   │   ├── blocking_prompt.rs
│   │   │   │   ├── chat.rs
│   │   │   │   ├── holodeck_viewport.rs
│   │   │   │   └── status_bar.rs
│   │   │   ├── keybinds.rs       # leader-key system
│   │   │   ├── theme.rs          # sci-fi color schemes
│   │   │   └── input.rs          # keyboard + mouse handling
│   │   └── Cargo.toml
│   ├── nexus-holodeck/           # Bevy headless renderer
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── headless.rs       # Bevy app in headless mode
│   │   │   ├── frame_capture.rs  # render to RGBA buffer
│   │   │   └── terminal_encode.rs # Kitty/Sixel encoding
│   │   └── Cargo.toml
│   ├── nexus-voice/              # STT + TTS
│   │   ├── src/
│   │   │   ├── lib.rs
│   │   │   ├── stt.rs            # Moonshine v2 streaming STT (ort/ONNX)
│   │   │   ├── tts.rs            # Piper ONNX TTS
│   │   │   └── vad.rs            # Silero VAD v4 (ort/ONNX)
│   │   └── Cargo.toml
│   └── nexus-mcp/                # MCP client implementation
│       ├── src/
│       │   ├── lib.rs
│       │   ├── transport.rs      # stdio + HTTP transports
│       │   ├── session.rs        # MCP session management
│       │   └── discovery.rs      # server capability discovery
│       └── Cargo.toml
├── src/
│   └── main.rs                   # binary entry point
├── nexus.toml.example            # example config
└── README.md
```

**Key architectural patterns:**
- **Tokio async runtime** for all I/O (WebSocket, REST, MCP, voice)
- **Channel-based communication** between subsystems (like holodeck's crossbeam pattern, but using tokio channels)
- **Reactive state store** — central `AppState` updated by protocol events, TUI re-renders on change
- **Plugin-style modules** — holodeck, voice, MCP are all optional features behind Cargo feature flags

---

## Phase 1: Foundation — Workspace, Protocol Client, Basic TUI

### Overview
Set up the Rust workspace, extract protocol types from the holodeck, build an async WebSocket client, and create the basic ratatui shell with agent list and detail panels.

### Changes Required

#### 1.1 Workspace Setup

**Create**: `nexus/Cargo.toml` (workspace root)
```toml
[workspace]
resolver = "2"
members = ["crates/*"]

[workspace.package]
version = "0.1.0"
edition = "2021"
license = "MIT"
rust-version = "1.75"

[workspace.dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
rmp-serde = "1"
uuid = { version = "1", features = ["v4", "serde"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
anyhow = "1"
thiserror = "2"
```

**Create**: `nexus/crates/nexus-protocol/Cargo.toml`
```toml
[package]
name = "nexus-protocol"
version.workspace = true
edition.workspace = true

[dependencies]
tokio.workspace = true
tokio-tungstenite = { version = "0.24", features = ["native-tls"] }
futures-util = "0.3"
reqwest = { version = "0.12", features = ["json", "native-tls"] }
serde.workspace = true
serde_json.workspace = true
rmp-serde.workspace = true
uuid.workspace = true
tracing.workspace = true
anyhow.workspace = true
thiserror.workspace = true
```

**Create**: `nexus/crates/nexus-tui/Cargo.toml`
```toml
[package]
name = "nexus-tui"
version.workspace = true
edition.workspace = true

[dependencies]
nexus-protocol = { path = "../nexus-protocol" }
ratatui = { version = "0.29", features = ["crossterm", "unstable-widget-ref"] }
crossterm = { version = "0.28", features = ["event-stream"] }
tokio.workspace = true
serde.workspace = true
serde_json.workspace = true
uuid.workspace = true
tracing.workspace = true
anyhow.workspace = true
```

#### 1.2 Protocol Types (extract from holodeck)

**Create**: `nexus/crates/nexus-protocol/src/types.rs`

Extract from `holodeck/src/protocol/types.rs` with these modifications:
- Remove Bevy-specific derives (`Event`, `Component`)
- Add `Clone`, `Debug`, `Serialize`, `Deserialize` on all types
- Support both camelCase (WebSocket) and snake_case (REST) via serde aliases:

```rust
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentState {
    Initialized,
    Running,
    Paused,
    Stopped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThoughtType {
    Observation,
    Decision,
    Action,
    Reflection,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentData {
    pub id: Uuid,
    pub name: String,
    pub state: AgentState,
    pub capabilities: Vec<String>,
    pub parent: Option<Uuid>,
    pub children: Vec<Uuid>,
    #[serde(alias = "thought_count")]   // REST uses snake_case
    #[serde(rename = "thoughtCount")]    // WS uses camelCase
    pub thought_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThoughtData {
    pub id: Uuid,
    pub timestamp: f64,
    #[serde(alias = "type")]
    pub thought_type: ThoughtType,
    pub confidence: f64,
    pub content: String,
    pub provenance: Option<String>,
    pub source: Option<String>,
    pub rationale: Option<String>,
    pub alternatives: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotData {
    pub id: String,
    pub parent: Option<String>,
    pub hash: Option<String>,
    pub metadata: Option<String>,
    pub timestamp: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchData {
    pub name: String,
    pub head: Option<String>,
    pub created: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlockingRequestData {
    pub id: String,
    pub prompt: String,
    pub context: Option<serde_json::Value>,
    pub options: Option<Vec<String>>,
    #[serde(alias = "default")]
    pub default_value: Option<String>,
    pub status: Option<String>,
    #[serde(alias = "created_at")]
    #[serde(rename = "createdAt")]
    pub created_at: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventData {
    pub id: String,
    #[serde(alias = "type")]
    pub event_type: String,
    pub source: Option<String>,
    #[serde(alias = "agent_id")]
    #[serde(rename = "agentId")]
    pub agent_id: Option<String>,
    pub timestamp: f64,
    pub data: serde_json::Value,
}

// Client → Server messages
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Ping,
    SystemInfo,
    SetStreamFormat { format: String },
    Subscribe { channel: String },
    Unsubscribe { channel: String },
    ListAgents,
    GetAgent { #[serde(rename = "agentId")] agent_id: Uuid },
    CreateAgent { name: String, capabilities: Vec<String> },
    AgentAction { #[serde(rename = "agentId")] agent_id: Uuid, action: String },
    StepAgent { #[serde(rename = "agentId")] agent_id: Uuid, environment: Option<serde_json::Value> },
    GetThoughts { #[serde(rename = "agentId")] agent_id: Uuid, limit: Option<u32> },
    InjectThought {
        #[serde(rename = "agentId")] agent_id: Uuid,
        content: String,
        #[serde(rename = "thoughtType")] thought_type: String,
    },
    ListSnapshots { limit: Option<u32> },
    GetSnapshot { #[serde(rename = "snapshotId")] snapshot_id: String },
    CreateSnapshot { #[serde(rename = "agentId")] agent_id: Uuid, label: Option<String> },
    ListBranches,
    CreateBranch { name: String, #[serde(rename = "fromSnapshot")] from_snapshot: Option<String> },
    SwitchBranch { name: String },
    ListBlockingRequests,
    RespondBlocking {
        #[serde(rename = "blockingRequestId")] blocking_request_id: String,
        response: serde_json::Value,
    },
    GetEvents { limit: Option<u32>, #[serde(rename = "eventType")] event_type: Option<String>, #[serde(rename = "agentId")] agent_id: Option<String> },
}

// Server → Client messages (tagged union)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerMessage {
    Connected { #[serde(rename = "connectionId")] connection_id: String, version: String },
    Pong,
    Subscribed { channel: String },
    Unsubscribed { channel: String },
    StreamFormatSet { format: String },
    SystemInfo(SystemInfoData),
    Agents { agents: Vec<AgentData> },
    Agent { agent: AgentData },
    AgentCreated { agent: AgentData },
    AgentStateChanged { #[serde(rename = "agentId")] agent_id: Uuid, state: AgentState },
    StepComplete { #[serde(rename = "agentId")] agent_id: Uuid, result: Option<serde_json::Value> },
    Thoughts { thoughts: Vec<ThoughtData>, total: Option<u32> },
    ThoughtAdded { #[serde(rename = "agentId")] agent_id: Uuid, thought: ThoughtData },
    Snapshots { snapshots: Vec<SnapshotData> },
    Snapshot { snapshot: SnapshotData, #[serde(rename = "agentState")] agent_state: Option<String> },
    SnapshotCreated { snapshot: SnapshotData },
    Branches { branches: Vec<BranchData>, current: Option<String> },
    BranchCreated { branch: BranchData },
    BranchSwitched { branch: BranchData },
    BlockingRequests { requests: Vec<BlockingRequestData> },
    BlockingRequest { request: BlockingRequestData },
    BlockingResponded { #[serde(rename = "blockingRequestId")] blocking_request_id: String },
    Events { events: Vec<EventData> },
    Event { event: EventData },
    Error { code: String, message: String, #[serde(rename = "requestId")] request_id: Option<String> },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SystemInfoData {
    pub version: String,
    pub health: String,
    #[serde(alias = "agent_count")]
    #[serde(rename = "agentCount")]
    pub agent_count: u32,
    #[serde(alias = "connection_count")]
    #[serde(rename = "connectionCount")]
    pub connection_count: u32,
}
```

#### 1.3 Async WebSocket Client

**Create**: `nexus/crates/nexus-protocol/src/ws.rs`

Architecture mirrors holodeck's `protocol/client.rs` but uses async tokio:

```rust
// Core design:
// - tokio::spawn a background task for the WS connection
// - tokio::sync::mpsc channels for bidirectional communication
// - Auto-reconnect with exponential backoff (2^min(attempt,5), cap 30s)
// - On connect: send set_stream_format("json"), subscribe("agents"),
//   subscribe("events"), system_info, list_agents
// - Frame dispatch: text → serde_json, binary → rmp_serde
// - requestId tracking: Arc<DashMap<String, oneshot::Sender>> for request/response correlation

pub struct WsClient {
    outbound: mpsc::Sender<ClientMessage>,
    events: broadcast::Receiver<WsEvent>,
}

pub enum WsEvent {
    Connected { connection_id: String, version: String },
    Disconnected(String),
    Reconnecting { attempt: u32 },
    Message(ServerMessage),
}

impl WsClient {
    pub async fn connect(url: &str) -> Result<Self>;
    pub async fn send(&self, msg: ClientMessage) -> Result<()>;
    pub async fn request(&self, msg: ClientMessage) -> Result<ServerMessage>; // with requestId correlation
    pub fn subscribe_events(&self) -> broadcast::Receiver<WsEvent>;
}
```

#### 1.4 REST Client

**Create**: `nexus/crates/nexus-protocol/src/rest.rs`

```rust
// Thin wrapper around reqwest with:
// - Bearer token auth from config
// - Base URL configuration (default http://localhost:8081)
// - Typed methods for each REST route
// - SSE stream support (reqwest-eventsource or manual)

pub struct RestClient {
    client: reqwest::Client,
    base_url: String,
    api_key: Option<String>,
}

impl RestClient {
    pub fn new(base_url: &str, api_key: Option<&str>) -> Self;
    pub async fn list_agents(&self) -> Result<Vec<AgentData>>;
    pub async fn create_agent(&self, name: &str) -> Result<AgentData>;
    pub async fn agent_action(&self, id: &str, action: &str) -> Result<AgentData>;
    pub async fn get_thoughts(&self, agent_id: &str, limit: Option<u32>) -> Result<Vec<ThoughtData>>;
    pub async fn system_info(&self) -> Result<SystemInfo>;
    pub async fn respond_blocking(&self, request_id: &str, response: serde_json::Value) -> Result<()>;
    // ... etc for all REST routes
}
```

#### 1.5 Basic TUI Shell

**Create**: `nexus/crates/nexus-tui/src/app.rs`

```rust
// Main application state and event loop
//
// Architecture:
// 1. tokio runtime drives WS client + REST client
// 2. crossterm event stream provides keyboard/mouse input
// 3. Central AppState struct holds all UI state
// 4. 60fps render loop: poll events → update state → draw frame
//
// Layout (Phase 1):
// ┌──────────────────────────────────────────┐
// │ NEXUS ── connected ── 3 agents  │ v0.1.0 │  ← status bar
// ├──────────────┬───────────────────────────┤
// │ Agents       │ Agent: researcher         │
// │              │ State: running            │
// │ > researcher │ Capabilities: ...         │
// │   coder      │                           │
// │   reviewer   │ Thoughts:                 │
// │              │ [OBS] Analyzing auth.py.. │
// │              │ [DEC] Found 3 injection.. │
// │              │ [ACT] Running grep on..   │
// ├──────────────┴───────────────────────────┤
// │ > _                            [/: cmd]  │  ← command bar
// └──────────────────────────────────────────┘

pub struct App {
    state: AppState,
    ws_client: WsClient,
    rest_client: RestClient,
    should_quit: bool,
}

pub struct AppState {
    agents: Vec<AgentData>,
    selected_agent: Option<usize>,
    thoughts: Vec<ThoughtData>,
    blocking_requests: Vec<BlockingRequestData>,
    connection_status: ConnectionStatus,
    system_info: Option<SystemInfoData>,
    command_input: String,
    command_mode: bool,
    // ... more state as needed
}
```

#### 1.6 Core Widgets

**Create**: `nexus/crates/nexus-tui/src/widgets/agent_list.rs`
- Stateful list widget showing agent name + state badge
- Color-coded: blue=initialized, green=running, amber=paused, red=stopped
- Arrow key navigation, Enter to select

**Create**: `nexus/crates/nexus-tui/src/widgets/agent_detail.rs`
- Right panel showing selected agent's full info
- Name, state, capabilities, thought count
- Action buttons rendered as `[S]tart [P]ause [R]esume [X]Stop`

**Create**: `nexus/crates/nexus-tui/src/widgets/thought_stream.rs`
- Scrollable list of thoughts with type badges
- `[OBS]` blue, `[DEC]` gold, `[ACT]` green, `[REF]` purple
- Truncated content with confidence percentage
- Click/Enter to expand full thought

**Create**: `nexus/crates/nexus-tui/src/widgets/command_bar.rs`
- Bottom input bar, activated by `/` key
- History with up/down arrows
- Command parsing: `create agent <name>`, `step`, `snapshot <label>`, freetext → inject thought

**Create**: `nexus/crates/nexus-tui/src/widgets/status_bar.rs`
- Top bar: "NEXUS" title, connection status dot, agent count, system version

#### 1.7 Binary Entry Point

**Create**: `nexus/src/main.rs`
```rust
// Parse CLI args (--ws-url, --rest-url, --api-key, --config)
// Initialize tracing
// Connect WS + REST clients
// Enter TUI event loop
// Clean shutdown on Ctrl+C
```

### Success Criteria

#### Automated Verification:
- [ ] `cargo build --release` in `nexus/` succeeds with no warnings
- [ ] `cargo test` in `nexus/` passes (unit tests for protocol types, codec, state management)
- [ ] `cargo clippy` passes with no warnings
- [ ] Binary runs and displays TUI with placeholder data when no backend is available (graceful disconnect)

#### Manual Verification:
- [ ] With Autopoiesis running, `nexus` connects and shows agent list within 2 seconds
- [ ] Selecting an agent shows its details and thought stream
- [ ] Creating an agent via command bar (`create agent test`) works
- [ ] Agent actions (start/pause/stop) via keybinds work
- [ ] Injecting a thought via command bar works
- [ ] Auto-reconnect works when backend is restarted
- [ ] Terminal resizing works without crashes

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding.

---

## Phase 2: Multi-Agent Cockpit

### Overview
Transform the basic TUI into a multi-pane cockpit where multiple agents are visible simultaneously, with real-time thought streaming, blocking request interaction, and rich formatting.

### Changes Required

#### 2.1 Split-Pane Layout System

**Create**: `nexus/crates/nexus-tui/src/layout.rs`

```rust
// Flexible pane layout system supporting:
// - Horizontal and vertical splits
// - Resizable borders (drag with mouse)
// - Tab groups within panes
// - Preset layouts: "cockpit" (default), "focused", "monitor"
//
// Cockpit layout:
// ┌────────────┬──────────────────────┬────────────┐
// │ Agent List │ Primary Agent Panel   │ Secondary  │
// │            │ (thoughts, chat)      │ Agent Panel│
// │            │                       │            │
// │            ├──────────────────────┤│            │
// │            │ Blocking Requests    ││            │
// ├────────────┴──────────────────────┴────────────┤
// │ Command Bar                                     │
// └─────────────────────────────────────────────────┘

pub enum Pane {
    AgentList,
    AgentDetail(Uuid),
    ThoughtStream(Uuid),
    BlockingRequests,
    Chat,
    SnapshotDag,
    HolodeckViewport,
    CommandBar,
    StatusBar,
}

pub struct Layout {
    root: SplitNode,
    focus: PaneId,
}

pub enum SplitNode {
    Leaf(Pane),
    Horizontal { children: Vec<(f32, SplitNode)> }, // (ratio, child)
    Vertical { children: Vec<(f32, SplitNode)> },
}
```

#### 2.2 Multi-Agent Thought Streaming

**Modify**: `nexus/crates/nexus-tui/src/widgets/thought_stream.rs`

- Subscribe to `thoughts:<agent-id>` for multiple agents simultaneously
- Each agent's thought stream is a separate widget instance
- New thoughts appear with a brief highlight animation (bold for 1 second)
- Auto-scroll to bottom, but pause auto-scroll when user scrolls up
- Show thought type with Unicode icons: `◉` observation, `◆` decision, `▶` action, `◈` reflection

#### 2.3 Blocking Request Widget

**Create**: `nexus/crates/nexus-tui/src/widgets/blocking_prompt.rs`

```rust
// Renders blocking requests as interactive prompts:
//
// ┌─ Blocking Request ──────────────────────────────┐
// │ ❓ Should I refactor to use prepared statements? │
// │                                                   │
// │  [1] Prepared statements                          │
// │  [2] SQLAlchemy ORM                               │
// │  [3] Both approaches                              │
// │                                                   │
// │  Or type a custom response: ___________           │
// │                                                   │
// │  [Enter] Submit  [Esc] Skip                       │
// └───────────────────────────────────────────────────┘
//
// When a blocking request arrives:
// 1. Notification sound (if enabled)
// 2. Panel appears with focus
// 3. Numbered options for quick selection
// 4. Free-text input for custom responses
// 5. Sends RespondBlocking via WebSocket
```

#### 2.4 Chat/Conversation Widget

**Create**: `nexus/crates/nexus-tui/src/widgets/chat.rs`

- Full conversation view with user and agent messages
- Markdown-like rendering (bold, code blocks, lists)
- Input area at bottom with multi-line support (Shift+Enter for newline)
- Messages map to inject_thought calls with `thoughtType: "observation"`

#### 2.5 Leader-Key System

**Create**: `nexus/crates/nexus-tui/src/keybinds.rs`

```rust
// Inspired by OpenCode's ctrl+x chord system and vim leader key:
//
// Global:
//   /         → focus command bar
//   Tab       → cycle pane focus
//   Shift+Tab → cycle reverse
//   Ctrl+q    → quit
//   ?         → help overlay
//
// Leader key (Space):
//   Space a   → agent actions submenu
//   Space s   → snapshot actions
//   Space b   → branch actions
//   Space v   → toggle holodeck viewport
//   Space m   → toggle MCP panel
//
// Agent actions (Space a):
//   c → create agent (prompts for name)
//   s → start selected agent
//   p → pause selected agent
//   x → stop selected agent
//   t → step selected agent
//   i → inject thought
//
// In agent list:
//   j/k or ↑/↓ → navigate
//   Enter      → select/focus
//   1-9        → quick select by index
//
// In thought stream:
//   j/k or ↑/↓ → scroll
//   g/G        → top/bottom
//   Enter      → inspect thought detail
//   /          → search thoughts
```

#### 2.6 Notification System

**Modify**: `nexus/crates/nexus-tui/src/app.rs`

- Toast notifications in top-right corner (like holodeck's notification system)
- Color-coded: green=success, yellow=warning, red=error, blue=info
- Auto-dismiss after 5 seconds, click to dismiss
- Notification for: new blocking request, agent state change, connection status change

#### 2.7 Theme System

**Create**: `nexus/crates/nexus-tui/src/theme.rs`

```rust
// Sci-fi color themes using ratatui's Style system
//
// Default "Tron" theme:
//   Background: deep navy (#0a0a1a)
//   Primary text: cyan (#00d4ff)
//   Secondary text: blue-white (#c0d0ff)
//   Accent: gold (#ffd700)
//   Success: green (#00ff88)
//   Warning: amber (#ffaa00)
//   Error: red (#ff3344)
//   Border: dim blue (#1a3050)
//   Selected: bright cyan bg (#003355)
//
// "Holodeck" theme: matches the 3D holodeck's bloom aesthetic
// "Matrix" theme: green-on-black
// "Minimal" theme: black and white, reduced chrome

pub struct Theme {
    pub bg: Color,
    pub fg: Color,
    pub accent: Color,
    pub border: Color,
    pub selected_bg: Color,
    pub agent_initialized: Color,
    pub agent_running: Color,
    pub agent_paused: Color,
    pub agent_stopped: Color,
    pub thought_observation: Color,
    pub thought_decision: Color,
    pub thought_action: Color,
    pub thought_reflection: Color,
    // ... etc
}
```

### Success Criteria

#### Automated Verification:
- [ ] `cargo build --release` succeeds
- [ ] `cargo test` passes (layout tests, keybind tests, theme tests)
- [ ] `cargo clippy` clean

#### Manual Verification:
- [ ] Multiple agents visible simultaneously in cockpit layout
- [ ] Thought streams update in real-time for all visible agents
- [ ] Blocking request appears as interactive prompt, response is sent correctly
- [ ] Leader key sequences work (Space → a → c creates agent)
- [ ] Tab cycles focus between panes
- [ ] Notifications appear and auto-dismiss
- [ ] Theme is visually cohesive and "sci-fi" feeling
- [ ] Resize works, pane proportions are maintained

**Implementation Note**: Pause for manual confirmation before Phase 3.

---

## Phase 3: Holodeck Integration — 3D in Terminal

### Overview
Embed the Bevy holodeck as a headless renderer, capture frames to an RGBA buffer, encode them using Kitty graphics protocol (with Sixel fallback), and display as an inline panel in the TUI.

### Changes Required

#### 3.1 Bevy Headless App

**Create**: `nexus/crates/nexus-holodeck/src/headless.rs`

```rust
// Run Bevy in headless mode with render-to-texture:
//
// 1. Bevy App with MinimalPlugins + RenderPlugin + no window
// 2. Camera renders to a RenderTarget::Image
// 3. Each frame: copy image data to a shared buffer
// 4. Buffer is read by the TUI thread for encoding
//
// Re-use holodeck's existing plugins:
// - ScenePlugin (grid, lights, camera)
// - AgentPlugin (all 3D systems: spawn, animate, particles, etc.)
// - ConnectionPlugin NOT used — Nexus's own WS client feeds data to Bevy via events
//
// New: NexusBridgePlugin
// - Receives WsEvent from nexus-protocol via channel
// - Translates to Bevy events (same types as holodeck's connection_plugin)
// - This means all existing holodeck systems work unchanged

use bevy::prelude::*;
use bevy::render::renderer::RenderDevice;
use bevy::render::texture::GpuImage;

pub struct HeadlessHolodeck {
    // Bevy app runs on its own thread
    frame_rx: watch::Receiver<Vec<u8>>,  // RGBA frame data
    event_tx: mpsc::Sender<WsEvent>,     // feed protocol events to Bevy
    width: u32,
    height: u32,
}

impl HeadlessHolodeck {
    pub fn spawn(width: u32, height: u32) -> Self;
    pub fn latest_frame(&self) -> &[u8];  // zero-copy access to latest RGBA frame
    pub fn resize(&mut self, width: u32, height: u32);
    pub fn send_event(&self, event: WsEvent);
}
```

#### 3.2 Terminal Graphics Encoding

**Create**: `nexus/crates/nexus-holodeck/src/terminal_encode.rs`

```rust
// Encode RGBA frames for display in terminal:
//
// Strategy 1: Kitty Graphics Protocol (preferred)
//   - Supports 24-bit color, alpha, animation
//   - Frame transmission: base64-encoded PNG chunks
//   - Placement: specify rows/columns for the viewport area
//   - Animation: replace existing image ID each frame
//   - ~30fps achievable in kitty/WezTerm/ghostty
//   - Detection: query \x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\ and check response
//
// Strategy 2: Sixel (fallback for xterm, mlterm, etc.)
//   - 256 colors (not 24-bit)
//   - Lower quality but broader compatibility
//   - Can use `sixel-rs` crate
//
// Strategy 3: Half-block characters (universal fallback)
//   - ▀▄█ characters with fg/bg colors → 2 pixels per character cell
//   - Works everywhere but very low resolution
//   - Good enough for a small viewport

pub enum GraphicsProtocol {
    Kitty,
    Sixel,
    HalfBlock,
}

pub fn detect_terminal_graphics() -> GraphicsProtocol;
pub fn encode_frame_kitty(rgba: &[u8], width: u32, height: u32, image_id: u32) -> Vec<u8>;
pub fn encode_frame_sixel(rgba: &[u8], width: u32, height: u32) -> Vec<u8>;
pub fn encode_frame_halfblock(rgba: &[u8], width: u32, height: u32) -> String;
```

#### 3.3 Holodeck Viewport Widget

**Create**: `nexus/crates/nexus-tui/src/widgets/holodeck_viewport.rs`

```rust
// Ratatui widget that displays the holodeck frame:
//
// ┌─ Holodeck ──────────────────────────────┐
// │                                          │
// │   [Kitty graphics / Sixel / halfblock   │
// │    rendered frame of the 3D scene]       │
// │                                          │
// │   Agents as glowing spheres, thought     │
// │   particles, snapshot tree               │
// │                                          │
// └──────────────────────────────────────────┘
//
// Features:
// - Resizes holodeck render resolution to match pane size
// - Toggle fullscreen with Space+v
// - Can also pop out to a separate window (fallback if no graphics protocol)
// - Frame rate limit: render at 15fps in viewport, 30fps fullscreen

impl Widget for HolodeckViewport {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // 1. Get latest frame from HeadlessHolodeck
        // 2. Encode using detected graphics protocol
        // 3. Write encoded data to terminal via raw escape sequences
        //    (bypass ratatui's buffer for the image area)
    }
}
```

#### 3.4 Holodeck Input Forwarding

When the holodeck viewport has focus:
- Mouse clicks → convert terminal coordinates to 3D ray for picking
- Keyboard: arrow keys → orbit camera, +/- → zoom, r → reset view
- All holodeck commands (create agent, step, inject thought) work from the same command bar

#### 3.5 Shared Crate Extraction

To avoid duplicating holodeck code, extract shared systems into a library crate:

**Modify**: `holodeck/Cargo.toml` → split into `holodeck-core` (lib) and `holodeck` (bin)

The `holodeck-core` crate contains:
- All rendering modules (materials, environment, postprocessing)
- All systems (agents, thoughts, snapshots, animation, selection, layout, blocking)
- All state (components, resources)
- Protocol types (shared with nexus-protocol)

Both `holodeck` (standalone 3D window) and `nexus-holodeck` (headless embed) depend on `holodeck-core`.

### Success Criteria

#### Automated Verification:
- [ ] `cargo build --release --features holodeck` succeeds
- [ ] `cargo test` passes for nexus-holodeck crate
- [ ] Frame capture produces valid RGBA data (unit test with known scene)

#### Manual Verification:
- [ ] Holodeck viewport renders in Kitty/WezTerm/Ghostty using Kitty graphics protocol
- [ ] Agents appear as colored spheres, thought particles burst on new thoughts
- [ ] Camera orbiting works via keyboard in viewport
- [ ] Viewport resizes correctly when pane is resized
- [ ] Fallback to halfblock rendering in terminals without graphics protocol support
- [ ] Frame rate is smooth (15+ fps in viewport)
- [ ] Toggle to fullscreen holodeck and back works

**Implementation Note**: Pause for manual confirmation before Phase 4.

---

## Phase 4: MCP Client — External Tool Integration

### Overview
Implement an MCP client that can connect to external MCP servers (Claude Code, other tools), discover their capabilities, and route tool calls through to Autopoiesis agents or execute locally.

### Changes Required

#### 4.1 MCP Client Transport

**Create**: `nexus/crates/nexus-mcp/src/transport.rs`

```rust
// Two MCP transport modes:
//
// 1. stdio — launch a subprocess, communicate via stdin/stdout JSON-RPC
//    Used for: local MCP servers (Claude Code, file tools, etc.)
//    Spawn: tokio::process::Command with stdin/stdout piped
//
// 2. Streamable HTTP — POST JSON-RPC to URL, GET SSE for notifications
//    Used for: remote MCP servers
//    Already used by Autopoiesis's own MCP server

pub enum McpTransport {
    Stdio {
        child: tokio::process::Child,
        stdin: tokio::process::ChildStdin,
        stdout: BufReader<tokio::process::ChildStdout>,
    },
    Http {
        client: reqwest::Client,
        url: String,
        session_id: Option<String>,
    },
}

impl McpTransport {
    pub async fn send_request(&mut self, method: &str, params: serde_json::Value) -> Result<serde_json::Value>;
    pub async fn send_notification(&mut self, method: &str, params: serde_json::Value) -> Result<()>;
}
```

#### 4.2 MCP Session Management

**Create**: `nexus/crates/nexus-mcp/src/session.rs`

```rust
// MCP session lifecycle:
// 1. Send initialize → get server capabilities
// 2. Send notifications/initialized
// 3. Call tools/list to discover available tools
// 4. Call tools/call to invoke tools
// 5. Handle resources/list, prompts/list if supported

pub struct McpSession {
    transport: McpTransport,
    server_info: ServerInfo,
    capabilities: ServerCapabilities,
    tools: Vec<McpTool>,
    session_id: Option<String>,
}

pub struct McpTool {
    pub name: String,
    pub description: String,
    pub input_schema: serde_json::Value,
}

impl McpSession {
    pub async fn initialize(transport: McpTransport) -> Result<Self>;
    pub async fn list_tools(&mut self) -> Result<Vec<McpTool>>;
    pub async fn call_tool(&mut self, name: &str, args: serde_json::Value) -> Result<ToolResult>;
    pub async fn shutdown(&mut self) -> Result<()>;
}
```

#### 4.3 MCP Server Registry

**Create**: `nexus/crates/nexus-mcp/src/discovery.rs`

```rust
// Configuration for MCP servers (in nexus.toml):
//
// [[mcp.servers]]
// name = "autopoiesis"
// transport = "http"
// url = "http://localhost:8081/mcp"
//
// [[mcp.servers]]
// name = "claude-code"
// transport = "stdio"
// command = "claude"
// args = ["mcp", "serve"]
//
// [[mcp.servers]]
// name = "filesystem"
// transport = "stdio"
// command = "npx"
// args = ["-y", "@modelcontextprotocol/server-filesystem", "/Users/reuben/projects"]

pub struct McpRegistry {
    servers: HashMap<String, McpSession>,
}

impl McpRegistry {
    pub fn from_config(config: &Config) -> Self;
    pub async fn connect_all(&mut self) -> Result<()>;
    pub fn all_tools(&self) -> Vec<(String, McpTool)>; // (server_name, tool)
    pub async fn call_tool(&mut self, server: &str, tool: &str, args: Value) -> Result<ToolResult>;
}
```

#### 4.4 MCP Panel in TUI

**Create**: `nexus/crates/nexus-tui/src/widgets/mcp_panel.rs`

```rust
// Panel showing connected MCP servers and their tools:
//
// ┌─ MCP Servers ────────────────────────────┐
// │ ● autopoiesis (21 tools)     connected   │
// │ ● claude-code (15 tools)     connected   │
// │ ○ filesystem (3 tools)       disconnected│
// │                                           │
// │ Tools from autopoiesis:                   │
// │   list_agents, create_agent, get_agent,   │
// │   start_agent, pause_agent, ...           │
// └───────────────────────────────────────────┘
```

#### 4.5 Tool Routing

When an Autopoiesis agent needs to call an external tool:
1. Agent's blocking request includes tool name + arguments
2. Nexus matches the tool name against MCP registry
3. Nexus calls the external MCP server
4. Nexus sends the result back as the blocking request response

This makes Nexus the bridge between Autopoiesis agents and external tool ecosystems.

### Success Criteria

#### Automated Verification:
- [ ] `cargo build --release --features mcp` succeeds
- [ ] `cargo test` passes for nexus-mcp crate (mock stdio transport)
- [ ] JSON-RPC 2.0 serialization/deserialization is correct

#### Manual Verification:
- [ ] Nexus connects to Autopoiesis MCP server and lists all 21 tools
- [ ] Nexus can call tools on Autopoiesis via MCP (e.g., `list_agents`)
- [ ] Nexus can connect to a stdio MCP server (e.g., filesystem server)
- [ ] MCP panel shows all connected servers and their tool counts
- [ ] Tool routing works: agent blocking request → MCP call → response back

**Implementation Note**: Pause for manual confirmation before Phase 5.

---

## Phase 5: Voice — STT + TTS

### Overview
Add voice input via Moonshine v2 (streaming ONNX models via `ort` crate) and voice output via Piper TTS, with Silero VAD v4 for voice activity detection and push-to-talk modes. Fully local, no cloud APIs. Architecture modeled after Handy.app (`/Applications/Handy.app`), which uses the same pure-Rust `transcribe_rs` + `ort` stack.

### Why Moonshine v2 over Whisper

| | Moonshine v2 Medium | Whisper Large v3 |
|---|---|---|
| WER (Open ASR) | **6.65%** | 7.44% |
| Latency (M3, 10s clip) | **258ms** | 11,286ms |
| Parameters | 245M | 1,500M |
| Streaming | **Native** (5-session pipeline) | No (requires full audio) |
| Architecture | Ergodic encoder (no positional embeddings, sliding-window attention) | Full-attention transformer |

Moonshine v2's streaming architecture means time-to-first-token does NOT grow with utterance length — critical for real-time TUI input.

### Changes Required

#### 5.1 Speech-to-Text (Moonshine v2 via ONNX Runtime)

**Create**: `nexus/crates/nexus-voice/src/stt.rs`

```rust
// Moonshine v2 streaming STT via ort (ONNX Runtime) crate.
//
// Architecture mirrors Handy.app's transcribe_rs engine:
// - 5 separate ORT sessions for the streaming pipeline:
//   1. frontend.ort  — raw audio → frame features (learned convolutional frontend)
//   2. encoder.ort   — frame features → hidden states
//   3. adapter.ort   — adapts encoder output for decoder
//   4. cross_kv.ort  — computes cross-attention key/value pairs
//   5. decoder_kv.ort — autoregressive decoder with KV caching
// - Binary tokenizer (tokenizer.bin, 32,768 tokens)
// - streaming_config.json defines model dimensions and buffer shapes
//
// Audio capture: cpal at 16kHz, mono, F32
//
// Model variants:
// - moonshine-small-streaming-en (123M params, 148ms on M3)
// - moonshine-medium-streaming-en (245M params, 258ms on M3, best accuracy)
//
// Model sources (in priority order):
// 1. Reuse existing Handy.app models at:
//    ~/Library/Application Support/com.pais.handy/models/moonshine-*-streaming-en/
// 2. Download from CDN: https://blob.handy.computer/<model-id>.tar.gz
// 3. Store at ~/.nexus/models/<model-id>/
//
// Expected files per model:
//   frontend.ort, encoder.ort, adapter.ort, cross_kv.ort, decoder_kv.ort,
//   tokenizer.bin, streaming_config.json

pub struct MoonshineSttEngine {
    frontend: ort::Session,
    encoder: ort::Session,
    adapter: ort::Session,
    cross_kv: ort::Session,
    decoder_kv: ort::Session,
    tokenizer: BinTokenizer,
    config: StreamingConfig,
    audio_stream: Option<cpal::Stream>,
    sample_buffer: Vec<f32>,
    mode: SttMode,
}

pub struct StreamingConfig {
    pub encoder_dim: u32,      // 620 (small) or 768 (medium)
    pub decoder_dim: u32,      // 512 (small) or 640 (medium)
    pub depth: u32,            // 10 (small) or 14 (medium)
    pub nheads: u32,           // 8 (small) or 10 (medium)
    pub head_dim: u32,         // 64
    pub vocab_size: u32,       // 32768
    pub bos_id: u32,           // 1
    pub eos_id: u32,           // 2
    pub frame_len: u32,        // 80
    pub total_lookahead: u32,  // 16
    // Frontend state buffer shapes for streaming
    pub sample_buffer_shape: Vec<usize>,
    pub conv1_buffer_shape: Vec<usize>,
    pub conv2_buffer_shape: Vec<usize>,
}

pub enum SttMode {
    PushToTalk { key: KeyCode },
    VoiceActivated { sensitivity: f32 },
    Disabled,
}

impl MoonshineSttEngine {
    /// Load model from directory containing the 5 .ort files + config + tokenizer.
    /// Looks for existing Handy models first, then ~/.nexus/models/.
    pub async fn new(model_path: &Path, mode: SttMode) -> Result<Self>;

    /// Start recording from microphone. Accumulates samples in buffer.
    pub fn start_recording(&mut self) -> Result<()>;

    /// Stop recording and run the streaming inference pipeline.
    /// Returns transcribed text.
    pub async fn stop_and_transcribe(&mut self) -> Result<String>;

    /// For streaming mode: feed audio chunks incrementally, get partial results.
    pub fn feed_audio_chunk(&mut self, samples: &[f32]) -> Result<Option<String>>;
}

/// Find the best available model directory.
/// Priority: Handy app models > ~/.nexus/models/ > None (needs download)
pub fn find_moonshine_model(model_id: &str) -> Option<PathBuf> {
    // Check Handy.app location first
    let handy_path = dirs::data_dir()? // ~/Library/Application Support/
        .join("com.pais.handy/models")
        .join(model_id);
    if handy_path.join("frontend.ort").exists() {
        return Some(handy_path);
    }
    // Check nexus models directory
    let nexus_path = dirs::home_dir()?
        .join(".nexus/models")
        .join(model_id);
    if nexus_path.join("frontend.ort").exists() {
        return Some(nexus_path);
    }
    None
}
```

#### 5.2 Text-to-Speech (Piper)

**Create**: `nexus/crates/nexus-voice/src/tts.rs`

```rust
// Piper TTS integration:
//
// Piper is a fast, local neural TTS engine using ONNX models.
// Voice models available at: https://github.com/rhasspy/piper/releases
// Recommended voice for "Jarvis" feel: en_US-lessac-medium (natural male voice)
//
// 1. Load ONNX model via ort (ONNX Runtime) crate
// 2. Synthesize text to WAV PCM
// 3. Play via cpal audio output
//
// Model files stored at ~/.nexus/models/piper/

pub struct TtsEngine {
    model: PiperModel,
    audio_output: cpal::Stream,
    speaking: Arc<AtomicBool>,
}

impl TtsEngine {
    pub async fn new(model_path: &str) -> Result<Self>;
    pub async fn speak(&self, text: &str) -> Result<()>;
    pub fn stop(&self);
    pub fn is_speaking(&self) -> bool;
}
```

#### 5.3 Voice Activity Detection (Silero VAD v4)

**Create**: `nexus/crates/nexus-voice/src/vad.rs`

```rust
// Silero VAD v4 (same model Handy.app bundles):
//
// - ONNX model: silero_vad_v4.onnx (~2MB, bundled in binary via include_bytes!)
// - Runs via ort crate (same ONNX Runtime as Moonshine)
// - Input: 512-sample chunks at 16kHz (32ms per chunk)
// - Output: speech probability [0.0, 1.0]
// - Maintains internal LSTM state across chunks
//
// Pipeline:
// 1. Feed 512-sample audio chunks continuously
// 2. If probability > start_threshold for N consecutive chunks → speech started
// 3. If probability < end_threshold for M consecutive chunks → speech ended
// 4. In voice-activated mode: trigger Moonshine transcription on speech end
//
// Source: bundle silero_vad_v4.onnx at build time (same file as
//   /Applications/Handy.app/Contents/Resources/resources/models/silero_vad_v4.onnx)

pub struct SileroVad {
    session: ort::Session,
    state: VadState,       // LSTM hidden states
    start_threshold: f32,  // default 0.5
    end_threshold: f32,    // default 0.35
    min_speech_ms: u32,    // minimum speech duration to trigger, default 250ms
    min_silence_ms: u32,   // silence duration to end speech, default 500ms
}

struct VadState {
    h: ndarray::Array3<f32>,  // LSTM hidden state
    c: ndarray::Array3<f32>,  // LSTM cell state
    speech_frames: u32,
    silence_frames: u32,
    is_speaking: bool,
}

impl SileroVad {
    pub fn new() -> Result<Self>;  // loads bundled model
    pub fn process_chunk(&mut self, samples: &[f32]) -> VadEvent;
    pub fn reset(&mut self);
}

pub enum VadEvent {
    Silence,
    SpeechStarted,
    SpeechContinuing,
    SpeechEnded,
}
```

#### 5.4 Voice Integration in TUI

**Modify**: `nexus/crates/nexus-tui/src/app.rs`

- Voice status indicator in status bar: `🎤` when recording, `🔊` when speaking
- F5 (configurable) for push-to-talk
- Transcribed text appears in command bar, then is sent as inject_thought or command
- TTS reads out: blocking request prompts, agent state changes, important notifications
- `Space v` toggles voice mode on/off

### Success Criteria

#### Automated Verification:
- [ ] `cargo build --release --features voice` succeeds
- [ ] `cargo test` for nexus-voice passes (mock audio, text processing)

#### Manual Verification:
- [ ] Push-to-talk: hold F5, speak, release → text appears in command bar
- [ ] Voice-activated mode (Silero VAD): speak → text appears after brief pause
- [ ] TTS reads blocking request prompts aloud in a natural voice
- [ ] Voice status indicator shows correctly in status bar
- [ ] Voice works without internet (fully local)
- [ ] Latency: Moonshine v2 Medium transcribes 10s audio in < 300ms on Apple Silicon
- [ ] Can reuse existing Handy.app models (no re-download needed)
- [ ] Streaming partial results appear while still speaking (voice-activated mode)

**Implementation Note**: Pause for manual confirmation before Phase 6.

---

## Phase 6: Snapshot & Timeline — Visual DAG

### Overview
Render the snapshot DAG as an interactive Unicode tree in the terminal, with branch visualization, time-travel navigation, and diff viewing.

### Changes Required

#### 6.1 Snapshot DAG Widget

**Create**: `nexus/crates/nexus-tui/src/widgets/snapshot_dag.rs`

```rust
// Unicode DAG rendering of the snapshot tree:
//
// ┌─ Timeline ───────────────────────────────────┐
// │                                               │
// │  main                                         │
// │  ●─── ●─── ●─── ◆─── ●─── ● HEAD            │
// │                  │                             │
// │                  └─── ●─── ●  experiment/fix   │
// │                                               │
// │  Legend: ● snapshot  ◆ branched  ● HEAD        │
// │  Branches: main (active), experiment/fix       │
// └───────────────────────────────────────────────┘
//
// Features:
// - Horizontal timeline with branch forks
// - Color-coded: gold for current branch, dim for others
// - Scroll left/right for long histories
// - Select snapshot with arrow keys → show metadata
// - Enter on snapshot → show diff from parent
// - 'c' on snapshot → checkout (switch branch + restore state)

// DAG layout algorithm:
// 1. Topological sort of snapshot nodes
// 2. Assign each branch a "lane" (vertical row)
// 3. Place nodes left-to-right by timestamp
// 4. Draw connection lines with Unicode box characters
//    ─ │ ┌ └ ├ ┤ ┬ ┴ ┼

pub struct SnapshotDag {
    nodes: Vec<SnapshotNode>,
    branches: Vec<BranchInfo>,
    current_branch: String,
    selected: Option<String>, // snapshot id
    scroll_offset: u16,
}
```

#### 6.2 Diff Viewer Widget

**Create**: `nexus/crates/nexus-tui/src/widgets/diff_viewer.rs`

```rust
// Show S-expression diff between two snapshots:
//
// ┌─ Diff: abc123 → def456 ──────────────────────┐
// │  - (confidence 0.8)                            │
// │  + (confidence 0.95)                           │
// │                                                │
// │  - (capabilities (observe analyze))            │
// │  + (capabilities (observe analyze synthesize)) │
// │                                                │
// │  + (thought "New insight about...")            │
// └────────────────────────────────────────────────┘
//
// Uses REST endpoint: GET /api/snapshots/:id/diff/:other-id
// Parses the S-expression diff string and renders with +/- coloring
```

#### 6.3 Branch Management

- List branches in snapshot panel header
- Create branch: `branch create <name>` in command bar
- Switch branch: `branch checkout <name>` or click in branch list
- Merge visualization (if/when Autopoiesis supports it)

### Success Criteria

#### Automated Verification:
- [ ] `cargo test` passes for DAG layout algorithm (unit tests with known topologies)
- [ ] Unicode rendering produces correct box-drawing for various DAG shapes

#### Manual Verification:
- [ ] Snapshot timeline shows the correct DAG structure
- [ ] Navigating snapshots with arrow keys works
- [ ] Viewing a diff between snapshots shows colored changes
- [ ] Branch creation and switching works from the command bar
- [ ] Long timelines scroll correctly
- [ ] Current branch is highlighted in gold

**Implementation Note**: Pause for manual confirmation before Phase 7.

---

## Phase 7: Polish — Config, Persistence, Animation, Sound

### Overview
Final polish pass: configuration file, session persistence, terminal animations, sound effects, and comprehensive help system.

### Changes Required

#### 7.1 Configuration File

**Create**: `nexus/nexus.toml.example`

```toml
[connection]
ws_url = "ws://localhost:8080/ws"
rest_url = "http://localhost:8081"
api_key = ""  # or use NEXUS_API_KEY env var

[tui]
theme = "tron"           # tron, holodeck, matrix, minimal
layout = "cockpit"       # cockpit, focused, monitor
fps = 60
mouse = true

[holodeck]
enabled = true
render_fps = 15
resolution = "auto"      # auto, 640x480, 1280x720
graphics_protocol = "auto"  # auto, kitty, sixel, halfblock

[voice]
enabled = false
stt_model = "moonshine-medium-streaming-en"  # or moonshine-small-streaming-en
tts_model = "~/.nexus/models/piper/en_US-lessac-medium.onnx"
mode = "push_to_talk"    # push_to_talk, voice_activated, disabled
push_to_talk_key = "F5"
tts_on_blocking = true
tts_on_state_change = false
# Model search order: Handy.app models → ~/.nexus/models/ → download from CDN
# Set explicit path to skip auto-detection:
# stt_model_path = "/path/to/moonshine-medium-streaming-en/"

[mcp]
# Autopoiesis as MCP server
[[mcp.servers]]
name = "autopoiesis"
transport = "http"
url = "http://localhost:8081/mcp"

# External tools
# [[mcp.servers]]
# name = "filesystem"
# transport = "stdio"
# command = "npx"
# args = ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"]

[keybinds]
leader = "Space"
quit = "Ctrl+q"
command = "/"
push_to_talk = "F5"
toggle_holodeck = "Space+v"
toggle_voice = "Space+V"
```

#### 7.2 Session Persistence

- SQLite database at `~/.nexus/sessions.db`
- Store: conversation history, selected agents, pane layout, scroll positions, command history
- Resume previous session on startup (prompt: "Resume last session? [Y/n]")
- Session list: `nexus --sessions` to list, `nexus --session <id>` to resume specific

#### 7.3 Terminal Animations

- Agent state badge: pulsing dot animation (●○●○) for running agents
- New thought: brief flash/highlight effect (bold + bright color for 500ms)
- Connection status: breathing animation on the status dot
- Blocking request arrival: border flash + optional bell character
- Smooth scrolling in thought stream (not jump-to-position)

#### 7.4 Sound Effects (Optional)

- Using `rodio` crate for audio playback
- Subtle sounds for: new blocking request (soft chime), agent start/stop (click), thought arrival (quiet blip)
- Volume control in config
- Disabled by default, enable with `[sound] enabled = true`

#### 7.5 Help System

- `?` key opens help overlay showing all keybinds
- `:help <topic>` in command bar for specific topics
- First-run tutorial mode: highlights key features with tooltips

#### 7.6 Model Download CLI

- `nexus setup` command to download required models:
  - Moonshine v2 streaming model from `https://blob.handy.computer/<model-id>.tar.gz`
    - `moonshine-small-streaming-en` (~120MB, faster, good accuracy)
    - `moonshine-medium-streaming-en` (~240MB, best accuracy)
  - Piper TTS model (en_US-lessac-medium.onnx, ~60MB)
  - Silero VAD v4 is bundled in binary (no download needed)
- Auto-detect existing Handy.app models and skip download if present:
  - `~/Library/Application Support/com.pais.handy/models/moonshine-*-streaming-en/`
- Progress bar during download
- Verify checksums
- `nexus setup --list` shows available models and which are already downloaded

### Success Criteria

#### Automated Verification:
- [ ] `cargo build --release --all-features` succeeds
- [ ] `cargo test --all-features` passes
- [ ] `cargo clippy --all-features` clean
- [ ] Config file parsing handles all fields correctly (unit tests)
- [ ] Session persistence: write and read back state (unit test)

#### Manual Verification:
- [ ] Config file is loaded and applied correctly
- [ ] Session persistence: quit and resume maintains state
- [ ] Animations are smooth and not distracting
- [ ] Help overlay shows all keybinds
- [ ] `nexus setup` downloads models successfully
- [ ] Full end-to-end: start Autopoiesis → start Nexus → create agent → observe thoughts → respond to blocking request → view snapshot timeline → switch to holodeck view → voice input

**Implementation Note**: This is the final phase. Full end-to-end testing.

---

## Testing Strategy

### Unit Tests
- Protocol type serialization/deserialization (both camelCase and snake_case)
- WebSocket client reconnect logic (mock server)
- MCP JSON-RPC protocol compliance
- DAG layout algorithm with known topologies
- Theme color calculations
- Config file parsing
- Keybind sequence matching

### Integration Tests
- WS client ↔ Autopoiesis WebSocket server
- REST client ↔ Autopoiesis REST API
- MCP client ↔ Autopoiesis MCP server
- End-to-end: create agent → step → get thoughts

### Manual Testing
1. Fresh install: clone, build, run — connects to running Autopoiesis
2. Multi-agent workflow: create 3 agents, observe all simultaneously
3. Blocking request: trigger one, respond via TUI, verify agent continues
4. Holodeck: toggle viewport, verify rendering matches standalone holodeck
5. Voice: push-to-talk input, TTS output for blocking requests
6. MCP: connect Claude Code as MCP server, route tools
7. Snapshot: create snapshots, view timeline, switch branches, view diffs
8. Resilience: kill Autopoiesis, verify reconnect; resize terminal; rapid key input

## Performance Considerations

- **TUI rendering**: ratatui's double-buffering with diff-only updates means only changed cells are written. Target 60fps for input responsiveness, actual redraws only when state changes.
- **Holodeck framerate**: Cap at 15fps in viewport mode to avoid overwhelming terminal bandwidth. Kitty protocol chunk size ~64KB per frame at 640x480.
- **WebSocket throughput**: MessagePack binary frames are ~40% smaller than JSON. Keep subscription count minimal (only subscribe to visible agents' thoughts).
- **Voice latency**: Moonshine v2 Medium transcribes 10 seconds of audio in ~258ms on Apple Silicon M3 (vs whisper.cpp base.en at ~1.9s for same). Moonshine v2 Small at ~148ms for lower accuracy. Streaming architecture means partial results arrive while still speaking. Piper TTS synthesizes at ~10x realtime. All three voice models (Moonshine, Silero VAD, Piper) share the same `ort` ONNX Runtime, so the runtime is loaded once.
- **Memory**: Thought streams should cap at ~1000 entries per agent with LRU eviction. Frame buffers are the biggest allocation (~1.2MB for 640x480 RGBA).

## Migration Notes

- Holodeck standalone binary is NOT removed — it continues to work independently
- Holodeck shared code is extracted to `holodeck-core` crate, breaking the existing single-crate structure (requires updating `holodeck/Cargo.toml`)
- No changes to Autopoiesis backend — Nexus is purely a new client
- Config at `~/.nexus/` is new; doesn't conflict with existing `~/.rho/` or `.opencode/`

## Dependencies Summary

| Crate | Version | Purpose |
|-------|---------|---------|
| ratatui | 0.29 | TUI framework |
| crossterm | 0.28 | Terminal I/O |
| tokio | 1.x | Async runtime |
| tokio-tungstenite | 0.24 | Async WebSocket |
| reqwest | 0.12 | HTTP client |
| serde + serde_json | 1.x | Serialization |
| rmp-serde | 1.x | MessagePack |
| uuid | 1.x | Identifiers |
| tracing | 0.1 | Logging |
| anyhow + thiserror | 1.x/2.x | Error handling |
| bevy | 0.15 | 3D rendering (headless) |
| ort | 2.x | ONNX Runtime (Moonshine v2 STT, Piper TTS, Silero VAD) |
| ndarray | 0.16 | Tensor manipulation for ORT inference |
| cpal | 0.15 | Audio I/O |
| rodio | 0.19 | Audio playback |
| rusqlite | 0.32 | Session persistence |
| toml | 0.8 | Config parsing |
| base64 | 0.22 | Kitty graphics encoding |
| image | 0.25 | Image processing |

## References

- Interaction surfaces research: `thoughts/shared/research/2026-02-17-interaction-surfaces-rho-holodeck-opencode.md`
- What is Autopoiesis: `thoughts/shared/research/2026-02-17-what-is-autopoiesis-how-to-use-it.md`
- Autopoiesis WS API: `platform/src/api/server.lisp:215`, `platform/src/api/handlers.lisp`
- Autopoiesis REST API: `platform/src/api/rest-server.lisp:36`, `platform/src/api/routes.lisp`
- Autopoiesis MCP server: `platform/src/api/mcp-server.lisp`
- Holodeck entry: `holodeck/src/main.rs`
- Holodeck WS client: `holodeck/src/protocol/client.rs:36`
- Holodeck agent rendering: `holodeck/src/systems/agents.rs`
- Rho workspace: `~/projects/rho/Cargo.toml`
- Rho auth: `~/projects/rho/crates/anthropic-auth/`
- Rho hashline: `~/projects/rho/crates/rho-hashline/`
- ratatui docs: https://ratatui.rs
- Kitty graphics protocol: https://sw.kovidgoyal.net/kitty/graphics-protocol/
- Moonshine v2: https://github.com/moonshine-ai/moonshine
- Moonshine v2 paper: https://arxiv.org/abs/2602.12241
- Moonshine models (HuggingFace): https://huggingface.co/UsefulSensors/moonshine
- Handy.app (reference implementation): /Applications/Handy.app (pure Rust, transcribe_rs + ort)
- Handy models location: ~/Library/Application Support/com.pais.handy/models/
- Handy model CDN: https://blob.handy.computer/
- transcribe-rs crate: https://github.com/cjpais/transcribe-rs
- ort (ONNX Runtime for Rust): https://github.com/pykeio/ort
- Silero VAD v4: https://github.com/snakers4/silero-vad
- Piper TTS: https://github.com/rhasspy/piper
- MCP spec: https://spec.modelcontextprotocol.io
