use ratatui::{
    buffer::Buffer,
    layout::{Alignment, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget, Wrap},
};

use crate::theme;

pub struct DiffViewer<'a> {
    diff_text: Option<&'a str>,
    scroll_offset: usize,
    is_focused: bool,
}

impl<'a> DiffViewer<'a> {
    pub fn new(diff_text: Option<&'a str>, scroll_offset: usize, is_focused: bool) -> Self {
        Self {
            diff_text,
            scroll_offset,
            is_focused,
        }
    }
}

impl<'a> Widget for DiffViewer<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(theme::border_style(self.is_focused))
            .title(Span::styled(
                " Snapshot Diff ",
                Style::default()
                    .fg(theme::COLOR_TITLE)
                    .add_modifier(Modifier::BOLD),
            ));

        match self.diff_text {
            None => {
                let placeholder = Paragraph::new(Line::from(Span::styled(
                    "[ No snapshot selected ]",
                    Style::default().fg(Color::DarkGray),
                )))
                .block(block)
                .alignment(Alignment::Center);
                placeholder.render(area, buf);
            }
            Some(text) => {
                let lines: Vec<Line> = text
                    .lines()
                    .skip(self.scroll_offset)
                    .map(|line| {
                        let color = if line.starts_with('+') {
                            Color::LightGreen
                        } else if line.starts_with('-') {
                            Color::LightRed
                        } else if line.starts_with("@@") {
                            Color::Cyan
                        } else {
                            Color::White
                        };
                        Line::from(Span::styled(line.to_string(), Style::default().fg(color)))
                    })
                    .collect();

                let paragraph = Paragraph::new(lines).block(block).wrap(Wrap { trim: false });
                paragraph.render(area, buf);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn buf_text(terminal: &Terminal<TestBackend>, w: u16, h: u16) -> String {
        let buf = terminal.backend().buffer().clone();
        let mut text = String::new();
        for y in 0..h {
            for x in 0..w {
                text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        text
    }

    #[test]
    fn test_no_snapshot_selected() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|f| {
                let area = f.area();
                let w = DiffViewer::new(None, 0, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(text.contains("Snapshot Diff"), "should show title");
        assert!(
            text.contains("No snapshot selected"),
            "should show placeholder"
        );
    }

    #[test]
    fn test_diff_renders_content() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let diff = "@@ -1,3 +1,3 @@\n context line\n-removed line\n+added line";

        terminal
            .draw(|f| {
                let area = f.area();
                let w = DiffViewer::new(Some(diff), 0, true);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(text.contains("context line"), "should show context");
        assert!(text.contains("removed line"), "should show removed line");
        assert!(text.contains("added line"), "should show added line");
    }

    #[test]
    fn test_diff_scroll_offset() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let diff = "line0\nline1\nline2\nline3\nline4";

        terminal
            .draw(|f| {
                let area = f.area();
                // Scroll past the first 2 lines
                let w = DiffViewer::new(Some(diff), 2, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(!text.contains("line0"), "should not show scrolled-past line0");
        assert!(!text.contains("line1"), "should not show scrolled-past line1");
        assert!(text.contains("line2"), "should show line2");
    }

    #[test]
    fn test_diff_title_always_shown() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let diff = "+added only";

        terminal
            .draw(|f| {
                let area = f.area();
                let w = DiffViewer::new(Some(diff), 0, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(text.contains("Snapshot Diff"), "title should always appear");
        assert!(text.contains("added only"), "content should render");
    }
}
