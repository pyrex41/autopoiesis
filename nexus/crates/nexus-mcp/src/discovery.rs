use std::collections::HashMap;

use serde_json::Value;

use crate::session::McpSession;
use crate::transport::McpTransport;
use crate::types::{McpError, McpTool, ToolResult};

#[derive(Debug, Clone)]
pub struct ServerConfig {
    pub name: String,
    pub transport_kind: TransportKind,
}

#[derive(Debug, Clone)]
pub enum TransportKind {
    Http { url: String },
    Stdio { command: String, args: Vec<String> },
}

pub struct McpRegistry {
    configs: Vec<ServerConfig>,
    sessions: HashMap<String, McpSession>,
}

impl McpRegistry {
    pub fn new(configs: Vec<ServerConfig>) -> Self {
        Self {
            configs,
            sessions: HashMap::new(),
        }
    }

    pub fn from_configs(configs: Vec<ServerConfig>) -> Self {
        Self::new(configs)
    }

    /// Connect to all configured servers.
    pub async fn connect_all(&mut self) -> Vec<(String, Result<(), McpError>)> {
        let mut results = Vec::new();
        for config in &self.configs {
            let transport = match &config.transport_kind {
                TransportKind::Http { url } => McpTransport::http(url),
                TransportKind::Stdio { command, args } => {
                    McpTransport::stdio(command, args.clone())
                }
            };
            let mut session = McpSession::new(transport);
            let result = session.initialize().await;
            if result.is_ok() {
                let _ = session.list_tools().await;
            }
            results.push((config.name.clone(), result));
            self.sessions.insert(config.name.clone(), session);
        }
        results
    }

    /// Return all tools across all connected servers, tagged with server name.
    pub fn all_tools(&self) -> Vec<(String, McpTool)> {
        self.sessions
            .iter()
            .flat_map(|(server, session)| {
                session
                    .tools
                    .iter()
                    .map(move |tool| (server.clone(), tool.clone()))
            })
            .collect()
    }

    /// Call a tool on a specific server.
    pub async fn call_tool(
        &mut self,
        server: &str,
        tool: &str,
        args: Value,
    ) -> Result<ToolResult, McpError> {
        let session = self
            .sessions
            .get_mut(server)
            .ok_or_else(|| McpError::Transport(format!("Unknown server: {}", server)))?;
        session.call_tool(tool, args).await
    }

    pub fn server_names(&self) -> Vec<&str> {
        self.configs.iter().map(|c| c.name.as_str()).collect()
    }

    pub fn server_status(&self, name: &str) -> Option<(bool, usize)> {
        self.sessions
            .get(name)
            .map(|s| (s.is_initialized(), s.tool_count()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_configs() -> Vec<ServerConfig> {
        vec![
            ServerConfig {
                name: "cortex".to_string(),
                transport_kind: TransportKind::Http {
                    url: "http://localhost:8081".to_string(),
                },
            },
            ServerConfig {
                name: "tools".to_string(),
                transport_kind: TransportKind::Stdio {
                    command: "mcp-tools".to_string(),
                    args: vec!["--stdio".to_string()],
                },
            },
        ]
    }

    #[test]
    fn test_registry_new_empty_sessions() {
        let registry = McpRegistry::new(test_configs());
        assert_eq!(registry.sessions.len(), 0);
        assert_eq!(registry.configs.len(), 2);
    }

    #[test]
    fn test_registry_server_names() {
        let registry = McpRegistry::new(test_configs());
        let names = registry.server_names();
        assert_eq!(names.len(), 2);
        assert!(names.contains(&"cortex"));
        assert!(names.contains(&"tools"));
    }

    #[test]
    fn test_registry_server_status_unknown() {
        let registry = McpRegistry::new(test_configs());
        assert!(registry.server_status("unknown").is_none());
    }

    #[test]
    fn test_registry_server_status_not_connected() {
        let registry = McpRegistry::new(test_configs());
        assert!(registry.server_status("cortex").is_none());
    }

    #[test]
    fn test_registry_from_configs() {
        let configs = test_configs();
        let registry = McpRegistry::from_configs(configs.clone());
        assert_eq!(registry.server_names().len(), configs.len());
    }

    #[test]
    fn test_registry_all_tools_empty_before_connect() {
        let registry = McpRegistry::new(test_configs());
        assert!(registry.all_tools().is_empty());
    }
}
