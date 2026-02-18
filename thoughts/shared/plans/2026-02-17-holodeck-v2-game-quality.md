# Holodeck v2: AAA Game-Quality Agent Visualization

**Date:** 2026-02-17
**Status:** Plan
**Scope:** Upgrade the existing Bevy 0.15 holodeck from prototype to AAA game-quality experience

---

## Vision

Transform the Autopoiesis holodeck from a functional prototype into an immersive **sci-fi operations center** that draws from the best game UI traditions:

- **Dead Space** — diegetic UI (information ON the entities, not in HUD overlays)
- **BioShock Infinite** — reveal-on-demand radial menus with Art Deco elegance
- **Fallout** — Pip-Boy data browser with CRT phosphor aesthetic for deep exploration
- **Elite Dangerous** — spatial holographic panel architecture for the cockpit
- **Halo/Destiny** — curved ergonomic HUD arcs, elemental color coding
- **DCS World / MSFS** — instrument scan patterns, MFD soft-key paradigm

The holodeck should feel like sitting in the command chair of a starship bridge, where your AI agents are crew members you can observe, inspect, and direct through a rich spatial interface.

---

## Current State (Gap Analysis)

### What Works
- Bevy 0.15 ECS architecture with 4 plugins (Connection, Scene, Agent, UI)
- WebSocket connection to CL backend with reconnect + MessagePack binary frames
- Agent entities as glowing icospheres with bloom postprocessing
- Force-directed layout (repulsion only)
- Click-to-select with torus ring
- Basic egui panels: connection status bar, agent detail panel, command bar, minimap, notifications

### 15 Identified Stubs / Incomplete Features

| # | Item | Location | Issue |
|---|------|----------|-------|
| 1 | `bevy_hanabi` | `Cargo.toml:11` | Imported, never used — no GPU particles |
| 2 | `bevy_tweening` | `Cargo.toml:12` | Imported, never used — no smooth transitions |
| 3 | `glow_intensity` | `animation.rs:32-55` | Written by thought spike/decay, never read back to material |
| 4 | Color transitions | `agents.rs:165` | Comment says "smooth lerps", code does instant material swap |
| 5 | Attraction force | `layout.rs:8-9` | `_ATTRACTION_K` defined with `_` prefix, never applied |
| 6 | Snapshot current-branch | `snapshots.rs:66` | Always passes `false` — gold highlight never shown |
| 7 | Snapshot tree edges | `components.rs:61` | `ConnectionBeam` defined, never spawned between nodes |
| 8 | `AgentLabel` | `components.rs:91` | Component defined, never spawned or queried |
| 9 | `InspectedThought` | `thought_inspector.rs` | Resource never populated, window never shown |
| 10 | Command history | `command_bar.rs:22` | `history_index` field exists, arrow-key nav never implemented |
| 11 | Minimap click | `hud.rs:83` | `Sense::click()` called, response discarded |
| 12 | Blocking response UI | `blocking.rs` | No way to respond to blocking requests from 3D scene |
| 13 | `StepComplete` | `connection.rs:96` | Handled with `{}` — no visual feedback |
| 14 | `DeselectEvent` | `selection.rs:50` | Handled but never written to |
| 15 | Blocking prompt stacking | `blocking.rs:17` | All prompts at `Vec3(0,3,0)` — overlap |

### Visual Quality Issues
- All UI is default egui dark theme — no custom styling
- Materials are all `StandardMaterial` with emissive — no custom WGSL shaders
- No particle effects (bevy_hanabi imported but unused)
- No smooth animations (bevy_tweening imported but unused)
- Agent entities are plain icospheres — no visual differentiation
- No spatial audio
- No world-space UI panels (everything is egui overlay)

---

## Design System: "Holographic Operations Center"

### Color Palette

```
VOID_BLACK       = #050A0F   // Scene background, near-black with cool blue tint
HOLO_CYAN        = #00B4D8   // Primary holographic UI, panels, borders
HOLO_CYAN_LIGHT  = #4CC9F0   // Secondary info, lighter cyan
AMBER_FOCUS      = #FFD166   // Active/focused element, draws eye (warm contrast)
TEAL_SUCCESS     = #06D6A0   // Positive state, "nominal"
AMBER_WARNING    = #FFB347   // Warning state
RED_CRITICAL     = #EF233C   // Error, critical alerts
STEEL_DIM        = #2D3A45   // Inactive, disabled, muted
TEXT_PRIMARY     = #E8F4F8   // Slightly cool white
TEXT_SECONDARY   = #7B9EAD   // Muted blue-grey labels
```

### Agent Element Colors (Destiny-inspired)

Each agent type/state gets an "elemental" identity:
```
Solar (Running)     = #FF6520   // Active, processing — warm fire
Arc (Communicating) = #7AB2FF   // Exchanging messages — electric blue
Void (Reflecting)   = #B48FFF   // Self-modification — deep purple
Stasis (Paused)     = #4CC9F0   // Frozen, waiting — ice cyan
Strand (Spawning)   = #5AFF7E   // New, initializing — growth green
Crimson (Error)     = #EF233C   // Failed state — alarm red
```

### Typography

```
Headlines:    Orbitron          (all caps, letter-spacing 0.2em)
Labels:       Share Tech Mono   (all caps, letter-spacing 0.1em)
Data values:  JetBrains Mono    (tabular figures, right-aligned)
Body text:    Rajdhani           (mixed case, line-height 1.6)
```

### Animation Contract

```
Micro (hover, focus):    80-120ms,  ease-out-cubic
Standard (open/close):   200-300ms, ease-in-out-cubic
Cinematic (mode switch): 400-600ms, spring (overshoot 1.1x)
NEVER linear easing for user-facing animations
NEVER instant state changes — minimum 80ms transition
```

