use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget},
};

use crate::state::McpServerStatus;

pub struct McpPanel<'a> {
    servers: &'a [McpServerStatus],
    selected_idx: usize,
    is_focused: bool,
}

impl<'a> McpPanel<'a> {
    pub fn new(servers: &'a [McpServerStatus], selected_idx: usize, is_focused: bool) -> Self {
        Self {
            servers,
            selected_idx,
            is_focused,
        }
    }
}

impl<'a> Widget for McpPanel<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let border_color = if self.is_focused {
            Color::Rgb(0, 200, 255)
        } else {
            Color::Rgb(80, 80, 100)
        };

        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(border_color))
            .title(Span::styled(
                " MCP Servers ",
                Style::default()
                    .fg(Color::Rgb(0, 200, 255))
                    .add_modifier(Modifier::BOLD),
            ));

        let inner = block.inner(area);
        block.render(area, buf);

        if inner.height == 0 {
            return;
        }

        if self.servers.is_empty() {
            let line = Line::from(Span::styled(
                " No MCP servers configured",
                Style::default().fg(Color::DarkGray),
            ));
            Paragraph::new(line).render(inner, buf);
            return;
        }

        let lines: Vec<Line> = self
            .servers
            .iter()
            .enumerate()
            .map(|(i, server)| {
                let is_selected = i == self.selected_idx;
                let (dot, dot_color) = if server.connected {
                    ("●", Color::Green)
                } else {
                    ("○", Color::Red)
                };

                let marker = if is_selected { ">" } else { " " };
                let style = if is_selected {
                    Style::default()
                        .fg(Color::Rgb(0, 200, 255))
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::White)
                };

                let tool_info = if server.connected {
                    format!(" ({} tools)", server.tool_count)
                } else if let Some(ref err) = server.error {
                    format!(" [{}]", &err[..err.len().min(20)])
                } else {
                    " (disconnected)".to_string()
                };

                Line::from(vec![
                    Span::styled(format!(" {} ", marker), style),
                    Span::styled(dot, Style::default().fg(dot_color)),
                    Span::styled(format!(" {}{}", server.name, tool_info), style),
                ])
            })
            .collect();

        Paragraph::new(lines).render(inner, buf);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    fn make_servers() -> Vec<McpServerStatus> {
        vec![
            McpServerStatus {
                name: "autopoiesis".to_string(),
                connected: true,
                tool_count: 21,
                error: None,
            },
            McpServerStatus {
                name: "filesystem".to_string(),
                connected: false,
                tool_count: 0,
                error: Some("Connection refused".to_string()),
            },
        ]
    }

    #[test]
    fn test_mcp_panel_empty() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                f.render_widget(McpPanel::new(&[], 0, false), f.area());
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let text: String = (0..10)
            .flat_map(|y| (0..40_u16).map(move |x| (x, y)))
            .map(|(x, y)| buf.cell((x, y)).unwrap().symbol().to_string())
            .collect();
        assert!(text.contains("MCP"));
        assert!(text.contains("No MCP"));
    }

    #[test]
    fn test_mcp_panel_with_servers() {
        let backend = TestBackend::new(60, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        let servers = make_servers();
        terminal
            .draw(|f| {
                f.render_widget(McpPanel::new(&servers, 0, true), f.area());
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let text: String = (0..15)
            .flat_map(|y| (0..60_u16).map(move |x| (x, y)))
            .map(|(x, y)| buf.cell((x, y)).unwrap().symbol().to_string())
            .collect();
        assert!(text.contains("autopoiesis"));
        assert!(text.contains("21 tools"));
        assert!(text.contains("filesystem"));
    }

    #[test]
    fn test_mcp_panel_focused_unfocused() {
        let backend = TestBackend::new(40, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        // Just verify it doesn't panic for both states
        terminal
            .draw(|f| {
                f.render_widget(McpPanel::new(&[], 0, true), f.area());
            })
            .unwrap();
        terminal
            .draw(|f| {
                f.render_widget(McpPanel::new(&[], 0, false), f.area());
            })
            .unwrap();
    }

    #[test]
    fn test_mcp_panel_selection() {
        let backend = TestBackend::new(60, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        let servers = make_servers();
        // Select index 1 (filesystem)
        terminal
            .draw(|f| {
                f.render_widget(McpPanel::new(&servers, 1, false), f.area());
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let text: String = (0..15)
            .flat_map(|y| (0..60_u16).map(move |x| (x, y)))
            .map(|(x, y)| buf.cell((x, y)).unwrap().symbol().to_string())
            .collect();
        // Both servers should appear
        assert!(text.contains("autopoiesis"));
        assert!(text.contains("filesystem"));
    }
}
