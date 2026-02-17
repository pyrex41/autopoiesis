//! Bevy Components: attached to ECS entities in the 3D scene.

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
        Self { velocity: Vec3::ZERO, pinned: false, mass: 1.0 }
    }
}

#[derive(Component, Debug)]
pub struct SelectionRing;

#[derive(Component, Debug)]
pub struct AgentLabel;

#[derive(Component, Debug)]
pub struct GridFloor;
