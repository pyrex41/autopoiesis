use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub id: Option<u64>,
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<Value>,
}

impl JsonRpcRequest {
    pub fn new(id: u64, method: impl Into<String>, params: Option<Value>) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: Some(id),
            method: method.into(),
            params,
        }
    }

    pub fn notification(method: impl Into<String>, params: Option<Value>) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id: None,
            method: method.into(),
            params,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    pub id: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

impl JsonRpcResponse {
    pub fn into_result(self) -> Result<Value, McpError> {
        if let Some(err) = self.error {
            Err(McpError::JsonRpc {
                code: err.code,
                message: err.message,
            })
        } else {
            Ok(self.result.unwrap_or(Value::Null))
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct JsonRpcError {
    pub code: i64,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpTool {
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(rename = "inputSchema")]
    pub input_schema: Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ToolResult {
    pub content: Vec<ToolContent>,
    #[serde(default)]
    pub is_error: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ToolContent {
    #[serde(rename = "type")]
    pub content_type: String,
    #[serde(default)]
    pub text: Option<String>,
}

impl ToolContent {
    pub fn text_content(&self) -> Option<&str> {
        self.text.as_deref()
    }
}

#[derive(Debug, Clone, Deserialize)]
pub struct McpServerInfo {
    pub name: String,
    pub version: String,
    #[serde(rename = "protocolVersion", default)]
    pub protocol_version: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct McpCapabilities {
    #[serde(default)]
    pub tools: Option<Value>,
    #[serde(default)]
    pub resources: Option<Value>,
    #[serde(default)]
    pub prompts: Option<Value>,
}

#[derive(Debug, thiserror::Error)]
pub enum McpError {
    #[error("JSON-RPC error {code}: {message}")]
    JsonRpc { code: i64, message: String },
    #[error("Transport error: {0}")]
    Transport(String),
    #[error("Session not initialized")]
    NotInitialized,
    #[error("Serialization error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("HTTP error: {0}")]
    Http(String),
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_jsonrpc_request_serialization() {
        let req = JsonRpcRequest::new(1, "foo", None);
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["jsonrpc"], "2.0");
        assert_eq!(json["id"], 1);
        assert_eq!(json["method"], "foo");
        assert!(json.get("params").is_none());
    }

    #[test]
    fn test_jsonrpc_request_with_params() {
        let req = JsonRpcRequest::new(42, "bar", Some(json!({"key": "value"})));
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["id"], 42);
        assert_eq!(json["method"], "bar");
        assert_eq!(json["params"]["key"], "value");
    }

    #[test]
    fn test_jsonrpc_notification_no_id() {
        let req = JsonRpcRequest::notification("notify", None);
        let json = serde_json::to_value(&req).unwrap();
        assert_eq!(json["jsonrpc"], "2.0");
        assert!(json["id"].is_null());
        assert_eq!(json["method"], "notify");
    }

    #[test]
    fn test_jsonrpc_response_into_result_ok() {
        let resp = JsonRpcResponse {
            jsonrpc: "2.0".to_string(),
            id: Some(1),
            result: Some(json!({"tools": []})),
            error: None,
        };
        let val = resp.into_result().unwrap();
        assert_eq!(val, json!({"tools": []}));
    }

    #[test]
    fn test_jsonrpc_response_into_result_null_when_missing() {
        let resp = JsonRpcResponse {
            jsonrpc: "2.0".to_string(),
            id: Some(1),
            result: None,
            error: None,
        };
        let val = resp.into_result().unwrap();
        assert_eq!(val, Value::Null);
    }

    #[test]
    fn test_jsonrpc_response_into_result_error() {
        let resp = JsonRpcResponse {
            jsonrpc: "2.0".to_string(),
            id: Some(1),
            result: None,
            error: Some(JsonRpcError {
                code: -32600,
                message: "Invalid Request".to_string(),
                data: None,
            }),
        };
        let err = resp.into_result().unwrap_err();
        assert!(matches!(err, McpError::JsonRpc { code: -32600, .. }));
        assert!(err.to_string().contains("Invalid Request"));
    }

    #[test]
    fn test_mcp_tool_deserialization() {
        let json = json!({
            "name": "bash",
            "description": "Run a bash command",
            "inputSchema": { "type": "object", "properties": { "command": { "type": "string" } } }
        });
        let tool: McpTool = serde_json::from_value(json).unwrap();
        assert_eq!(tool.name, "bash");
        assert_eq!(tool.description.as_deref(), Some("Run a bash command"));
    }

    #[test]
    fn test_mcp_tool_deserialization_no_description() {
        let json = json!({
            "name": "read",
            "inputSchema": {}
        });
        let tool: McpTool = serde_json::from_value(json).unwrap();
        assert_eq!(tool.name, "read");
        assert!(tool.description.is_none());
    }

    #[test]
    fn test_tool_content_text_content() {
        let content = ToolContent {
            content_type: "text".to_string(),
            text: Some("hello world".to_string()),
        };
        assert_eq!(content.text_content(), Some("hello world"));
    }

    #[test]
    fn test_tool_content_no_text() {
        let content = ToolContent {
            content_type: "image".to_string(),
            text: None,
        };
        assert_eq!(content.text_content(), None);
    }
}
