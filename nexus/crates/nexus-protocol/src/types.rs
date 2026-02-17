use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AgentState {
    #[default]
    Initialized,
    Running,
    Paused,
    Stopped,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThoughtType {
    Observation,
    Decision,
    Action,
    Reflection,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentData {
    pub id: Uuid,
    pub name: String,
    pub state: AgentState,
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub parent: Option<Uuid>,
    #[serde(default)]
    pub children: Vec<Uuid>,
    #[serde(default)]
    pub thought_count: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThoughtData {
    pub id: Uuid,
    #[serde(default)]
    pub timestamp: f64,
    #[serde(rename = "type")]
    pub thought_type: ThoughtType,
    #[serde(default)]
    pub confidence: f64,
    #[serde(default)]
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchData {
    pub name: String,
    #[serde(default)]
    pub head: Option<String>,
    #[serde(default)]
    pub created: Option<f64>,
}

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
    SetStreamFormat { format: String },
    Subscribe { channel: String },
    Unsubscribe { channel: String },
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
    SwitchBranch { name: String },
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_state_roundtrip() {
        for state in [
            AgentState::Initialized,
            AgentState::Running,
            AgentState::Paused,
            AgentState::Stopped,
        ] {
            let json = serde_json::to_string(&state).unwrap();
            let back: AgentState = serde_json::from_str(&json).unwrap();
            assert_eq!(state, back);
        }
    }

    #[test]
    fn test_agent_state_default() {
        assert_eq!(AgentState::default(), AgentState::Initialized);
    }

    #[test]
    fn test_thought_type_roundtrip() {
        for tt in [
            ThoughtType::Observation,
            ThoughtType::Decision,
            ThoughtType::Action,
            ThoughtType::Reflection,
        ] {
            let json = serde_json::to_string(&tt).unwrap();
            let back: ThoughtType = serde_json::from_str(&json).unwrap();
            assert_eq!(tt, back);
        }
    }

    #[test]
    fn test_client_message_ping() {
        let msg = ClientMessage::Ping;
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "ping");
    }

    #[test]
    fn test_client_message_system_info() {
        let msg = ClientMessage::SystemInfo;
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "system_info");
    }

    #[test]
    fn test_client_message_set_stream_format() {
        let msg = ClientMessage::SetStreamFormat {
            format: "msgpack".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "set_stream_format");
        assert_eq!(v["format"], "msgpack");
    }

    #[test]
    fn test_client_message_subscribe() {
        let msg = ClientMessage::Subscribe {
            channel: "agents".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "subscribe");
        assert_eq!(v["channel"], "agents");
    }

    #[test]
    fn test_client_message_list_agents() {
        let msg = ClientMessage::ListAgents;
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "list_agents");
    }

    #[test]
    fn test_client_message_get_agent() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::GetAgent { agent_id: id };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "get_agent");
        assert_eq!(v["agentId"], id.to_string());
    }

    #[test]
    fn test_client_message_create_agent() {
        let msg = ClientMessage::CreateAgent {
            name: "test-agent".to_string(),
            capabilities: vec!["observe".to_string(), "decide".to_string()],
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "create_agent");
        assert_eq!(v["name"], "test-agent");
        assert_eq!(v["capabilities"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_client_message_agent_action() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::AgentAction {
            agent_id: id,
            action: "start".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "agent_action");
        assert_eq!(v["action"], "start");
    }

    #[test]
    fn test_client_message_step_agent_no_env() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::StepAgent {
            agent_id: id,
            environment: None,
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "step_agent");
        assert!(v.get("environment").is_none());
    }

    #[test]
    fn test_client_message_step_agent_with_env() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::StepAgent {
            agent_id: id,
            environment: Some(serde_json::json!({"key": "value"})),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "step_agent");
        assert_eq!(v["environment"]["key"], "value");
    }

    #[test]
    fn test_client_message_get_thoughts() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::GetThoughts {
            agent_id: id,
            limit: Some(10),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "get_thoughts");
        assert_eq!(v["limit"], 10);
    }

    #[test]
    fn test_client_message_inject_thought() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::InjectThought {
            agent_id: id,
            content: "test thought".to_string(),
            thought_type: "observation".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "inject_thought");
        assert_eq!(v["content"], "test thought");
        assert_eq!(v["thoughtType"], "observation");
    }

    #[test]
    fn test_client_message_list_snapshots() {
        let msg = ClientMessage::ListSnapshots { limit: None };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "list_snapshots");
        assert!(v.get("limit").is_none());
    }

    #[test]
    fn test_client_message_get_snapshot() {
        let msg = ClientMessage::GetSnapshot {
            snapshot_id: "snap-123".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "get_snapshot");
        assert_eq!(v["snapshotId"], "snap-123");
    }

    #[test]
    fn test_client_message_create_snapshot() {
        let id = Uuid::new_v4();
        let msg = ClientMessage::CreateSnapshot {
            agent_id: id,
            label: "checkpoint".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "create_snapshot");
        assert_eq!(v["label"], "checkpoint");
    }

    #[test]
    fn test_client_message_list_branches() {
        let msg = ClientMessage::ListBranches;
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "list_branches");
    }

    #[test]
    fn test_client_message_create_branch() {
        let msg = ClientMessage::CreateBranch {
            name: "feature-x".to_string(),
            from_snapshot: "snap-abc".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "create_branch");
        assert_eq!(v["name"], "feature-x");
        assert_eq!(v["fromSnapshot"], "snap-abc");
    }

    #[test]
    fn test_client_message_switch_branch() {
        let msg = ClientMessage::SwitchBranch {
            name: "main".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "switch_branch");
        assert_eq!(v["name"], "main");
    }

    #[test]
    fn test_client_message_list_blocking_requests() {
        let msg = ClientMessage::ListBlockingRequests;
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "list_blocking_requests");
    }

    #[test]
    fn test_client_message_respond_blocking() {
        let msg = ClientMessage::RespondBlocking {
            blocking_request_id: "req-42".to_string(),
            response: "approved".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "respond_blocking");
        assert_eq!(v["blockingRequestId"], "req-42");
        assert_eq!(v["response"], "approved");
    }

    #[test]
    fn test_client_message_get_events() {
        let msg = ClientMessage::GetEvents {
            limit: Some(50),
            event_type: Some("agent_action".to_string()),
            agent_id: None,
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "get_events");
        assert_eq!(v["limit"], 50);
        assert_eq!(v["eventType"], "agent_action");
        assert!(v.get("agentId").is_none());
    }

    #[test]
    fn test_client_message_unsubscribe() {
        let msg = ClientMessage::Unsubscribe {
            channel: "thoughts".to_string(),
        };
        let json = serde_json::to_string(&msg).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(v["type"], "unsubscribe");
        assert_eq!(v["channel"], "thoughts");
    }

    #[test]
    fn test_server_message_pong() {
        let json = r#"{"type": "pong"}"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        assert!(matches!(msg, ServerMessage::Pong));
    }

    #[test]
    fn test_server_message_system_info() {
        let json = r#"{
            "type": "system_info",
            "version": "0.1.0",
            "health": "healthy",
            "agentCount": 3,
            "connectionCount": 1
        }"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::SystemInfo(info) => {
                assert_eq!(info.version, "0.1.0");
                assert_eq!(info.health, "healthy");
                assert_eq!(info.agent_count, 3);
                assert_eq!(info.connection_count, 1);
            }
            _ => panic!("Expected SystemInfo"),
        }
    }

    #[test]
    fn test_server_message_subscribed() {
        let json = r#"{"type": "subscribed", "channel": "agents"}"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::Subscribed { channel } => assert_eq!(channel, "agents"),
            _ => panic!("Expected Subscribed"),
        }
    }

    #[test]
    fn test_server_message_agents() {
        let id = Uuid::new_v4();
        let json = format!(
            r#"{{
                "type": "agents",
                "agents": [{{
                    "id": "{}",
                    "name": "agent-1",
                    "state": "running",
                    "capabilities": ["observe"],
                    "children": [],
                    "thoughtCount": 5
                }}]
            }}"#,
            id
        );
        let msg: ServerMessage = serde_json::from_str(&json).unwrap();
        match msg {
            ServerMessage::Agents { agents } => {
                assert_eq!(agents.len(), 1);
                assert_eq!(agents[0].name, "agent-1");
                assert_eq!(agents[0].state, AgentState::Running);
                assert_eq!(agents[0].thought_count, 5);
            }
            _ => panic!("Expected Agents"),
        }
    }

    #[test]
    fn test_server_message_agent_state_changed() {
        let id = Uuid::new_v4();
        let json = format!(
            r#"{{"type": "agent_state_changed", "agentId": "{}", "state": "paused"}}"#,
            id
        );
        let msg: ServerMessage = serde_json::from_str(&json).unwrap();
        match msg {
            ServerMessage::AgentStateChanged { agent_id, state } => {
                assert_eq!(agent_id, id);
                assert_eq!(state, AgentState::Paused);
            }
            _ => panic!("Expected AgentStateChanged"),
        }
    }

    #[test]
    fn test_server_message_thoughts() {
        let id = Uuid::new_v4();
        let json = format!(
            r#"{{
                "type": "thoughts",
                "thoughts": [{{
                    "id": "{}",
                    "timestamp": 1234.5,
                    "type": "observation",
                    "confidence": 0.95,
                    "content": "I see something"
                }}],
                "total": 1
            }}"#,
            id
        );
        let msg: ServerMessage = serde_json::from_str(&json).unwrap();
        match msg {
            ServerMessage::Thoughts { thoughts, total } => {
                assert_eq!(thoughts.len(), 1);
                assert_eq!(thoughts[0].thought_type, ThoughtType::Observation);
                assert_eq!(thoughts[0].confidence, 0.95);
                assert_eq!(total, 1);
            }
            _ => panic!("Expected Thoughts"),
        }
    }

    #[test]
    fn test_server_message_snapshots() {
        let json = r#"{
            "type": "snapshots",
            "snapshots": [{
                "id": "snap-1",
                "timestamp": 100.0
            }]
        }"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::Snapshots { snapshots } => {
                assert_eq!(snapshots.len(), 1);
                assert_eq!(snapshots[0].id, "snap-1");
            }
            _ => panic!("Expected Snapshots"),
        }
    }

    #[test]
    fn test_server_message_branches() {
        let json = r#"{
            "type": "branches",
            "branches": [{"name": "main", "head": "snap-1"}],
            "current": "main"
        }"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::Branches { branches, current } => {
                assert_eq!(branches.len(), 1);
                assert_eq!(branches[0].name, "main");
                assert_eq!(current, Some("main".to_string()));
            }
            _ => panic!("Expected Branches"),
        }
    }

    #[test]
    fn test_server_message_blocking_requests() {
        let json = r#"{
            "type": "blocking_requests",
            "requests": [{
                "id": "req-1",
                "prompt": "Continue?",
                "options": ["yes", "no"]
            }]
        }"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::BlockingRequests { requests } => {
                assert_eq!(requests.len(), 1);
                assert_eq!(requests[0].prompt, "Continue?");
                assert_eq!(requests[0].options.len(), 2);
            }
            _ => panic!("Expected BlockingRequests"),
        }
    }

    #[test]
    fn test_server_message_events() {
        let json = r#"{
            "type": "events",
            "events": [{
                "type": "agent_action",
                "timestamp": 99.0,
                "data": {"action": "start"}
            }]
        }"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::Events { events } => {
                assert_eq!(events.len(), 1);
                assert_eq!(events[0].event_type, "agent_action");
            }
            _ => panic!("Expected Events"),
        }
    }

    #[test]
    fn test_server_message_unknown() {
        let json = r#"{"type": "some_future_message", "data": 42}"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        assert!(matches!(msg, ServerMessage::Unknown));
    }

    #[test]
    fn test_server_message_stream_format_set() {
        let json = r#"{"type": "stream_format_set"}"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        assert!(matches!(msg, ServerMessage::StreamFormatSet));
    }

    #[test]
    fn test_server_message_step_complete() {
        let id = Uuid::new_v4();
        let json = format!(
            r#"{{"type": "step_complete", "agentId": "{}", "result": {{"status": "ok"}}}}"#,
            id
        );
        let msg: ServerMessage = serde_json::from_str(&json).unwrap();
        match msg {
            ServerMessage::StepComplete { agent_id, result } => {
                assert_eq!(agent_id, id);
                assert_eq!(result["status"], "ok");
            }
            _ => panic!("Expected StepComplete"),
        }
    }

    #[test]
    fn test_server_message_snapshot_created() {
        let json = r#"{
            "type": "snapshot_created",
            "snapshot": {"id": "snap-new", "timestamp": 200.0}
        }"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::SnapshotCreated { snapshot } => {
                assert_eq!(snapshot.id, "snap-new");
            }
            _ => panic!("Expected SnapshotCreated"),
        }
    }

    #[test]
    fn test_server_message_blocking_responded() {
        let json =
            r#"{"type": "blocking_responded", "blockingRequestId": "req-99"}"#;
        let msg: ServerMessage = serde_json::from_str(json).unwrap();
        match msg {
            ServerMessage::BlockingResponded {
                blocking_request_id,
            } => {
                assert_eq!(blocking_request_id, "req-99");
            }
            _ => panic!("Expected BlockingResponded"),
        }
    }

    #[test]
    fn test_agent_data_optional_fields() {
        let id = Uuid::new_v4();
        let json = format!(
            r#"{{"id": "{}", "name": "minimal", "state": "initialized", "capabilities": []}}"#,
            id
        );
        let agent: AgentData = serde_json::from_str(&json).unwrap();
        assert_eq!(agent.name, "minimal");
        assert!(agent.parent.is_none());
        assert!(agent.children.is_empty());
        assert_eq!(agent.thought_count, 0);
    }

    #[test]
    fn test_thought_data_optional_fields() {
        let id = Uuid::new_v4();
        let json = format!(
            r#"{{"id": "{}", "type": "decision", "content": "choose A"}}"#,
            id
        );
        let thought: ThoughtData = serde_json::from_str(&json).unwrap();
        assert_eq!(thought.thought_type, ThoughtType::Decision);
        assert_eq!(thought.timestamp, 0.0);
        assert_eq!(thought.confidence, 0.0);
        assert!(thought.provenance.is_none());
        assert!(thought.source.is_none());
        assert!(thought.rationale.is_none());
        assert!(thought.alternatives.is_empty());
    }
}
