# Autopoiesis Holodeck — 3D Spatial Operating System (Bevy/Rust)

This document is a standalone bootstrap prompt for spinning up a separate Bevy (Rust) project that serves as the 3D frontend for the Autopoiesis agent platform. Hand this entire file to an agent in a fresh repo.

---

## What this is

A 3D game-like interface for the Autopoiesis agent platform. Think Jarvis from Iron Man — a spatial environment where you operate an entire system of AI agents through keyboard, mouse, and text commands. It connects to a Common Lisp backend over WebSocket.

This is NOT a dashboard. It is a place you inhabit. Terminals float in 3D space. Agent thought streams visualize as particle flows. Snapshot branches render as a living tree you can walk through. When an agent needs your input, it manifests as an object in your space that demands attention.

The backend is an ECS-based system (cl-fast-ecs). This frontend is also ECS (Bevy). The two think the same way.

## Backend connection

The backend runs at `ws://localhost:8080/ws` and speaks a hybrid protocol:
- **Client sends**: JSON text frames always
- **Server responds**: JSON text frames for direct responses
- **Server pushes**: MessagePack binary frames for real-time data (events, thoughts, state changes)
- Client can send `{"type": "set_stream_format", "format": "json"}` to get everything as JSON (useful for development)

### Message types the backend supports

**Control:**
```
{"type": "ping"}                                          -> {"type": "pong"}
{"type": "system_info"}                                   -> {"type": "system_info", "version": "...", "health": "...", "agentCount": N, "connectionCount": N}
{"type": "subscribe", "channel": "events"}                -> {"type": "subscribed", "channel": "events"}
{"type": "subscribe", "channel": "events:tool-called"}    -> subscribe to specific event type
{"type": "subscribe", "channel": "agent:<id>"}            -> subscribe to specific agent's updates
{"type": "subscribe", "channel": "agents"}                -> subscribe to all agent lifecycle
{"type": "subscribe", "channel": "thoughts:<agent-id>"}   -> subscribe to agent's thought stream
{"type": "unsubscribe", "channel": "..."}                 -> {"type": "unsubscribed"}
{"type": "set_stream_format", "format": "msgpack"|"json"} -> {"type": "stream_format_set"}
```

**Agents:**
```
{"type": "list_agents"}                                   -> {"type": "agents", "agents": [...]}
{"type": "get_agent", "agentId": "..."}                   -> {"type": "agent", "agent": {...}}
{"type": "create_agent", "name": "...", "capabilities": ["..."]} -> {"type": "agent_created", "agent": {...}}
{"type": "agent_action", "agentId": "...", "action": "start"|"stop"|"pause"|"resume"} -> {"type": "agent_state_changed", ...}
{"type": "step_agent", "agentId": "...", "environment": {...}} -> {"type": "step_complete", ...}
```

**Thoughts:**
```
{"type": "get_thoughts", "agentId": "...", "limit": 50}   -> {"type": "thoughts", "thoughts": [...], "total": N}
{"type": "inject_thought", "agentId": "...", "content": "...", "thoughtType": "observation"|"reflection"} -> {"type": "thought_added", ...}
```

**Snapshots:**
```
{"type": "list_snapshots", "limit": 50}                   -> {"type": "snapshots", "snapshots": [...]}
{"type": "get_snapshot", "snapshotId": "..."}              -> {"type": "snapshot", "snapshot": {...}, "agentState": "..."}
{"type": "create_snapshot", "agentId": "...", "label": "..."} -> {"type": "snapshot_created", ...}
```

**Branches:**
```
{"type": "list_branches"}                                  -> {"type": "branches", "branches": [...], "current": "..."}
{"type": "create_branch", "name": "...", "fromSnapshot": "..."} -> {"type": "branch_created", ...}
{"type": "switch_branch", "name": "..."}                   -> {"type": "branch_switched", ...}
```

**Blocking requests (agent asking human for input):**
```
{"type": "list_blocking_requests"}                         -> {"type": "blocking_requests", "requests": [...]}
{"type": "respond_blocking", "requestId": "...", "response": "..."} -> {"type": "blocking_responded", ...}
```

