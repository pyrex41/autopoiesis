use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, StatefulWidget, Widget},
};

use crate::state::AppState;
use crate::theme;

pub struct AgentList<'a> {
    state: &'a AppState,
}

impl<'a> AgentList<'a> {
    pub fn new(state: &'a AppState) -> Self {
        Self { state }
    }

    pub fn list_state(state: &AppState) -> ListState {
        let mut ls = ListState::default();
        if !state.agents.is_empty() {
            ls.select(Some(state.selected_agent_index));
        }
        ls
    }
}

impl<'a> Widget for AgentList<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let items: Vec<ListItem> = self
            .state
            .agents
            .iter()
            .enumerate()
            .map(|(i, agent)| {
                let color = theme::agent_state_color(&agent.state);
                let bullet = if i == self.state.selected_agent_index {
                    "*"
                } else {
                    " "
                };
                let line = Line::from(vec![
                    Span::styled(format!(" {bullet} "), Style::default().fg(color)),
                    Span::styled(
                        &agent.name,
                        if i == self.state.selected_agent_index {
                            theme::selected_style()
                        } else {
                            Style::default().fg(Color::White)
                        },
                    ),
                ]);
                ListItem::new(line)
            })
            .collect();

        let list = List::new(items).block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(theme::COLOR_BORDER))
                .title(Span::styled(
                    " Agents ",
                    Style::default()
                        .fg(theme::COLOR_TITLE)
                        .add_modifier(Modifier::BOLD),
                )),
        );

        let mut ls = AgentList::list_state(self.state);
        StatefulWidget::render(list, area, buf, &mut ls);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nexus_protocol::types::{AgentData, AgentState};
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;
    use uuid::Uuid;

    fn make_agent(name: &str, state: AgentState) -> AgentData {
        AgentData {
            id: Uuid::new_v4(),
            name: name.to_string(),
            state,
            capabilities: vec![],
            parent: None,
            children: vec![],
            thought_count: 0,
        }
    }

    #[test]
    fn test_agent_list_empty() {
        let backend = TestBackend::new(20, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let state = AppState::default();
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(AgentList::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        // Scan row-first so horizontal text like "Agents" is contiguous
        let mut all_text = String::new();
        for y in 0..10 {
            for x in 0..20 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("Agents"));
    }

    #[test]
    fn test_agent_list_with_agents() {
        let backend = TestBackend::new(30, 10);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.agents = vec![
            make_agent("researcher", AgentState::Running),
            make_agent("coder", AgentState::Paused),
        ];

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(AgentList::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        // Check that agent names appear in the buffer
        let mut all_text = String::new();
        for y in 0..10 {
            for x in 0..30 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("researcher"));
        assert!(all_text.contains("coder"));
    }
}
