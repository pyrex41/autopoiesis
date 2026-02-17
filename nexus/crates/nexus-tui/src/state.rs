use nexus_protocol::types::*;
use uuid::Uuid;

use crate::layout::{FocusedPane, LayoutMode};
use crate::notifications::{Notification, NotificationLevel};
use crate::widgets::chat::ChatMessage;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum ConnectionStatus {
    #[default]
    Disconnected,
    Connecting,
    Connected,
    Reconnecting { attempt: u32 },
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum InputMode {
    #[default]
    Normal,
    Command,
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
    pub auto_scroll_thoughts: bool,
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
            auto_scroll_thoughts: true,
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

}
