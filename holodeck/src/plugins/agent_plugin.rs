//! Bundles agent visualization systems.
//!
//! Handles spawning/updating agent entities, thought particles,
//! snapshot tree, force layout, selection, animations, and blocking prompts.

use bevy::prelude::*;

use crate::systems::{agents, animation, blocking, layout, selection, snapshots, thoughts};

/// Plugin for agent and snapshot visualization.
pub struct AgentPlugin;

impl Plugin for AgentPlugin {
    fn build(&self, app: &mut App) {
        app
            // Entity lookup resources
            .init_resource::<agents::AgentEntityMap>()
            .init_resource::<snapshots::SnapshotEntityMap>()
            // Agent entity lifecycle
            .add_systems(Update, (
                agents::spawn_agents_from_list,
                agents::spawn_agent_on_created,
                agents::update_agent_state,
            ))
            // Thought particles
            .add_systems(Update, (
                thoughts::spawn_thought_particles,
                thoughts::animate_thought_particles,
            ))
            // Snapshot tree
            .add_systems(Update, snapshots::build_snapshot_tree)
            // Selection
            .add_systems(Update, (
                selection::handle_agent_click,
                selection::handle_deselect,
            ))
            // Animation
            .add_systems(Update, (
                animation::animate_agents,
                animation::thought_glow_spike,
                animation::decay_glow,
                animation::animate_selection_ring,
            ))
            // Blocking prompts
            .add_systems(Update, (
                blocking::spawn_blocking_indicators,
                blocking::despawn_blocking_indicators,
                blocking::animate_blocking_prompts,
            ))
            // Force-directed layout runs in FixedUpdate for determinism
            .add_systems(FixedUpdate, layout::force_directed_layout);
    }
}
