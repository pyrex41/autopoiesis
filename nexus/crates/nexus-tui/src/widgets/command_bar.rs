use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

use crate::state::{AppState, InputMode};
use crate::theme;

pub struct CommandBar<'a> {
    state: &'a AppState,
}

impl<'a> CommandBar<'a> {
    pub fn new(state: &'a AppState) -> Self {
        Self { state }
    }
}

impl<'a> Widget for CommandBar<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(theme::COLOR_BORDER));

        let (prompt_style, hint) = match self.state.input_mode {
            InputMode::Normal => (
                Style::default().fg(theme::COLOR_DIM),
                Span::styled("  [/ command]", Style::default().fg(theme::COLOR_DIM)),
            ),
            InputMode::Command => (
                Style::default()
                    .fg(theme::COLOR_TITLE)
                    .add_modifier(Modifier::BOLD),
                Span::raw(""),
            ),
        };

        let input_text = if self.state.input_mode == InputMode::Command {
            &self.state.command_input
        } else {
            ""
        };

        let cursor = if self.state.input_mode == InputMode::Command {
            Span::styled("_", Style::default().fg(theme::COLOR_TITLE))
        } else {
            Span::raw("")
        };

        let line = Line::from(vec![
            Span::styled(" > ", prompt_style),
            Span::styled(input_text, Style::default().fg(Color::White)),
            cursor,
            hint,
        ]);

        Paragraph::new(line).block(block).render(area, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    #[test]
    fn test_command_bar_normal_mode() {
        let backend = TestBackend::new(50, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let state = AppState::default();
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(CommandBar::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..3 {
            for x in 0..50 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains(">"));
        assert!(all_text.contains("[/ command]"));
    }

    #[test]
    fn test_command_bar_command_mode() {
        let backend = TestBackend::new(50, 3);
        let mut terminal = Terminal::new(backend).unwrap();

        let mut state = AppState::default();
        state.input_mode = InputMode::Command;
        state.command_input = "create agent".to_string();

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(CommandBar::new(&state), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..3 {
            for x in 0..50 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("create agent"));
        // Should NOT contain the hint in command mode
        assert!(!all_text.contains("[/ command]"));
    }
}
