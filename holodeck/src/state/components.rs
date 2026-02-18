//! Bevy Components: attached to ECS entities in the 3D scene.

use std::collections::HashMap;

use bevy::prelude::*;
use uuid::Uuid;

use crate::protocol::types::{AgentState, ThoughtType};

#[derive(Component, Debug)]
pub struct AgentNode {
    pub agent_id: Uuid,
    pub name: String,
    pub state: AgentState,
    pub capabilities: Vec<String>,
    pub thought_count: u32,
}

#[derive(Component, Debug)]
pub struct AgentVisual {
    pub base_color: Color,
    pub pulse_phase: f32,
    pub glow_intensity: f32,
}

impl AgentVisual {
    pub fn color_for_state(state: &AgentState) -> Color {
        match state {
            AgentState::Initialized => Color::srgb(0.0, 0.533, 1.0),
            AgentState::Running => Color::srgb(0.0, 1.0, 0.533),
            AgentState::Paused => Color::srgb(1.0, 0.667, 0.0),
            AgentState::Stopped => Color::srgb(1.0, 0.2, 0.267),
        }
    }
}

/// Marker: entity can be picked (Bevy 0.15 built-in picking).
#[derive(Component, Debug)]
pub struct Selectable;

#[derive(Component, Debug)]
pub struct Selected;

#[derive(Component, Debug)]
pub struct ThoughtParticle {
    pub thought_id: Uuid,
    pub agent_id: Uuid,
    pub thought_type: ThoughtType,
    pub lifetime: Timer,
    pub velocity: Vec3,
}

#[derive(Component, Debug)]
pub struct SnapshotNode {
    pub snapshot_id: String,
    pub parent: Option<String>,
    pub hash: Option<String>,
    pub metadata: Option<String>,
    pub timestamp: f64,
}

#[derive(Component, Debug)]
pub struct ConnectionBeam {
    pub from: Entity,
    pub to: Entity,
    pub color: Color,
}

#[derive(Component, Debug)]
pub struct BlockingPrompt {
    pub request_id: String,
    pub prompt_text: String,
    pub options: Vec<String>,
}

#[derive(Component, Debug)]
pub struct ForceNode {
    pub velocity: Vec3,
    pub pinned: bool,
    pub mass: f32,
}

impl Default for ForceNode {
    fn default() -> Self {
        Self {
            velocity: Vec3::ZERO,
            pinned: false,
            mass: 1.0,
        }
    }
}

#[derive(Component, Debug)]
pub struct SelectionRing;

#[derive(Component, Debug)]
pub struct AgentLabel;

#[derive(Component, Debug)]
pub struct GridFloor;

#[derive(Component, Debug)]
pub struct BlockingOptionButton {
    pub request_id: String,
    pub option_text: String,
}

#[derive(Component, Debug)]
pub struct StepCompleteParticle {
    pub lifetime: Timer,
    pub velocity: Vec3,
}

/// Tracks the particle effect child entity attached to an agent.
#[derive(Component, Debug)]
pub struct AgentParticles {
    pub effect_entity: Entity,
}

// --- Phase 2: Diegetic Agent Entity Components ---

/// Marker for the status spine (Dead Space health bar) parent entity.
#[derive(Component, Debug)]
pub struct StatusSpine;

/// Individual spine segment (child of StatusSpine).
#[derive(Component, Debug)]
pub struct SpineSegment {
    pub index: usize,
    pub health_value: f32,
}

/// Orbiting capability module shape.
#[derive(Component, Debug)]
pub struct CapabilityModule {
    pub capability_name: String,
    pub orbit_radius: f32,
    pub orbit_phase: f32,
    pub orbit_speed: f32,
    pub is_active: bool,
}

/// Task progress ring (partial torus around agent).
#[derive(Component, Debug)]
pub struct TaskRing {
    pub progress: f32,
    pub task_name: String,
}

/// Marker for compound agent entity (has spine, modules, ring, particles as children).
#[derive(Component, Debug)]
pub struct AgentCompound;

/// Per-agent metrics driving visual elements.
#[derive(Debug, Clone, Default)]
pub struct AgentMetricData {
    pub cognitive_load: f32,
    pub token_usage: f32,
    pub task_progress: f32,
    pub active_capability: Option<String>,
}

/// Resource tracking metrics for all agents.
#[derive(Resource, Debug, Default)]
pub struct AgentMetrics {
    pub metrics: HashMap<Uuid, AgentMetricData>,
}
