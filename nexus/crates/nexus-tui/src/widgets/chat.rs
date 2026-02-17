use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget, Wrap},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatSender {
    User,
    Agent(String),
    System,
}

#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub sender: ChatSender,
    pub content: String,
}

pub struct Chat<'a> {
    messages: &'a [ChatMessage],
    input: &'a str,
    is_active: bool,
}

impl<'a> Chat<'a> {
    pub fn new(messages: &'a [ChatMessage], input: &'a str, is_active: bool) -> Self {
        Self {
            messages,
            input,
            is_active,
        }
    }
}

impl<'a> Widget for Chat<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let border_color = if self.is_active {
            Color::Rgb(0, 200, 255)
        } else {
            Color::Rgb(80, 80, 100)
        };
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(border_color))
            .title(Span::styled(
                " Chat ",
                Style::default()
                    .fg(Color::Rgb(0, 200, 255))
                    .add_modifier(Modifier::BOLD),
            ));

        let inner = block.inner(area);
        block.render(area, buf);

        if inner.height < 2 {
            return;
        }

        // Reserve last line for input
        let messages_area = Rect {
            height: inner.height.saturating_sub(1),
            ..inner
        };
        let input_area = Rect {
            y: inner.y + inner.height.saturating_sub(1),
            height: 1,
            ..inner
        };

        // Render messages
        let lines: Vec<Line> = self
            .messages
            .iter()
            .map(|msg| {
                let (prefix, prefix_color) = match &msg.sender {
                    ChatSender::User => ("you", Color::Rgb(0, 200, 255)),
                    ChatSender::Agent(name) => (name.as_str(), Color::Rgb(100, 200, 255)),
                    ChatSender::System => ("sys", Color::DarkGray),
                };
                Line::from(vec![
                    Span::styled(
                        format!(" {prefix}: "),
                        Style::default()
                            .fg(prefix_color)
                            .add_modifier(Modifier::BOLD),
                    ),
                    Span::styled(&msg.content, Style::default().fg(Color::White)),
                ])
            })
            .collect();

        Paragraph::new(lines)
            .wrap(Wrap { trim: true })
            .render(messages_area, buf);

        // Render input line
        let input_line = Line::from(vec![
            Span::styled(" > ", Style::default().fg(Color::Rgb(0, 200, 255))),
            Span::styled(self.input, Style::default().fg(Color::White)),
            if self.is_active {
                Span::styled("|", Style::default().fg(Color::Rgb(0, 200, 255)))
            } else {
                Span::raw("")
            },
        ]);
        Paragraph::new(input_line).render(input_area, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    #[test]
    fn test_chat_empty() {
        let backend = TestBackend::new(50, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                f.render_widget(Chat::new(&[], "", false), f.area());
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let mut text = String::new();
        for y in 0..10 {
            for x in 0..50 {
                text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(text.contains("Chat"));
    }

    #[test]
    fn test_chat_with_messages() {
        let backend = TestBackend::new(60, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let messages = vec![
            ChatMessage {
                sender: ChatSender::User,
                content: "hello agent".to_string(),
            },
            ChatMessage {
                sender: ChatSender::Agent("researcher".to_string()),
                content: "analyzing...".to_string(),
            },
        ];
        terminal
            .draw(|f| {
                f.render_widget(Chat::new(&messages, "typing here", true), f.area());
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let mut text = String::new();
        for y in 0..10 {
            for x in 0..60 {
                text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(text.contains("hello agent"));
        assert!(text.contains("analyzing"));
    }
}