### The Glow Budget
Maximum 3-4 glowing elements at any time. Reserve glow for:
- Currently selected entity
- Active alerts
- The element requiring user attention

Everything else uses dim/muted variants.

---

## Architecture

### New Crate / Plugin Structure

```
holodeck/
├── Cargo.toml                    # Updated deps
├── assets/
│   ├── fonts/
│   │   ├── orbitron.ttf
│   │   ├── share_tech_mono.ttf
│   │   ├── jetbrains_mono.ttf
│   │   └── rajdhani.ttf
│   ├── shaders/
│   │   ├── hologram.wgsl         # Holographic panel material
│   │   ├── energy_beam.wgsl      # Connection beam shader
│   │   ├── grid.wgsl             # Infinite grid shader
│   │   ├── agent_shell.wgsl      # Agent outer shell (fresnel + scanlines)
│   │   ├── crt_phosphor.wgsl     # Pip-Boy CRT effect
│   │   └── shield_arc.wgsl       # Halo-style curved health arc
│   ├── audio/
│   │   ├── ui_hover.ogg
│   │   ├── ui_select.ogg
│   │   ├── ui_error.ogg
│   │   ├── agent_spawn.ogg
│   │   ├── task_complete.ogg
│   │   ├── alert_pulse.ogg
│   │   └── ambient_hum.ogg
│   └── models/
│       └── (optional .glb meshes for agent archetypes)
├── src/
│   ├── main.rs
│   ├── plugins/
│   │   ├── connection_plugin.rs  # Existing (enhanced)
│   │   ├── scene_plugin.rs       # Existing (enhanced)
│   │   ├── agent_plugin.rs       # Existing (enhanced)
│   │   ├── ui_plugin.rs          # Existing (rewritten)
│   │   ├── audio_plugin.rs       # NEW — spatial + UI audio
│   │   └── shader_plugin.rs      # NEW — registers custom materials
│   ├── shaders/
│   │   ├── hologram_material.rs  # Rust bindings for hologram.wgsl
│   │   ├── energy_beam_material.rs
│   │   ├── grid_material.rs
│   │   ├── agent_shell_material.rs
│   │   ├── crt_material.rs
│   │   └── shield_arc_material.rs
│   ├── systems/
│   │   ├── agents.rs             # Rewritten — diegetic agent entities
│   │   ├── animation.rs          # Rewritten — bevy_tweening integration
│   │   ├── thoughts.rs           # Rewritten — bevy_hanabi GPU particles
│   │   ├── snapshots.rs          # Enhanced — tree edges, current branch
│   │   ├── blocking.rs           # Enhanced — spatial stacking, response UI
│   │   ├── selection.rs          # Enhanced — V.A.T.S. inspect mode
│   │   ├── layout.rs             # Enhanced — attraction forces, edge springs
│   │   ├── connection.rs         # Existing (minor fixes)
│   │   ├── audio.rs              # NEW — spatial audio events
│   │   ├── camera.rs             # NEW — cinematic camera modes
│   │   └── vats.rs               # NEW — V.A.T.S. agent inspection
│   ├── ui/
│   │   ├── mod.rs
│   │   ├── hud.rs                # Rewritten — Halo-style curved arcs
│   │   ├── agent_panel.rs        # Rewritten — holographic world-space panel
│   │   ├── command_bar.rs        # Enhanced — history nav, autocomplete
│   │   ├── notifications.rs      # Rewritten — spatial toast system
│   │   ├── thought_inspector.rs  # Rewritten — Dead Space holographic popup
│   │   ├── pipboy.rs             # NEW — Fallout-style data browser
│   │   ├── minimap.rs            # NEW — Elite-style radar with interaction
│   │   └── cockpit.rs            # NEW — Elite-style spatial panel manager
│   ├── rendering/
│   │   ├── materials.rs          # Rewritten — custom shader materials
│   │   ├── environment.rs        # Rewritten — shader-based infinite grid
│   │   └── postprocessing.rs     # Enhanced — bloom tuning, render layers
│   ├── state/
│   │   ├── components.rs         # Enhanced — new diegetic components
│   │   ├── resources.rs          # Enhanced — audio, camera state
│   │   └── events.rs             # Enhanced — audio events
│   └── protocol/
│       ├── client.rs             # Existing
│       ├── codec.rs              # Existing
│       └── events.rs             # Existing
```

### Render Layer Strategy

```
Layer 0: 3D World         — agents, environment, snapshot tree
Layer 1: World-space UI   — holographic panels attached to entities
Layer 2: Screen-space HUD — always-on arcs, minimap radar
```

Different post-processing per layer: Layer 0 gets full bloom, Layer 1 gets hologram scanline pass, Layer 2 is rendered crisp without bloom.

---

## Phases

### Phase 1: Foundation — Fix All Stubs, Custom Shaders, Tweening

**Goal:** Complete everything that's stubbed, replace StandardMaterial with custom WGSL shaders, activate bevy_hanabi and bevy_tweening.

#### 1.1 Activate Dormant Dependencies

```rust
// main.rs — add to plugin chain
.add_plugins(HanabiPlugin)
.add_plugins(TweeningPlugin)
.add_plugins(ShaderPlugin)  // NEW — registers all custom materials
```

#### 1.2 Custom WGSL Shaders

**`grid.wgsl` — Infinite Procedural Grid**

Replace the 82 cuboid entities with a single full-screen quad and a fragment shader:

