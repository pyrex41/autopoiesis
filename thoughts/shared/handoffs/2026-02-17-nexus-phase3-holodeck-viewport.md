# Nexus Phase 3: Holodeck Terminal Viewport — Implementation Handoff

**Date:** 2026-02-17
**Commit:** `10bb092` on `main`
**Tests:** 225 passing (18 nexus-holodeck + 207 nexus-tui), 0 warnings

## What Was Done

Implemented the full Phase 3 plan from `thoughts/shared/plans/2026-02-17-nexus-option-d-jarvis-cockpit.md`, delivering a headless Bevy renderer embedded in the Nexus TUI with terminal graphics output.

### Work Packages Completed

| WP | Description | Status |
|----|-------------|--------|
| 3.0 | Delete holodeck-core (stub crate) | Done |
| 3.1 | Kitty protocol chunking (4096-byte chunks) | Done |
| 3.2 | Sixel nearest-neighbor color matching | Done |
| 3.3 | Terminal protocol detection improvements | Done |
| 3.4 | Stateful holodeck viewport widget | Done |
| 3.5 | Layout integration (cockpit, focused modes) | Done |
| 3.6 | Keybinds (Space+d) and app integration | Done |
| 3.7 | Headless Bevy renderer (offscreen, threaded) | Done |
| 3.8 | Wire together (event loop, frame streaming) | Done |

### Architecture

```
[Bevy Thread (std::thread)]              [Tokio/TUI Thread]
  DefaultPlugins, primary_window: None     ratatui event loop
  Camera3d -> RenderTarget::Image          reads watch::Receiver<Vec<u8>>
  extract_and_send_frame() copies pixels   encodes to Kitty/Sixel/HalfBlock
  Sends via watch::Sender                  writes escape sequences post-flush
  Receives events via mpsc::Receiver       sends events via mpsc::Sender
  30fps via ScheduleRunnerPlugin           16ms tick rate
```

### Key Files

| File | Role |
|------|------|
| `nexus/crates/nexus-holodeck/src/headless.rs` | Bevy headless renderer, thread management, frame streaming |
| `nexus/crates/nexus-holodeck/src/terminal_encode.rs` | Kitty/Sixel/HalfBlock encoding, protocol detection |
| `nexus/crates/nexus-tui/src/widgets/holodeck_viewport.rs` | StatefulWidget, frame hash dedup, HalfBlock buffer rendering |
| `nexus/crates/nexus-tui/src/layout.rs` | Cockpit/Focused holodeck viewport areas, FocusedPane::HolodeckViewport |
| `nexus/crates/nexus-tui/src/keybinds.rs` | Space+d toggle, ToggleHolodeck action |
| `nexus/crates/nexus-tui/src/app.rs` | Event loop integration, post-flush escape output, viewport state |
| `nexus/crates/nexus-tui/src/state.rs` | show_holodeck_viewport, holodeck_frame, holodeck_connected |

### What Was Removed

- `nexus/crates/holodeck-core/` — Was pure stubs (`Camera = f32`, `Entity = u32`, `Shader = &'static str`). Provided zero value. nexus-holodeck is the real library crate.

## What's Not Yet Done (Follow-Up Work)

1. **Resize handling** — `HolodeckEvent::Resize` is received but render target isn't actually resized yet. Need to recreate the `Image` asset with new dimensions.

2. **Mouse/key forwarding** — Events are plumbed through but not acted upon in the Bevy scene. Need ray picking for mouse clicks, key input for camera control.

3. **Full holodeck scene** — Current scene is a demo (grid + cubes). Needs integration with the real autopoiesis agent visualization (agent spheres, thought particles, connection spines, etc.).

4. **GPU availability fallback** — `HeadlessHolodeck::start()` will panic if no GPU is available. Should detect GPU availability and fall back to a synthetic frame generator or HalfBlock-only mode.

5. **Frame throttling** — Kitty/Sixel escape sequences are large. Should throttle to max 10fps for graphics protocols and only re-encode when frames actually change (hash dedup is in place but throttling isn't).

6. **Cursor positioning** — Kitty/Sixel output currently writes to wherever the cursor is. Should use `crossterm::cursor::MoveTo` to position at the viewport area before writing escape sequences.

7. **Terminal cell size detection** — For proper Kitty/Sixel output, need to know terminal cell dimensions in pixels. Can query via `\x1b[16t` escape sequence or use `TIOCGWINSZ` ioctl.

## Verification

```bash
# Check compilation
cargo check --workspace

# Run holodeck tests (encoding, channel streaming)
cargo test -p nexus-holodeck

# Run TUI tests (widget rendering, layout, keybinds, app integration)
cargo test -p nexus-tui

# Manual test: run nexus TUI, press Space+d to toggle viewport
# In Kitty/WezTerm/Ghostty: should see "[Kitty] Rendering..." status
# In other terminals: should see HalfBlock colored cells
```