**Events (history query):**
```
{"type": "get_events", "limit": 50, "eventType": "...", "agentId": "..."} -> {"type": "events", "events": [...]}
```

### Push messages (server -> client, arrive as MessagePack binary by default)

```
{"type": "event", "event": {...}}                          // when subscribed to "events"
{"type": "thought_added", "agentId": "...", "thought": {...}} // when subscribed to "thoughts:<id>"
{"type": "agent_state_changed", "agentId": "...", "state": "..."} // when subscribed to "agents"
{"type": "agent_created", "agent": {...}}                  // when subscribed to "agents"
{"type": "blocking_request", "request": {...}}             // always pushed to all clients
```

All messages support `"requestId": "..."` for client-side correlation (echoed back in response).

### Data shapes

**Agent object:**
```json
{"id": "uuid", "name": "string", "state": "initialized|running|paused|stopped", "capabilities": ["string"], "parent": "uuid|null", "children": ["uuid"], "thoughtCount": 0}
```

**Thought object:**
```json
{"id": "uuid", "timestamp": 1234567890.123, "type": "observation|decision|action|reflection", "confidence": 0.95, "content": "s-expression string", "provenance": "...", "source": "...", "rationale": "...", "alternatives": [...]}
```

## Tech stack

```toml
[dependencies]
bevy = { version = "0.15", features = ["wayland"] }
bevy_egui = "0.35"                    # Immediate-mode UI for HUD/panels
bevy_hanabi = "0.15"                  # GPU particle systems
bevy_mod_picking = "0.22"             # Ray casting, click/hover on 3D entities
bevy_tweening = "0.12"               # Animation/easing for smooth transitions
bevy_panorbit_camera = "0.22"        # Orbit camera controls

# Networking
tungstenite = "0.24"                  # WebSocket client
rmp-serde = "1"                       # MessagePack <-> serde
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Async runtime for WebSocket on background thread
crossbeam-channel = "0.5"            # Lock-free channels between WS thread and Bevy
uuid = { version = "1", features = ["v4", "serde"] }
```

## Architecture

```
src/
  main.rs                 # App entry, plugin registration, window config

  protocol/
    mod.rs
    client.rs             # WebSocket client on dedicated thread, crossbeam channels
    codec.rs              # JSON encode, MessagePack decode, frame detection
    types.rs              # Serde structs for all backend message types
    events.rs             # Bevy events generated from backend messages

  state/
    mod.rs
    resources.rs          # Bevy Resources: AgentRegistry, SnapshotTree, ConnectionStatus
    components.rs         # Bevy Components: AgentNode, ThoughtParticle, SnapshotNode, etc.
    events.rs             # Bevy Events for UI actions (SelectAgent, SendCommand, etc.)

  systems/
    mod.rs
    connection.rs         # System: drain crossbeam channel, emit Bevy events
    agents.rs             # System: spawn/despawn/update agent entities from backend state
    thoughts.rs           # System: spawn thought particles, animate streams
    snapshots.rs          # System: build/update snapshot tree geometry
    layout.rs             # System: force-directed positioning of agent nodes
    selection.rs          # System: handle pick events, update selection state
    animation.rs          # System: pulse, glow, orbit animations
    blocking.rs           # System: spawn/despawn blocking request prompts

  rendering/
    mod.rs
    materials.rs          # Custom materials: glow, hologram, energy beam
    environment.rs        # Skybox, grid floor, fog, lighting setup
    postprocessing.rs     # Bloom, ambient occlusion config

  ui/
    mod.rs
    hud.rs                # egui: connection status, selected agent panel, minimap
    command_bar.rs         # egui: text input for commands
    agent_panel.rs         # egui: agent detail view, thought list, action buttons
    notifications.rs       # egui: toast notifications for events
    thought_inspector.rs   # egui: detailed thought view when clicking a particle

  plugins/
    mod.rs
    connection_plugin.rs   # Bundles connection systems + resources
    scene_plugin.rs        # Bundles environment + rendering setup
    agent_plugin.rs        # Bundles agent visualization systems
    ui_plugin.rs           # Bundles all egui UI systems
```

