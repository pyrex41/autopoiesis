//! Bevy events generated from backend WebSocket messages.
//!
//! Each variant corresponds to a server push or response that systems
//! should react to.

use bevy::prelude::*;
use uuid::Uuid;

use crate::protocol::types::*;

// ---------------------------------------------------------------------------
// Connection events
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct BackendConnected;

#[derive(Event, Debug, Clone)]
pub struct BackendDisconnected {
    pub reason: String,
}

#[derive(Event, Debug, Clone)]
pub struct BackendReconnecting {
    pub attempt: u32,
}

#[derive(Event, Debug, Clone)]
pub struct SystemInfoReceived(pub SystemInfoData);

// ---------------------------------------------------------------------------
// Agent events
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct AgentListReceived {
    pub agents: Vec<AgentData>,
}

#[derive(Event, Debug, Clone)]
pub struct AgentCreatedEvent {
    pub agent: AgentData,
}

#[derive(Event, Debug, Clone)]
pub struct AgentStateChangedEvent {
    pub agent_id: Uuid,
    pub state: AgentState,
}

// ---------------------------------------------------------------------------
// Thought events
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct ThoughtListReceived {
    pub thoughts: Vec<ThoughtData>,
    pub total: u32,
}

#[derive(Event, Debug, Clone)]
pub struct ThoughtReceivedEvent {
    pub agent_id: Uuid,
    pub thought: ThoughtData,
}

// ---------------------------------------------------------------------------
// Snapshot events
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct SnapshotListReceived {
    pub snapshots: Vec<SnapshotData>,
}

#[derive(Event, Debug, Clone)]
pub struct SnapshotCreatedEvent {
    pub snapshot: SnapshotData,
}

// ---------------------------------------------------------------------------
// Branch events
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct BranchListReceived {
    pub branches: Vec<BranchData>,
    pub current: Option<String>,
}

#[derive(Event, Debug, Clone)]
pub struct BranchCreatedEvent {
    pub name: String,
}

#[derive(Event, Debug, Clone)]
pub struct BranchSwitchedEvent {
    pub name: String,
}

// ---------------------------------------------------------------------------
// Blocking events
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct BlockingRequestListReceived {
    pub requests: Vec<BlockingRequestData>,
}

#[derive(Event, Debug, Clone)]
pub struct BlockingRequestEvent {
    pub request: BlockingRequestData,
}

#[derive(Event, Debug, Clone)]
pub struct BlockingRespondedEvent {
    pub request_id: String,
}

// ---------------------------------------------------------------------------
// Step complete
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct StepCompleteEvent {
    pub agent_id: Uuid,
}

// ---------------------------------------------------------------------------
// Generic event bus
// ---------------------------------------------------------------------------

#[derive(Event, Debug, Clone)]
pub struct BackendEvent {
    pub event: EventData,
}
