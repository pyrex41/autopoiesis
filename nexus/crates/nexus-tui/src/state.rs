use nexus_protocol::types::*;
use uuid::Uuid;

use crate::layout::{FocusedPane, LayoutMode};
use crate::notifications::{Notification, NotificationLevel};
use crate::widgets::chat::ChatMessage;
use std::cmp::Ordering;

#[derive(Debug, Clone, Default)]
pub struct McpServerStatus {
    pub name: String,
    pub connected: bool,
    pub tool_count: usize,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum ConnectionStatus {
    #[default]
    Disconnected,
    Connecting,
    Connected,
    Reconnecting {
        attempt: u32,
    },
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum InputMode {
    #[default]
    Normal,
    Command,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VoiceMode {
    #[default]
    Disabled,
    PushToTalk,
    VoiceActivated,
}

#[derive(Debug)]
pub struct AppState {
    pub connection: ConnectionStatus,
    pub agents: Vec<AgentData>,
    pub selected_agent_index: usize,
    pub thoughts: Vec<ThoughtData>,
    pub blocking_requests: Vec<BlockingRequestData>,
    pub system_info: Option<SystemInfoData>,
    pub input_mode: InputMode,
    pub command_input: String,
    pub command_history: Vec<String>,
    pub thought_scroll_offset: usize,
    pub should_quit: bool,
    // Phase 2 fields:
    pub layout_mode: LayoutMode,
    pub focused_pane: FocusedPane,
    pub pinned_agent_ids: Vec<Uuid>,
    pub notifications: Vec<Notification>,
    pub show_help: bool,
    pub leader_key_active: bool,
    pub leader_key_prefix: Option<char>,
    pub chat_messages: Vec<ChatMessage>,
    pub chat_input: String,
    pub chat_session_active: bool,
    pub chat_waiting_response: bool,
    pub auto_scroll_thoughts: bool,
    // Phase 6 fields:
    pub snapshots: Vec<SnapshotData>,
    pub branches: Vec<BranchData>,
    pub current_branch: Option<String>,
    pub selected_snapshot_idx: usize,
    pub snapshot_diff: Option<String>,
    pub show_snapshot_panel: bool,
    pub snapshot_scroll_offset: usize,
    pub diff_scroll_offset: usize,
    // MCP fields:
    pub mcp_servers: Vec<McpServerStatus>,
    pub selected_mcp_server_idx: usize,
    // Voice fields:
    pub voice_mode: VoiceMode,
    pub is_recording: bool,
    pub is_speaking: bool,
    pub transcribed_text: Option<String>,
    pub voice_error: Option<String>,
    // Holodeck fields:
    pub holodeck_connected: bool,
    pub show_holodeck_viewport: bool,
    /// Raw RGBA frame data + dimensions, updated from watch channel.
    pub holodeck_frame: Option<(Vec<u8>, u32, u32)>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            connection: ConnectionStatus::default(),
            agents: Vec::new(),
            selected_agent_index: 0,
            thoughts: Vec::new(),
            blocking_requests: Vec::new(),
            system_info: None,
            input_mode: InputMode::default(),
            command_input: String::new(),
            command_history: Vec::new(),
            thought_scroll_offset: 0,
            should_quit: false,
            layout_mode: LayoutMode::default(),
            focused_pane: FocusedPane::default(),
            pinned_agent_ids: Vec::new(),
            notifications: Vec::new(),
            show_help: false,
            leader_key_active: false,
            leader_key_prefix: None,
            chat_messages: Vec::new(),
            chat_input: String::new(),
            chat_session_active: false,
            chat_waiting_response: false,
            auto_scroll_thoughts: true,
            snapshots: Vec::new(),
            branches: Vec::new(),
            current_branch: None,
            selected_snapshot_idx: 0,
            snapshot_diff: None,
            show_snapshot_panel: false,
            snapshot_scroll_offset: 0,
            diff_scroll_offset: 0,
            mcp_servers: Vec::new(),
            selected_mcp_server_idx: 0,
            voice_mode: VoiceMode::Disabled,
            is_recording: false,
            is_speaking: false,
            transcribed_text: None,
            voice_error: None,
            holodeck_connected: false,
            show_holodeck_viewport: false,
            holodeck_frame: None,
        }
    }
}

impl AppState {
    pub fn selected_agent(&self) -> Option<&AgentData> {
        self.agents.get(self.selected_agent_index)
    }

