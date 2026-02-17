//! Autopoiesis Holodeck — 3D Spatial Operating System
//!
//! A Bevy-based 3D frontend for the Autopoiesis agent platform.
//! Connects to the Common Lisp backend over WebSocket and visualizes
//! agents, thoughts, snapshots, and blocking requests in a Tron-aesthetic
//! spatial environment.
//!
//! # Architecture
//!
//! The app is organized as a plugin hierarchy:
//! - `ConnectionPlugin` — WebSocket lifecycle, channel bridge, event dispatch
//! - `ScenePlugin` — 3D environment, lighting, camera, bloom
//! - `AgentPlugin` — Agent entity lifecycle, particles, layout, selection
//! - `UiPlugin` — egui panels: HUD, command bar, agent detail, notifications

mod plugins;
mod protocol;
mod rendering;
mod state;
mod systems;
mod ui;

use bevy::prelude::*;
use bevy_egui::EguiPlugin;
use bevy_panorbit_camera::PanOrbitCameraPlugin;

use plugins::agent_plugin::AgentPlugin;
use plugins::connection_plugin::ConnectionPlugin;
use plugins::scene_plugin::ScenePlugin;
use plugins::ui_plugin::UiPlugin;

fn main() {
    App::new()
        // Bevy defaults with custom window
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: "Autopoiesis Holodeck".into(),
                resolution: (1600.0, 900.0).into(),
                ..default()
            }),
            ..default()
        }))
        // Third-party plugins
        .add_plugins(EguiPlugin)
        .add_plugins(PanOrbitCameraPlugin)
        // Our plugins
        .add_plugins(ConnectionPlugin::default())
        .add_plugins(ScenePlugin)
        .add_plugins(AgentPlugin)
        .add_plugins(UiPlugin)
        .run();
}
