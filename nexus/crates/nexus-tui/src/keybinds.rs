use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

/// Represents a keybind action from the leader-key system.
/// The leader key is Space. When pressed, the system waits for the next key.
#[derive(Debug, Clone, PartialEq)]
pub enum LeaderAction {
    // Space + a -> Agent actions submenu
    AgentMenu,
    // Space + s -> Snapshot actions submenu
    SnapshotMenu,
    // Space + b -> Branch actions submenu
    BranchMenu,
    // Space + l -> Cycle layout mode
    CycleLayout,
    // Space + h -> Toggle help overlay
    ToggleHelp,

    // Agent submenu (Space + a + ...)
    AgentCreate,        // Space a c
    AgentStart,         // Space a s
    AgentPause,         // Space a p
    AgentStop,          // Space a x
    AgentStep,          // Space a t
    AgentInjectThought, // Space a i

    // Voice (Space + v)
    ToggleVoice,

    // Holodeck viewport (Space + d)
    ToggleHolodeck,

    // Global shortcuts (no leader key needed)
    FocusNext, // Tab
    FocusPrev, // Shift+Tab
    Quit,      // Ctrl+q
    Help,      // ?

    // Not a recognized leader sequence
    Cancelled,
    None,
}

/// State machine for leader-key sequence recognition.
#[derive(Debug, Clone, Default, PartialEq)]
pub enum LeaderState {
    #[default]
    Idle,
    WaitingForGroup,        // Space pressed, waiting for group key (a/s/b/l/h)
    WaitingForAction(char), // Group key pressed (e.g., 'a'), waiting for action key
}

impl LeaderState {
    /// Process a key event and return (new_state, optional_action).
    pub fn process(&self, key: KeyEvent) -> (Self, LeaderAction) {
        match self {
            LeaderState::Idle => {
                // Check for global shortcuts first
                if key.modifiers.contains(KeyModifiers::CONTROL)
                    && key.code == KeyCode::Char('q')
                {
                    return (LeaderState::Idle, LeaderAction::Quit);
                }
                match key.code {
                    KeyCode::Char(' ') => (LeaderState::WaitingForGroup, LeaderAction::None),
                    KeyCode::Tab if key.modifiers.contains(KeyModifiers::SHIFT) => {
                        (LeaderState::Idle, LeaderAction::FocusPrev)
                    }
                    KeyCode::Tab => (LeaderState::Idle, LeaderAction::FocusNext),
                    KeyCode::Char('?') => (LeaderState::Idle, LeaderAction::Help),
                    _ => (LeaderState::Idle, LeaderAction::None),
                }
            }
            LeaderState::WaitingForGroup => match key.code {
                KeyCode::Char('a') => {
                    (LeaderState::WaitingForAction('a'), LeaderAction::AgentMenu)
                }
                KeyCode::Char('s') => (
                    LeaderState::WaitingForAction('s'),
                    LeaderAction::SnapshotMenu,
                ),
                KeyCode::Char('b') => {
                    (LeaderState::WaitingForAction('b'), LeaderAction::BranchMenu)
                }
                KeyCode::Char('l') => (LeaderState::Idle, LeaderAction::CycleLayout),
                KeyCode::Char('h') => (LeaderState::Idle, LeaderAction::ToggleHelp),
                KeyCode::Char('v') => (LeaderState::Idle, LeaderAction::ToggleVoice),
                KeyCode::Char('d') => (LeaderState::Idle, LeaderAction::ToggleHolodeck),
                KeyCode::Esc => (LeaderState::Idle, LeaderAction::Cancelled),
                _ => (LeaderState::Idle, LeaderAction::Cancelled),
            },
            LeaderState::WaitingForAction(group) => {
                let action = match (*group, key.code) {
                    ('a', KeyCode::Char('c')) => LeaderAction::AgentCreate,
                    ('a', KeyCode::Char('s')) => LeaderAction::AgentStart,
                    ('a', KeyCode::Char('p')) => LeaderAction::AgentPause,
                    ('a', KeyCode::Char('x')) => LeaderAction::AgentStop,
                    ('a', KeyCode::Char('t')) => LeaderAction::AgentStep,
                    ('a', KeyCode::Char('i')) => LeaderAction::AgentInjectThought,
                    _ => LeaderAction::Cancelled,
                };
                (LeaderState::Idle, action)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::KeyEvent;

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }
    fn shift_key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::SHIFT)
    }
    fn ctrl_key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::CONTROL)
    }

    #[test]
    fn test_space_starts_leader() {
        let (state, action) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
        assert_eq!(state, LeaderState::WaitingForGroup);
        assert_eq!(action, LeaderAction::None);
    }

    #[test]
    fn test_space_a_c_creates_agent() {
        let (state, _) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
        let (state, _) = state.process(key(KeyCode::Char('a')));
        assert_eq!(state, LeaderState::WaitingForAction('a'));
        let (state, action) = state.process(key(KeyCode::Char('c')));
        assert_eq!(state, LeaderState::Idle);
        assert_eq!(action, LeaderAction::AgentCreate);
    }

    #[test]
    fn test_esc_cancels_leader() {
        let (state, _) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
        let (state, action) = state.process(key(KeyCode::Esc));
        assert_eq!(state, LeaderState::Idle);
        assert_eq!(action, LeaderAction::Cancelled);
    }

    #[test]
    fn test_tab_cycles_focus() {
        let (_, action) = LeaderState::Idle.process(key(KeyCode::Tab));
        assert_eq!(action, LeaderAction::FocusNext);
    }

    #[test]
    fn test_shift_tab_cycles_reverse() {
        let (_, action) = LeaderState::Idle.process(shift_key(KeyCode::Tab));
        assert_eq!(action, LeaderAction::FocusPrev);
    }

    #[test]
    fn test_ctrl_q_quits() {
        let (_, action) = LeaderState::Idle.process(ctrl_key(KeyCode::Char('q')));
        assert_eq!(action, LeaderAction::Quit);
    }

    #[test]
    fn test_question_mark_help() {
        let (_, action) = LeaderState::Idle.process(key(KeyCode::Char('?')));
        assert_eq!(action, LeaderAction::Help);
    }

    #[test]
    fn test_space_l_cycles_layout() {
        let (state, _) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
        let (_, action) = state.process(key(KeyCode::Char('l')));
        assert_eq!(action, LeaderAction::CycleLayout);
    }

    #[test]
    fn test_space_v_toggles_voice() {
        let (state, _) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
        let (state, action) = state.process(key(KeyCode::Char('v')));
        assert_eq!(state, LeaderState::Idle);
        assert_eq!(action, LeaderAction::ToggleVoice);
    }

    #[test]
    fn test_space_d_toggles_holodeck() {
        let (state, _) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
        let (state, action) = state.process(key(KeyCode::Char('d')));
        assert_eq!(state, LeaderState::Idle);
        assert_eq!(action, LeaderAction::ToggleHolodeck);
    }

    #[test]
    fn test_all_agent_actions() {
        for (ch, expected) in [
            ('s', LeaderAction::AgentStart),
            ('p', LeaderAction::AgentPause),
            ('x', LeaderAction::AgentStop),
            ('t', LeaderAction::AgentStep),
            ('i', LeaderAction::AgentInjectThought),
        ] {
            let (state, _) = LeaderState::Idle.process(key(KeyCode::Char(' ')));
            let (state, _) = state.process(key(KeyCode::Char('a')));
            let (_, action) = state.process(key(KeyCode::Char(ch)));
            assert_eq!(action, expected, "Failed for key '{ch}'");
        }
    }
}