    pub fn selected_agent_id(&self) -> Option<Uuid> {
        self.selected_agent().map(|a| a.id)
    }

    pub fn agent_count(&self) -> usize {
        self.agents.len()
    }

    pub fn select_next_agent(&mut self) {
        if !self.agents.is_empty() {
            self.selected_agent_index = (self.selected_agent_index + 1) % self.agents.len();
        }
    }

    pub fn select_prev_agent(&mut self) {
        if !self.agents.is_empty() {
            self.selected_agent_index = if self.selected_agent_index == 0 {
                self.agents.len() - 1
            } else {
                self.selected_agent_index - 1
            };
        }
    }

    pub fn version_string(&self) -> &str {
        self.system_info
            .as_ref()
            .map(|i| i.version.as_str())
            .unwrap_or("v0.1.0")
    }

    // Phase 2 methods:

    pub fn push_notification(&mut self, msg: &str, level: NotificationLevel) {
        self.notifications.push(Notification::new(msg, level));
    }

    pub fn prune_notifications(&mut self) {
        crate::notifications::prune_expired(&mut self.notifications);
    }

    pub fn cycle_layout_mode(&mut self) {
        self.layout_mode = match self.layout_mode {
            LayoutMode::Cockpit => LayoutMode::Focused,
            LayoutMode::Focused => LayoutMode::Monitor,
            LayoutMode::Monitor => LayoutMode::Cockpit,
        };
    }

    pub fn toggle_help(&mut self) {
        self.show_help = !self.show_help;
    }

    // Phase 6 methods:

    pub fn push_snapshot(&mut self, snap: SnapshotData) {
        self.snapshots.push(snap);
        self.snapshots.sort_by(|a, b| {
            a.timestamp
                .partial_cmp(&b.timestamp)
                .unwrap_or(Ordering::Equal)
        });
    }

    pub fn update_branches(&mut self, branches: Vec<BranchData>, current: Option<String>) {
        self.branches = branches;
        self.current_branch = current;
    }

    pub fn select_next_snapshot(&mut self) {
        if !self.snapshots.is_empty() {
            self.selected_snapshot_idx = (self.selected_snapshot_idx + 1) % self.snapshots.len();
        }
    }

    pub fn select_prev_snapshot(&mut self) {
        if !self.snapshots.is_empty() {
            self.selected_snapshot_idx = if self.selected_snapshot_idx == 0 {
                self.snapshots.len() - 1
            } else {
                self.selected_snapshot_idx - 1
            };
        }
    }

    // MCP methods:

    pub fn update_mcp_server(
        &mut self,
        name: &str,
        connected: bool,
        tool_count: usize,
        error: Option<String>,
    ) {
        if let Some(server) = self.mcp_servers.iter_mut().find(|s| s.name == name) {
            server.connected = connected;
            server.tool_count = tool_count;
            server.error = error;
        } else {
            self.mcp_servers.push(McpServerStatus {
                name: name.to_string(),
                connected,
                tool_count,
                error,
            });
        }
    }

    pub fn select_next_mcp_server(&mut self) {
        if !self.mcp_servers.is_empty() {
            self.selected_mcp_server_idx =
                (self.selected_mcp_server_idx + 1) % self.mcp_servers.len();
        }
    }

    pub fn select_prev_mcp_server(&mut self) {
        if !self.mcp_servers.is_empty() {
            self.selected_mcp_server_idx = if self.selected_mcp_server_idx == 0 {
                self.mcp_servers.len() - 1
            } else {
                self.selected_mcp_server_idx - 1
            };
        }
    }

    // Voice methods:

    pub fn toggle_voice_mode(&mut self) {
        self.voice_mode = match self.voice_mode {
            VoiceMode::Disabled => VoiceMode::PushToTalk,
            VoiceMode::PushToTalk => VoiceMode::VoiceActivated,
            VoiceMode::VoiceActivated => VoiceMode::Disabled,
        };
    }

    pub fn set_transcription(&mut self, text: String) {
        self.command_input = text.clone();
        self.transcribed_text = Some(text);
    }

    // Holodeck methods:

