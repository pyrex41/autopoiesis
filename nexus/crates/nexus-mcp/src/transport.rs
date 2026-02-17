use crate::types::{JsonRpcRequest, JsonRpcResponse, McpError};
use serde_json::Value;

pub enum McpTransport {
    Stdio {
        command: String,
        args: Vec<String>,
    },
    Http {
        client: reqwest::Client,
        url: String,
        session_id: Option<String>,
    },
    #[cfg(test)]
    Mock {
        responses: std::collections::VecDeque<Value>,
    },
}

impl McpTransport {
    pub fn stdio(command: impl Into<String>, args: Vec<String>) -> Self {
        Self::Stdio {
            command: command.into(),
            args,
        }
    }

    pub fn http(url: impl Into<String>) -> Self {
        Self::Http {
            client: reqwest::Client::new(),
            url: url.into(),
            session_id: None,
        }
    }

    /// Send a JSON-RPC request and wait for response.
    pub async fn send(&mut self, request: &JsonRpcRequest) -> Result<JsonRpcResponse, McpError> {
        match self {
            Self::Http {
                client,
                url,
                session_id,
            } => {
                let mut req = client.post(url.as_str()).json(request);
                if let Some(sid) = session_id {
                    req = req.header("Mcp-Session-Id", sid.as_str());
                }
                let resp = req.send().await.map_err(|e| McpError::Http(e.to_string()))?;
                if let Some(new_sid) = resp.headers().get("Mcp-Session-Id") {
                    *session_id = Some(new_sid.to_str().unwrap_or("").to_string());
                }
                let json_resp = resp
                    .json::<JsonRpcResponse>()
                    .await
                    .map_err(|e| McpError::Http(e.to_string()))?;
                Ok(json_resp)
            }
            Self::Stdio { .. } => Err(McpError::Transport(
                "Stdio transport not yet connected".to_string(),
            )),
            #[cfg(test)]
            Self::Mock { responses } => {
                if let Some(value) = responses.pop_front() {
                    Ok(JsonRpcResponse {
                        jsonrpc: "2.0".to_string(),
                        id: request.id,
                        result: Some(value),
                        error: None,
                    })
                } else {
                    Err(McpError::Transport("Mock: no more responses".to_string()))
                }
            }
        }
    }

    /// Send a JSON-RPC notification (no response expected).
    pub async fn notify(&mut self, method: &str, params: Option<Value>) -> Result<(), McpError> {
        let req = JsonRpcRequest::notification(method, params);
        match self {
            Self::Http {
                client,
                url,
                session_id,
            } => {
                let mut r = client.post(url.as_str()).json(&req);
                if let Some(sid) = session_id {
                    r = r.header("Mcp-Session-Id", sid.as_str());
                }
                r.send().await.map_err(|e| McpError::Http(e.to_string()))?;
                Ok(())
            }
            Self::Stdio { .. } => Ok(()),
            #[cfg(test)]
            Self::Mock { .. } => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_http_transport_construction() {
        let transport = McpTransport::http("http://localhost:8081");
        assert!(matches!(transport, McpTransport::Http { .. }));
        if let McpTransport::Http { url, session_id, .. } = &transport {
            assert_eq!(url, "http://localhost:8081");
            assert!(session_id.is_none());
        }
    }

    #[test]
    fn test_stdio_transport_construction() {
        let transport = McpTransport::stdio("claude", vec!["--mcp".to_string()]);
        assert!(matches!(transport, McpTransport::Stdio { .. }));
        if let McpTransport::Stdio { command, args } = &transport {
            assert_eq!(command, "claude");
            assert_eq!(args, &["--mcp"]);
        }
    }

    #[tokio::test]
    async fn test_mock_transport_returns_responses_in_order() {
        use serde_json::json;
        let mut transport = McpTransport::Mock {
            responses: vec![json!({"first": true}), json!({"second": true})]
                .into_iter()
                .collect(),
        };
        let req1 = JsonRpcRequest::new(1, "test", None);
        let resp1 = transport.send(&req1).await.unwrap();
        assert_eq!(resp1.result.unwrap()["first"], true);

        let req2 = JsonRpcRequest::new(2, "test", None);
        let resp2 = transport.send(&req2).await.unwrap();
        assert_eq!(resp2.result.unwrap()["second"], true);
    }

    #[tokio::test]
    async fn test_mock_transport_exhausted() {
        let mut transport = McpTransport::Mock {
            responses: std::collections::VecDeque::new(),
        };
        let req = JsonRpcRequest::new(1, "test", None);
        let err = transport.send(&req).await.unwrap_err();
        assert!(matches!(err, McpError::Transport(_)));
    }

    #[tokio::test]
    async fn test_mock_notify_succeeds() {
        let mut transport = McpTransport::Mock {
            responses: std::collections::VecDeque::new(),
        };
        transport.notify("test/notification", None).await.unwrap();
    }

    #[tokio::test]
    async fn test_stdio_transport_send_returns_error() {
        let mut transport = McpTransport::stdio("cmd", vec![]);
        let req = JsonRpcRequest::new(1, "test", None);
        let err = transport.send(&req).await.unwrap_err();
        assert!(matches!(err, McpError::Transport(_)));
    }

    #[tokio::test]
    async fn test_stdio_transport_notify_succeeds() {
        let mut transport = McpTransport::stdio("cmd", vec![]);
        transport.notify("test", None).await.unwrap();
    }
}
