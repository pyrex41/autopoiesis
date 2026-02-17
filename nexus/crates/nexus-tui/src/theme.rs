use nexus_protocol::types::{AgentState, ThoughtType};
use ratatui::style::{Color, Modifier, Style};

// Connection status colors
pub const COLOR_CONNECTED: Color = Color::Green;
pub const COLOR_DISCONNECTED: Color = Color::Red;
pub const COLOR_RECONNECTING: Color = Color::Yellow;

// Agent state colors
pub const COLOR_AGENT_RUNNING: Color = Color::Rgb(100, 200, 255);
pub const COLOR_AGENT_INITIALIZED: Color = Color::Green;
pub const COLOR_AGENT_PAUSED: Color = Color::Rgb(255, 191, 0);
pub const COLOR_AGENT_STOPPED: Color = Color::Red;

// Thought type colors
pub const COLOR_THOUGHT_OBS: Color = Color::Rgb(100, 149, 237);
pub const COLOR_THOUGHT_DEC: Color = Color::Rgb(255, 215, 0);
pub const COLOR_THOUGHT_ACT: Color = Color::Green;
pub const COLOR_THOUGHT_REF: Color = Color::Rgb(200, 150, 255);

// UI chrome
pub const COLOR_BORDER: Color = Color::Rgb(80, 80, 100);
pub const COLOR_TITLE: Color = Color::Rgb(0, 200, 255);
pub const COLOR_SELECTED: Color = Color::Rgb(0, 200, 255);
pub const COLOR_DIM: Color = Color::DarkGray;

pub fn agent_state_color(state: &AgentState) -> Color {
    match state {
        AgentState::Running => COLOR_AGENT_RUNNING,
        AgentState::Initialized => COLOR_AGENT_INITIALIZED,
        AgentState::Paused => COLOR_AGENT_PAUSED,
        AgentState::Stopped => COLOR_AGENT_STOPPED,
    }
}

pub fn thought_type_style(tt: &ThoughtType) -> Style {
    let color = match tt {
        ThoughtType::Observation => COLOR_THOUGHT_OBS,
        ThoughtType::Decision => COLOR_THOUGHT_DEC,
        ThoughtType::Action => COLOR_THOUGHT_ACT,
        ThoughtType::Reflection => COLOR_THOUGHT_REF,
    };
    Style::default().fg(color).add_modifier(Modifier::BOLD)
}

pub fn status_bar_style() -> Style {
    Style::default()
        .bg(Color::Rgb(30, 30, 50))
        .fg(Color::White)
}

pub fn selected_style() -> Style {
    Style::default()
        .fg(COLOR_SELECTED)
        .add_modifier(Modifier::BOLD)
}
