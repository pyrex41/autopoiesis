use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::state::InputMode;

#[derive(Debug, Clone, PartialEq)]
pub enum Action {
    Quit,
    SelectNextAgent,
    SelectPrevAgent,
    EnterCommandMode,
    ExitCommandMode,
    SubmitCommand(String),
    CommandInput(char),
    CommandBackspace,
    ScrollThoughtsUp,
    ScrollThoughtsDown,
    Refresh,
    None,
}

pub fn handle_key_event(key: KeyEvent, mode: &InputMode, command_input: &str) -> Action {
    match mode {
        InputMode::Normal => handle_normal_mode(key),
        InputMode::Command => handle_command_mode(key, command_input),
    }
}

fn handle_normal_mode(key: KeyEvent) -> Action {
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        return Action::Quit;
    }
    match key.code {
        KeyCode::Char('q') => Action::Quit,
        KeyCode::Char('j') | KeyCode::Down => Action::SelectNextAgent,
        KeyCode::Char('k') | KeyCode::Up => Action::SelectPrevAgent,
        KeyCode::Char('/') | KeyCode::Char(':') => Action::EnterCommandMode,
        KeyCode::Char('r') => Action::Refresh,
        KeyCode::PageUp => Action::ScrollThoughtsUp,
        KeyCode::PageDown => Action::ScrollThoughtsDown,
        _ => Action::None,
    }
}

fn handle_command_mode(key: KeyEvent, command_input: &str) -> Action {
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        return Action::ExitCommandMode;
    }
    match key.code {
        KeyCode::Esc => Action::ExitCommandMode,
        KeyCode::Enter => Action::SubmitCommand(command_input.to_string()),
        KeyCode::Backspace => Action::CommandBackspace,
        KeyCode::Char(c) => Action::CommandInput(c),
        _ => Action::None,
    }
}

