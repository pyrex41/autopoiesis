use nexus_protocol::types::{AgentState, ThoughtType};
use ratatui::style::{Color, Modifier, Style};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ThemeName {
    #[default]
    Tron,
    Holodeck,
    Matrix,
    Minimal,
}

#[derive(Debug, Clone)]
pub struct Theme {
    pub name: ThemeName,
    // Background and text
    pub bg: Color,
    pub fg: Color,
    pub fg_dim: Color,
    pub fg_accent: Color,
    // Borders and chrome
    pub border: Color,
    pub border_focused: Color,
    pub title: Color,
    pub selected_fg: Color,
    pub selected_bg: Color,
    // Status bar
    pub status_bar_bg: Color,
    pub status_bar_fg: Color,
    // Connection
    pub connected: Color,
    pub disconnected: Color,
    pub reconnecting: Color,
    // Agent states
    pub agent_initialized: Color,
    pub agent_running: Color,
    pub agent_paused: Color,
    pub agent_stopped: Color,
    // Thought types
    pub thought_obs: Color,
    pub thought_dec: Color,
    pub thought_act: Color,
    pub thought_ref: Color,
    // Notifications
    pub notify_info: Color,
    pub notify_success: Color,
    pub notify_warning: Color,
    pub notify_error: Color,
}

impl Theme {
    pub fn tron() -> Self {
        Self {
            name: ThemeName::Tron,
            bg: Color::Rgb(10, 10, 26),
            fg: Color::White,
            fg_dim: Color::DarkGray,
            fg_accent: Color::Rgb(0, 212, 255),
            border: Color::Rgb(80, 80, 100),
            border_focused: Color::Rgb(0, 200, 255),
            title: Color::Rgb(0, 200, 255),
            selected_fg: Color::Rgb(0, 200, 255),
            selected_bg: Color::Rgb(0, 51, 85),
            status_bar_bg: Color::Rgb(30, 30, 50),
            status_bar_fg: Color::White,
            connected: Color::Green,
            disconnected: Color::Red,
            reconnecting: Color::Yellow,
            agent_initialized: Color::Green,
            agent_running: Color::Rgb(100, 200, 255),
            agent_paused: Color::Rgb(255, 191, 0),
            agent_stopped: Color::Red,
            thought_obs: Color::Rgb(100, 149, 237),
            thought_dec: Color::Rgb(255, 215, 0),
            thought_act: Color::Green,
            thought_ref: Color::Rgb(200, 150, 255),
            notify_info: Color::Rgb(100, 149, 237),
            notify_success: Color::Rgb(0, 255, 136),
            notify_warning: Color::Rgb(255, 170, 0),
            notify_error: Color::Rgb(255, 51, 68),
        }
    }

    pub fn holodeck() -> Self {
        Self {
            name: ThemeName::Holodeck,
            bg: Color::Rgb(15, 5, 25),
            fg: Color::Rgb(230, 210, 255),
            fg_dim: Color::Rgb(100, 80, 130),
            fg_accent: Color::Rgb(255, 0, 200),
            border: Color::Rgb(80, 40, 120),
            border_focused: Color::Rgb(200, 50, 255),
            title: Color::Rgb(200, 50, 255),
            selected_fg: Color::Rgb(255, 100, 220),
            selected_bg: Color::Rgb(50, 10, 70),
            status_bar_bg: Color::Rgb(30, 10, 50),
            status_bar_fg: Color::Rgb(230, 210, 255),
            connected: Color::Rgb(0, 255, 136),
            disconnected: Color::Rgb(255, 50, 80),
            reconnecting: Color::Rgb(255, 200, 0),
            agent_initialized: Color::Rgb(0, 255, 136),
            agent_running: Color::Rgb(150, 100, 255),
            agent_paused: Color::Rgb(255, 200, 0),
            agent_stopped: Color::Rgb(255, 50, 80),
            thought_obs: Color::Rgb(120, 80, 255),
            thought_dec: Color::Rgb(255, 180, 50),
            thought_act: Color::Rgb(0, 255, 136),
            thought_ref: Color::Rgb(255, 100, 220),
            notify_info: Color::Rgb(120, 80, 255),
            notify_success: Color::Rgb(0, 255, 136),
            notify_warning: Color::Rgb(255, 200, 0),
            notify_error: Color::Rgb(255, 50, 80),
        }
    }

    pub fn matrix() -> Self {
        Self {
            name: ThemeName::Matrix,
            bg: Color::Black,
            fg: Color::Rgb(0, 200, 0),
            fg_dim: Color::Rgb(0, 80, 0),
            fg_accent: Color::Rgb(0, 255, 0),
            border: Color::Rgb(0, 80, 0),
            border_focused: Color::Rgb(0, 255, 0),
            title: Color::Rgb(0, 255, 0),
            selected_fg: Color::Rgb(0, 255, 0),
            selected_bg: Color::Rgb(0, 40, 0),
            status_bar_bg: Color::Rgb(0, 20, 0),
            status_bar_fg: Color::Rgb(0, 200, 0),
            connected: Color::Rgb(0, 255, 0),
            disconnected: Color::Rgb(200, 0, 0),
            reconnecting: Color::Rgb(200, 200, 0),
            agent_initialized: Color::Rgb(0, 200, 0),
            agent_running: Color::Rgb(0, 255, 0),
            agent_paused: Color::Rgb(200, 200, 0),
            agent_stopped: Color::Rgb(200, 0, 0),
            thought_obs: Color::Rgb(0, 180, 0),
            thought_dec: Color::Rgb(0, 255, 0),
            thought_act: Color::Rgb(100, 255, 100),
            thought_ref: Color::Rgb(0, 150, 50),
            notify_info: Color::Rgb(0, 180, 0),
            notify_success: Color::Rgb(0, 255, 0),
            notify_warning: Color::Rgb(200, 200, 0),
            notify_error: Color::Rgb(200, 0, 0),
        }
    }

