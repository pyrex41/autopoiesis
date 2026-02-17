use nexus_protocol::types::{BranchData, SnapshotData};
use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Widget, Wrap},
};

use crate::theme;

pub struct SnapshotDag<'a> {
    nodes: &'a [SnapshotData],
    branches: &'a [BranchData],
    current_branch: Option<&'a str>,
    selected_idx: usize,
    is_focused: bool,
}

impl<'a> SnapshotDag<'a> {
    pub fn new(
        nodes: &'a [SnapshotData],
        branches: &'a [BranchData],
        current_branch: Option<&'a str>,
        selected_idx: usize,
        is_focused: bool,
    ) -> Self {
        Self {
            nodes,
            branches,
            current_branch,
            selected_idx,
            is_focused,
        }
    }
}

/// Format a timestamp delta as a human-readable "ago" string.
fn format_ago(now: f64, ts: f64) -> String {
    let delta = (now - ts).max(0.0) as u64;
    if delta < 60 {
        "just now".to_string()
    } else if delta < 3600 {
        format!("{}m ago", delta / 60)
    } else if delta < 86400 {
        format!("{}h ago", delta / 3600)
    } else {
        format!("{}d ago", delta / 86400)
    }
}

impl<'a> Widget for SnapshotDag<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // Sort snapshots by timestamp (most recent first)
        let mut sorted: Vec<(usize, &SnapshotData)> =
            self.nodes.iter().enumerate().collect();
        sorted.sort_by(|a, b| b.1.timestamp.partial_cmp(&a.1.timestamp).unwrap_or(std::cmp::Ordering::Equal));

        // Build map: snapshot_id -> list of branch names pointing at it
        let mut branch_map: std::collections::HashMap<&str, Vec<&str>> =
            std::collections::HashMap::new();
        for b in self.branches {
            if let Some(ref head) = b.head {
                branch_map.entry(head.as_str()).or_default().push(&b.name);
            }
        }

        // Find the HEAD snapshot: most recent snapshot on the current branch
        let head_id: Option<&str> = self.current_branch.and_then(|cb| {
            self.branches
                .iter()
                .find(|b| b.name == cb)
                .and_then(|b| b.head.as_deref())
        });

        // Determine "now" for relative timestamps
        let now = sorted
            .first()
            .map(|(_, s)| s.timestamp)
            .unwrap_or(0.0);

        // Build lines
        let lines: Vec<Line> = if sorted.is_empty() {
            vec![Line::from(Span::styled(
                "  No snapshots",
                Style::default().fg(Color::DarkGray),
            ))]
        } else {
            sorted
                .iter()
                .enumerate()
                .map(|(display_idx, (_orig_idx, snap))| {
                    let is_selected = display_idx == self.selected_idx;
                    let is_head = head_id.is_some_and(|h| h == snap.id);

                    // Is this snapshot on the current branch?
                    let on_current_branch = self.current_branch.is_some_and(|cb| {
                        branch_map
                            .get(snap.id.as_str())
                            .is_some_and(|names| names.contains(&cb))
                    });

                    let marker = if is_selected { ">" } else { " " };
                    let symbol = if is_head { "◆" } else { "●" };
                    let short_id = &snap.id[..snap.id.len().min(8)];
                    let ago = format_ago(now, snap.timestamp);

                    // Branch labels
                    let labels: String = branch_map
                        .get(snap.id.as_str())
                        .map(|names| {
                            names.iter().map(|n| format!("[{}]", n)).collect::<Vec<_>>().join("")
                        })
                        .unwrap_or_default();

                    // Colors
                    let base_color = if is_selected {
                        Color::Cyan
                    } else if on_current_branch || is_head {
                        Color::Rgb(255, 215, 0) // gold
                    } else {
                        Color::Rgb(100, 130, 180) // dim blue
                    };

                    let style = if is_selected {
                        Style::default().fg(base_color).add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(base_color)
                    };

                    let label_text = if labels.is_empty() {
                        String::new()
                    } else {
                        format!(" {}", labels)
                    };

                    Line::from(vec![
                        Span::styled(format!(" {} {} ", marker, symbol), style),
                        Span::styled(short_id.to_string(), style),
                        Span::styled(
                            label_text,
                            Style::default()
                                .fg(Color::Rgb(255, 215, 0))
                                .add_modifier(Modifier::BOLD),
                        ),
                        Span::styled(format!(" {}", ago), Style::default().fg(Color::DarkGray)),
                    ])
                })
                .collect()
        };

        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(theme::border_style(self.is_focused))
            .title(Span::styled(
                " Snapshot DAG ",
                Style::default()
                    .fg(theme::COLOR_TITLE)
                    .add_modifier(Modifier::BOLD),
            ));

        let paragraph = Paragraph::new(lines).block(block).wrap(Wrap { trim: false });
        paragraph.render(area, buf);
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

    fn make_snap(id: &str, ts: f64) -> SnapshotData {
        SnapshotData {
            id: id.to_string(),
            parent: None,
            hash: None,
            metadata: None,
            timestamp: ts,
        }
    }

    fn make_branch(name: &str, head: &str) -> BranchData {
        BranchData {
            name: name.to_string(),
            head: Some(head.to_string()),
            created: None,
        }
    }

    #[test]
    fn test_empty_dag() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|f| {
                let area = f.area();
                let w = SnapshotDag::new(&[], &[], None, 0, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(text.contains("Snapshot DAG"), "should show title");
        assert!(text.contains("No snapshots"), "should show empty message");
    }

    #[test]
    fn test_dag_renders_snapshot_ids() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let snaps = vec![
            make_snap("abcdef1234567890", 1000.0),
            make_snap("deadbeef12345678", 900.0),
        ];

        terminal
            .draw(|f| {
                let area = f.area();
                let w = SnapshotDag::new(&snaps, &[], None, 0, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(text.contains("abcdef12"), "should show truncated id of first snap");
        assert!(text.contains("deadbeef"), "should show truncated id of second snap");
    }

    #[test]
    fn test_dag_shows_branch_labels() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let snaps = vec![make_snap("abcdef1234567890", 1000.0)];
        let branches = vec![make_branch("main", "abcdef1234567890")];

        terminal
            .draw(|f| {
                let area = f.area();
                let w = SnapshotDag::new(&snaps, &branches, Some("main"), 0, true);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        assert!(text.contains("[main]"), "should show branch label");
    }

    #[test]
    fn test_dag_selected_marker() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let snaps = vec![
            make_snap("aaaa111122223333", 1000.0),
            make_snap("bbbb444455556666", 500.0),
        ];

        terminal
            .draw(|f| {
                let area = f.area();
                // Select the second item (index 1)
                let w = SnapshotDag::new(&snaps, &[], None, 1, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        // The selected marker ">" should appear before the second snapshot
        assert!(text.contains(">"), "should show selection marker");
        assert!(text.contains("bbbb4444"), "should show second snap id");
    }

    #[test]
    fn test_dag_head_symbol() {
        let backend = TestBackend::new(40, 15);
        let mut terminal = Terminal::new(backend).unwrap();

        let snaps = vec![
            make_snap("head_snap_id_abc", 2000.0),
            make_snap("older_snap_id_xy", 1000.0),
        ];
        let branches = vec![make_branch("main", "head_snap_id_abc")];

        terminal
            .draw(|f| {
                let area = f.area();
                let w = SnapshotDag::new(&snaps, &branches, Some("main"), 0, false);
                f.render_widget(w, area);
            })
            .unwrap();

        let text = buf_text(&terminal, 40, 15);
        // HEAD snapshot gets diamond, others get circle
        assert!(text.contains("◆"), "HEAD should get diamond symbol");
        assert!(text.contains("●"), "non-HEAD should get circle symbol");
    }

    #[test]
    fn test_format_ago() {
        assert_eq!(format_ago(100.0, 100.0), "just now");
        assert_eq!(format_ago(100.0, 95.0), "just now"); // 5s
        assert_eq!(format_ago(1000.0, 700.0), "5m ago"); // 300s
        assert_eq!(format_ago(10000.0, 2800.0), "2h ago"); // 7200s
        assert_eq!(format_ago(500000.0, 241600.0), "2d ago"); // 259200s => 3 days, wait: 258400/86400=2.99 => 2d
    }
}