```wgsl
// Grid shader — procedural infinite grid with distance fade
@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let world_pos = in.world_position.xz;
    let grid_size = 5.0;

    // Anti-aliased grid lines
    let grid = abs(fract(world_pos / grid_size - 0.5) - 0.5);
    let line = min(grid.x, grid.y);
    let line_width = fwidth(line);
    let grid_alpha = 1.0 - smoothstep(0.0, line_width * 1.5, line);

    // Distance fade
    let dist = length(world_pos);
    let fade = 1.0 - smoothstep(50.0, 150.0, dist);

    let color = vec3<f32>(0.0, 0.15, 0.35);
    let emissive = vec3<f32>(0.0, 0.1, 0.25) * grid_alpha;

    return vec4<f32>(color + emissive, grid_alpha * fade * 0.4);
}
```

**`agent_shell.wgsl` — Holographic Agent Shell**

Replace `StandardMaterial` on agents with a custom material that provides:
- Fresnel edge glow (bright rim where surface is tangent to view)
- Scanline overlay (horizontal bands scrolling downward)
- Flicker (subtle 0.5-2% opacity oscillation)
- `glow_intensity` uniform that actually drives emissive brightness

```wgsl
struct AgentShellMaterial {
    base_color: vec4<f32>,
    glow_intensity: f32,
    scan_speed: f32,
    flicker_phase: f32,
    _padding: f32,
}

@group(2) @binding(0)
var<uniform> material: AgentShellMaterial;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let normal = normalize(in.world_normal);
    let view_dir = normalize(in.world_position.xyz - view.world_position);

    // Fresnel rim glow
    let fresnel = pow(1.0 - abs(dot(normal, -view_dir)), 3.0);
    let rim = fresnel * material.glow_intensity;

    // Scanlines (scroll downward)
    let scan = sin(in.world_position.y * 40.0 - globals.time * material.scan_speed) * 0.08 + 0.92;

    // Subtle flicker
    let flicker = 0.97 + 0.03 * sin(globals.time * 47.3 + material.flicker_phase);

    let base = material.base_color.rgb * material.glow_intensity;
    let final_color = (base + rim * material.base_color.rgb) * scan * flicker;

    return vec4<f32>(final_color, material.base_color.a * (0.85 + rim * 0.15));
}
```

**`hologram.wgsl` — Holographic Panel Material**

For world-space UI panels (Dead Space / Elite Dangerous style):
- Transparent dark background with bright edge borders
- Chromatic aberration at edges (RGB channel offset)
- Scanline overlay
- Content rendered to texture, then applied to this material

```wgsl
struct HologramMaterial {
    border_color: vec4<f32>,
    scan_density: f32,
    aberration_strength: f32,
    opacity: f32,
    _padding: f32,
}

@group(2) @binding(0)
var<uniform> material: HologramMaterial;
@group(2) @binding(1)
var content_texture: texture_2d<f32>;
@group(2) @binding(2)
var content_sampler: sampler;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = in.uv;

    // Chromatic aberration at edges
    let edge_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let aberration = material.aberration_strength * (1.0 - smoothstep(0.0, 0.15, edge_dist));
    let r = textureSample(content_texture, content_sampler, uv + vec2<f32>(aberration, 0.0)).r;
    let g = textureSample(content_texture, content_sampler, uv).g;
    let b = textureSample(content_texture, content_sampler, uv - vec2<f32>(aberration, 0.0)).b;
    let content = vec3<f32>(r, g, b);

    // Scanlines
    let scan = sin(uv.y * material.scan_density) * 0.05 + 0.95;

    // Edge glow border
    let border = smoothstep(0.02, 0.0, edge_dist) * material.border_color.rgb;

    let final_color = content * scan + border;
    return vec4<f32>(final_color, material.opacity);
}
```

**`energy_beam.wgsl` — Connection Beams**

For edges between snapshot nodes and agent-to-agent connections:
- Animated energy flow along the beam length
- Pulsing brightness
- Additive blending

```wgsl
@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let flow = fract(in.uv.x * 3.0 - globals.time * 2.0);
    let pulse = sin(globals.time * 3.0) * 0.2 + 0.8;
    let edge_fade = 1.0 - pow(abs(in.uv.y * 2.0 - 1.0), 2.0);

    let color = material.base_color.rgb * pulse * (0.5 + flow * 0.5);
    return vec4<f32>(color * edge_fade, edge_fade * 0.8);
}
```

**`shield_arc.wgsl` — Halo-style Curved HUD Arcs**

For screen-space health/status arcs:
- Curved bar that fills from center outward
- Segmented (discrete blocks like Halo health)
- Glow on the filled portion
- Flash + deplete animation when value drops

#### 1.3 Fix All 15 Stubs

Each stub fix in order:

**Stub 1-2: Activate bevy_hanabi + bevy_tweening** — Add plugins to main.rs.

**Stub 3: glow_intensity → material** — In `animate_agents`, query for `Handle<AgentShellMaterial>` and update the `glow_intensity` uniform every frame via `materials.get_mut()`.

**Stub 4: Smooth color transitions** — Use `bevy_tweening` `Animator<AgentShellMaterial>`:
```rust
// On state change, create a color tween instead of instant swap
let tween = Tween::new(
    EaseFunction::CubicInOut,
    Duration::from_millis(300),
    AgentColorLens {
        start: current_color,
        end: new_color,
    },
);
commands.entity(entity).insert(Animator::new(tween));
```

**Stub 5: Attraction force** — Remove `_` prefix from constants, implement spring force between connected agents (agents that share tasks, or parent-child relationships):
```rust
// In layout.rs, add after repulsion loop:
for (a_entity, a_pos, _) in &nodes {
    for (b_entity, b_pos, _) in &nodes {
        if connected(a_entity, b_entity, &connections) {
            let delta = b_pos - a_pos;
            let dist = delta.length();
            let force_mag = ATTRACTION_K * (dist - IDEAL_DISTANCE);
            let force = delta.normalize_or_zero() * force_mag;
            // Apply spring force
        }
    }
}
```

