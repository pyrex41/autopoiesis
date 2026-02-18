//! Serde structs for all backend message types.
//!
//! The backend speaks JSON for control messages and MessagePack for
//! real-time push data. These types handle both directions.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentState {
    Initialized,
    Running,
    Paused,
    Stopped,
}

impl Default for AgentState {
    fn default() -> Self {
        Self::Initialized
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThoughtType {
    Observation,
    Decision,
    Action,
    Reflection,
}

// Data shapes matching backend serializers.lisp

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentData {
    pub id: Uuid,
    pub name: String,
    pub state: AgentState,
    pub capabilities: Vec<String>,
    pub parent: Option<Uuid>,
    pub children: Vec<Uuid>,
    pub thought_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThoughtData {
    pub id: Uuid,
    pub timestamp: f64,
    #[serde(rename = "type")]
    pub thought_type: ThoughtType,
    pub confidence: f64,
    pub content: String,
    #[serde(default)]
    pub provenance: Option<String>,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub rationale: Option<String>,
    #[serde(default)]
    pub alternatives: Vec<String>,
}

/// Backend sends: id, timestamp, parent, hash, metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotData {
    pub id: String,
    #[serde(default)]
    pub parent: Option<String>,
    #[serde(default)]
    pub hash: Option<String>,
    #[serde(default)]
    pub metadata: Option<String>,
    #[serde(default)]
    pub timestamp: f64,
}

/// Backend sends: name, head, created
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchData {
    pub name: String,
    #[serde(default)]
    pub head: Option<String>,
    #[serde(default)]
    pub created: Option<f64>,
}

/// Backend sends: id, prompt, context, options, default, status, createdAt
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BlockingRequestData {
    pub id: String,
    #[serde(default)]
    pub prompt: String,
    #[serde(default)]
    pub context: Option<String>,
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(default, rename = "default")]
    pub default_value: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub created_at: Option<f64>,
}

/// Backend sends: id, type, source, agentId, data, timestamp
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventData {
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default, rename = "type")]
    pub event_type: String,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub agent_id: Option<Uuid>,
    #[serde(default)]
    pub timestamp: f64,
    #[serde(default)]
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfoData {
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub health: String,
    #[serde(default)]
    pub agent_count: u32,
    #[serde(default)]
    pub connection_count: u32,
}

// Client -> Server

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type")]
#[serde(rename_all = "snake_case")]
pub enum ClientMessage {
    Ping,
    SystemInfo,
    #[serde(rename = "set_stream_format")]
    SetStreamFormat {
        format: String,
    },
    Subscribe {
        channel: String,
    },
    Unsubscribe {
        channel: String,
    },
    ListAgents,
    GetAgent {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
    },
    CreateAgent {
        name: String,
        capabilities: Vec<String>,
    },
    AgentAction {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        action: String,
    },
    StepAgent {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        #[serde(skip_serializing_if = "Option::is_none")]
        environment: Option<serde_json::Value>,
    },
    GetThoughts {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        #[serde(skip_serializing_if = "Option::is_none")]
        limit: Option<u32>,
    },
    InjectThought {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        content: String,
        #[serde(rename = "thoughtType")]
        thought_type: String,
    },
    ListSnapshots {
        #[serde(skip_serializing_if = "Option::is_none")]
        limit: Option<u32>,
    },
    GetSnapshot {
        #[serde(rename = "snapshotId")]
        snapshot_id: String,
    },
    CreateSnapshot {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        label: String,
    },
    ListBranches,
    CreateBranch {
        name: String,
        #[serde(rename = "fromSnapshot")]
        from_snapshot: String,
    },
    SwitchBranch {
        name: String,
    },
    ListBlockingRequests,
    RespondBlocking {
        #[serde(rename = "blockingRequestId")]
        blocking_request_id: String,
        response: String,
    },
    GetEvents {
        #[serde(skip_serializing_if = "Option::is_none")]
        limit: Option<u32>,
        #[serde(rename = "eventType", skip_serializing_if = "Option::is_none")]
        event_type: Option<String>,
        #[serde(rename = "agentId", skip_serializing_if = "Option::is_none")]
        agent_id: Option<Uuid>,
    },
}

// Server -> Client

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type")]
#[serde(rename_all = "snake_case")]
pub enum ServerMessage {
    Pong,
    #[serde(rename = "system_info")]
    SystemInfo(SystemInfoData),
    Subscribed {
        channel: String,
    },
    Unsubscribed {
        channel: String,
    },
    #[serde(rename = "stream_format_set")]
    StreamFormatSet,
    Agents {
        agents: Vec<AgentData>,
    },
    Agent {
        agent: AgentData,
    },
    #[serde(rename = "agent_created")]
    AgentCreated {
        agent: AgentData,
    },
    #[serde(rename = "agent_state_changed")]
    AgentStateChanged {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        state: AgentState,
    },
    #[serde(rename = "step_complete")]
    StepComplete {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        #[serde(default)]
        result: serde_json::Value,
    },
    Thoughts {
        thoughts: Vec<ThoughtData>,
        #[serde(default)]
        total: u32,
    },
    #[serde(rename = "thought_added")]
    ThoughtAdded {
        #[serde(rename = "agentId")]
        agent_id: Uuid,
        thought: ThoughtData,
    },
    Snapshots {
        snapshots: Vec<SnapshotData>,
    },
    Snapshot {
        snapshot: SnapshotData,
        #[serde(rename = "agentState", default)]
        agent_state: Option<String>,
    },
    #[serde(rename = "snapshot_created")]
    SnapshotCreated {
        snapshot: SnapshotData,
    },
    Branches {
        branches: Vec<BranchData>,
        #[serde(default)]
        current: Option<String>,
    },
    #[serde(rename = "branch_created")]
    BranchCreated {
        branch: BranchData,
    },
    #[serde(rename = "branch_switched")]
    BranchSwitched {
        branch: BranchData,
    },
    #[serde(rename = "blocking_requests")]
    BlockingRequests {
        requests: Vec<BlockingRequestData>,
    },
    #[serde(rename = "blocking_request")]
    BlockingRequest {
        request: BlockingRequestData,
    },
    #[serde(rename = "blocking_responded")]
    BlockingResponded {
        #[serde(rename = "blockingRequestId")]
        blocking_request_id: String,
    },
    Events {
        events: Vec<EventData>,
    },
    Event {
        event: EventData,
    },
    #[serde(other)]
    Unknown,
}
