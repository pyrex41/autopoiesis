# Qualification Guide

This document explains how to try out the three Rust/Go components of the Autopoiesis platform.

## Nexus TUI

**Build Status:** ✅ Ready (binary exists)

**How to Try:**
```bash
./nexus/target/release/nexus --offline
```

**Expected Behavior:**
- Launches a full terminal UI with agent list, thought streams, chat interface, snapshot DAG viewer, and Holodeck viewport.
- Runs in offline demo mode without requiring a backend server.
- Interactive navigation with keyboard shortcuts (help overlay available).
- Shows simulated agent activity and thought flows.

## Holodeck

**Build Status:** ⚠️ Compiles but requires build (slow due to dependencies)

**How to Try:**
```bash
cd holodeck
cargo build --release
./target/release/autopoiesis-holodeck
```

**Expected Behavior:**
- Launches a 3D spatial operating system with agent shells, particle effects, and orbit camera.
- Connects to the same WebSocket backend as Nexus (requires running Autopoiesis server).
- Interactive 3D scene with egui panels for HUD and controls.
- Visualizes agent cognition, connections, and thought particles in real-time.

## Go SDK (apcli)

**Build Status:** ✅ Ready

**How to Try:**
```bash
cd sdk/go
go build ./cmd/apcli
./apcli --help
# Example: ./apcli system  # (requires running Autopoiesis server at localhost:8080)
```

**Expected Behavior:**
- Command-line interface for Autopoiesis Control API.
- Supports 20+ commands: system info, agent management, snapshots, branches, etc.
- REST client with JSON output (or text mode).
- Can connect to running Autopoiesis instance for full functionality.</content>
<parameter name="filePath">QUALIFICATION.md