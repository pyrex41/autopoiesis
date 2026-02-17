use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

use crate::state::AppState;
use crate::theme;

pub struct AgentDetail<'a> {
    state: &'a AppState,
}

impl<'a> AgentDetail<'a> {
    pub fn new(state: &'a AppState) -> Self {
        Self { state }
    }
}

impl<'a> Widget for AgentDetail<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(theme::COLOR_BORDER))
            .title(Span::styled(
                " Detail ",
                Style::default()
                    .fg(theme::COLOR_TITLE)
                    .add_modifier(Modifier::BOLD),
            ));

        if let Some(agent) = self.state.selected_agent() {
            let state_color = theme::agent_state_color(&agent.state);
            let state_label = format!("{:?}", agent.state).to_lowercase();
            let lines = vec![
                Line::from(vec![
                    Span::styled(" Agent: ", Style::default().fg(theme::COLOR_DIM)),
                    Span::styled(
                        &agent.name,
                        Style::default()
                            .fg(Color::White)
                            .add_modifier(Modifier::BOLD),
                    ),
                ]),
                Line::from(vec![
                    Span::styled(" State: ", Style::default().fg(theme::COLOR_DIM)),
                    Span::styled("* ", Style::default().fg(state_color)),
                    Span::styled(&state_label, Style::default().fg(state_color)),
                ]),
                Line::from(vec![
                    Span::styled(" Caps:  ", Style::default().fg(theme::COLOR_DIM)),
                    Span::styled(
                        agent.capabilities.join(", "),
                        Style::default().fg(Color::White),
                    ),
                ]),
                Line::from(vec![
                    Span::styled(" Thoughts: ", Style::default().fg(theme::COLOR_DIM)),
                    Span::styled(
                        agent.thought_count.to_string(),
                        Style::default().fg(Color::White),
                    ),
                ]),
            ];
            Paragraph::new(lines).block(block).render(area, buf);
        } else {
            let lines = vec![Line::from(Span::styled(
                " No agent selected",
                Style::default().fg(theme::COLOR_DIM),
            ))];
            Paragraph::new(lines).block(block).render(area, buf);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nexus_protocol::types::{AgentData, AgentState};
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;
    use uuid::Uuid;

    #[test]
    fn test_agent_detail_no_selection() {
        let backend = TestBackend::new(40, 8);
        let mut terminal = Terminal::new(backend).unwrap();

        let state = AppState::default();
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(AgentDetail::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..8 {
            for x in 0..40 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("No agent selected"));
    }

    #[test]
    fn test_agent_detail_with_agent() {
        let backend = TestBackend::new(40, 8);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.agents = vec![AgentData {
            id: Uuid::new_v4(),
            name: "researcher".to_string(),
            state: AgentState::Running,
            capabilities: vec!["code".to_string(), "review".to_string()],
            parent: None,
            children: vec![],
            thought_count: 42,
        }];

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(AgentDetail::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..8 {
            for x in 0..40 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("researcher"));
        assert!(all_text.contains("running"));
        assert!(all_text.contains("code, review"));
        assert!(all_text.contains("42"));
    }
}
