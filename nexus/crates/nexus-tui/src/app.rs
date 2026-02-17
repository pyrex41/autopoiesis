use std::io;
use std::time::Duration;

use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use tokio::sync::broadcast;

use nexus_protocol::types::*;
use nexus_protocol::ws::WsHandle;

use crate::input::{self, Action};
use crate::keybinds::{LeaderAction, LeaderState};
use crate::layout::{AppLayout, FocusedPane};
use crate::notifications::{NotificationLevel, NotificationStack};
use crate::state::{AppState, ConnectionStatus, InputMode, VoiceMode};
use crate::widgets::{
    agent_detail::AgentDetail, agent_list::AgentList, blocking_prompt::BlockingPrompt,
    chat::Chat, command_bar::CommandBar, status_bar::StatusBar, thought_stream::ThoughtStream,
};

const TICK_RATE: Duration = Duration::from_millis(16); // ~60fps

pub struct App {
    pub state: AppState,
    ws_handle: Option<WsHandle>,
    ws_rx: Option<broadcast::Receiver<ServerMessage>>,
    leader_state: LeaderState,
    blocking_selected_option: usize,
    blocking_custom_input: String,
    blocking_is_typing_custom: bool,
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
            leader_state: LeaderState::default(),
            blocking_selected_option: 0,
            blocking_custom_input: String::new(),
            blocking_is_typing_custom: false,
        }
    }

    pub fn with_history(mut self, history: Vec<String>) -> Self {
        self.state.command_history = history;
        self
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
                    self.state.prune_notifications();
                    if let Some(err) = self.state.voice_error.take() {
                        self.state.push_notification(&format!("Voice: {}", err), NotificationLevel::Warning);
                    }
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
        let has_blocking = !self.state.blocking_requests.is_empty();
        let layout = AppLayout::with_mode(frame.area(), self.state.layout_mode, has_blocking);

        frame.render_widget(StatusBar::new(&self.state), layout.status_bar);
        frame.render_widget(AgentList::new(&self.state), layout.agent_list);
        frame.render_widget(AgentDetail::new(&self.state), layout.agent_detail);
        frame.render_widget(ThoughtStream::new(&self.state), layout.thought_stream);
        frame.render_widget(CommandBar::new(&self.state), layout.command_bar);

        // Blocking prompt overlay
        if let Some(blocking_area) = layout.blocking_prompt {
            if let Some(request) = self.state.blocking_requests.first() {
                frame.render_widget(
                    BlockingPrompt::new(
                        request,
                        self.blocking_selected_option,
                        &self.blocking_custom_input,
                        self.blocking_is_typing_custom,
                    ),
                    blocking_area,
                );
            }
        }

        // Chat panel (only in Focused mode)
        if let Some(chat_area) = layout.chat_area {
            let is_active = self.state.focused_pane == FocusedPane::Chat;
            frame.render_widget(
                Chat::new(&self.state.chat_messages, &self.state.chat_input, is_active),
                chat_area,
            );
        }

        // Secondary panel: MCP panel or Snapshot DAG
        if let Some(snap_area) = layout.secondary_panel {
            if self.state.focused_pane == FocusedPane::McpPanel {
                use crate::widgets::mcp_panel::McpPanel;
                frame.render_widget(
                    McpPanel::new(
                        &self.state.mcp_servers,
                        self.state.selected_mcp_server_idx,
                        true,
                    ),
                    snap_area,
                );
            } else {
                use crate::widgets::snapshot_dag::SnapshotDag;
                let is_focused = self.state.focused_pane == FocusedPane::SnapshotDag;
                frame.render_widget(
                    SnapshotDag::new(
                        &self.state.snapshots,
                        &self.state.branches,
                        self.state.current_branch.as_deref(),
                        self.state.selected_snapshot_idx,
                        is_focused,
                    ),
                    snap_area,
                );
            }
        }

        // Notifications always render
        frame.render_widget(
            NotificationStack::new(&self.state.notifications),
            layout.notification_area,
        );

        // Help overlay (renders on top of everything else)
        if self.state.show_help {
            use crate::widgets::help_overlay::HelpOverlay;
            use ratatui::widgets::Widget;
            HelpOverlay::new().render(frame.area(), frame.buffer_mut());
        }
    }

    fn handle_input(&mut self, key: crossterm::event::KeyEvent) {
        // Help overlay consumes all keys when shown
        if self.state.show_help {
            if matches!(key.code, KeyCode::Esc | KeyCode::Char('?')) {
                self.state.show_help = false;
            }
            return;
        }

        // Ctrl+L force redraw — consumed, next render tick handles it
        if key.modifiers.contains(crossterm::event::KeyModifiers::CONTROL)
            && key.code == KeyCode::Char('l')
        {
            return;
        }

        // Handle blocking prompt focus
        if self.state.focused_pane == FocusedPane::BlockingPrompt {
            self.handle_blocking_input(key);
            return;
        }

        // Handle chat focus
        if self.state.focused_pane == FocusedPane::Chat {
            self.handle_chat_input(key);
            return;
        }

        // Handle snapshot DAG focus
        if self.state.focused_pane == FocusedPane::SnapshotDag {
            match key.code {
                KeyCode::Char('j') | KeyCode::Down => self.state.select_next_snapshot(),
                KeyCode::Char('k') | KeyCode::Up => self.state.select_prev_snapshot(),
                KeyCode::Esc => self.state.focused_pane = FocusedPane::AgentList,
                _ => {}
            }
            return;
        }

        // Handle MCP panel focus
        if self.state.focused_pane == FocusedPane::McpPanel {
            match key.code {
                KeyCode::Char('j') | KeyCode::Down => self.state.select_next_mcp_server(),
                KeyCode::Char('k') | KeyCode::Up => self.state.select_prev_mcp_server(),
                KeyCode::Esc => self.state.focused_pane = FocusedPane::AgentList,
                _ => {}
            }
            return;
        }

        // In command mode, delegate to the existing input handler
        if self.state.input_mode == InputMode::Command {
            let action =
                input::handle_key_event(key, &self.state.input_mode, &self.state.command_input);
            self.dispatch_action(action);
            return;
        }

        // F5: push-to-talk toggle
        if key.code == KeyCode::F(5) {
            if self.state.voice_mode == VoiceMode::PushToTalk {
                if self.state.is_recording {
                    self.state.is_recording = false;
                    self.state
                        .push_notification("Recording stopped", NotificationLevel::Info);
                } else {
                    self.state.is_recording = true;
                    self.state.push_notification(
                        "Recording... (press F5 again to stop)",
                        NotificationLevel::Warning,
                    );
                }
            }
            return;
        }

        // Normal mode: try leader-key system first
        let (new_leader, leader_action) = self.leader_state.process(key);
        self.leader_state = new_leader;

        // Update state for status bar indicator
        self.state.leader_key_active = self.leader_state != LeaderState::Idle;
        self.state.leader_key_prefix = match &self.leader_state {
            LeaderState::WaitingForAction(ch) => Some(*ch),
            _ => None,
        };

        match leader_action {
            LeaderAction::Quit => self.state.should_quit = true,
            LeaderAction::CycleLayout => {
                self.state.cycle_layout_mode();
                let mode_name = match self.state.layout_mode {
                    crate::layout::LayoutMode::Cockpit => "Cockpit",
                    crate::layout::LayoutMode::Focused => "Focused",
                    crate::layout::LayoutMode::Monitor => "Monitor",
                };
                self.state
                    .push_notification(&format!("Layout: {mode_name}"), NotificationLevel::Info);
            }
            LeaderAction::ToggleHelp | LeaderAction::Help => {
                self.state.toggle_help();
            }
            LeaderAction::ToggleVoice => {
                self.state.toggle_voice_mode();
                let mode_name = match self.state.voice_mode {
                    VoiceMode::Disabled => "Off",
                    VoiceMode::PushToTalk => "Push-to-Talk",
                    VoiceMode::VoiceActivated => "Voice Activated",
                };
                self.state
                    .push_notification(&format!("Voice: {mode_name}"), NotificationLevel::Info);
            }
            LeaderAction::FocusNext => {
                self.state.focused_pane = self.state.focused_pane.next();
            }
            LeaderAction::FocusPrev => {
                self.state.focused_pane = self.state.focused_pane.prev();
            }
            LeaderAction::AgentCreate => {
                self.state.input_mode = InputMode::Command;
                self.state.command_input = "create agent ".to_string();
            }
            LeaderAction::AgentStep => {
                if let Some(id) = self.state.selected_agent_id() {
                    self.send_ws(ClientMessage::StepAgent {
                        agent_id: id,
                        environment: None,
                    });
                }
            }
            LeaderAction::AgentStart => {
                if let Some(id) = self.state.selected_agent_id() {
                    self.send_ws(ClientMessage::AgentAction {
                        agent_id: id,
                        action: "start".to_string(),
                    });
                }
            }
            LeaderAction::AgentPause => {
                if let Some(id) = self.state.selected_agent_id() {
                    self.send_ws(ClientMessage::AgentAction {
                        agent_id: id,
                        action: "pause".to_string(),
                    });
                }
            }
            LeaderAction::AgentStop => {
                if let Some(id) = self.state.selected_agent_id() {
                    self.send_ws(ClientMessage::AgentAction {
                        agent_id: id,
                        action: "stop".to_string(),
                    });
                }
            }
            LeaderAction::AgentInjectThought => {
                self.state.input_mode = InputMode::Command;
                self.state.command_input.clear();
            }
            LeaderAction::AgentMenu | LeaderAction::SnapshotMenu | LeaderAction::BranchMenu => {
                // These are intermediate states — waiting for next key
            }
            LeaderAction::Cancelled => {
                // Leader sequence cancelled, do nothing
            }
            LeaderAction::None => {
                // No leader action consumed the key — fall through to normal input
                let action = input::handle_key_event(
                    key,
                    &self.state.input_mode,
                    &self.state.command_input,
                );
                self.dispatch_action(action);
            }
        }
    }

    fn handle_blocking_input(&mut self, key: crossterm::event::KeyEvent) {
        let option_count = self
            .state
            .blocking_requests
            .first()
            .map(|r| r.options.len())
            .unwrap_or(0);

        match key.code {
            KeyCode::Char('j') | KeyCode::Down => {
                if !self.blocking_is_typing_custom && option_count > 0 {
                    self.blocking_selected_option =
                        (self.blocking_selected_option + 1) % option_count;
                }
            }
            KeyCode::Char('k') | KeyCode::Up => {
                if !self.blocking_is_typing_custom && option_count > 0 {
                    self.blocking_selected_option = if self.blocking_selected_option == 0 {
                        option_count.saturating_sub(1)
                    } else {
                        self.blocking_selected_option - 1
                    };
                }
            }
            KeyCode::Tab => {
                self.blocking_is_typing_custom = !self.blocking_is_typing_custom;
            }
            KeyCode::Enter => {
                let response = if self.blocking_is_typing_custom {
                    self.blocking_custom_input.clone()
                } else if let Some(request) = self.state.blocking_requests.first() {
                    request
                        .options
                        .get(self.blocking_selected_option)
                        .cloned()
                        .unwrap_or_default()
                } else {
                    String::new()
                };

                if let Some(request) = self.state.blocking_requests.first() {
                    let request_id = request.id.clone();
                    self.send_ws(ClientMessage::RespondBlocking {
                        blocking_request_id: request_id,
                        response,
                    });
                }

                // Reset blocking state
                self.blocking_selected_option = 0;
                self.blocking_custom_input.clear();
                self.blocking_is_typing_custom = false;
                self.state.focused_pane = FocusedPane::AgentList;
            }
            KeyCode::Esc => {
                self.state.focused_pane = FocusedPane::AgentList;
                self.blocking_is_typing_custom = false;
            }
            KeyCode::Backspace if self.blocking_is_typing_custom => {
                self.blocking_custom_input.pop();
            }
            KeyCode::Char(c) if self.blocking_is_typing_custom => {
                self.blocking_custom_input.push(c);
            }
            _ => {}
        }
    }

    fn handle_chat_input(&mut self, key: crossterm::event::KeyEvent) {
        match key.code {
            KeyCode::Esc => {
                self.state.focused_pane = FocusedPane::AgentList;
            }
            KeyCode::Enter => {
                if !self.state.chat_input.is_empty() {
                    let content = self.state.chat_input.clone();
                    self.state.chat_messages.push(
                        crate::widgets::chat::ChatMessage {
                            sender: crate::widgets::chat::ChatSender::User,
                            content,
                        },
                    );
                    self.state.chat_input.clear();
                }
            }
            KeyCode::Backspace => {
                self.state.chat_input.pop();
            }
            KeyCode::Char(c) => {
                self.state.chat_input.push(c);
            }
            _ => {}
        }
    }

    fn dispatch_action(&mut self, action: Action) {
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
                let name = agent.name.clone();
                self.upsert_agent(agent);
                self.state.push_notification(
                    &format!("Agent '{name}' created"),
                    NotificationLevel::Success,
                );
            }
            ServerMessage::AgentStateChanged { agent_id, state } => {
                let state_label = format!("{state:?}");
                if let Some(a) = self.state.agents.iter_mut().find(|a| a.id == agent_id) {
                    a.state = state;
                }
                self.state.push_notification(
                    &format!("Agent state -> {state_label}"),
                    NotificationLevel::Info,
                );
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
            ServerMessage::Snapshots { snapshots } => {
                self.state.snapshots = snapshots;
            }
            ServerMessage::Snapshot { snapshot, .. } => {
                if let Some(existing) = self.state.snapshots.iter_mut().find(|s| s.id == snapshot.id)
                {
                    *existing = snapshot;
                } else {
                    self.state.push_snapshot(snapshot);
                }
            }
            ServerMessage::SnapshotCreated { snapshot } => {
                let short_id: String = snapshot.id.chars().take(8).collect();
                self.state.push_snapshot(snapshot);
                self.state.push_notification(
                    &format!("Snapshot created: {}", short_id),
                    NotificationLevel::Success,
                );
            }
            ServerMessage::Branches { branches, current } => {
                self.state.update_branches(branches, current);
            }
            ServerMessage::BranchCreated { branch } => {
                self.state.push_notification(
                    &format!("Branch created: {}", branch.name),
                    NotificationLevel::Success,
                );
                self.state.branches.push(branch);
            }
            ServerMessage::BranchSwitched { branch } => {
                self.state.push_notification(
                    &format!("Switched to branch: {}", branch.name),
                    NotificationLevel::Info,
                );
                self.state.current_branch = Some(branch.name);
            }
            ServerMessage::BlockingRequests { requests } => {
                self.state.blocking_requests = requests;
            }
            ServerMessage::BlockingRequest { request } => {
                let prompt_preview: String = request.prompt.chars().take(40).collect();
                self.state.blocking_requests.push(request);
                self.state.push_notification(
                    &format!("Blocking: {prompt_preview}"),
                    NotificationLevel::Warning,
                );
                self.state.focused_pane = FocusedPane::BlockingPrompt;
                self.blocking_selected_option = 0;
                self.blocking_custom_input.clear();
                self.blocking_is_typing_custom = false;
            }
            ServerMessage::BlockingResponded {
                blocking_request_id,
            } => {
                self.state
                    .blocking_requests
                    .retain(|r| r.id != blocking_request_id);
                self.state
                    .push_notification("Request resolved", NotificationLevel::Info);
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

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    fn ctrl_key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::CONTROL)
    }

    fn shift_key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::SHIFT)
    }

    #[test]
    fn test_app_new_default_state() {
        let app = App::new();
        assert_eq!(app.state.connection, ConnectionStatus::Disconnected);
        assert!(app.state.agents.is_empty());
        assert!(app.ws_handle.is_none());
        assert!(app.ws_rx.is_none());
        assert!(!app.state.should_quit);
        assert_eq!(app.leader_state, LeaderState::Idle);
        assert_eq!(app.blocking_selected_option, 0);
        assert!(app.blocking_custom_input.is_empty());
        assert!(!app.blocking_is_typing_custom);
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

    // === Phase 2 tests ===

    #[test]
    fn test_leader_key_space_l_cycles_layout() {
        let mut app = App::new();
        assert_eq!(app.state.layout_mode, crate::layout::LayoutMode::Cockpit);

        // Space
        app.handle_input(key(KeyCode::Char(' ')));
        assert!(app.state.leader_key_active);

        // l
        app.handle_input(key(KeyCode::Char('l')));
        assert_eq!(app.state.layout_mode, crate::layout::LayoutMode::Focused);
        assert!(!app.state.leader_key_active);
        assert_eq!(app.state.notifications.len(), 1);
    }

    #[test]
    fn test_leader_key_space_h_toggles_help() {
        let mut app = App::new();
        assert!(!app.state.show_help);

        // Space h opens help
        app.handle_input(key(KeyCode::Char(' ')));
        app.handle_input(key(KeyCode::Char('h')));
        assert!(app.state.show_help);

        // ? closes help (help overlay consumes all keys, so Space h won't work)
        app.handle_input(key(KeyCode::Char('?')));
        assert!(!app.state.show_help);
    }

    #[test]
    fn test_help_overlay_esc_closes() {
        let mut app = App::new();
        app.state.show_help = true;

        app.handle_input(key(KeyCode::Esc));
        assert!(!app.state.show_help);
    }

    #[test]
    fn test_help_overlay_consumes_other_keys() {
        let mut app = App::new();
        app.state.show_help = true;

        // Other keys should be consumed without effect
        app.handle_input(key(KeyCode::Char('q')));
        assert!(!app.state.should_quit);
        assert!(app.state.show_help);
    }

    #[test]
    fn test_tab_cycles_focus() {
        let mut app = App::new();
        assert_eq!(app.state.focused_pane, FocusedPane::AgentList);

        app.handle_input(key(KeyCode::Tab));
        assert_eq!(app.state.focused_pane, FocusedPane::PrimaryDetail);
    }

    #[test]
    fn test_shift_tab_cycles_focus_reverse() {
        let mut app = App::new();
        assert_eq!(app.state.focused_pane, FocusedPane::AgentList);

        app.handle_input(shift_key(KeyCode::Tab));
        assert_eq!(app.state.focused_pane, FocusedPane::CommandBar);
    }

    #[test]
    fn test_ctrl_q_quits() {
        let mut app = App::new();
        app.handle_input(ctrl_key(KeyCode::Char('q')));
        assert!(app.state.should_quit);
    }

    #[test]
    fn test_agent_created_emits_notification() {
        let mut app = App::new();
        let agent = make_agent("test-bot");
        app.dispatch_server_message(ServerMessage::AgentCreated {
            agent: agent.clone(),
        });
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0].message.contains("test-bot"));
        assert_eq!(
            app.state.notifications[0].level,
            NotificationLevel::Success
        );
    }

    #[test]
    fn test_agent_state_changed_emits_notification() {
        let mut app = App::new();
        let id = Uuid::new_v4();
        app.state.agents = vec![make_agent_with_id(id, "test")];

        app.dispatch_server_message(ServerMessage::AgentStateChanged {
            agent_id: id,
            state: AgentState::Paused,
        });
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0].message.contains("Paused"));
    }

    #[test]
    fn test_blocking_request_emits_notification_and_focuses() {
        let mut app = App::new();
        let request = BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Should I continue?".to_string(),
            context: None,
            options: vec!["yes".to_string(), "no".to_string()],
            default_value: None,
            status: None,
            created_at: None,
        };
        app.dispatch_server_message(ServerMessage::BlockingRequest { request });
        assert_eq!(app.state.focused_pane, FocusedPane::BlockingPrompt);
        assert_eq!(app.state.notifications.len(), 1);
        assert_eq!(
            app.state.notifications[0].level,
            NotificationLevel::Warning
        );
    }

    #[test]
    fn test_blocking_responded_emits_notification() {
        let mut app = App::new();
        app.state.blocking_requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "test".to_string(),
            context: None,
            options: vec![],
            default_value: None,
            status: None,
            created_at: None,
        }];
        app.dispatch_server_message(ServerMessage::BlockingResponded {
            blocking_request_id: "req-1".to_string(),
        });
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0]
            .message
            .contains("Request resolved"));
    }

    #[test]
    fn test_blocking_prompt_option_navigation() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::BlockingPrompt;
        app.state.blocking_requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Choose".to_string(),
            context: None,
            options: vec!["a".to_string(), "b".to_string(), "c".to_string()],
            default_value: None,
            status: None,
            created_at: None,
        }];

        assert_eq!(app.blocking_selected_option, 0);
        app.handle_input(key(KeyCode::Char('j')));
        assert_eq!(app.blocking_selected_option, 1);
        app.handle_input(key(KeyCode::Char('j')));
        assert_eq!(app.blocking_selected_option, 2);
        app.handle_input(key(KeyCode::Char('j')));
        assert_eq!(app.blocking_selected_option, 0); // wraps

        app.handle_input(key(KeyCode::Char('k')));
        assert_eq!(app.blocking_selected_option, 2); // wraps back
    }

    #[test]
    fn test_blocking_prompt_tab_toggles_custom() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::BlockingPrompt;
        app.state.blocking_requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Choose".to_string(),
            context: None,
            options: vec!["a".to_string()],
            default_value: None,
            status: None,
            created_at: None,
        }];

        assert!(!app.blocking_is_typing_custom);
        app.handle_input(key(KeyCode::Tab));
        assert!(app.blocking_is_typing_custom);
        app.handle_input(key(KeyCode::Tab));
        assert!(!app.blocking_is_typing_custom);
    }

    #[test]
    fn test_blocking_prompt_custom_typing() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::BlockingPrompt;
        app.blocking_is_typing_custom = true;
        app.state.blocking_requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Choose".to_string(),
            context: None,
            options: vec![],
            default_value: None,
            status: None,
            created_at: None,
        }];

        app.handle_input(key(KeyCode::Char('h')));
        app.handle_input(key(KeyCode::Char('i')));
        assert_eq!(app.blocking_custom_input, "hi");

        app.handle_input(key(KeyCode::Backspace));
        assert_eq!(app.blocking_custom_input, "h");
    }

    #[test]
    fn test_blocking_prompt_esc_returns_focus() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::BlockingPrompt;
        app.state.blocking_requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Choose".to_string(),
            context: None,
            options: vec![],
            default_value: None,
            status: None,
            created_at: None,
        }];

        app.handle_input(key(KeyCode::Esc));
        assert_eq!(app.state.focused_pane, FocusedPane::AgentList);
    }

    #[test]
    fn test_chat_input_esc_returns_focus() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::Chat;

        app.handle_input(key(KeyCode::Esc));
        assert_eq!(app.state.focused_pane, FocusedPane::AgentList);
    }

    #[test]
    fn test_chat_typing_and_submit() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::Chat;

        app.handle_input(key(KeyCode::Char('h')));
        app.handle_input(key(KeyCode::Char('i')));
        assert_eq!(app.state.chat_input, "hi");

        app.handle_input(key(KeyCode::Enter));
        assert!(app.state.chat_input.is_empty());
        assert_eq!(app.state.chat_messages.len(), 1);
        assert_eq!(app.state.chat_messages[0].content, "hi");
    }

    #[test]
    fn test_leader_key_space_a_c_enters_command_mode() {
        let mut app = App::new();
        app.handle_input(key(KeyCode::Char(' ')));
        app.handle_input(key(KeyCode::Char('a')));
        app.handle_input(key(KeyCode::Char('c')));
        assert_eq!(app.state.input_mode, InputMode::Command);
        assert_eq!(app.state.command_input, "create agent ");
    }

    #[test]
    fn test_render_with_layout_modes() {
        use ratatui::backend::TestBackend;

        let app = App::new();
        let backend = TestBackend::new(120, 40);
        let mut terminal = Terminal::new(backend).unwrap();

        // Cockpit mode
        terminal
            .draw(|f| {
                app.render(f);
            })
            .unwrap();

        // Focused mode
        let mut app = App::new();
        app.state.layout_mode = crate::layout::LayoutMode::Focused;
        terminal
            .draw(|f| {
                app.render(f);
            })
            .unwrap();

        // Monitor mode
        app.state.layout_mode = crate::layout::LayoutMode::Monitor;
        terminal
            .draw(|f| {
                app.render(f);
            })
            .unwrap();
    }

    #[test]
    fn test_render_with_blocking_request() {
        use ratatui::backend::TestBackend;

        let mut app = App::new();
        app.state.blocking_requests = vec![BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Continue?".to_string(),
            context: None,
            options: vec!["yes".to_string(), "no".to_string()],
            default_value: None,
            status: None,
            created_at: None,
        }];

        let backend = TestBackend::new(120, 40);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                app.render(f);
            })
            .unwrap();
    }

    #[test]
    fn test_render_with_notifications() {
        use ratatui::backend::TestBackend;

        let mut app = App::new();
        app.state
            .push_notification("Test notification", NotificationLevel::Info);

        let backend = TestBackend::new(120, 40);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                app.render(f);
            })
            .unwrap();
    }

    // === Phase 6 tests ===

    fn make_snapshot(id: &str, ts: f64) -> SnapshotData {
        SnapshotData {
            id: id.to_string(),
            parent: None,
            hash: None,
            metadata: None,
            timestamp: ts,
        }
    }

    fn make_branch(name: &str, head: Option<&str>) -> BranchData {
        BranchData {
            name: name.to_string(),
            head: head.map(|s| s.to_string()),
            created: None,
        }
    }

    #[test]
    fn test_dispatch_snapshots() {
        let mut app = App::new();
        let snaps = vec![make_snapshot("s1", 100.0), make_snapshot("s2", 200.0)];
        app.dispatch_server_message(ServerMessage::Snapshots { snapshots: snaps });
        assert_eq!(app.state.snapshots.len(), 2);
        assert_eq!(app.state.snapshots[0].id, "s1");
    }

    #[test]
    fn test_dispatch_snapshot_upsert_existing() {
        let mut app = App::new();
        app.state.snapshots = vec![make_snapshot("s1", 100.0)];

        let mut updated = make_snapshot("s1", 150.0);
        updated.hash = Some("newhash".to_string());
        app.dispatch_server_message(ServerMessage::Snapshot {
            snapshot: updated,
            agent_state: None,
        });
        assert_eq!(app.state.snapshots.len(), 1);
        assert_eq!(app.state.snapshots[0].hash, Some("newhash".to_string()));
    }

    #[test]
    fn test_dispatch_snapshot_upsert_new() {
        let mut app = App::new();
        app.state.snapshots = vec![make_snapshot("s1", 100.0)];

        app.dispatch_server_message(ServerMessage::Snapshot {
            snapshot: make_snapshot("s2", 200.0),
            agent_state: None,
        });
        assert_eq!(app.state.snapshots.len(), 2);
    }

    #[test]
    fn test_dispatch_snapshot_created() {
        let mut app = App::new();
        app.dispatch_server_message(ServerMessage::SnapshotCreated {
            snapshot: make_snapshot("abcd1234rest", 100.0),
        });
        assert_eq!(app.state.snapshots.len(), 1);
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0].message.contains("abcd1234"));
        assert_eq!(
            app.state.notifications[0].level,
            NotificationLevel::Success,
        );
    }

    #[test]
    fn test_dispatch_branches() {
        let mut app = App::new();
        let branches = vec![
            make_branch("main", Some("s1")),
            make_branch("dev", None),
        ];
        app.dispatch_server_message(ServerMessage::Branches {
            branches,
            current: Some("main".to_string()),
        });
        assert_eq!(app.state.branches.len(), 2);
        assert_eq!(app.state.current_branch, Some("main".to_string()));
    }

    #[test]
    fn test_dispatch_branch_created() {
        let mut app = App::new();
        app.dispatch_server_message(ServerMessage::BranchCreated {
            branch: make_branch("feature", Some("s1")),
        });
        assert_eq!(app.state.branches.len(), 1);
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0].message.contains("feature"));
    }

    #[test]
    fn test_dispatch_branch_switched() {
        let mut app = App::new();
        app.dispatch_server_message(ServerMessage::BranchSwitched {
            branch: make_branch("dev", Some("s2")),
        });
        assert_eq!(app.state.current_branch, Some("dev".to_string()));
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0].message.contains("dev"));
    }

    #[test]
    fn test_snapshot_dag_navigation() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::SnapshotDag;
        app.state.snapshots = vec![
            make_snapshot("a", 1.0),
            make_snapshot("b", 2.0),
            make_snapshot("c", 3.0),
        ];
        assert_eq!(app.state.selected_snapshot_idx, 0);

        app.handle_input(key(KeyCode::Char('j')));
        assert_eq!(app.state.selected_snapshot_idx, 1);

        app.handle_input(key(KeyCode::Char('k')));
        assert_eq!(app.state.selected_snapshot_idx, 0);

        app.handle_input(key(KeyCode::Down));
        assert_eq!(app.state.selected_snapshot_idx, 1);

        app.handle_input(key(KeyCode::Up));
        assert_eq!(app.state.selected_snapshot_idx, 0);
    }

    #[test]
    fn test_snapshot_dag_esc_returns_focus() {
        let mut app = App::new();
        app.state.focused_pane = FocusedPane::SnapshotDag;

        app.handle_input(key(KeyCode::Esc));
        assert_eq!(app.state.focused_pane, FocusedPane::AgentList);
    }

    #[test]
    fn test_render_with_snapshots() {
        use ratatui::backend::TestBackend;

        let mut app = App::new();
        app.state.snapshots = vec![
            make_snapshot("snap1234abcd", 100.0),
            make_snapshot("snap5678efgh", 200.0),
        ];
        app.state.branches = vec![make_branch("main", Some("snap5678efgh"))];
        app.state.current_branch = Some("main".to_string());

        let backend = TestBackend::new(120, 40);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                app.render(f);
            })
            .unwrap();
    }

    // === Voice tests ===

    #[test]
    fn test_leader_key_space_v_toggles_voice() {
        let mut app = App::new();
        assert_eq!(app.state.voice_mode, VoiceMode::Disabled);

        // Space v -> PushToTalk
        app.handle_input(key(KeyCode::Char(' ')));
        app.handle_input(key(KeyCode::Char('v')));
        assert_eq!(app.state.voice_mode, VoiceMode::PushToTalk);
        assert_eq!(app.state.notifications.len(), 1);
        assert!(app.state.notifications[0].message.contains("Push-to-Talk"));

        // Space v -> VoiceActivated
        app.handle_input(key(KeyCode::Char(' ')));
        app.handle_input(key(KeyCode::Char('v')));
        assert_eq!(app.state.voice_mode, VoiceMode::VoiceActivated);

        // Space v -> Disabled
        app.handle_input(key(KeyCode::Char(' ')));
        app.handle_input(key(KeyCode::Char('v')));
        assert_eq!(app.state.voice_mode, VoiceMode::Disabled);
    }

    #[test]
    fn test_f5_push_to_talk_toggle() {
        let mut app = App::new();
        app.state.voice_mode = VoiceMode::PushToTalk;

        // F5 starts recording
        app.handle_input(key(KeyCode::F(5)));
        assert!(app.state.is_recording);
        assert_eq!(app.state.notifications.len(), 1);

        // F5 again stops recording
        app.handle_input(key(KeyCode::F(5)));
        assert!(!app.state.is_recording);
        assert_eq!(app.state.notifications.len(), 2);
    }

    #[test]
    fn test_f5_does_nothing_when_voice_disabled() {
        let mut app = App::new();
        assert_eq!(app.state.voice_mode, VoiceMode::Disabled);

        app.handle_input(key(KeyCode::F(5)));
        assert!(!app.state.is_recording);
        assert!(app.state.notifications.is_empty());
    }

    #[test]
    fn test_f5_does_nothing_in_vad_mode() {
        let mut app = App::new();
        app.state.voice_mode = VoiceMode::VoiceActivated;

        app.handle_input(key(KeyCode::F(5)));
        assert!(!app.state.is_recording);
        assert!(app.state.notifications.is_empty());
    }
}
