use crate::error::ProtocolError;
use crate::types::{ClientMessage, ServerMessage};

pub fn encode_client_message(msg: &ClientMessage) -> Result<String, ProtocolError> {
    serde_json::to_string(msg).map_err(ProtocolError::JsonEncode)
}

pub fn decode_text_frame(text: &str) -> Result<ServerMessage, ProtocolError> {
    serde_json::from_str(text).map_err(ProtocolError::JsonDecode)
}

pub fn decode_binary_frame(data: &[u8]) -> Result<ServerMessage, ProtocolError> {
    rmp_serde::from_slice(data).map_err(ProtocolError::MsgPackDecode)
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn test_encode_ping() {
        let msg = ClientMessage::Ping;
        let json = encode_client_message(&msg).unwrap();
        assert!(json.contains(r#""type":"ping""#));
    }

    #[test]
    fn test_encode_create_agent() {
        let msg = ClientMessage::CreateAgent {
            name: "test".to_string(),
            capabilities: vec!["observe".to_string()],
        };
        let json = encode_client_message(&msg).unwrap();
        assert!(json.contains(r#""type":"create_agent""#));
        assert!(json.contains(r#""name":"test""#));
    }

    #[test]
    fn test_decode_text_pong() {
        let msg = decode_text_frame(r#"{"type": "pong"}"#).unwrap();
        assert!(matches!(msg, ServerMessage::Pong));
    }

    #[test]
    fn test_decode_text_system_info() {
        let json = r#"{
            "type": "system_info",
            "version": "1.0",
            "health": "ok",
            "agentCount": 2,
            "connectionCount": 1
        }"#;
        let msg = decode_text_frame(json).unwrap();
        match msg {
            ServerMessage::SystemInfo(info) => {
                assert_eq!(info.version, "1.0");
                assert_eq!(info.agent_count, 2);
            }
            _ => panic!("Expected SystemInfo"),
        }
    }

    #[test]
    fn test_decode_text_invalid_json() {
        let result = decode_text_frame("not json");
        assert!(result.is_err());
    }

    #[test]
    fn test_roundtrip_encode_decode_agents() {
        let id = Uuid::new_v4();
        // Encode a ListAgents request
        let client_msg = ClientMessage::ListAgents;
        let encoded = encode_client_message(&client_msg).unwrap();
        assert!(encoded.contains("list_agents"));

        // Simulate server response
        let server_json = format!(
            r#"{{
                "type": "agents",
                "agents": [{{
                    "id": "{}",
                    "name": "roundtrip-agent",
                    "state": "running",
                    "capabilities": [],
                    "children": []
                }}]
            }}"#,
            id
        );
        let response = decode_text_frame(&server_json).unwrap();
        match response {
            ServerMessage::Agents { agents } => {
                assert_eq!(agents[0].name, "roundtrip-agent");
            }
            _ => panic!("Expected Agents"),
        }
    }
}