**Stub 6: Snapshot current-branch highlight** — Pass `snapshot.id == tree.current_snapshot_id` to `snapshot_node_material()`.

**Stub 7: Snapshot tree edges** — After building snapshot node positions, iterate parent→child pairs and spawn `ConnectionBeam` entities with the `energy_beam` shader material between them.

**Stub 8: AgentLabel** — Spawn 3D `Text2d` (Bevy 0.15 built-in, formerly `Text2dBundle`) as a child entity of each agent, positioned `Vec3(0, 1.5, 0)` above the icosphere. Use `Share Tech Mono` font, agent name in `HOLO_CYAN`, scaled based on camera distance.

**Stub 9: InspectedThought** — In the agent panel thought list, clicking a thought row sets `InspectedThought.thought = Some(thought)`. The thought inspector window then renders.

**Stub 10: Command history navigation** — In `command_bar.rs`, handle `Key::ArrowUp` and `Key::ArrowDown` to cycle through `history` using `history_index`.

**Stub 11: Minimap click** — Convert minimap click position to world coordinates, move camera to that position with a smooth tween.

**Stub 12: Blocking response UI** — Spawn world-space holographic panel near the blocking prompt cube. Panel shows prompt text + clickable option buttons. Clicking sends `SendRespondBlocking`.

**Stub 13: StepComplete feedback** — Trigger a brief particle burst on the agent + a toast notification.

**Stub 14: DeselectEvent** — Pressing `Escape` writes `DeselectEvent`. Clicking empty space writes `DeselectEvent`.

**Stub 15: Blocking prompt stacking** — Position prompts in a vertical stack: `Vec3(0, 3.0 + index * 2.0, 0)`, or orbit them around a fixed point.

#### 1.4 Success Criteria — Phase 1
- [ ] `bevy_hanabi` plugin registered, at least one GPU particle effect spawns
- [ ] `bevy_tweening` plugin registered, agent color transitions use tweens
- [ ] All 4 custom WGSL shaders compile and render
- [ ] Agent `glow_intensity` visibly affects the shell brightness
- [ ] Snapshot tree shows gold current-branch node + energy beams between nodes
- [ ] Agent names visible as 3D labels
- [ ] Command bar up/down arrow cycles history
- [ ] Clicking minimap moves camera
- [ ] Blocking prompts don't overlap, can be responded to
- [ ] `Escape` deselects

---

### Phase 2: Diegetic Agent Entities — Dead Space Meets Destiny

**Goal:** Transform agents from plain icospheres into rich diegetic entities where their state is embedded in their visual form.

#### 2.1 Agent Visual Anatomy

Each agent entity becomes a compound object:

```
Agent Entity
├── Core Sphere          — icosphere with agent_shell shader
│   └── Inner Glow       — smaller sphere with additive blending
├── Status Spine          — Dead Space-style vertical bar on "back"
│   ├── Segment 0..N     — discrete blocks showing health/progress
│   └── Color shifts      — green → yellow → red as resources deplete
├── Capability Modules    — small orbiting shapes around the sphere
│   ├── Module 0          — each capability = one orbiting diamond
│   ├── Module 1          — glows when actively using that capability
│   └── Module 2          — dim when available but unused
├── Task Ring             — torus at "waist" level
│   └── Fill Arc          — partial torus showing task progress 0-100%
├── Particle Emitter      — bevy_hanabi effect attached to entity
│   ├── Idle: 5-10/sec    — dim ambient particles, "breathing"
│   ├── Active: 50-100/sec — bright processing particles
│   └── Error: burst 200  — red explosion
├── Label                 — 3D text above, agent name + state
└── Point Light           — colored by state, intensity by activity
```

#### 2.2 Status Spine (Dead Space Health)

The signature Dead Space innovation — health displayed ON the entity:

```rust
#[derive(Component)]
struct StatusSpine {
    segments: u8,           // typically 8
    fill_level: f32,        // 0.0..1.0
    color_low: Color,       // red
    color_mid: Color,       // amber
    color_high: Color,      // teal
}

fn build_spine(commands: &mut Commands, parent: Entity, meshes: &mut Assets<Mesh>,
               materials: &mut Assets<AgentShellMaterial>) {
    let segment_height = 0.15;
    let segment_gap = 0.03;
    for i in 0..8 {
        let y_offset = -0.5 + (i as f32) * (segment_height + segment_gap);
        commands.entity(parent).with_children(|parent| {
            parent.spawn((
                Mesh3d(meshes.add(Cuboid::new(0.08, segment_height, 0.08))),
                MeshMaterial3d(materials.add(/* per-segment material */)),
                Transform::from_xyz(-0.85, y_offset, 0.0), // on "back" of sphere
                SpineSegment { index: i },
            ));
        });
    }
}
```

The spine color interpolates based on the agent's cognitive load / token usage / error count — whatever metric is most relevant. Visual update runs per-frame to smoothly animate segment fill.

#### 2.3 Capability Modules (Orbiting Shapes)

Each capability the agent has (from `AgentNode.capabilities`) becomes a small geometric shape orbiting the core sphere at different radii and speeds:

```rust
struct CapabilityModule {
    capability_name: String,
    orbit_radius: f32,      // 1.2..1.8
    orbit_speed: f32,       // 0.3..0.8 rad/s
    orbit_phase: f32,       // staggered start
    active: bool,           // glows bright when in use
}
```

Shapes are small diamonds (octahedron, 0.1 scale) with the hologram shader. When a capability is being used (e.g., agent is running a tool), that module flares bright and emits particles — the other modules stay dim. This gives an at-a-glance read of *what* an agent is doing, not just *that* it's doing something.