## Core design: how data flows

```
Backend (WebSocket)
    |
    v (dedicated thread, tungstenite)
crossbeam::channel
    |
    v (Bevy system, runs every frame)
Bevy Events (AgentUpdated, ThoughtReceived, SnapshotCreated, ...)
    |
    +-->  Systems read events, update Resources (AgentRegistry, etc.)
    +-->  Systems spawn/update/despawn ECS entities (agent orbs, particles, etc.)
    +-->  UI systems read Resources, render egui panels
```

**Outbound** (user actions -> backend):
```
egui panel button click / command bar input
    |
    v
Bevy Event (SendAgentAction, SendCommand, RespondBlocking, ...)
    |
    v (system reads event, serializes JSON)
crossbeam::channel -> WebSocket thread -> backend
```

This means the Bevy main loop never blocks on I/O. The WebSocket lives on its own thread. Communication is lock-free via crossbeam channels.

## ECS component design

```rust
// Agents are entities with these components
#[derive(Component)]
struct AgentNode {
    agent_id: Uuid,
    name: String,
    state: AgentState,         // Initialized | Running | Paused | Stopped
    capabilities: Vec<String>,
    thought_count: u32,
}

#[derive(Component)]
struct AgentVisual {
    base_color: Color,
    pulse_phase: f32,          // For breathing animation
    glow_intensity: f32,       // Spikes when receiving thoughts
}

#[derive(Component)]
struct Selectable;              // Marker: can be clicked via bevy_mod_picking

#[derive(Component)]
struct Selected;                // Marker: currently selected

// Thoughts are short-lived particle entities
#[derive(Component)]
struct ThoughtParticle {
    thought_id: Uuid,
    agent_id: Uuid,
    thought_type: ThoughtType, // Observation | Decision | Action | Reflection
    lifetime: Timer,
    velocity: Vec3,
}

// Snapshot tree nodes
#[derive(Component)]
struct SnapshotNode {
    snapshot_id: String,
    parent_id: Option<String>,
    branch: String,
    label: Option<String>,
    timestamp: f64,
}

// Beams connecting parent/child agents or snapshot edges
#[derive(Component)]
struct ConnectionBeam {
    from: Entity,
    to: Entity,
    color: Color,
}

// Blocking request prompts
#[derive(Component)]
struct BlockingPrompt {
    request_id: String,
    agent_id: Uuid,
    prompt_text: String,
    options: Vec<String>,
}

// Force-directed layout participation
#[derive(Component)]
struct ForceNode {
    velocity: Vec3,
    pinned: bool,
    mass: f32,
}
```

## Phase 1: Foundation (build this first)

1. **WebSocket client** (`protocol/client.rs`):
   - Spawn a `std::thread` that connects via `tungstenite`.
   - Auto-reconnect with exponential backoff (1s, 2s, 4s, 8s, max 30s).
   - Detect text vs binary frames. Text -> `serde_json::from_str`. Binary -> `rmp_serde::from_slice`.
   - Two crossbeam channels: `inbound: Receiver<ServerMessage>` (resource) and `outbound: Sender<ClientMessage>` (resource).
   - On connect, send `set_stream_format` with `"json"` for initial development.
   - Send `subscribe` for `"agents"` and `"events"` channels.

2. **Connection drain system** (`systems/connection.rs`):
   - Runs in `Update` schedule.
   - Calls `inbound.try_iter()` to drain all pending messages without blocking.
   - Converts each `ServerMessage` into the appropriate Bevy `Event`.
   - Updates `ConnectionStatus` resource (connected/disconnected/reconnecting, server version, agent count).

3. **Basic 3D scene** (`rendering/environment.rs`):
   - Black background (`ClearColor`).
   - Infinite grid floor: use a custom shader or a large plane with a grid texture. Subtle blue lines on dark grey.
   - Lighting: one directional light (dim, blue-white) + ambient light (very low). Point lights added dynamically near agent nodes.
   - Camera: `bevy_panorbit_camera` for orbit/pan/zoom. Start positioned at `(0, 15, 25)` looking at origin.
   - Post-processing: Bevy's built-in bloom (`BloomSettings`) on the camera. Low intensity, wide radius. Makes emissive materials glow.

