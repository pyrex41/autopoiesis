//! Bundles agent visualization systems.
//!
//! Handles spawning/updating agent entities, thought particles,
//! snapshot tree, force layout, selection, animations, and blocking prompts.

use bevy::prelude::*;
use bevy_tweening::asset_animator_system;

use crate::shaders::agent_shell_material::AgentShellMaterial;
use crate::state::components::AgentMetrics;
use crate::systems::{agents, animation, blocking, capabilities, disconnect_visual, layout, particles, selection, snapshots, spine, step_complete, task_ring, thoughts};

/// Plugin for agent and snapshot visualization.
pub struct AgentPlugin;

impl Plugin for AgentPlugin {
    fn build(&self, app: &mut App) {
        app
            // Entity lookup resources
            .init_resource::<agents::AgentEntityMap>()
            .init_resource::<snapshots::SnapshotEntityMap>()
            .init_resource::<AgentMetrics>()
            // Particle presets + task ring meshes
            .add_systems(Startup, (
                particles::init_particle_presets,
                task_ring::init_task_ring_meshes,
            ))
            // Agent entity lifecycle
            .add_systems(Update, (
                agents::spawn_agents_from_list,
                agents::spawn_agent_on_created,
                agents::update_agent_state,
            ))
            // Thought particles (GPU-driven via bevy_hanabi)
            .add_systems(Update, thoughts::spawn_thought_particles)
            // Agent-attached persistent particles
            .add_systems(Update, (
                particles::attach_agent_particles,
                particles::update_agent_particles,
            ))
            // Snapshot tree
            .add_systems(Update, snapshots::build_snapshot_tree)
            // Selection
            .add_systems(Update, (
                selection::handle_agent_click,
                selection::handle_deselect,
                selection::deselect_on_escape,
            ))
            // Animation
            .add_systems(Update, (
                animation::animate_agents,
                animation::thought_glow_spike,
                animation::decay_glow,
                animation::sync_glow_to_shader,
                animation::animate_selection_ring,
            ))
            // Blocking prompts
            .add_systems(Update, (
                blocking::spawn_blocking_indicators,
                blocking::handle_blocking_option_click,
                blocking::despawn_blocking_indicators,
                blocking::animate_blocking_prompts,
            ))
            // Step-complete feedback
            .add_systems(Update, (
                step_complete::on_step_complete,
                step_complete::animate_step_complete_particles,
            ))
            // Status spine (Dead Space health bar)
            .add_systems(Update, (
                spine::attach_spine_to_agents,
                spine::update_spine_system,
            ))
            // Task progress ring
            .add_systems(Update, (
                task_ring::attach_task_ring_to_agents,
                task_ring::update_task_ring,
                task_ring::task_completion_burst,
            ))
            // Capability modules (orbiting shapes)
            .add_systems(Update, (
                capabilities::spawn_capability_modules_from_list,
                capabilities::spawn_capability_modules_on_created,
                capabilities::orbit_capabilities,
                capabilities::highlight_active_capability,
                capabilities::decay_capability_glow,
            ))
            // Connection visual feedback (desaturate on disconnect, flash on reconnect)
            .init_resource::<disconnect_visual::ConnectionOverlay>()
            .add_systems(Update, (
                disconnect_visual::on_disconnect,
                disconnect_visual::on_reconnect,
                disconnect_visual::tick_overlay,
                disconnect_visual::render_connection_overlay,
            ))
            // Force-directed layout runs in FixedUpdate for determinism
            .add_systems(FixedUpdate, layout::force_directed_layout)
            // Asset animation for custom materials (bevy_tweening)
            .add_systems(Update, asset_animator_system::<AgentShellMaterial, MeshMaterial3d<AgentShellMaterial>>);
    }
}