#### 2.4 Task Progress Ring

A torus ring at the agent's mid-section showing current task progress:

```rust
struct TaskRing {
    progress: f32,          // 0.0..1.0
    task_name: String,
}
```

The ring is a partial torus mesh — progress 0.5 means half the torus is visible. The filled portion uses the `AMBER_FOCUS` color; the unfilled is a dim ghost outline. On task completion, the ring flashes bright and expands briefly (spring animation) before dissolving into particles.

#### 2.5 GPU Particle Effects (bevy_hanabi)

Define particle effect presets:

```rust
// Idle ambient "breathing"
fn idle_particles(color: Color) -> EffectAsset {
    let mut gradient = Gradient::new();
    gradient.add_key(0.0, color.with_alpha(0.6).to_linear().to_vec4());
    gradient.add_key(1.0, Vec4::ZERO);

    EffectAsset::new(256, Spawner::rate(8.0.into()), module)
        .with_name("agent_idle")
    // init: random sphere radius 0.3..0.8
    // update: slight upward drift, turbulence noise
    // render: 2-4px additive sprites
}

// Active processing
fn active_particles(color: Color) -> EffectAsset {
    // 50-100 particles/sec, outward burst with upward bias
    // 0.5-1.5s lifetime, scale 1.0→0.0, low-frequency turbulence
}

// Error burst
fn error_burst(color: Color) -> EffectAsset {
    // Single burst of 200 particles, red-orange
    // Outward explosion with slight gravity
    // 0.3s lifetime, each particle spins
}

// Task completion fountain
fn completion_burst() -> EffectAsset {
    // Gold → white → transparent
    // Upward fountain arc, 1-2s lifetime
    // Plus a ring shockwave mesh that expands and fades
}
```

#### 2.6 Success Criteria — Phase 2
- [ ] Each agent has visible spine, capability modules, task ring, label
- [ ] Spine color reflects agent's actual metric (token count, error rate, etc.)
- [ ] Capability modules orbit and flare when in use
- [ ] Task ring fills as tasks progress, dissolves on completion
- [ ] Three distinct particle presets visible: idle, active, error
- [ ] Completion burst plays when agent finishes a task
- [ ] Agent entities are visually distinguishable at a glance from across the scene

---

### Phase 3: The HUD — Halo Arcs + Elite Radar

**Goal:** Replace egui overlays with custom-rendered screen-space HUD elements.

#### 3.1 Halo-Style Status Arcs

Replace the flat egui top bar with curved arcs rendered as screen-space meshes:

```
┌─────────────────────────────────────────────────┐
│                                                 │
│  ╭──── SYSTEM ────╮        ╭──── AGENTS ────╮   │
│  │ ████████░░░░░░ │        │ 5 active  2 idle│  │
│  ╰────────────────╯        ╰─────────────────╯  │
│                                                 │
│                    [3D SCENE]                    │
│                                                 │
│                                                 │
│  ┌────┐                                        │
│  │RADAR│                                        │
│  │ · · │                           ┌──────────┐ │
│  │· ◉ ·│                           │> command_ │ │
│  └────┘                           └──────────┘ │
└─────────────────────────────────────────────────┘
```

**System Arc (top-left):** Curved bar showing overall system health — backend connection status, total agent count, event throughput. Uses `shield_arc.wgsl` with segmented fill.

**Agent Summary Arc (top-right):** Shows agent state distribution — N active, N idle, N error. Each segment of the arc represents one agent, colored by state. Clicking a segment selects that agent.

Both arcs use the Halo pattern: always visible but minimal, no text-heavy overlays during normal operation. They fade to 30% opacity when the camera is moving (orbit/pan), full opacity when still.

#### 3.2 Elite-Style Radar

Replace the basic egui minimap with a proper 3D radar:

```rust
struct Radar {
    radius: f32,                // screen-space radius
    range: f32,                 // world-unit range
    mode: RadarMode,            // TopDown or Altitude
    contacts: Vec<RadarContact>,
}

struct RadarContact {
    entity: Entity,
    position: Vec3,             // relative to camera
    contact_type: ContactType,  // Agent, Snapshot, Blocking
    is_active: bool,            // active agents pulse
}
```

The radar is a circular mesh in screen-space with:
- Dark navy background (`#0D1117` at 80% opacity)
- Concentric range rings (30%, 60%, 100% of max range)
- Agent contacts as colored dots (state color)
- Active agents shown as pulsing dots
- Selected agent has a bright highlight ring
- **Altitude dimension:** contacts above/below camera Y shown as dots with a vertical line up/down from the radar plane (Elite Dangerous style)
- **Clicking a contact on the radar selects that agent** (fixes Stub 11)
- Sweep line rotating at 2 RPM for visual flair

#### 3.3 Notification Toasts (Redesigned)

Replace egui toast overlay with custom screen-space panels:
- Toasts slide in from the right edge with a spring animation
- Each toast is a small holographic panel (hologram shader)
- Icon + message + timestamp
- Auto-dismiss after 5s with fade animation
- Stacking: each new toast pushes the stack down
- Clicking a toast focuses on the relevant entity

#### 3.4 Command Bar (Enhanced)

Keep the command bar as a screen-space element at the bottom, but:
- Custom rendered with hologram shader background
- Monospace font (JetBrains Mono)
- Up/down arrow cycles command history (fixes Stub 10)
- Tab completion for command names and agent names
- Typing `/` from anywhere focuses the command bar
- Results appear as a dropdown above the bar
- The bar glows cyan when focused, dims when unfocused