pub fn parse_command(
    input: &str,
    selected_agent_id: Option<uuid::Uuid>,
) -> Option<nexus_protocol::types::ClientMessage> {
    let parts: Vec<&str> = input.split_whitespace().collect();

    match parts.as_slice() {
        ["create", "agent", name, ..] => Some(nexus_protocol::types::ClientMessage::CreateAgent {
            name: name.to_string(),
            capabilities: vec![],
        }),
        ["snapshot", label, ..] => {
            selected_agent_id.map(|id| nexus_protocol::types::ClientMessage::CreateSnapshot {
                agent_id: id,
                label: label.to_string(),
            })
        }
        ["step", ..] => {
            selected_agent_id.map(|id| nexus_protocol::types::ClientMessage::StepAgent {
                agent_id: id,
                environment: None,
            })
        }
        _ if !input.trim().is_empty() => {
            selected_agent_id.map(|id| nexus_protocol::types::ClientMessage::InjectThought {
                agent_id: id,
                content: input.to_string(),
                thought_type: "observation".into(),
            })
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::KeyEvent;

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    fn ctrl_key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::CONTROL)
    }

    #[test]
    fn test_normal_mode_quit_q() {
        assert_eq!(
            handle_key_event(key(KeyCode::Char('q')), &InputMode::Normal, ""),
            Action::Quit
        );
    }

    #[test]
    fn test_normal_mode_quit_ctrl_c() {
        assert_eq!(
            handle_key_event(ctrl_key(KeyCode::Char('c')), &InputMode::Normal, ""),
            Action::Quit
        );
    }

    #[test]
    fn test_normal_mode_navigation() {
        assert_eq!(
            handle_key_event(key(KeyCode::Char('j')), &InputMode::Normal, ""),
            Action::SelectNextAgent
        );
        assert_eq!(
            handle_key_event(key(KeyCode::Down), &InputMode::Normal, ""),
            Action::SelectNextAgent
        );
        assert_eq!(
            handle_key_event(key(KeyCode::Char('k')), &InputMode::Normal, ""),
            Action::SelectPrevAgent
        );
        assert_eq!(
            handle_key_event(key(KeyCode::Up), &InputMode::Normal, ""),
            Action::SelectPrevAgent
        );
    }

    #[test]
    fn test_normal_mode_enter_command() {
        assert_eq!(
            handle_key_event(key(KeyCode::Char('/')), &InputMode::Normal, ""),
            Action::EnterCommandMode
        );
        assert_eq!(
            handle_key_event(key(KeyCode::Char(':')), &InputMode::Normal, ""),
            Action::EnterCommandMode
        );
    }

    #[test]
    fn test_normal_mode_scroll() {
        assert_eq!(
            handle_key_event(key(KeyCode::PageUp), &InputMode::Normal, ""),
            Action::ScrollThoughtsUp
        );
        assert_eq!(
            handle_key_event(key(KeyCode::PageDown), &InputMode::Normal, ""),
            Action::ScrollThoughtsDown
        );
    }

    #[test]
    fn test_normal_mode_refresh() {
        assert_eq!(
            handle_key_event(key(KeyCode::Char('r')), &InputMode::Normal, ""),
            Action::Refresh
        );
    }

    #[test]
    fn test_normal_mode_unhandled() {
        assert_eq!(
            handle_key_event(key(KeyCode::Char('x')), &InputMode::Normal, ""),
            Action::None
        );
    }

    #[test]
    fn test_command_mode_exit_esc() {
        assert_eq!(
            handle_key_event(key(KeyCode::Esc), &InputMode::Command, ""),
            Action::ExitCommandMode
        );
    }

    #[test]
    fn test_command_mode_exit_ctrl_c() {
        assert_eq!(
            handle_key_event(ctrl_key(KeyCode::Char('c')), &InputMode::Command, ""),
            Action::ExitCommandMode
        );
    }

    #[test]
    fn test_command_mode_submit() {
        assert_eq!(
            handle_key_event(key(KeyCode::Enter), &InputMode::Command, "hello"),
            Action::SubmitCommand("hello".to_string())
        );
    }

    #[test]
    fn test_command_mode_backspace() {
        assert_eq!(
            handle_key_event(key(KeyCode::Backspace), &InputMode::Command, "ab"),
            Action::CommandBackspace
        );
    }

    #[test]
    fn test_command_mode_input() {
        assert_eq!(
            handle_key_event(key(KeyCode::Char('a')), &InputMode::Command, ""),
            Action::CommandInput('a')
        );
    }

    #[test]
    fn test_parse_command_create_agent() {
        let msg = parse_command("create agent foo", None);
        assert!(msg.is_some());
        match msg.unwrap() {
            nexus_protocol::types::ClientMessage::CreateAgent { name, .. } => {
                assert_eq!(name, "foo");
            }
            _ => panic!("Expected CreateAgent"),
        }
    }

    #[test]
    fn test_parse_command_snapshot_requires_agent() {
        assert!(parse_command("snapshot test", None).is_none());

        let id = uuid::Uuid::new_v4();
        let msg = parse_command("snapshot test", Some(id));
        assert!(msg.is_some());
    }

    #[test]
    fn test_parse_command_step_requires_agent() {
        assert!(parse_command("step", None).is_none());

        let id = uuid::Uuid::new_v4();
        let msg = parse_command("step", Some(id));
        assert!(msg.is_some());
    }

    #[test]
    fn test_parse_command_text_injects_thought() {
        let id = uuid::Uuid::new_v4();
        let msg = parse_command("hello world", Some(id));
        assert!(msg.is_some());
        match msg.unwrap() {
            nexus_protocol::types::ClientMessage::InjectThought { content, .. } => {
                assert_eq!(content, "hello world");
            }
            _ => panic!("Expected InjectThought"),
        }
    }

    #[test]
    fn test_parse_command_empty() {
        assert!(parse_command("", None).is_none());
        assert!(parse_command("   ", None).is_none());
    }
}
