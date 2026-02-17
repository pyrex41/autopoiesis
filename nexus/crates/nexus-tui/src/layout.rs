use ratatui::layout::{Constraint, Direction, Layout, Rect};

pub struct AppLayout {
    pub status_bar: Rect,
    pub main_area: Rect,
    pub command_bar: Rect,
    pub agent_list: Rect,
    pub detail_area: Rect,
    pub agent_detail: Rect,
    pub thought_stream: Rect,
}

impl AppLayout {
    pub fn new(area: Rect) -> Self {
        let vertical = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1),  // status bar
                Constraint::Min(5),    // main area
                Constraint::Length(3), // command bar
            ])
            .split(area);

        let status_bar = vertical[0];
        let main_area = vertical[1];
        let command_bar = vertical[2];

        let horizontal = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(25),
                Constraint::Percentage(75),
            ])
            .split(main_area);

        let agent_list = horizontal[0];
        let detail_area = horizontal[1];

        let detail_split = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(6), // agent detail
                Constraint::Min(3),   // thought stream
            ])
            .split(detail_area);

        Self {
            status_bar,
            main_area,
            command_bar,
            agent_list,
            detail_area,
            agent_detail: detail_split[0],
            thought_stream: detail_split[1],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_layout_80x24() {
        let area = Rect::new(0, 0, 80, 24);
        let layout = AppLayout::new(area);

        // Status bar is 1 row at the top
        assert_eq!(layout.status_bar.height, 1);
        assert_eq!(layout.status_bar.y, 0);

        // Command bar is 3 rows at the bottom
        assert_eq!(layout.command_bar.height, 3);

        // Agent list takes ~25% of width
        assert!(layout.agent_list.width > 0);
        assert!(layout.agent_list.width < 30);

        // Detail area takes ~75% of width
        assert!(layout.detail_area.width > 50);

        // All rects have non-zero area
        assert!(layout.status_bar.area() > 0);
        assert!(layout.main_area.area() > 0);
        assert!(layout.command_bar.area() > 0);
        assert!(layout.agent_list.area() > 0);
        assert!(layout.detail_area.area() > 0);
        assert!(layout.agent_detail.area() > 0);
        assert!(layout.thought_stream.area() > 0);
    }

    #[test]
    fn test_layout_small_terminal() {
        let area = Rect::new(0, 0, 40, 12);
        let layout = AppLayout::new(area);

        assert_eq!(layout.status_bar.height, 1);
        assert_eq!(layout.command_bar.height, 3);
        assert!(layout.agent_list.width > 0);
        assert!(layout.thought_stream.height > 0);
    }
}