    pub fn minimal() -> Self {
        Self {
            name: ThemeName::Minimal,
            bg: Color::Black,
            fg: Color::White,
            fg_dim: Color::DarkGray,
            fg_accent: Color::White,
            border: Color::DarkGray,
            border_focused: Color::White,
            title: Color::White,
            selected_fg: Color::Black,
            selected_bg: Color::White,
            status_bar_bg: Color::DarkGray,
            status_bar_fg: Color::White,
            connected: Color::White,
            disconnected: Color::DarkGray,
            reconnecting: Color::Gray,
            agent_initialized: Color::White,
            agent_running: Color::White,
            agent_paused: Color::Gray,
            agent_stopped: Color::DarkGray,
            thought_obs: Color::White,
            thought_dec: Color::White,
            thought_act: Color::White,
            thought_ref: Color::Gray,
            notify_info: Color::White,
            notify_success: Color::White,
            notify_warning: Color::Gray,
            notify_error: Color::DarkGray,
        }
    }

    pub fn from_name(name: ThemeName) -> Self {
        match name {
            ThemeName::Tron => Self::tron(),
            ThemeName::Holodeck => Self::holodeck(),
            ThemeName::Matrix => Self::matrix(),
            ThemeName::Minimal => Self::minimal(),
        }
    }
}

impl Default for Theme {
    fn default() -> Self {
        Self::tron()
    }
}

// === Backward-compatible constants (match the Tron theme) ===

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

// === Backward-compatible helper functions ===

pub fn agent_state_color(state: &AgentState) -> Color {
    let theme = Theme::default();
    match state {
        AgentState::Running => theme.agent_running,
        AgentState::Initialized => theme.agent_initialized,
        AgentState::Paused => theme.agent_paused,
        AgentState::Stopped => theme.agent_stopped,
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

// === New Phase 2 helper functions ===

pub fn notification_color(level: &crate::notifications::NotificationLevel) -> Color {
    let theme = Theme::default();
    match level {
        crate::notifications::NotificationLevel::Info => theme.notify_info,
        crate::notifications::NotificationLevel::Success => theme.notify_success,
        crate::notifications::NotificationLevel::Warning => theme.notify_warning,
        crate::notifications::NotificationLevel::Error => theme.notify_error,
    }
}

pub fn border_style(focused: bool) -> Style {
    let theme = Theme::default();
    if focused {
        Style::default().fg(theme.border_focused)
    } else {
        Style::default().fg(theme.border)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_theme_default_is_tron() {
        let theme = Theme::default();
        assert_eq!(theme.name, ThemeName::Tron);
    }

    #[test]
    fn test_theme_name_default() {
        assert_eq!(ThemeName::default(), ThemeName::Tron);
    }

    #[test]
    fn test_all_themes_construct() {
        let _ = Theme::tron();
        let _ = Theme::holodeck();
        let _ = Theme::matrix();
        let _ = Theme::minimal();
    }

    #[test]
    fn test_from_name() {
        assert_eq!(Theme::from_name(ThemeName::Tron).name, ThemeName::Tron);
        assert_eq!(Theme::from_name(ThemeName::Holodeck).name, ThemeName::Holodeck);
        assert_eq!(Theme::from_name(ThemeName::Matrix).name, ThemeName::Matrix);
        assert_eq!(Theme::from_name(ThemeName::Minimal).name, ThemeName::Minimal);
    }

    #[test]
    fn test_agent_state_color_backward_compat() {
        assert_eq!(agent_state_color(&AgentState::Running), COLOR_AGENT_RUNNING);
        assert_eq!(agent_state_color(&AgentState::Initialized), COLOR_AGENT_INITIALIZED);
        assert_eq!(agent_state_color(&AgentState::Paused), COLOR_AGENT_PAUSED);
        assert_eq!(agent_state_color(&AgentState::Stopped), COLOR_AGENT_STOPPED);
    }

    #[test]
    fn test_thought_type_style_returns_bold() {
        let style = thought_type_style(&ThoughtType::Observation);
        assert!(style.add_modifier == Modifier::BOLD);
    }

    #[test]
    fn test_status_bar_style_has_bg() {
        let style = status_bar_style();
        assert_eq!(style.bg, Some(Color::Rgb(30, 30, 50)));
    }

    #[test]
    fn test_selected_style_is_bold() {
        let style = selected_style();
        assert!(style.add_modifier == Modifier::BOLD);
    }

    #[test]
    fn test_notification_color_variants() {
        use crate::notifications::NotificationLevel;
        // Just verify these don't panic and return colors
        let _ = notification_color(&NotificationLevel::Info);
        let _ = notification_color(&NotificationLevel::Success);
        let _ = notification_color(&NotificationLevel::Warning);
        let _ = notification_color(&NotificationLevel::Error);
    }

    #[test]
    fn test_border_style_focused_vs_unfocused() {
        let focused = border_style(true);
        let unfocused = border_style(false);
        // They should be different
        assert_ne!(focused.fg, unfocused.fg);
    }
}