#### 3.5 Success Criteria — Phase 3
- [ ] System and Agent arcs render as curved screen-space meshes
- [ ] Arcs fade during camera movement, restore when still
- [ ] Radar shows all agents as colored contacts with altitude lines
- [ ] Clicking radar contacts selects agents
- [ ] Toasts slide in with spring animation, stack properly
- [ ] Command bar has working history navigation and tab completion
- [ ] No egui panels remain in the main HUD (egui only for debug/dev)

---

### Phase 4: V.A.T.S. Inspection Mode — Fallout Meets Dead Space

**Goal:** Create a deep-inspection mode triggered by selecting an agent, where time slows and holographic panels radiate outward showing the agent's internals.

#### 4.1 V.A.T.S. Activation

When the user selects an agent (click in 3D or radar), the scene enters **inspection mode**:

1. **Time dilation:** All other agents slow to 10% animation speed (not paused — still subtly moving)
2. **Camera focus:** Camera smoothly orbits to face the selected agent at distance ~5 units
3. **Background dim:** Non-selected entities fade to 30% opacity
4. **Panel radiate:** Holographic info panels spring outward from the agent in a radial arrangement

```rust
#[derive(Resource)]
struct InspectionMode {
    active: bool,
    target: Option<Entity>,
    panel_states: Vec<PanelState>,
    time_scale: f32,            // 1.0 normal, 0.1 inspection
    transition_progress: f32,   // 0.0..1.0 for enter/exit animation
}

enum PanelPosition {
    Left,       // Agent details
    Right,      // Thought stream
    Above,      // Capability radar chart
    Below,      // Task history timeline
}
```

#### 4.2 Inspection Panels

Four holographic panels surround the selected agent in world-space:

**Left Panel — Agent Profile:**
- Name, ID, current state (with elemental color)
- Uptime, cognitive cycle count
- Memory/token usage bar
- Current persona/config

**Right Panel — Thought Stream:**
- Live scrolling list of recent thoughts
- Each thought shows: type badge (colored), timestamp, content preview
- Clicking a thought expands it (InspectedThought — fixes Stub 9)
- New thoughts animate in from the top with a "materialize" effect

**Top Panel — Capability Web:**
- Radar chart / spider diagram showing agent capabilities
- Each axis = one capability
- Fill level = usage frequency or proficiency
- Active capabilities pulse

**Bottom Panel — Task Timeline:**
- Horizontal timeline of recent tasks
- Each task is a colored block (green=complete, amber=active, red=failed)
- Hovering shows task details
- Connects to the main task queue

All panels use the `hologram.wgsl` shader with `HOLO_CYAN` borders.

#### 4.3 Thought Expansion (Dead Space Holographic Menu)

Clicking a thought in the right panel triggers a Dead Space-style holographic expansion:
- The thought "card" expands into a larger panel in front of the agent
- Shows full content, rationale, alternatives, confidence
- 3D model or icon representing the thought type rotates slowly
- Closing the card uses a "de-materialize" (shrink + fade) animation

#### 4.4 Exit Inspection

- Press `Escape` or click empty space
- Time scale returns to 1.0 with ease-in-out over 400ms
- Panels retract back into the agent (reverse of the radiate animation)
- Camera returns to previous orbit position

#### 4.5 Success Criteria — Phase 4
- [ ] Clicking an agent enters inspection mode with visible time dilation
- [ ] Camera smoothly focuses on selected agent
- [ ] Four holographic panels radiate outward from agent
- [ ] Panels show live data (thoughts update in real-time)
- [ ] Clicking a thought expands it Dead Space style
- [ ] Escape exits inspection cleanly
- [ ] Non-selected agents dim during inspection

---

### Phase 5: Pip-Boy Data Browser — Fallout-Style Deep Dive

**Goal:** A slide-in panel for deep system exploration, styled as a CRT phosphor display.

#### 5.1 The Pip-Boy Panel

Activated by pressing `Tab` (or a dedicated key), a large panel slides in from the right edge:

```
╔═══════════════════════════════════════╗
║  AUTOPOIESIS  ║ AGENTS │ TASKS │ LOG ║
╠═══════════════════════════════════════╣
║                                       ║
║  ▸ Agent Alpha .............. RUNNING ║
║    Agent Beta ............... PAUSED  ║
║    Agent Gamma .............. IDLE    ║
║    Agent Delta .............. ERROR   ║
║                                       ║
║  ─────────────────────────────────────║
║  DETAILS:                             ║
║  State: Running                       ║
║  Uptime: 2h 14m                       ║
║  Thoughts: 847                        ║
║  Capabilities: [tool-use, reasoning]  ║
║                                       ║
║  [▶ Step] [⏸ Pause] [⏹ Stop]        ║
╚═══════════════════════════════════════╝
         ▒▒▒ scanline overlay ▒▒▒
```

#### 5.2 CRT Phosphor Aesthetic

The Pip-Boy panel uses `crt_phosphor.wgsl`:

```wgsl
struct CrtMaterial {
    phosphor_color: vec4<f32>,  // #59FF59 (green) or #00B4D8 (cyan)
    scan_line_opacity: f32,     // 0.3-0.4
    bloom_radius: f32,          // 8-12px equivalent
    curvature: f32,             // barrel distortion strength
    flicker_intensity: f32,     // 0.005-0.02
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    var uv = in.uv;

    // Barrel distortion (CRT curvature)
    let center = uv - 0.5;
    let r2 = dot(center, center);
    uv = uv + center * r2 * material.curvature;

    // Sample content
    let content = textureSample(content_texture, content_sampler, uv);

    // Phosphor tint
    let phosphor = content.rgb * material.phosphor_color.rgb;

    // Scanlines
    let scan = sin(uv.y * 600.0) * material.scan_line_opacity + (1.0 - material.scan_line_opacity);

    // Pixel grid (subtle)
    let pixel_grid = sin(uv.x * 1200.0) * 0.03 + 0.97;

    // Bloom (soft glow on bright pixels)
    let bloom = textureSample(content_texture, content_sampler, uv) * 0.3;

    // Flicker
    let flicker = 1.0 - material.flicker_intensity * sin(globals.time * 60.0);

    return vec4<f32>((phosphor + bloom.rgb * 0.1) * scan * pixel_grid * flicker, content.a);
}
```