    pub fn toggle_holodeck_viewport(&mut self) {
        self.show_holodeck_viewport = !self.show_holodeck_viewport;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::widgets::chat::ChatSender;
    use nexus_protocol::types::AgentState;

    fn make_agent(name: &str) -> AgentData {
        AgentData {
            id: Uuid::new_v4(),
            name: name.to_string(),
            state: AgentState::Running,
            capabilities: vec!["observe".to_string()],
            parent: None,
            children: vec![],
            thought_count: 0,
        }
    }

    // === Existing tests (all preserved) ===

    #[test]
    fn test_default_state() {
        let state = AppState::default();
        assert_eq!(state.connection, ConnectionStatus::Disconnected);
        assert!(state.agents.is_empty());
        assert_eq!(state.selected_agent_index, 0);
        assert_eq!(state.input_mode, InputMode::Normal);
        assert!(!state.should_quit);
    }

    #[test]
    fn test_selected_agent_empty() {
        let state = AppState::default();
        assert!(state.selected_agent().is_none());
        assert!(state.selected_agent_id().is_none());
    }

    #[test]
    fn test_select_next_agent_wraps() {
        let mut state = AppState::default();
        state.agents = vec![make_agent("a"), make_agent("b"), make_agent("c")];
        assert_eq!(state.selected_agent_index, 0);

        state.select_next_agent();
        assert_eq!(state.selected_agent_index, 1);

        state.select_next_agent();
        assert_eq!(state.selected_agent_index, 2);

        state.select_next_agent();
        assert_eq!(state.selected_agent_index, 0); // wraps
    }

    #[test]
    fn test_select_prev_agent_wraps() {
        let mut state = AppState::default();
        state.agents = vec![make_agent("a"), make_agent("b"), make_agent("c")];
        assert_eq!(state.selected_agent_index, 0);

        state.select_prev_agent();
        assert_eq!(state.selected_agent_index, 2); // wraps to end

        state.select_prev_agent();
        assert_eq!(state.selected_agent_index, 1);
    }

    #[test]
    fn test_select_on_empty_agents() {
        let mut state = AppState::default();
        state.select_next_agent(); // no panic
        state.select_prev_agent(); // no panic
        assert_eq!(state.selected_agent_index, 0);
    }

    #[test]
    fn test_version_string_default() {
        let state = AppState::default();
        assert_eq!(state.version_string(), "v0.1.0");
    }

    #[test]
    fn test_version_string_from_system_info() {
        let mut state = AppState::default();
        state.system_info = Some(SystemInfoData {
            version: "1.2.3".to_string(),
            health: "healthy".to_string(),
            agent_count: 0,
            connection_count: 0,
        });
        assert_eq!(state.version_string(), "1.2.3");
    }

    #[test]
    fn test_agent_count() {
        let mut state = AppState::default();
        assert_eq!(state.agent_count(), 0);
        state.agents = vec![make_agent("a"), make_agent("b")];
        assert_eq!(state.agent_count(), 2);
    }

    #[test]
    fn test_selected_agent_id() {
        let mut state = AppState::default();
        let agent = make_agent("test");
        let expected_id = agent.id;
        state.agents = vec![agent];
        assert_eq!(state.selected_agent_id(), Some(expected_id));
    }

    // === New Phase 2 tests ===

    #[test]
    fn test_default_phase2_fields() {
        let state = AppState::default();
        assert_eq!(state.layout_mode, LayoutMode::Cockpit);
        assert_eq!(state.focused_pane, FocusedPane::AgentList);
        assert!(state.pinned_agent_ids.is_empty());
        assert!(state.notifications.is_empty());
        assert!(!state.show_help);
        assert!(!state.leader_key_active);
        assert!(state.leader_key_prefix.is_none());
        assert!(state.chat_messages.is_empty());
        assert!(state.chat_input.is_empty());
        assert!(state.auto_scroll_thoughts);
    }

    #[test]
    fn test_push_notification() {
        let mut state = AppState::default();
        state.push_notification("test message", NotificationLevel::Info);
        assert_eq!(state.notifications.len(), 1);
        assert_eq!(state.notifications[0].message, "test message");
        assert_eq!(state.notifications[0].level, NotificationLevel::Info);
    }

    #[test]
    fn test_prune_notifications_keeps_recent() {
        let mut state = AppState::default();
        state.push_notification("recent", NotificationLevel::Info);
        state.prune_notifications();
        // Just pushed, should still be there
        assert_eq!(state.notifications.len(), 1);
    }

    #[test]
    fn test_prune_notifications_removes_old() {
        let mut state = AppState::default();
        state.notifications.push(Notification {
            message: "old".to_string(),
            level: NotificationLevel::Warning,
            created_at: std::time::Instant::now() - std::time::Duration::from_secs(10),
        });
        state.prune_notifications();
        assert!(state.notifications.is_empty());
    }

    #[test]
    fn test_chat_sender_equality() {
        assert_eq!(ChatSender::User, ChatSender::User);
        assert_eq!(ChatSender::System, ChatSender::System);
        assert_eq!(
            ChatSender::Agent("foo".to_string()),
            ChatSender::Agent("foo".to_string())
        );
        assert_ne!(ChatSender::User, ChatSender::System);
    }

    #[test]
    fn test_cycle_layout_mode() {
        let mut state = AppState::default();
        assert_eq!(state.layout_mode, LayoutMode::Cockpit);

        state.cycle_layout_mode();
        assert_eq!(state.layout_mode, LayoutMode::Focused);

        state.cycle_layout_mode();
        assert_eq!(state.layout_mode, LayoutMode::Monitor);

        state.cycle_layout_mode();
        assert_eq!(state.layout_mode, LayoutMode::Cockpit);
    }

    #[test]
    fn test_toggle_help() {
        let mut state = AppState::default();
        assert!(!state.show_help);

        state.toggle_help();
        assert!(state.show_help);

        state.toggle_help();
        assert!(!state.show_help);
    }

    // === Phase 6 tests ===

    #[test]
    fn test_default_phase6_fields() {
        let state = AppState::default();
        assert!(state.snapshots.is_empty());
        assert!(state.branches.is_empty());
        assert!(state.current_branch.is_none());
        assert_eq!(state.selected_snapshot_idx, 0);
        assert!(state.snapshot_diff.is_none());
        assert!(!state.show_snapshot_panel);
        assert_eq!(state.snapshot_scroll_offset, 0);
        assert_eq!(state.diff_scroll_offset, 0);
    }

    fn make_snapshot(id: &str, ts: f64) -> SnapshotData {
        SnapshotData {
            id: id.to_string(),
            parent: None,
            hash: None,
            metadata: None,
            timestamp: ts,
        }
    }

    #[test]
    fn test_push_snapshot_sorts_by_timestamp() {
        let mut state = AppState::default();
        state.push_snapshot(make_snapshot("b", 200.0));
        state.push_snapshot(make_snapshot("a", 100.0));
        state.push_snapshot(make_snapshot("c", 150.0));

        assert_eq!(state.snapshots[0].id, "a");
        assert_eq!(state.snapshots[1].id, "c");
        assert_eq!(state.snapshots[2].id, "b");
    }

    #[test]
    fn test_update_branches() {
        let mut state = AppState::default();
        let branches = vec![
            BranchData {
                name: "main".to_string(),
                head: Some("snap-1".to_string()),
                created: None,
            },
            BranchData {
                name: "dev".to_string(),
                head: None,
                created: None,
            },
        ];
        state.update_branches(branches, Some("main".to_string()));
        assert_eq!(state.branches.len(), 2);
        assert_eq!(state.current_branch, Some("main".to_string()));
    }

    #[test]
    fn test_select_next_snapshot_wraps() {
        let mut state = AppState::default();
        state.snapshots = vec![
            make_snapshot("a", 1.0),
            make_snapshot("b", 2.0),
            make_snapshot("c", 3.0),
        ];
        assert_eq!(state.selected_snapshot_idx, 0);

        state.select_next_snapshot();
        assert_eq!(state.selected_snapshot_idx, 1);
        state.select_next_snapshot();
        assert_eq!(state.selected_snapshot_idx, 2);
        state.select_next_snapshot();
        assert_eq!(state.selected_snapshot_idx, 0); // wraps
    }

    #[test]
    fn test_select_prev_snapshot_wraps() {
        let mut state = AppState::default();
        state.snapshots = vec![
            make_snapshot("a", 1.0),
            make_snapshot("b", 2.0),
            make_snapshot("c", 3.0),
        ];
        assert_eq!(state.selected_snapshot_idx, 0);

        state.select_prev_snapshot();
        assert_eq!(state.selected_snapshot_idx, 2); // wraps to end
        state.select_prev_snapshot();
        assert_eq!(state.selected_snapshot_idx, 1);
    }

    #[test]
    fn test_select_snapshot_on_empty() {
        let mut state = AppState::default();
        state.select_next_snapshot(); // no panic
        state.select_prev_snapshot(); // no panic
        assert_eq!(state.selected_snapshot_idx, 0);
    }

    // === MCP tests ===

    #[test]
    fn test_default_mcp_fields() {
        let state = AppState::default();
        assert!(state.mcp_servers.is_empty());
        assert_eq!(state.selected_mcp_server_idx, 0);
    }

    #[test]
    fn test_update_mcp_server_insert() {
        let mut state = AppState::default();
        state.update_mcp_server("cortex", true, 15, None);
        assert_eq!(state.mcp_servers.len(), 1);
        assert_eq!(state.mcp_servers[0].name, "cortex");
        assert!(state.mcp_servers[0].connected);
        assert_eq!(state.mcp_servers[0].tool_count, 15);
        assert!(state.mcp_servers[0].error.is_none());
    }

    #[test]
    fn test_update_mcp_server_update() {
        let mut state = AppState::default();
        state.update_mcp_server("cortex", true, 15, None);
        state.update_mcp_server("cortex", false, 0, Some("timeout".to_string()));
        assert_eq!(state.mcp_servers.len(), 1);
        assert!(!state.mcp_servers[0].connected);
        assert_eq!(state.mcp_servers[0].tool_count, 0);
        assert_eq!(state.mcp_servers[0].error, Some("timeout".to_string()));
    }

    #[test]
    fn test_select_next_mcp_server_wraps() {
        let mut state = AppState::default();
        state.update_mcp_server("a", true, 1, None);
        state.update_mcp_server("b", true, 2, None);
        assert_eq!(state.selected_mcp_server_idx, 0);

        state.select_next_mcp_server();
        assert_eq!(state.selected_mcp_server_idx, 1);
        state.select_next_mcp_server();
        assert_eq!(state.selected_mcp_server_idx, 0); // wraps
    }

    #[test]
    fn test_select_prev_mcp_server_wraps() {
        let mut state = AppState::default();
        state.update_mcp_server("a", true, 1, None);
        state.update_mcp_server("b", true, 2, None);
        assert_eq!(state.selected_mcp_server_idx, 0);

        state.select_prev_mcp_server();
        assert_eq!(state.selected_mcp_server_idx, 1); // wraps to end
        state.select_prev_mcp_server();
        assert_eq!(state.selected_mcp_server_idx, 0);
    }

    #[test]
    fn test_select_mcp_server_on_empty() {
        let mut state = AppState::default();
        state.select_next_mcp_server(); // no panic
        state.select_prev_mcp_server(); // no panic
        assert_eq!(state.selected_mcp_server_idx, 0);
    }

    // === Voice tests ===

    #[test]
    fn test_voice_mode_default() {
        let state = AppState::default();
        assert_eq!(state.voice_mode, VoiceMode::Disabled);
        assert!(!state.is_recording);
        assert!(!state.is_speaking);
        assert!(state.transcribed_text.is_none());
    }

    #[test]
    fn test_toggle_voice_mode() {
        let mut state = AppState::default();
        assert_eq!(state.voice_mode, VoiceMode::Disabled);
        state.toggle_voice_mode();
        assert_eq!(state.voice_mode, VoiceMode::PushToTalk);
        state.toggle_voice_mode();
        assert_eq!(state.voice_mode, VoiceMode::VoiceActivated);
        state.toggle_voice_mode();
        assert_eq!(state.voice_mode, VoiceMode::Disabled);
    }

    #[test]
    fn test_set_transcription() {
        let mut state = AppState::default();
        state.set_transcription("hello world".to_string());
        assert_eq!(state.transcribed_text, Some("hello world".to_string()));
        assert_eq!(state.command_input, "hello world");
    }
}
