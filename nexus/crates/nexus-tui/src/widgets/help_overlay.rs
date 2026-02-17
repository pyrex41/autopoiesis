use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Widget, Wrap},
};

#[derive(Default)]
pub struct HelpOverlay;

impl HelpOverlay {
    pub fn new() -> Self {
        Self
    }

    /// Center a rect of given size in the terminal area
    pub fn centered_rect(area: Rect, width_pct: u16, height_pct: u16) -> Rect {
        let w = (area.width * width_pct / 100).min(area.width);
        let h = (area.height * height_pct / 100).min(area.height);
        Rect {
            x: area.x + (area.width.saturating_sub(w)) / 2,
            y: area.y + (area.height.saturating_sub(h)) / 2,
            width: w,
            height: h,
        }
    }
}

impl Widget for HelpOverlay {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // Clear the full area first, then render centered box
        Clear.render(area, buf);

        let popup = Self::centered_rect(area, 80, 85);
        Clear.render(popup, buf);

        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Rgb(0, 200, 255)))
            .title(Span::styled(
                " Nexus Help — Press ? or Esc to close ",
                Style::default()
                    .fg(Color::Rgb(0, 200, 255))
                    .add_modifier(Modifier::BOLD),
            ));

        let inner = block.inner(popup);
        block.render(popup, buf);

        // Build help content as sections
        let lines = build_help_lines();

        Paragraph::new(lines)
            .wrap(Wrap { trim: false })
            .render(inner, buf);
    }
}

fn section(title: &str) -> Line<'static> {
    Line::from(vec![Span::styled(
        format!("  {} ", title),
        Style::default()
            .fg(Color::Rgb(0, 200, 255))
            .add_modifier(Modifier::BOLD | Modifier::UNDERLINED),
    )])
}

fn key_line(key: &str, desc: &str) -> Line<'static> {
    Line::from(vec![
        Span::styled(
            format!("  {:20}", key),
            Style::default()
                .fg(Color::Rgb(255, 215, 0))
                .add_modifier(Modifier::BOLD),
        ),
        Span::styled(desc.to_string(), Style::default().fg(Color::White)),
    ])
}

fn blank() -> Line<'static> {
    Line::from("")
}

fn build_help_lines() -> Vec<Line<'static>> {
    vec![
        blank(),
        section("Navigation"),
        key_line("j / Down", "Select next agent / scroll down"),
        key_line("k / Up", "Select prev agent / scroll up"),
        key_line("Tab", "Focus next pane"),
        key_line("Shift+Tab", "Focus prev pane"),
        key_line("g / G", "Jump to top / bottom of thought stream"),
        blank(),
        section("Pane Focus Order"),
        key_line(
            "Tab cycles:",
            "AgentList -> Detail -> Thoughts -> CommandBar -> SnapshotDag -> DiffViewer -> McpPanel -> (loop)",
        ),
        blank(),
        section("Commands  (press / to enter command mode)"),
        key_line("create agent <name>", "Create a new agent"),
        key_line("snapshot <label>", "Create a snapshot of selected agent"),
        key_line("branch create <name>", "Create a new branch"),
        key_line("branch checkout <n>", "Switch to branch"),
        key_line("step", "Step selected agent one cycle"),
        key_line("<anything else>", "Inject as observation to selected agent"),
        blank(),
        section("Leader Keys  (Space = leader)"),
        key_line("Space a c", "Create agent (prompt)"),
        key_line("Space a s", "Start selected agent"),
        key_line("Space a p", "Pause selected agent"),
        key_line("Space a x", "Stop selected agent"),
        key_line("Space a t", "Step selected agent"),
        key_line("Space l", "Cycle layout (Cockpit -> Focused -> Monitor)"),
        key_line("Space ?  or  ?", "Toggle this help"),
        key_line("Space q  or  q", "Quit Nexus"),
        blank(),
        section("Blocking Prompt (when a request arrives)"),
        key_line("j / k", "Select option"),
        key_line("Tab", "Toggle custom input"),
        key_line("Enter", "Submit response"),
        key_line("Esc", "Cancel / dismiss"),
        blank(),
        section("Chat (in Focused layout)"),
        key_line("Type text", "Compose message"),
        key_line("Enter", "Send to selected agent as observation"),
        key_line("Esc", "Close chat input"),
        blank(),
        section("Snapshot DAG (when SnapshotDag pane is focused)"),
        key_line("j / k", "Navigate snapshots"),
        key_line("Enter", "Load diff from parent"),
        blank(),
        section("Layout Modes"),
        key_line("Cockpit", "3-pane: agents | detail+thoughts | snapshot/MCP"),
        key_line("Focused", "Full-width: expanded thought stream + chat"),
        key_line("Monitor", "All agents side-by-side"),
        blank(),
        section("General"),
        key_line("Ctrl+c", "Force quit"),
        key_line("Ctrl+l", "Force redraw"),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn test_help_overlay_renders() {
        let backend = TestBackend::new(100, 40);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                f.render_widget(HelpOverlay::new(), f.area());
            })
            .unwrap();
        let buf = terminal.backend().buffer().clone();
        let text: String = (0..40)
            .flat_map(|y: u16| (0..100_u16).map(move |x| (x, y)))
            .map(|(x, y)| buf.cell((x, y)).unwrap().symbol().to_string())
            .collect();
        assert!(text.contains("Help"));
        assert!(text.contains("Navigation"));
        assert!(text.contains("Leader Keys"));
    }

    #[test]
    fn test_help_overlay_small_area() {
        // Should not panic with small area
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| {
                f.render_widget(HelpOverlay::new(), f.area());
            })
            .unwrap();
    }

    #[test]
    fn test_centered_rect_full_size() {
        let area = Rect::new(0, 0, 100, 50);
        let centered = HelpOverlay::centered_rect(area, 80, 85);
        // Should be centered
        assert!(centered.x >= area.x);
        assert!(centered.y >= area.y);
        assert!(centered.width <= area.width);
        assert!(centered.height <= area.height);
        // Width should be 80% of 100 = 80
        assert_eq!(centered.width, 80);
    }

    #[test]
    fn test_centered_rect_tiny_area() {
        let area = Rect::new(0, 0, 10, 5);
        let centered = HelpOverlay::centered_rect(area, 80, 85);
        // Should not exceed bounds
        assert!(centered.x + centered.width <= area.x + area.width);
        assert!(centered.y + centered.height <= area.y + area.height);
    }

    #[test]
    fn test_build_help_lines_non_empty() {
        let lines = build_help_lines();
        assert!(!lines.is_empty());
        // Should have multiple sections
        assert!(lines.len() > 20);
    }
}
