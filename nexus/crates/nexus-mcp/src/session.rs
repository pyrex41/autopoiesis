use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};

use crate::transport::McpTransport;
use crate::types::{JsonRpcRequest, McpCapabilities, McpError, McpServerInfo, McpTool, ToolResult};

static REQUEST_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    REQUEST_ID.fetch_add(1, Ordering::SeqCst)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionState {
    Uninitialized,
    Initialized,
    Closed,
}

pub struct McpSession {
    pub transport: McpTransport,
    pub state: SessionState,
    pub server_info: Option<McpServerInfo>,
    pub capabilities: Option<McpCapabilities>,
    pub tools: Vec<McpTool>,
}

impl McpSession {
    pub fn new(transport: McpTransport) -> Self {
        Self {
            transport,
            state: SessionState::Uninitialized,
            server_info: None,
            capabilities: None,
            tools: Vec::new(),
        }
    }

    pub async fn initialize(&mut self) -> Result<(), McpError> {
        let req = JsonRpcRequest::new(
            next_id(),
            "initialize",
            Some(json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": { "name": "nexus", "version": "0.1.0" }
            })),
        );
        let resp = self.transport.send(&req).await?.into_result()?;

        if let Some(server_info) = resp.get("serverInfo") {
            self.server_info = serde_json::from_value(server_info.clone()).ok();
        }
        if let Some(caps) = resp.get("capabilities") {
            self.capabilities = serde_json::from_value(caps.clone()).ok();
        }

        self.transport
            .notify("notifications/initialized", None)
            .await?;
        self.state = SessionState::Initialized;
        Ok(())
    }

    pub async fn list_tools(&mut self) -> Result<Vec<McpTool>, McpError> {
        if self.state != SessionState::Initialized {
            return Err(McpError::NotInitialized);
        }
        let req = JsonRpcRequest::new(next_id(), "tools/list", None);
        let resp = self.transport.send(&req).await?.into_result()?;
        let tools: Vec<McpTool> = resp
            .get("tools")
            .and_then(|t| serde_json::from_value(t.clone()).ok())
            .unwrap_or_default();
        self.tools = tools.clone();
        Ok(tools)
    }

    pub async fn call_tool(&mut self, name: &str, arguments: Value) -> Result<ToolResult, McpError> {
        if self.state != SessionState::Initialized {
            return Err(McpError::NotInitialized);
        }
        let req = JsonRpcRequest::new(
            next_id(),
            "tools/call",
            Some(json!({ "name": name, "arguments": arguments })),
        );
        let resp = self.transport.send(&req).await?.into_result()?;
        let result: ToolResult = serde_json::from_value(resp)?;
        Ok(result)
    }

    pub async fn shutdown(&mut self) -> Result<(), McpError> {
        self.transport
            .notify("notifications/cancelled", None)
            .await
            .ok();
        self.state = SessionState::Closed;
        Ok(())
    }

    pub fn tool_count(&self) -> usize {
        self.tools.len()
    }

    pub fn is_initialized(&self) -> bool {
        self.state == SessionState::Initialized
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn mock_session(responses: Vec<serde_json::Value>) -> McpSession {
        let transport = McpTransport::Mock {
            responses: responses.into_iter().collect(),
        };
        McpSession::new(transport)
    }

    #[tokio::test]
    async fn test_initialize_success() {
        let mut session = mock_session(vec![json!({
            "serverInfo": {"name": "test-server", "version": "1.0", "protocolVersion": "2024-11-05"},
            "capabilities": {}
        })]);
        session.initialize().await.unwrap();
        assert!(session.is_initialized());
        assert_eq!(session.server_info.as_ref().unwrap().name, "test-server");
    }

    #[tokio::test]
    async fn test_initialize_sets_capabilities() {
        let mut session = mock_session(vec![json!({
            "serverInfo": {"name": "s", "version": "1", "protocolVersion": "x"},
            "capabilities": { "tools": {} }
        })]);
        session.initialize().await.unwrap();
        assert!(session.capabilities.is_some());
        assert!(session.capabilities.as_ref().unwrap().tools.is_some());
    }

    #[tokio::test]
    async fn test_list_tools() {
        let mut session = mock_session(vec![
            json!({"serverInfo": {"name": "s", "version": "1", "protocolVersion": "x"}, "capabilities": {}}),
            json!({"tools": [{"name": "bash", "description": "Run bash", "inputSchema": {}}]}),
        ]);
        session.initialize().await.unwrap();
        let tools = session.list_tools().await.unwrap();
        assert_eq!(tools.len(), 1);
        assert_eq!(tools[0].name, "bash");
        assert_eq!(session.tool_count(), 1);
    }

    #[tokio::test]
    async fn test_list_tools_not_initialized() {
        let mut session = mock_session(vec![]);
        let result = session.list_tools().await;
        assert!(matches!(result, Err(McpError::NotInitialized)));
    }

    #[tokio::test]
    async fn test_call_tool_not_initialized() {
        let mut session = mock_session(vec![]);
        let result = session.call_tool("bash", json!({})).await;
        assert!(matches!(result, Err(McpError::NotInitialized)));
    }

    #[tokio::test]
    async fn test_call_tool_success() {
        let mut session = mock_session(vec![
            json!({"serverInfo": {"name": "s", "version": "1", "protocolVersion": "x"}, "capabilities": {}}),
            json!({"content": [{"type": "text", "text": "hello"}], "is_error": false}),
        ]);
        session.initialize().await.unwrap();
        let result = session.call_tool("echo", json!({"msg": "hello"})).await.unwrap();
        assert!(!result.is_error);
        assert_eq!(result.content.len(), 1);
        assert_eq!(result.content[0].text_content(), Some("hello"));
    }

    #[tokio::test]
    async fn test_shutdown() {
        let mut session = mock_session(vec![json!({
            "serverInfo": {"name": "s", "version": "1", "protocolVersion": "x"},
            "capabilities": {}
        })]);
        session.initialize().await.unwrap();
        assert!(session.is_initialized());
        session.shutdown().await.unwrap();
        assert_eq!(session.state, SessionState::Closed);
        assert!(!session.is_initialized());
    }

    #[test]
    fn test_session_state_uninitialized() {
        let transport = McpTransport::Mock {
            responses: std::collections::VecDeque::new(),
        };
        let session = McpSession::new(transport);
        assert!(!session.is_initialized());
        assert_eq!(session.tool_count(), 0);
        assert_eq!(session.state, SessionState::Uninitialized);
    }
}
