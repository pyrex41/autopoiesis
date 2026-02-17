use nexus_protocol::types::*;
use uuid::Uuid;

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

#[derive(Debug, Default)]
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
}

#[cfg(test)]
mod tests {
    use super::*;
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
}
