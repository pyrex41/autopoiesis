//! Bevy Resources: global state shared across systems.

use std::collections::HashMap;

use bevy::prelude::*;
use crossbeam_channel::{Receiver, Sender};
use uuid::Uuid;

use crate::protocol::client::ConnectionEvent;
use crate::protocol::types::*;

// ---------------------------------------------------------------------------
// WebSocket channel handles
// ---------------------------------------------------------------------------

/// Inbound channel from the WebSocket thread (server → Bevy).
#[derive(Resource)]
pub struct WsInbound(pub Receiver<ConnectionEvent>);

/// Outbound channel to the WebSocket thread (Bevy → server).
#[derive(Resource)]
pub struct WsOutbound(pub Sender<ClientMessage>);

// ---------------------------------------------------------------------------
// Connection status
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Reconnecting { attempt: u32 },
    Connected,
}

#[derive(Resource, Debug)]
pub struct ConnectionStatus {
    pub state: ConnectionState,
    pub server_version: String,
    pub agent_count: u32,
    pub connection_count: u32,
}

impl Default for ConnectionStatus {
    fn default() -> Self {
        Self {
            state: ConnectionState::Disconnected,
            server_version: String::new(),
            agent_count: 0,
            connection_count: 0,
        }
    }
}

// ---------------------------------------------------------------------------
// Agent registry
// ---------------------------------------------------------------------------

/// Central registry of all known agents, keyed by UUID.
#[derive(Resource, Debug, Default)]
pub struct AgentRegistry {
    pub agents: HashMap<Uuid, AgentData>,
}

impl AgentRegistry {
    pub fn upsert(&mut self, agent: AgentData) {
        self.agents.insert(agent.id, agent);
    }

    pub fn update_state(&mut self, id: Uuid, state: AgentState) {
        if let Some(a) = self.agents.get_mut(&id) {
            a.state = state;
        }
    }

    pub fn get(&self, id: &Uuid) -> Option<&AgentData> {
        self.agents.get(id)
    }
}

// ---------------------------------------------------------------------------
// Selection
// ---------------------------------------------------------------------------

/// Currently selected agent (if any).
#[derive(Resource, Debug, Default)]
pub struct SelectedAgent {
    pub agent_id: Option<Uuid>,
    pub entity: Option<Entity>,
}

// ---------------------------------------------------------------------------
// Snapshot tree
// ---------------------------------------------------------------------------

/// All known snapshots, keyed by snapshot ID.
#[derive(Resource, Debug, Default)]
pub struct SnapshotTree {
    pub snapshots: HashMap<String, SnapshotData>,
    pub current_branch: Option<String>,
}

impl SnapshotTree {
    pub fn upsert(&mut self, snapshot: SnapshotData) {
        self.snapshots.insert(snapshot.id.clone(), snapshot);
    }
}

// ---------------------------------------------------------------------------
// Thought cache
// ---------------------------------------------------------------------------

/// Recent thoughts for the selected agent.
#[derive(Resource, Debug, Default)]
pub struct ThoughtCache {
    pub thoughts: Vec<ThoughtData>,
    pub agent_id: Option<Uuid>,
}

// ---------------------------------------------------------------------------
// Blocking requests
// ---------------------------------------------------------------------------

/// Active blocking requests awaiting human response.
#[derive(Resource, Debug, Default)]
pub struct BlockingRequests {
    pub requests: Vec<BlockingRequestData>,
}

