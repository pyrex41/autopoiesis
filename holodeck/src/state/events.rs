//! Bevy Events for UI actions (outbound: user → backend).
//!
//! These are fired by egui panels and command bar, then picked up by
//! systems that serialize them into `ClientMessage` and push them down
//! the outbound WebSocket channel.

use bevy::prelude::*;
use uuid::Uuid;

/// User wants to create a new agent.
#[derive(Event, Debug, Clone)]
pub struct SendCreateAgent {
    pub name: String,
    pub capabilities: Vec<String>,
}

/// User wants to perform an action on an agent (start/stop/pause/resume).
#[derive(Event, Debug, Clone)]
pub struct SendAgentAction {
    pub agent_id: Uuid,
    pub action: String,
}

/// User wants to step an agent through one cognitive cycle.
#[derive(Event, Debug, Clone)]
pub struct SendStepAgent {
    pub agent_id: Uuid,
}

/// User wants to inject a thought into an agent.
#[derive(Event, Debug, Clone)]
pub struct SendInjectThought {
    pub agent_id: Uuid,
    pub content: String,
    pub thought_type: String,
}

/// User wants to create a snapshot.
#[derive(Event, Debug, Clone)]
pub struct SendCreateSnapshot {
    pub agent_id: Uuid,
    pub label: String,
}

/// User wants to respond to a blocking request.
#[derive(Event, Debug, Clone)]
pub struct SendRespondBlocking {
    pub request_id: String,
    pub response: String,
}

/// User wants to fetch thoughts for an agent.
#[derive(Event, Debug, Clone)]
pub struct SendGetThoughts {
    pub agent_id: Uuid,
    pub limit: u32,
}

/// User wants to select an agent in the 3D view.
#[derive(Event, Debug, Clone)]
pub struct SelectAgentEvent {
    pub agent_id: Uuid,
}

/// User wants to deselect the current selection.
#[derive(Event, Debug, Clone)]
pub struct DeselectEvent;

/// Generic command string from the command bar.
#[derive(Event, Debug, Clone)]
pub struct SendCommand {
    pub raw: String,
}