Color options — user-configurable:
- Classic green phosphor: `#59FF59` (Fallout)
- Cool cyan: `#00B4D8` (matching holographic theme)
- Warm amber: `#FFD166` (classic terminal)

#### 5.3 Pip-Boy Tabs

Three top-level tabs (mapped to `1`, `2`, `3` keys):

**AGENTS** — List all agents with state badges, select to see details
- Sub-sections: Details, Capabilities, Config
- Action buttons for selected agent

**TASKS** — Task queue browser
- Active tasks with progress bars
- Completed tasks (recent)
- Failed tasks with error messages
- V.A.T.S.-style: clicking a task highlights the agent working on it

**LOG** — Event stream
- Real-time event log with type filters
- Color-coded: system events (cyan), agent events (elemental), errors (red)
- Searchable with `/` within the log

#### 5.4 Navigation

- `Tab` to open/close
- `1`/`2`/`3` to switch tabs
- Arrow keys to navigate lists
- `Enter` to select/expand
- `Backspace` to go back one level
- The whole panel has a mechanical "slide in" animation (not a fade — like the Pip-Boy arm raise)

#### 5.5 Success Criteria — Phase 5
- [ ] Tab opens/closes the Pip-Boy panel with slide animation
- [ ] CRT phosphor shader renders with scanlines, curvature, flicker
- [ ] Three tabs functional: Agents, Tasks, Log
- [ ] Agent list shows all agents with live state updates
- [ ] Task list shows active/completed/failed tasks
- [ ] Log shows filterable real-time event stream
- [ ] Keyboard navigation works throughout

---

### Phase 6: Spatial Audio + Camera Modes

**Goal:** Add spatial audio for immersion and multiple camera modes for different workflows.

#### 6.1 Audio System

Add `bevy_kira_audio` for spatial and non-spatial audio:

```rust
pub struct AudioPlugin;

impl Plugin for AudioPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(AudioPlugin)
            .init_resource::<AudioSettings>()
            .add_systems(Update, (
                play_ui_sounds,
                play_spatial_agent_sounds,
                manage_ambient_loop,
            ));
    }
}

struct AudioSettings {
    master_volume: f32,
    ui_volume: f32,
    spatial_volume: f32,
    ambient_volume: f32,
    enabled: bool,
}
```

**Sound events:**

| Event | Sound | Spatial? | Duration |
|-------|-------|----------|----------|
| UI hover | Soft tick | No | 50ms |
| UI select/confirm | Crisp click | No | 150ms |
| UI error/invalid | Low buzz | No | 200ms |
| Agent spawn | Rising materialize tone | Yes, at agent pos | 500ms |
| Agent state change | Short chime (pitch varies by state) | Yes | 200ms |
| Task complete | Ascending 3-note arpeggio | No (world event) | 400ms |
| Error/failure | Descending buzz | Yes, at agent pos | 300ms |
| Alert (high priority) | Looping pulse, 1Hz | Yes | Until dismissed |
| Notification toast | Soft ding | No | 100ms |
| V.A.T.S. enter | Dramatic slowdown whoosh | No | 600ms |
| V.A.T.S. exit | Reverse whoosh | No | 400ms |
| Pip-Boy open | Mechanical slide + CRT power-on hum | No | 300ms |
| Pip-Boy close | Mechanical slide + CRT power-off click | No | 200ms |
| Ambient | Low persistent machinery hum | No | Looping |

Spatial audio uses Bevy's built-in `SpatialListener` on the camera and `AudioEmitter` on agent entities. Rolloff: inverse distance, ref distance 5.0, max distance 50.0.

#### 6.2 Camera Modes

```rust
enum CameraMode {
    Orbit,          // Default — free orbit around scene center
    Follow(Entity), // Lock orbit center to a specific agent
    Overview,       // High-altitude top-down view of entire graph
    Cinematic,      // Slow automated fly-through of the scene
}
```

**Orbit (default):** PanOrbitCamera as-is, enhanced with smooth damping.

**Follow:** Press `F` while an agent is selected to lock the camera to that agent. Camera orbits around the agent as center. Agent label stays face-camera.

**Overview:** Press `O` for a bird's-eye view. Camera moves to Y=40, looking straight down. All agent labels rotate to face upward. The graph layout is most visible from this angle.

**Cinematic:** Press `C` for an automated slow fly-through. Camera follows a smooth spline through interesting scene points (agent clusters, snapshot tree, any high-activity areas). Good for leaving the holodeck on a monitor as an ambient display.

Transitions between modes use smooth camera tweens (400ms, spring ease).

#### 6.3 Success Criteria — Phase 6
- [ ] UI sounds play on hover, select, error
- [ ] Spatial audio: agent spawn/error sounds come from agent positions
- [ ] Ambient hum plays continuously at low volume
- [ ] V.A.T.S. and Pip-Boy have enter/exit sounds
- [ ] Four camera modes work: Orbit, Follow, Overview, Cinematic
- [ ] Camera transitions are smooth (no teleporting)
- [ ] Audio respects volume settings

---

### Phase 7: Polish — Premium Feel

**Goal:** The final 20% that makes the difference between "prototype" and "production."

#### 7.1 Micro-Animations Everywhere

