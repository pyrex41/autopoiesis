use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Widget, Wrap},
};

use nexus_protocol::types::BlockingRequestData;

pub struct BlockingPrompt<'a> {
    request: &'a BlockingRequestData,
    selected_option: usize,
    custom_input: &'a str,
    is_typing_custom: bool,
}

impl<'a> BlockingPrompt<'a> {
    pub fn new(
        request: &'a BlockingRequestData,
        selected_option: usize,
        custom_input: &'a str,
        is_typing_custom: bool,
    ) -> Self {
        Self {
            request,
            selected_option,
            custom_input,
            is_typing_custom,
        }
    }
}

impl<'a> Widget for BlockingPrompt<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // Clear the area first (since this is an overlay)
        Clear.render(area, buf);

        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(255, 170, 0)))
            .title(Span::styled(
                " Blocking Request ",
                Style::default()
                    .fg(Color::Rgb(255, 170, 0))
                    .add_modifier(Modifier::BOLD),
            ));

        let mut lines = vec![
            Line::from(Span::styled(
                format!(" ? {}", &self.request.prompt),
                Style::default()
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
        ];

        // Render options if available
        for (i, option) in self.request.options.iter().enumerate() {
            let is_selected = i == self.selected_option && !self.is_typing_custom;
            let style = if is_selected {
                Style::default()
                    .fg(Color::Rgb(0, 200, 255))
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };
            let marker = if is_selected { ">" } else { " " };
            lines.push(Line::from(Span::styled(
                format!("  {marker} [{}] {option}", i + 1),
                style,
            )));
        }

        lines.push(Line::from(""));

        // Custom input line
        let custom_style = if self.is_typing_custom {
            Style::default().fg(Color::Rgb(0, 200, 255))
        } else {
            Style::default().fg(Color::DarkGray)
        };
        lines.push(Line::from(vec![
            Span::styled("  Or type: ", custom_style),
            Span::styled(self.custom_input, Style::default().fg(Color::White)),
            if self.is_typing_custom {
                Span::styled("|", Style::default().fg(Color::Rgb(0, 200, 255)))
            } else {
                Span::raw("")
            },
        ]));

        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "  [Enter] Submit  [Esc] Cancel  [Tab] Toggle custom",
            Style::default().fg(Color::DarkGray),
        )));

        Paragraph::new(lines)
            .block(block)
            .wrap(Wrap { trim: false })
            .render(area, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn make_request() -> BlockingRequestData {
        BlockingRequestData {
            id: "req-1".to_string(),
            prompt: "Should I refactor to prepared statements?".to_string(),
            context: None,
            options: vec![
                "Prepared statements".to_string(),
                "ORM".to_string(),
                "Both".to_string(),
            ],
            default_value: None,
            status: None,
            created_at: None,
        }
    }

    #[test]
    fn test_blocking_prompt_renders() {
        let backend = TestBackend::new(60, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        let request = make_request();

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(BlockingPrompt::new(&request, 0, "", false), area);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut text = String::new();
        for y in 0..15 {
            for x in 0..60 {
                text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(text.contains("Blocking Request"));
        assert!(text.contains("refactor"));
        assert!(text.contains("Prepared statements"));
    }

    #[test]
    fn test_blocking_prompt_custom_input() {
        let backend = TestBackend::new(60, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        let request = make_request();

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_widget(
                    BlockingPrompt::new(&request, 0, "my custom response", true),
                    area,
                );
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut text = String::new();
        for y in 0..15 {
            for x in 0..60 {
                text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(text.contains("my custom response"));
    }
}
