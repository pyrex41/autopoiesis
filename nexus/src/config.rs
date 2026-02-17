use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct NexusConfig {
    #[serde(default)]
    pub connection: ConnectionConfig,
    #[serde(default)]
    pub tui: TuiConfig,
    #[serde(default)]
    pub mcp: McpConfig,
    #[serde(default)]
    pub keybinds: KeybindsConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ConnectionConfig {
    pub ws_url: String,
    pub rest_url: String,
    #[serde(default)]
    pub api_key: Option<String>,
    #[serde(default = "default_reconnect_secs")]
    pub reconnect_max_secs: u64,
}

fn default_reconnect_secs() -> u64 {
    30
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        Self {
            ws_url: "ws://localhost:8080/ws".to_string(),
            rest_url: "http://localhost:8081".to_string(),
            api_key: None,
            reconnect_max_secs: 30,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TuiConfig {
    #[serde(default = "default_theme")]
    pub theme: String,
    #[serde(default = "default_layout")]
    pub layout: String,
    #[serde(default = "default_fps")]
    pub fps: u64,
    #[serde(default = "default_true")]
    pub mouse: bool,
}

fn default_theme() -> String {
    "tron".to_string()
}
fn default_layout() -> String {
    "cockpit".to_string()
}
fn default_fps() -> u64 {
    60
}
fn default_true() -> bool {
    true
}

impl Default for TuiConfig {
    fn default() -> Self {
        Self {
            theme: default_theme(),
            layout: default_layout(),
            fps: default_fps(),
            mouse: default_true(),
        }
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct McpConfig {
    #[serde(default)]
    pub servers: Vec<McpServerConfig>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct McpServerConfig {
    pub name: String,
    pub transport: String,
    #[serde(default)]
    pub url: Option<String>,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct KeybindsConfig {
    #[serde(default = "default_leader")]
    pub leader: String,
    #[serde(default = "default_quit")]
    pub quit: String,
    #[serde(default = "default_command")]
    pub command: String,
}

fn default_leader() -> String {
    "space".to_string()
}
fn default_quit() -> String {
    "q".to_string()
}
fn default_command() -> String {
    "/".to_string()
}

impl Default for KeybindsConfig {
    fn default() -> Self {
        Self {
            leader: default_leader(),
            quit: default_quit(),
            command: default_command(),
        }
    }
}

impl NexusConfig {
    /// Search for nexus.toml in: cwd, ~/.nexus/nexus.toml
    #[allow(dead_code)]
    pub fn load() -> Self {
        Self::load_from(None)
    }

    pub fn load_from(path: Option<PathBuf>) -> Self {
        let search_paths: Vec<PathBuf> = if let Some(p) = path {
            vec![p]
        } else {
            let mut paths = vec![PathBuf::from("nexus.toml")];
            if let Some(home) = dirs_next_home() {
                paths.push(home.join(".nexus").join("nexus.toml"));
            }
            paths
        };

        for path in &search_paths {
            if path.exists() {
                if let Ok(contents) = std::fs::read_to_string(path) {
                    match toml::from_str::<NexusConfig>(&contents) {
                        Ok(config) => return config,
                        Err(e) => {
                            eprintln!("Warning: Failed to parse {:?}: {}", path, e);
                        }
                    }
                }
            }
        }
        NexusConfig::default()
    }

    /// Override config values from CLI args (args take priority)
    pub fn apply_cli_overrides(
        &mut self,
        ws_url: Option<String>,
        rest_url: Option<String>,
        api_key: Option<String>,
    ) {
        if let Some(url) = ws_url {
            self.connection.ws_url = url;
        }
        if let Some(url) = rest_url {
            self.connection.rest_url = url;
        }
        if let Some(key) = api_key {
            self.connection.api_key = Some(key);
        }
    }
}

fn dirs_next_home() -> Option<PathBuf> {
    std::env::var("HOME").ok().map(PathBuf::from)
}

/// Command history persistence
pub struct HistoryStore {
    path: PathBuf,
}

impl HistoryStore {
    pub fn new() -> Self {
        let path = if let Some(home) = dirs_next_home() {
            let nexus_dir = home.join(".nexus");
            let _ = std::fs::create_dir_all(&nexus_dir);
            nexus_dir.join("history.txt")
        } else {
            PathBuf::from(".nexus_history")
        };
        Self { path }
    }

    pub fn load(&self) -> Vec<String> {
        std::fs::read_to_string(&self.path)
            .unwrap_or_default()
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| l.to_string())
            .collect()
    }

    #[allow(dead_code)]
    pub fn append(&self, command: &str) {
        if command.trim().is_empty() {
            return;
        }
        use std::io::Write;
        if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.path)
        {
            let _ = writeln!(f, "{}", command);
        }
    }

    pub fn save_all(&self, history: &[String]) {
        let mut content = history.join("\n");
        if !content.is_empty() {
            content.push('\n');
        }
        let _ = std::fs::write(&self.path, content);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = NexusConfig::default();
        assert_eq!(config.connection.ws_url, "ws://localhost:8080/ws");
        assert_eq!(config.connection.rest_url, "http://localhost:8081");
        assert_eq!(config.connection.reconnect_max_secs, 30);
        assert!(config.connection.api_key.is_none());
    }

    #[test]
    fn test_parse_minimal_toml() {
        let toml_str = r#"
[connection]
ws_url = "ws://myserver:9090/ws"
rest_url = "http://myserver:9091"
"#;
        let config: NexusConfig = toml::from_str(toml_str).unwrap();
        assert_eq!(config.connection.ws_url, "ws://myserver:9090/ws");
        assert_eq!(config.connection.rest_url, "http://myserver:9091");
        assert_eq!(config.tui.theme, "tron"); // default
    }

    #[test]
    fn test_parse_full_toml() {
        let toml_str = r#"
[connection]
ws_url = "ws://localhost:8080/ws"
rest_url = "http://localhost:8081"
api_key = "secret"
reconnect_max_secs = 60

[tui]
theme = "matrix"
layout = "focused"
fps = 30
mouse = false

[[mcp.servers]]
name = "autopoiesis"
transport = "http"
url = "http://localhost:8081/mcp"

[[mcp.servers]]
name = "filesystem"
transport = "stdio"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
"#;
        let config: NexusConfig = toml::from_str(toml_str).unwrap();
        assert_eq!(config.connection.api_key, Some("secret".to_string()));
        assert_eq!(config.tui.theme, "matrix");
        assert_eq!(config.tui.fps, 30);
        assert!(!config.tui.mouse);
        assert_eq!(config.mcp.servers.len(), 2);
        assert_eq!(config.mcp.servers[0].name, "autopoiesis");
        assert_eq!(config.mcp.servers[1].name, "filesystem");
        assert_eq!(
            config.mcp.servers[1].args,
            vec!["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
        );
    }

    #[test]
    fn test_apply_cli_overrides() {
        let mut config = NexusConfig::default();
        config.apply_cli_overrides(
            Some("ws://override:9999/ws".to_string()),
            None,
            Some("my-key".to_string()),
        );
        assert_eq!(config.connection.ws_url, "ws://override:9999/ws");
        assert_eq!(config.connection.rest_url, "http://localhost:8081"); // unchanged
        assert_eq!(config.connection.api_key, Some("my-key".to_string()));
    }

    #[test]
    fn test_load_nonexistent_returns_default() {
        let config = NexusConfig::load_from(Some(PathBuf::from("/nonexistent/nexus.toml")));
        assert_eq!(config.connection.ws_url, "ws://localhost:8080/ws");
    }

    #[test]
    fn test_parse_empty_toml() {
        let config: NexusConfig = toml::from_str("").unwrap();
        assert_eq!(config.connection.ws_url, "ws://localhost:8080/ws");
    }

    #[test]
    fn test_history_store_roundtrip() {
        let dir = std::env::temp_dir().join("nexus_test_history");
        let _ = std::fs::create_dir_all(&dir);
        let store = HistoryStore {
            path: dir.join("history.txt"),
        };

        store.save_all(&["create agent foo".to_string(), "step".to_string()]);
        let loaded = store.load();
        assert_eq!(loaded.len(), 2);
        assert_eq!(loaded[0], "create agent foo");
        assert_eq!(loaded[1], "step");

        store.append("snapshot checkpoint");
        let loaded2 = store.load();
        assert_eq!(loaded2.len(), 3);
        assert_eq!(loaded2[2], "snapshot checkpoint");

        // Cleanup
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_history_append_empty_skipped() {
        let dir = std::env::temp_dir().join("nexus_test_history2");
        let _ = std::fs::create_dir_all(&dir);
        let store = HistoryStore {
            path: dir.join("history.txt"),
        };

        store.append("  "); // whitespace only - should be skipped
        let loaded = store.load();
        assert!(loaded.is_empty());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