4. **Agent visualization** (`systems/agents.rs`):
   - When `AgentCreated` event fires, spawn an entity with: `Mesh3d` (icosphere), `MeshMaterial3d` (emissive `StandardMaterial`), `AgentNode`, `AgentVisual`, `Selectable`, `ForceNode`, `Transform`.
   - Color by state: blue (#0088ff) = initialized, green (#00ff88) = running, amber (#ffaa00) = paused, red (#ff3344) = stopped.
   - Emissive intensity high enough to trigger bloom.
   - When `AgentStateChanged` event fires, update color with a smooth lerp via `bevy_tweening`.
   - Floating text label above each sphere: spawn a child entity with `Text2d` or use `bevy_egui` world-space labels.

5. **Animation system** (`systems/animation.rs`):
   - Breathing pulse: sinusoidal scale oscillation on all `AgentVisual` entities. `scale = 1.0 + 0.05 * sin(time * 2.0 + phase)`.
   - Thought spike: when `ThoughtReceived` event matches an agent, temporarily boost `glow_intensity` which decays over 0.5s.
   - Gentle rotation: agent spheres slowly rotate on Y axis.

6. **Selection** (`systems/selection.rs`):
   - Use `bevy_mod_picking` for ray casting on `Selectable` entities.
   - On click: add `Selected` marker component (remove from previous). Spawn a wireframe ring child around selected agent. Update `SelectedAgent` resource.
   - On click empty space: deselect.

7. **HUD** (`ui/hud.rs`, `ui/agent_panel.rs`):
   - `bevy_egui` side panel (right side, ~300px).
   - Connection status bar at top: green dot + "Connected" or red dot + "Reconnecting...". Show backend version, agent count.
   - When an agent is selected, show: name, state, capabilities list, thought count. Buttons: Start, Stop, Pause, Resume (send `agent_action`). Text input to inject a thought.
   - Thought list: scrollable list of recent thoughts for selected agent. Color-coded by type. Show timestamp, type badge, content preview.

8. **Command bar** (`ui/command_bar.rs`):
   - egui panel at bottom of screen. Text input field.
   - Press `/` or `Enter` to focus.
   - Simple command parsing:
     - `create agent <name>` -> send `create_agent`
     - `snapshot <agent> <label>` -> send `create_snapshot`
     - `step <agent>` -> send `step_agent`
     - Anything else -> inject as observation thought to selected agent.

## Phase 2: Particle systems and depth

9. **Thought stream particles** (`systems/thoughts.rs`):
   - Use `bevy_hanabi` for GPU-accelerated particle effects.
   - Each agent has a particle `EffectSpawner` as a child entity.
   - When a thought arrives, burst-emit particles:
     - Observation: blue particles, drift upward gently.
     - Decision: gold particles, burst outward.
     - Action: green particles, shoot forward in agent's facing direction.
     - Reflection: purple particles, orbit the agent briefly.
   - Particles have short lifetime (2-3s), fade out.
   - Clicking near a fresh particle cluster opens the thought inspector panel.

10. **Connection beams** (`rendering/materials.rs`, `systems/agents.rs`):
    - Between parent and child agents: animated energy beam.
    - Custom shader: scrolling UV on a cylinder mesh, additive blending, emissive.
    - Or simpler: `Gizmos::line` with color, if you want to start simple.

11. **Blocking request prompts** (`systems/blocking.rs`):
    - When `BlockingRequest` event arrives, spawn a 3D panel entity near the requesting agent.
    - Use `bevy_egui` world-space UI or a flat mesh with text rendered via `bevy_egui`.
    - Show the prompt text and response options as buttons.
    - Pulsing red/orange border to draw attention.
    - Audio cue if possible (bevy has `AudioPlayer`).
    - On response, send `respond_blocking` and despawn the prompt entity.

12. **Notification toasts** (`ui/notifications.rs`):
    - Queue of recent events shown as fading toasts in top-right.
    - Agent created/destroyed, state changes, errors.
    - Auto-dismiss after 5s, or click to dismiss.

## Phase 3: Spatial intelligence

13. **Force-directed layout** (`systems/layout.rs`):
    - Every `ForceNode` entity participates in physics each frame.
    - Repulsion: all nodes repel each other (inverse-square, capped).
    - Attraction: parent-child agents attract toward optimal distance.
    - Capability clustering: agents sharing capabilities attract weakly.
    - Damping: velocity *= 0.95 each frame.
    - Pinning: user can right-click an agent -> "Pin position". Sets `pinned = true`.
    - Constraint: keep all nodes above the grid floor (y > 1.0).
    - Run in `FixedUpdate` at 60Hz for determinism.

14. **Snapshot tree** (`systems/snapshots.rs`):
    - Fetch snapshot list on connect and periodically.
    - Build DAG from parent_id relationships.
    - Render as 3D tree growing from a root point (off to the side of agents, like a separate zone in the world).
    - Each snapshot = small sphere/cube. Color by branch.
    - Edges = thin beams/lines between parent-child snapshots.
    - Current branch highlighted (brighter, thicker edges).
    - Click a snapshot node -> show details in egui panel (ID, label, timestamp, agent state preview).
    - Branch points are visually distinct (larger node, glow effect).

15. **Event ambiance** (visual):
    - System events create brief environmental effects:
      - Tool calls: small flash at relevant agent.
      - Errors: brief red pulse on the grid floor.
      - New agent spawned: expanding ring effect at spawn point.
      - Snapshot created: brief golden flash in the snapshot tree.
    - These are cosmetic. Use `bevy_hanabi` one-shot effects or simple mesh flashes.

16. **Minimap** (`ui/hud.rs`):
    - Small egui panel in bottom-left showing top-down view of all agent positions.
    - Colored dots for agents. Click to recenter camera.

## Design principles

- **Tron aesthetic**: Black void, neon blue/cyan/gold accents. Emissive materials everywhere. Bloom makes it sing. No textures — pure geometry and light.
- **The 3D scene IS the interface**: egui panels are supporting actors, not the main event. Keep them minimal, translucent, non-intrusive.
- **Everything breathes**: nothing is static. Agents pulse. Particles drift. Beams shimmer. The grid subtly shifts. The world feels alive even when idle.
- **ECS all the way down**: don't fight Bevy. Every visual element is an entity. State changes flow through events. Systems are small and focused. One system per file if it helps clarity.
- **Performance by default**: Bevy gives you this for free with ECS. But also: use instanced meshes for particles if bevy_hanabi isn't enough. LOD is unlikely to be needed at <100 agents but plan for it. Profile with `bevy_diagnostic` early.

## Getting started

```bash
cargo init autopoiesis-holodeck
cd autopoiesis-holodeck
```

Add the dependencies to `Cargo.toml` as specified above, then:

```bash
cargo run
```

Start by building the WebSocket client on a background thread and the crossbeam channel bridge. Send `set_stream_format` with `"json"` initially for easy debugging. Subscribe to `"agents"` and `"events"`. Spawn agent icospheres in the scene when agents appear. Get the basics working end-to-end before making it pretty.

Build it as a Bevy plugin hierarchy:
```rust
fn main() {
    App::new()
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "Autopoiesis Holodeck".into(),
                ..default()
            }),
            ..default()
        }))
        .add_plugins(BloomPlugin::default())
        .add_plugins(EguiPlugin)
        .add_plugins(HanabiPlugin)
        .add_plugins(PanOrbitCameraPlugin)
        .add_plugins(DefaultPickingPlugins)
        // Our plugins
        .add_plugins(ConnectionPlugin)
        .add_plugins(ScenePlugin)
        .add_plugins(AgentPlugin)
        .add_plugins(UiPlugin)
        .run();
}
```

Each plugin registers its own systems, resources, and events. Keep them decoupled. The `ConnectionPlugin` knows nothing about rendering. The `AgentPlugin` knows nothing about egui. They communicate through Bevy events and shared resources.

The backend is already running. Connect to it and make it real.
