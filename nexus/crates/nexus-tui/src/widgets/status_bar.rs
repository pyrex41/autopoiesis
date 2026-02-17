use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Paragraph, Widget},
};

use crate::state::{AppState, ConnectionStatus, VoiceMode};
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

        // Build voice indicator spans
        let mut voice_spans: Vec<Span> = Vec::new();
        let mut voice_len: usize = 0;

        if self.state.is_recording {
            let rec = " \u{25CE} REC";
            voice_spans.push(Span::styled(
                rec,
                Style::default()
                    .fg(Color::Red)
                    .add_modifier(Modifier::BOLD),
            ));
            voice_len += rec.len();
        } else if self.state.is_speaking {
            let tts = " \u{266B} TTS";
            voice_spans.push(Span::styled(
                tts,
                Style::default().fg(Color::Rgb(100, 149, 237)),
            ));
            voice_len += tts.len();
        } else {
            match self.state.voice_mode {
                VoiceMode::PushToTalk => {
                    let badge = " [PTT]";
                    voice_spans.push(Span::styled(
                        badge,
                        Style::default().fg(Color::DarkGray),
                    ));
                    voice_len += badge.len();
                }
                VoiceMode::VoiceActivated => {
                    let badge = " [VAD]";
                    voice_spans.push(Span::styled(
                        badge,
                        Style::default().fg(Color::DarkGray),
                    ));
                    voice_len += badge.len();
                }
                VoiceMode::Disabled => {}
            }
        }

        // Calculate padding for right-alignment of version
        let left_len =
            7 + 1 + 1 + 1 + status_text.len() + 2 + agent_count_text.len() + voice_len;
        let right_len = version.len();
        let padding = (area.width as usize).saturating_sub(left_len + right_len);

        let mut spans = vec![
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
        ];
        spans.extend(voice_spans);
        spans.push(Span::raw(" ".repeat(padding)));
        spans.push(Span::styled(version, Style::default().fg(theme::COLOR_DIM)));

        let line = Line::from(spans);

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

    #[test]
    fn test_status_bar_voice_recording() {
        let backend = TestBackend::new(80, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.voice_mode = VoiceMode::PushToTalk;
        state.is_recording = true;

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(StatusBar::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let content: String = (0..80).map(|x| buf.cell((x, 0)).unwrap().symbol().to_string()).collect();
        assert!(content.contains("REC"));
    }

    #[test]
    fn test_status_bar_voice_ptt_badge() {
        let backend = TestBackend::new(80, 1);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.voice_mode = VoiceMode::PushToTalk;

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(StatusBar::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let content: String = (0..80).map(|x| buf.cell((x, 0)).unwrap().symbol().to_string()).collect();
        assert!(content.contains("[PTT]"));
    }
}
