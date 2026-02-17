use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget, Wrap},
};

use crate::state::AppState;
use crate::theme;
use nexus_protocol::types::ThoughtType;

pub struct ThoughtStream<'a> {
    state: &'a AppState,
}

impl<'a> ThoughtStream<'a> {
    pub fn new(state: &'a AppState) -> Self {
        Self { state }
    }
}

fn badge(tt: &ThoughtType) -> (&'static str, ratatui::style::Color) {
    match tt {
        ThoughtType::Observation => ("◉ OBS", theme::COLOR_THOUGHT_OBS),
        ThoughtType::Decision => ("◆ DEC", theme::COLOR_THOUGHT_DEC),
        ThoughtType::Action => ("▶ ACT", theme::COLOR_THOUGHT_ACT),
        ThoughtType::Reflection => ("◈ REF", theme::COLOR_THOUGHT_REF),
    }
}

impl<'a> Widget for ThoughtStream<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(theme::COLOR_BORDER))
            .title(Span::styled(
                " Thoughts ",
                Style::default()
                    .fg(theme::COLOR_TITLE)
                    .add_modifier(Modifier::BOLD),
            ));

        if self.state.thoughts.is_empty() {
            let lines = vec![Line::from(Span::styled(
                " No thoughts yet",
                Style::default().fg(theme::COLOR_DIM),
            ))];
            Paragraph::new(lines).block(block).render(area, buf);
            return;
        }

        let lines: Vec<Line> = self
            .state
            .thoughts
            .iter()
            .map(|t| {
                let (badge_text, badge_color) = badge(&t.thought_type);
                Line::from(vec![
                    Span::styled(
                        format!(" {badge_text} "),
                        Style::default()
                            .fg(badge_color)
                            .add_modifier(Modifier::BOLD),
                    ),
                    Span::styled(
                        &t.content,
                        Style::default().fg(ratatui::style::Color::White),
                    ),
                ])
            })
            .collect();

        let scroll = self.state.thought_scroll_offset as u16;
        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: true })
            .scroll((scroll, 0))
            .render(area, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nexus_protocol::types::ThoughtData;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;
    use uuid::Uuid;

    fn make_thought(tt: ThoughtType, content: &str) -> ThoughtData {
        ThoughtData {
            id: Uuid::new_v4(),
            timestamp: 0.0,
            thought_type: tt,
            confidence: 0.9,
            content: content.to_string(),
            provenance: None,
            source: None,
            rationale: None,
            alternatives: vec![],
        }
    }

    #[test]
    fn test_thought_stream_empty() {
        let backend = TestBackend::new(50, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let state = AppState::default();
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(ThoughtStream::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..10 {
            for x in 0..50 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("No thoughts yet"));
    }

    #[test]
    fn test_thought_stream_with_thoughts() {
        let backend = TestBackend::new(60, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.thoughts = vec![
            make_thought(ThoughtType::Observation, "Analyzing auth module"),
            make_thought(ThoughtType::Decision, "Found injection risk"),
            make_thought(ThoughtType::Action, "Running grep scan"),
            make_thought(ThoughtType::Reflection, "Results suggest fix"),
        ];

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(ThoughtStream::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..10 {
            for x in 0..60 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("OBS"));
        assert!(all_text.contains("DEC"));
        assert!(all_text.contains("ACT"));
        assert!(all_text.contains("REF"));
        assert!(all_text.contains("Analyzing auth module"));
    }

    #[test]
    fn test_badge_colors() {
        let (text, _) = badge(&ThoughtType::Observation);
        assert_eq!(text, "◉ OBS");

        let (text, _) = badge(&ThoughtType::Decision);
        assert_eq!(text, "◆ DEC");

        let (text, _) = badge(&ThoughtType::Action);
        assert_eq!(text, "▶ ACT");

        let (text, _) = badge(&ThoughtType::Reflection);
        assert_eq!(text, "◈ REF");
    }
}
