use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Paragraph, Widget},
};

use crate::state::{AppState, ConnectionStatus};
use crate::theme;

pub struct StatusBar<'a> {
    state: &'a AppState,
}

impl<'a> StatusBar<'a> {
    pub fn new(state: &'a AppState) -> Self {
        Self { state }
    }
}

impl<'a> Widget for StatusBar<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let (dot, dot_color) = match &self.state.connection {
            ConnectionStatus::Connected => ("*", theme::COLOR_CONNECTED),
            ConnectionStatus::Disconnected => ("*", theme::COLOR_DISCONNECTED),
            ConnectionStatus::Connecting => ("*", theme::COLOR_RECONNECTING),
            ConnectionStatus::Reconnecting { .. } => ("*", theme::COLOR_RECONNECTING),
        };

        let status_text = match &self.state.connection {
            ConnectionStatus::Connected => "connected".to_string(),
            ConnectionStatus::Disconnected => "disconnected".to_string(),
            ConnectionStatus::Connecting => "connecting...".to_string(),
            ConnectionStatus::Reconnecting { attempt } => format!("reconnecting ({attempt})"),
        };

        let agent_count_text = format!("{} agents", self.state.agent_count());
        let version = self.state.version_string();

        // Calculate padding for right-alignment of version
        let left_len = 7 + 1 + 1 + 1 + status_text.len() + 2 + agent_count_text.len();
        let right_len = version.len();
        let padding = (area.width as usize).saturating_sub(left_len + right_len);

        let line = Line::from(vec![
            Span::styled(
                " NEXUS ",
                Style::default()
                    .fg(theme::COLOR_TITLE)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::raw(" "),
            Span::styled(dot, Style::default().fg(dot_color)),
            Span::raw(" "),
            Span::styled(&status_text, Style::default().fg(dot_color)),
            Span::raw("  "),
            Span::styled(agent_count_text, Style::default().fg(Color::White)),
            Span::raw(" ".repeat(padding)),
            Span::styled(version, Style::default().fg(theme::COLOR_DIM)),
        ]);

        Paragraph::new(line)
            .style(theme::status_bar_style())
            .render(area, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    #[test]
    fn test_status_bar_renders() {
        let backend = TestBackend::new(80, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let state = AppState::default();
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(StatusBar::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let content: String = (0..80).map(|x| buf.cell((x, 0)).unwrap().symbol().to_string()).collect();
        assert!(content.contains("NEXUS"));
        assert!(content.contains("disconnected"));
        assert!(content.contains("0 agents"));
    }

    #[test]
    fn test_status_bar_connected() {
        let backend = TestBackend::new(80, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.connection = ConnectionStatus::Connected;

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(StatusBar::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let content: String = (0..80).map(|x| buf.cell((x, 0)).unwrap().symbol().to_string()).collect();
        assert!(content.contains("connected"));
    }
}
