# Holodeck-TUI Integration

## Overview
Integrate the 3D holodeck visualization into the terminal TUI using headless Bevy rendering and terminal graphics protocols (Kitty/Sixel).

## Tasks

### 1. Create nexus-holodeck crate
**Complexity**: 8 | **Priority**: High

Create `nexus/crates/nexus-holodeck/` with:
- Cargo.toml with bevy, holodeck-core dependencies
- src/lib.rs exporting headless module

### 1.1 Implement headless.rs - Bevy headless rendering
**Complexity**: 8 | **Priority**: High | **Depends on**: 1

Create `src/headless.rs`:
- Bevy App with MinimalPlugins + RenderPlugin (no window)
- Camera renders to RenderTarget::Image
- Copy frame to shared buffer each frame
- NexusBridgePlugin receives WsEvent from nexus-protocol
- Re-use holodeck's ScenePlugin, AgentPlugin (not ConnectionPlugin)

```rust
pub struct HeadlessHolodeck {
    frame_rx: watch::Receiver<Vec<u8>>,
    event_tx: mpsc::Sender<WsEvent>,
    width: u32,
    height: u32,
}
```

### 1.2 Implement terminal_encode.rs - Graphics encoding
**Complexity**: 5 | **Priority**: High | **Depends on**: 1

Create `src/terminal_encode.rs`:
- detect_terminal_graphics() → Kitty/Sixel/HalfBlock
- encode_frame_kitty(rgba, width, height, image_id) → Vec<u8>
- encode_frame_sixel(rgba, width, height) → Vec<u8>  
- encode_frame_halfblock(rgba, width, height) → String

### 2. Add holodeck_viewport widget to nexus-tui
**Complexity**: 5 | **Priority**: High | **Depends on**: 1.1, 1.2

Create `nexus/crates/nexus-tui/src/widgets/holodeck_viewport.rs`:
- Ratatui Widget implementation
- Get frame from HeadlessHolodeck
- Encode using detected protocol
- Write to terminal via raw escape sequences
- Support resize, fullscreen toggle

### 3. Holodeck input forwarding
**Complexity**: 3 | **Priority**: Medium | **Depends on**: 2

When viewport has focus:
- Mouse clicks → terminal coords to 3D ray picking
- Arrow keys → orbit camera
- +/- → zoom, r → reset view

### 4. (Optional) Extract holodeck-core library
**Complexity**: 5 | **Priority**: Low | **Depends on**: -

Only if needed to share code between holodeck bin and nexus-holodeck:
- Split holodeck/Cargo.toml → holodeck-core (lib) + holodeck (bin)
- Both projects depend on holodeck-core

## Verification
- [ ] cargo build --release succeeds for nexus-holodeck
- [ ] cargo test passes for nexus-holodeck
- [ ] Holodeck viewport renders in Kitty/WezTerm/Ghostty
- [ ] Frame rate 15+ fps in viewport