Every interactive element gets:
- **Hover:** Scale to 1.05x over 80ms, subtle glow increase
- **Press:** Scale to 0.95x over 40ms, then spring back to 1.0x
- **Focus:** Gentle pulse (1.0 → 1.02 → 1.0) at 0.5Hz
- **Disabled:** Desaturate + reduce opacity to 40%

#### 7.2 Scene Ambiance

- **Floating dust motes:** Very subtle, sparse particles drifting across the scene (5-10 visible at any time). Barely perceptible but adds life.
- **Grid breathing:** The grid floor's emissive intensity gently pulses with a 10-second period — like the scene is alive.
- **Light flickering:** Very occasional (every 30-60s) brief dimming of the directional light, as if power fluctuated. Subtle enough to be subconscious.
- **Distant fog:** Very subtle depth fog starting at 80 units — gives the scene a sense of scale without obscuring anything useful.

#### 7.3 Connection Status Theater

When the WebSocket disconnects:
- All agent entities "freeze" in place (stop animations)
- Colors desaturate over 2 seconds
- A subtle red vignette appears at screen edges
- The ambient hum pitch-shifts downward
- Status arc flashes red

On reconnect:
- Colors re-saturate with a "power-on" sweep from center outward
- Agents resume animation
- A "systems online" audio cue plays
- Brief green flash on status arc

#### 7.4 Performance Optimization

- **Frustum culling:** Ensure all custom meshes have AABB bounds for automatic culling
- **LOD for agent labels:** Only render labels for agents within 20 units of camera
- **Particle budget:** Cap total particles at 5000 across all effects
- **Instancing:** Use instanced rendering for spine segments and capability modules
- **Frame pacing:** UI animations on a separate fixed timestep to stay smooth even during scene hitches

#### 7.5 Configuration

`~/.holodeck/config.toml`:
```toml
[display]
window_width = 1920
window_height = 1080
fullscreen = false
vsync = true
bloom_intensity = 0.15
render_scale = 1.0

[theme]
color_scheme = "cyan"        # "cyan", "amber", "green"
pipboy_phosphor = "#00B4D8"  # override phosphor color
font_scale = 1.0

[audio]
master_volume = 0.8
ui_volume = 0.6
spatial_volume = 0.7
ambient_volume = 0.3

[camera]
default_mode = "orbit"
orbit_sensitivity = 1.0
follow_distance = 8.0

[connection]
ws_url = "ws://127.0.0.1:8080/ws"
reconnect_max_attempts = 10
```

#### 7.6 Keybindings

| Key | Action |
|-----|--------|
| `Click` | Select agent |
| `Escape` | Deselect / Exit mode |
| `/` | Focus command bar |
| `Tab` | Toggle Pip-Boy |
| `1`/`2`/`3` | Pip-Boy tabs |
| `F` | Follow selected agent |
| `O` | Overview camera |
| `C` | Cinematic camera |
| `Space` | Pause/resume selected agent |
| `S` | Step selected agent |
| `Delete` | Stop selected agent |
| `?` | Show help overlay |
| `Arrow Up/Down` | Command history |
| `Mouse wheel` | Zoom |
| `Middle drag` | Pan |
| `Right drag` | Orbit |

#### 7.7 Success Criteria — Phase 7
- [ ] Every interactive element has hover + press animations
- [ ] Scene has ambient particles, grid breathing, occasional light flicker
- [ ] Disconnect/reconnect has dramatic visual feedback
- [ ] Performance: 60fps with 20 agents, each with full visual anatomy
- [ ] Config file loads and applies settings
- [ ] All keybindings work
- [ ] Help overlay shows all keybindings

---

## Dependency Updates

### Cargo.toml Changes

```toml
[dependencies]
bevy = { version = "0.15", features = ["wayland"] }
bevy_egui = "0.33"                    # Keep for debug panels only
bevy_hanabi = "0.15"                  # ACTIVATE — GPU particles
bevy_tweening = "0.12"                # ACTIVATE — smooth animations
bevy_panorbit_camera = "0.25"         # Keep
bevy_kira_audio = "0.22"              # NEW — spatial + UI audio

# Networking (unchanged)
tungstenite = "0.24"
rmp-serde = "1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
crossbeam-channel = "0.5"
uuid = { version = "1", features = ["v4", "serde"] }
tracing = "0.1"

# NEW
toml = "0.8"                          # Config file parsing
dirs = "5"                            # Platform-appropriate config paths
```

### Font Assets to Add

Download and place in `holodeck/assets/fonts/`:
- Orbitron (SIL OFL) — headlines
- Share Tech Mono (SIL OFL) — labels
- JetBrains Mono (SIL OFL) — data values
- Rajdhani (SIL OFL) — body text

All available from Google Fonts under SIL Open Font License.

---

## Performance Targets

| Metric | Target | Method |
|--------|--------|--------|
| Frame rate | 60fps steady | Instanced rendering, particle budget, LOD |
| Agents rendered | 50+ with full visual anatomy | ECS batch queries, frustum culling |
| Particle count | 5000 max | bevy_hanabi GPU compute, budget per agent |
| Shader compile | < 2s on launch | Pre-warm shader cache |
| Memory | < 500MB | Shared mesh/material handles, texture atlasing |
| Input latency | < 16ms (1 frame) | UI on Update schedule, not FixedUpdate |

---

## References

- Fagerholt & Lorentzon, "Beyond the HUD" (2009) — diegetic UI framework
- Dead Space GDC talk on zero-HUD design
- Elite Dangerous cockpit panel architecture
- Halo UI retrospective (shield arc, motion tracker)
- Fallout Pip-Boy as "interface-as-object"
- MIL-STD-1787 HUD symbology standard
- Bevy 0.15 changelog — improved render pipeline, built-in picking
- bevy_hanabi docs — GPU particle effects
- bevy_tweening docs — animation/tween system
