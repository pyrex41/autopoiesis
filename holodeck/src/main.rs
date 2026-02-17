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
//! - `ShaderPlugin` — Custom material shaders (grid, agent shell, energy beam, hologram)
//! - `ConnectionPlugin` — WebSocket lifecycle, channel bridge, event dispatch
//! - `ScenePlugin` — 3D environment, lighting, camera, bloom
//! - `AgentPlugin` — Agent entity lifecycle, particles, layout, selection
//! - `UiPlugin` — egui panels: HUD, command bar, agent detail, notifications

mod config;
mod plugins;
mod protocol;
mod rendering;
mod shaders;
mod state;
mod systems;
mod ui;

use bevy::prelude::*;
use bevy_egui::EguiPlugin;
use bevy_hanabi::prelude::HanabiPlugin;
use bevy_panorbit_camera::PanOrbitCameraPlugin;
use bevy_tweening::TweeningPlugin;

use config::HolodeckConfig;
use plugins::agent_plugin::AgentPlugin;
use plugins::connection_plugin::ConnectionPlugin;
use plugins::scene_plugin::ScenePlugin;
use plugins::shader_plugin::ShaderPlugin;
use plugins::ui_plugin::UiPlugin;

fn main() {
    let config = config::load_config();

    App::new()
        // Bevy defaults with custom window
        .add_plugins(DefaultPlugins.set(WindowPlugin {
            primary_window: Some(Window {
                title: config.window.title.clone(),
                resolution: (config.window.width as f32, config.window.height as f32).into(),
                ..default()
            }),
            ..default()
        }))
        // Configuration resource (available to all systems)
        .insert_resource(config)
        // Third-party plugins
        .add_plugins(EguiPlugin)
        .add_plugins(PanOrbitCameraPlugin)
        // Custom shader materials (must register before scene uses them)
        .add_plugins(ShaderPlugin)
        // Particle effects (GPU-accelerated)
        .add_plugins(HanabiPlugin)
        // Animation tweening
        .add_plugins(TweeningPlugin)
        // Our plugins
        .add_plugins(ConnectionPlugin::default())
        .add_plugins(ScenePlugin)
        .add_plugins(AgentPlugin)
        .add_plugins(UiPlugin)
        .run();
}
