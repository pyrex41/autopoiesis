use std::io;
use std::time::Duration;

use crossterm::{
    event::{self, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use tokio::sync::broadcast;

use nexus_protocol::types::*;
use nexus_protocol::ws::WsHandle;

use crate::input::{self, Action};
use crate::layout::AppLayout;
use crate::state::{AppState, ConnectionStatus, InputMode};
use crate::widgets::{
    agent_detail::AgentDetail, agent_list::AgentList, command_bar::CommandBar,
    status_bar::StatusBar, thought_stream::ThoughtStream,
};

const TICK_RATE: Duration = Duration::from_millis(16); // ~60fps

pub struct App {
    pub state: AppState,
    ws_handle: Option<WsHandle>,
    ws_rx: Option<broadcast::Receiver<ServerMessage>>,
}

impl Default for App {
    fn default() -> Self {
        Self::new()
    }
}

impl App {
    pub fn new() -> Self {
        Self {
            state: AppState::default(),
            ws_handle: None,
            ws_rx: None,
        }
    }

    pub fn with_ws(mut self, handle: WsHandle, rx: broadcast::Receiver<ServerMessage>) -> Self {
        self.ws_handle = Some(handle);
        self.ws_rx = Some(rx);
        self.state.connection = ConnectionStatus::Connecting;
        self
    }

    /// Run the TUI event loop. This takes over the terminal.
    pub async fn run(&mut self) -> anyhow::Result<()> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen)?;
        let backend = CrosstermBackend::new(stdout);
        let mut terminal = Terminal::new(backend)?;

        // Install panic hook that restores terminal
        let original_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |panic_info| {
            let _ = disable_raw_mode();
            let _ = execute!(io::stdout(), LeaveAlternateScreen);
            original_hook(panic_info);
        }));

        let result = self.event_loop(&mut terminal).await;

        disable_raw_mode()?;
        execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
        terminal.show_cursor()?;

        result
    }

    async fn event_loop(
        &mut self,
        terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    ) -> anyhow::Result<()> {
        loop {
            terminal.draw(|frame| {
                self.render(frame);
            })?;

            if self.state.should_quit {
                return Ok(());
            }

            tokio::select! {
                _ = tokio::time::sleep(TICK_RATE) => {
                    while event::poll(Duration::ZERO)? {
                        if let Event::Key(key) = event::read()? {
                            if key.kind == KeyEventKind::Press {
                                self.handle_input(key);
                            }
                        }
                    }
                }
                msg = async {
                    if let Some(ref mut rx) = self.ws_rx {
                        rx.recv().await
                    } else {
                        std::future::pending::<Result<ServerMessage, broadcast::error::RecvError>>().await
                    }
                } => {
                    match msg {
                        Ok(server_msg) => self.dispatch_server_message(server_msg),
                        Err(broadcast::error::RecvError::Lagged(n)) => {
                            tracing::warn!("Skipped {n} WS messages (lagged)");
                        }
                        Err(broadcast::error::RecvError::Closed) => {
                            self.state.connection = ConnectionStatus::Disconnected;
                        }
                    }
                }
            }
        }
    }

    fn render(&self, frame: &mut ratatui::Frame) {
        let layout = AppLayout::new(frame.area());
        frame.render_widget(StatusBar::new(&self.state), layout.status_bar);
        frame.render_widget(AgentList::new(&self.state), layout.agent_list);
        frame.render_widget(AgentDetail::new(&self.state), layout.agent_detail);
        frame.render_widget(ThoughtStream::new(&self.state), layout.thought_stream);
        frame.render_widget(CommandBar::new(&self.state), layout.command_bar);
    }

    fn handle_input(&mut self, key: crossterm::event::KeyEvent) {
        let action =
            input::handle_key_event(key, &self.state.input_mode, &self.state.command_input);

        match action {
            Action::Quit => self.state.should_quit = true,
            Action::SelectNextAgent => {
                self.state.select_next_agent();
                self.request_thoughts_for_selected();
            }
            Action::SelectPrevAgent => {
                self.state.select_prev_agent();
                self.request_thoughts_for_selected();
            }
            Action::EnterCommandMode => {
                self.state.input_mode = InputMode::Command;
                self.state.command_input.clear();
            }
            Action::ExitCommandMode => {
                self.state.input_mode = InputMode::Normal;
                self.state.command_input.clear();
            }
            Action::SubmitCommand(cmd) => {
                self.state.command_history.push(cmd.clone());
                self.state.input_mode = InputMode::Normal;
                self.state.command_input.clear();
                self.execute_command(&cmd);
            }
            Action::CommandInput(c) => {
                self.state.command_input.push(c);
            }
            Action::CommandBackspace => {
                self.state.command_input.pop();
            }
            Action::ScrollThoughtsUp => {
                self.state.thought_scroll_offset =
                    self.state.thought_scroll_offset.saturating_sub(3);
            }
            Action::ScrollThoughtsDown => {
                self.state.thought_scroll_offset =
                    self.state.thought_scroll_offset.saturating_add(3);
            }
            Action::Refresh => {
                self.send_ws(ClientMessage::SystemInfo);
                self.send_ws(ClientMessage::ListAgents);
            }
            Action::None => {}
        }
    }

    fn execute_command(&mut self, cmd: &str) {
        if let Some(msg) = input::parse_command(cmd, self.state.selected_agent_id()) {
            self.send_ws(msg);
        }
    }

    fn request_thoughts_for_selected(&mut self) {
        if let Some(id) = self.state.selected_agent_id() {
            self.state.thoughts.clear();
            self.state.thought_scroll_offset = 0;
            self.send_ws(ClientMessage::GetThoughts {
                agent_id: id,
                limit: Some(100),
            });
        }
    }

    fn send_ws(&self, msg: ClientMessage) {
        if let Some(ref handle) = self.ws_handle {
            let handle = handle.clone();
            tokio::spawn(async move {
                if let Err(e) = handle.send(msg).await {
                    tracing::warn!("Failed to send WS message: {e}");
                }
            });
        }
    }

    /// Dispatch a server message to update app state.
    pub fn dispatch_server_message(&mut self, msg: ServerMessage) {
        match msg {
            ServerMessage::Pong
            | ServerMessage::Subscribed { .. }
            | ServerMessage::Unsubscribed { .. }
            | ServerMessage::StreamFormatSet => {
                if self.state.connection != ConnectionStatus::Connected {
                    self.state.connection = ConnectionStatus::Connected;
                }
            }
            ServerMessage::SystemInfo(info) => {
                self.state.connection = ConnectionStatus::Connected;
                self.state.system_info = Some(info);
            }
            ServerMessage::Agents { agents } => {
                self.state.agents = agents;
                if self.state.selected_agent_index >= self.state.agents.len()
                    && !self.state.agents.is_empty()
                {
                    self.state.selected_agent_index = 0;
                }
            }
            ServerMessage::Agent { agent } => {
                self.upsert_agent(agent);
            }
            ServerMessage::AgentCreated { agent } => {
                self.upsert_agent(agent);
            }
            ServerMessage::AgentStateChanged { agent_id, state } => {
                if let Some(a) = self.state.agents.iter_mut().find(|a| a.id == agent_id) {
                    a.state = state;
                }
            }
            ServerMessage::StepComplete { .. } => {}
            ServerMessage::Thoughts { thoughts, .. } => {
                self.state.thoughts = thoughts;
                self.state.thought_scroll_offset = 0;
            }
            ServerMessage::ThoughtAdded { agent_id, thought } => {
                if self.state.selected_agent_id() == Some(agent_id) {
                    self.state.thoughts.push(thought);
                }
                if let Some(a) = self.state.agents.iter_mut().find(|a| a.id == agent_id) {
                    a.thought_count += 1;
                }
            }
            ServerMessage::Snapshots { .. } => {}
            ServerMessage::Snapshot { .. } => {}
            ServerMessage::SnapshotCreated { .. } => {}
            ServerMessage::Branches { .. } => {}
            ServerMessage::BranchCreated { .. } => {}
            ServerMessage::BranchSwitched { .. } => {}
            ServerMessage::BlockingRequests { requests } => {
                self.state.blocking_requests = requests;
            }
            ServerMessage::BlockingRequest { request } => {
                self.state.blocking_requests.push(request);
            }
            ServerMessage::BlockingResponded {
                blocking_request_id,
            } => {
                self.state
                    .blocking_requests
                    .retain(|r| r.id != blocking_request_id);
            }
            ServerMessage::Events { .. } => {}
            ServerMessage::Event { .. } => {}
            ServerMessage::Unknown => {}
        }
    }

    fn upsert_agent(&mut self, agent: AgentData) {
        if let Some(existing) = self.state.agents.iter_mut().find(|a| a.id == agent.id) {
            *existing = agent;
        } else {
            self.state.agents.push(agent);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use uuid::Uuid;

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

    fn make_agent_with_id(id: Uuid, name: &str) -> AgentData {
        AgentData {
            id,
            name: name.to_string(),
            state: AgentState::Running,
            capabilities: vec![],
            parent: None,
            children: vec![],
            thought_count: 0,
        }
    }

    fn make_thought(_agent_id: Uuid) -> ThoughtData {
        ThoughtData {
            id: Uuid::new_v4(),
            timestamp: 1.0,
            thought_type: ThoughtType::Observation,
            confidence: 0.9,
            content: "test thought".to_string(),
            provenance: None,
            source: None,
            rationale: None,
            alternatives: vec![],
        }
    }

    #[test]
    fn test_app_new_default_state() {
        let app = App::new();
        assert_eq!(app.state.connection, ConnectionStatus::Disconnected);
        assert!(app.state.agents.is_empty());
        assert!(app.ws_handle.is_none());
        assert!(app.ws_rx.is_none());
        assert!(!app.state.should_quit);
    }

    #[test]
    fn test_dispatch_system_info() {
        let mut app = App::new();
        let info = SystemInfoData {
            version: "1.0.0".to_string(),
            health: "healthy".to_string(),
            agent_count: 3,
            connection_count: 1,
        };
        app.dispatch_server_message(ServerMessage::SystemInfo(info));
        assert_eq!(app.state.connection, ConnectionStatus::Connected);
        assert!(app.state.system_info.is_some());
        let si = app.state.system_info.as_ref().unwrap();
        assert_eq!(si.version, "1.0.0");
        assert_eq!(si.agent_count, 3);
    }

    #[test]
    fn test_dispatch_agents_updates_list() {
        let mut app = App::new();
        let agents = vec![make_agent("alpha"), make_agent("beta")];
        app.dispatch_server_message(ServerMessage::Agents { agents });
        assert_eq!(app.state.agents.len(), 2);
        assert_eq!(app.state.agents[0].name, "alpha");
        assert_eq!(app.state.agents[1].name, "beta");
    }

    #[test]
    fn test_dispatch_agents_clamps_selected_index() {
        let mut app = App::new();
        app.state.selected_agent_index = 5;
        let agents = vec![make_agent("only")];
        app.dispatch_server_message(ServerMessage::Agents { agents });
        assert_eq!(app.state.selected_agent_index, 0);
    }

    #[test]
    fn test_dispatch_agent_created_adds() {
        let mut app = App::new();
        let agent = make_agent("new-agent");
        app.dispatch_server_message(ServerMessage::AgentCreated {
            agent: agent.clone(),
        });
        assert_eq!(app.state.agents.len(), 1);
        assert_eq!(app.state.agents[0].name, "new-agent");
    }

    #[test]
    fn test_dispatch_agent_state_changed() {
        let mut app = App::new();
        let id = Uuid::new_v4();
        app.state.agents = vec![make_agent_with_id(id, "test")];
        assert_eq!(app.state.agents[0].state, AgentState::Running);

        app.dispatch_server_message(ServerMessage::AgentStateChanged {
            agent_id: id,
            state: AgentState::Paused,
        });
        assert_eq!(app.state.agents[0].state, AgentState::Paused);
    }

    #[test]
    fn test_dispatch_agent_state_changed_unknown_id() {
        let mut app = App::new();
        app.state.agents = vec![make_agent("test")];
        let original_state = app.state.agents[0].state.clone();

        app.dispatch_server_message(ServerMessage::AgentStateChanged {
            agent_id: Uuid::new_v4(),
            state: AgentState::Stopped,
        });
        // Should not change anything since the id doesn't match
        assert_eq!(app.state.agents[0].state, original_state);
    }

    #[test]
    fn test_dispatch_thoughts_replaces_list() {
        let mut app = App::new();
        app.state.thought_scroll_offset = 10;
        let thoughts = vec![ThoughtData {
            id: Uuid::new_v4(),
            timestamp: 1.0,
            thought_type: ThoughtType::Decision,
            confidence: 0.8,
            content: "decided something".to_string(),
            provenance: None,
            source: None,
            rationale: None,
            alternatives: vec![],
        }];
        app.dispatch_server_message(ServerMessage::Thoughts {
            thoughts,
            total: 1,
        });
        assert_eq!(app.state.thoughts.len(), 1);
        assert_eq!(app.state.thoughts[0].content, "decided something");
        assert_eq!(app.state.thought_scroll_offset, 0);
    }

    #[test]
    fn test_dispatch_thought_added_matching_agent() {
        let mut app = App::new();
        let agent_id = Uuid::new_v4();
        app.state.agents = vec![make_agent_with_id(agent_id, "selected")];
        app.state.selected_agent_index = 0;

        let thought = make_thought(agent_id);
        app.dispatch_server_message(ServerMessage::ThoughtAdded {
            agent_id,
            thought: thought.clone(),
        });

        assert_eq!(app.state.thoughts.len(), 1);
        assert_eq!(app.state.agents[0].thought_count, 1);
    }

    #[test]
    fn test_dispatch_thought_added_different_agent() {
        let mut app = App::new();
        let selected_id = Uuid::new_v4();
        let other_id = Uuid::new_v4();
        app.state.agents = vec![
            make_agent_with_id(selected_id, "selected"),
            make_agent_with_id(other_id, "other"),
        ];
        app.state.selected_agent_index = 0;

        let thought = make_thought(other_id);
        app.dispatch_server_message(ServerMessage::ThoughtAdded {
            agent_id: other_id,
            thought,
        });

        // Thought should NOT be added to the view since it's for a different agent
        assert!(app.state.thoughts.is_empty());
        // But the thought count should still be incremented
        assert_eq!(app.state.agents[1].thought_count, 1);
    }

    #[test]
    fn test_dispatch_blocking_requests() {
        let mut app = App::new();
        let requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Continue?".to_string(),
            context: None,
            options: vec!["yes".to_string(), "no".to_string()],
            default_value: None,
            status: None,
            created_at: None,
        }];
        app.dispatch_server_message(ServerMessage::BlockingRequests { requests });
        assert_eq!(app.state.blocking_requests.len(), 1);
        assert_eq!(app.state.blocking_requests[0].id, "req-1");
    }

    #[test]
    fn test_dispatch_blocking_request_pushes() {
        let mut app = App::new();
        let request = BlockingRequestData {
            id: "req-2".to_string(),
            prompt: "Approve?".to_string(),
            context: None,
            options: vec![],
            default_value: None,
            status: None,
            created_at: None,
        };
        app.dispatch_server_message(ServerMessage::BlockingRequest { request });
        assert_eq!(app.state.blocking_requests.len(), 1);
        assert_eq!(app.state.blocking_requests[0].prompt, "Approve?");
    }

    #[test]
    fn test_dispatch_blocking_responded_removes() {
        let mut app = App::new();
        app.state.blocking_requests = vec![
            BlockingRequestData {
                id: "req-a".to_string(),
                prompt: "A?".to_string(),
                context: None,
                options: vec![],
                default_value: None,
                status: None,
                created_at: None,
            },
            BlockingRequestData {
                id: "req-b".to_string(),
                prompt: "B?".to_string(),
                context: None,
                options: vec![],
                default_value: None,
                status: None,
                created_at: None,
            },
        ];
        app.dispatch_server_message(ServerMessage::BlockingResponded {
            blocking_request_id: "req-a".to_string(),
        });
        assert_eq!(app.state.blocking_requests.len(), 1);
        assert_eq!(app.state.blocking_requests[0].id, "req-b");
    }

    #[test]
    fn test_upsert_agent_insert() {
        let mut app = App::new();
        let agent = make_agent("new");
        app.upsert_agent(agent.clone());
        assert_eq!(app.state.agents.len(), 1);
        assert_eq!(app.state.agents[0].name, "new");
    }

    #[test]
    fn test_upsert_agent_update() {
        let mut app = App::new();
        let id = Uuid::new_v4();
        app.state.agents = vec![make_agent_with_id(id, "original")];

        let mut updated = make_agent_with_id(id, "updated");
        updated.state = AgentState::Paused;
        app.upsert_agent(updated);

        assert_eq!(app.state.agents.len(), 1);
        assert_eq!(app.state.agents[0].name, "updated");
        assert_eq!(app.state.agents[0].state, AgentState::Paused);
    }

    #[test]
    fn test_dispatch_pong_sets_connected() {
        let mut app = App::new();
        assert_eq!(app.state.connection, ConnectionStatus::Disconnected);
        app.dispatch_server_message(ServerMessage::Pong);
        assert_eq!(app.state.connection, ConnectionStatus::Connected);
    }

    #[test]
    fn test_dispatch_subscribed_sets_connected() {
        let mut app = App::new();
        app.dispatch_server_message(ServerMessage::Subscribed {
            channel: "agents".to_string(),
        });
        assert_eq!(app.state.connection, ConnectionStatus::Connected);
    }

    #[test]
    fn test_dispatch_unknown_is_noop() {
        let mut app = App::new();
        app.dispatch_server_message(ServerMessage::Unknown);
        assert_eq!(app.state.connection, ConnectionStatus::Disconnected);
        assert!(app.state.agents.is_empty());
    }

    #[test]
    fn test_handle_input_quit() {
        let mut app = App::new();
        let key = KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE);
        app.handle_input(key);
        assert!(app.state.should_quit);
    }

    #[test]
    fn test_handle_input_enter_command_mode() {
        let mut app = App::new();
        let key = KeyEvent::new(KeyCode::Char(':'), KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.input_mode, InputMode::Command);
    }

    #[test]
    fn test_handle_input_exit_command_mode() {
        let mut app = App::new();
        app.state.input_mode = InputMode::Command;
        app.state.command_input = "partial".to_string();
        let key = KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.input_mode, InputMode::Normal);
        assert!(app.state.command_input.is_empty());
    }

    #[test]
    fn test_handle_input_command_typing() {
        let mut app = App::new();
        app.state.input_mode = InputMode::Command;
        let key = KeyEvent::new(KeyCode::Char('a'), KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.command_input, "a");
    }

    #[test]
    fn test_handle_input_command_backspace() {
        let mut app = App::new();
        app.state.input_mode = InputMode::Command;
        app.state.command_input = "ab".to_string();
        let key = KeyEvent::new(KeyCode::Backspace, KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.command_input, "a");
    }

    #[test]
    fn test_handle_input_submit_command() {
        let mut app = App::new();
        app.state.input_mode = InputMode::Command;
        app.state.command_input = "create agent foo".to_string();
        let key = KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.input_mode, InputMode::Normal);
        assert!(app.state.command_input.is_empty());
        assert_eq!(app.state.command_history.len(), 1);
        assert_eq!(app.state.command_history[0], "create agent foo");
    }

    #[test]
    fn test_handle_input_scroll_up() {
        let mut app = App::new();
        app.state.thought_scroll_offset = 5;
        let key = KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.thought_scroll_offset, 2);
    }

    #[test]
    fn test_handle_input_scroll_down() {
        let mut app = App::new();
        app.state.thought_scroll_offset = 0;
        let key = KeyEvent::new(KeyCode::PageDown, KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.thought_scroll_offset, 3);
    }

    #[test]
    fn test_handle_input_scroll_up_clamps_to_zero() {
        let mut app = App::new();
        app.state.thought_scroll_offset = 1;
        let key = KeyEvent::new(KeyCode::PageUp, KeyModifiers::NONE);
        app.handle_input(key);
        assert_eq!(app.state.thought_scroll_offset, 0);
    }

    #[test]
    fn test_handle_input_agent_navigation() {
        let mut app = App::new();
        app.state.agents = vec![make_agent("a"), make_agent("b"), make_agent("c")];
        assert_eq!(app.state.selected_agent_index, 0);

        let key_j = KeyEvent::new(KeyCode::Char('j'), KeyModifiers::NONE);
        app.handle_input(key_j);
        assert_eq!(app.state.selected_agent_index, 1);

        let key_k = KeyEvent::new(KeyCode::Char('k'), KeyModifiers::NONE);
        app.handle_input(key_k);
        assert_eq!(app.state.selected_agent_index, 0);
    }

    #[test]
    fn test_dispatch_agent_updates_existing() {
        let mut app = App::new();
        let id = Uuid::new_v4();
        app.state.agents = vec![make_agent_with_id(id, "v1")];

        let mut updated = make_agent_with_id(id, "v2");
        updated.thought_count = 42;
        app.dispatch_server_message(ServerMessage::Agent { agent: updated });

        assert_eq!(app.state.agents.len(), 1);
        assert_eq!(app.state.agents[0].name, "v2");
        assert_eq!(app.state.agents[0].thought_count, 42);
    }

    #[test]
    fn test_dispatch_stream_format_set_connects() {
        let mut app = App::new();
        app.dispatch_server_message(ServerMessage::StreamFormatSet);
        assert_eq!(app.state.connection, ConnectionStatus::Connected);
    }
}
