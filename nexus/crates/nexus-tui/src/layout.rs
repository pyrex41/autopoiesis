use ratatui::layout::{Constraint, Direction, Layout, Rect};

/// Which layout preset is active
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LayoutMode {
    #[default]
    Cockpit, // Multi-pane: agent list | primary detail + thoughts | secondary panel
    Focused, // Full-width: single agent with expanded thought stream
    Monitor, // All agents side-by-side, minimal chrome
}

/// Identifies which pane has focus
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum FocusedPane {
    #[default]
    AgentList,
    PrimaryDetail,
    ThoughtStream,
    BlockingPrompt,
    Chat,
    SnapshotDag,
    DiffViewer,
    McpPanel,
    HolodeckViewport,
    CommandBar,
    SecondaryPanel,
}

impl FocusedPane {
    /// Cycle to the next pane in order
    pub fn next(self) -> Self {
        match self {
            Self::AgentList => Self::PrimaryDetail,
            Self::PrimaryDetail => Self::ThoughtStream,
            Self::ThoughtStream => Self::Chat,
            Self::Chat => Self::SnapshotDag,
            Self::SnapshotDag => Self::DiffViewer,
            Self::DiffViewer => Self::McpPanel,
            Self::McpPanel => Self::HolodeckViewport,
            Self::HolodeckViewport => Self::CommandBar,
            Self::CommandBar => Self::AgentList,
            Self::BlockingPrompt => Self::AgentList,
            Self::SecondaryPanel => Self::CommandBar,
        }
    }

    /// Cycle to the previous pane in reverse order
    pub fn prev(self) -> Self {
        match self {
            Self::AgentList => Self::CommandBar,
            Self::PrimaryDetail => Self::AgentList,
            Self::ThoughtStream => Self::PrimaryDetail,
            Self::Chat => Self::ThoughtStream,
            Self::SnapshotDag => Self::Chat,
            Self::DiffViewer => Self::SnapshotDag,
            Self::McpPanel => Self::DiffViewer,
            Self::HolodeckViewport => Self::McpPanel,
            Self::CommandBar => Self::HolodeckViewport,
            Self::BlockingPrompt => Self::ThoughtStream,
            Self::SecondaryPanel => Self::ThoughtStream,
        }
    }
}

pub struct AppLayout {
    pub status_bar: Rect,
    pub main_area: Rect,
    pub command_bar: Rect,
    pub agent_list: Rect,
    pub detail_area: Rect,
    pub agent_detail: Rect,
    pub thought_stream: Rect,
    // New for Phase 2:
    pub secondary_panel: Option<Rect>,
    pub blocking_prompt: Option<Rect>,
    pub chat_area: Option<Rect>,
    pub notification_area: Rect,
    // Phase 3: Holodeck viewport
    pub holodeck_viewport: Option<Rect>,
}

impl AppLayout {
    /// Create a layout for the given area and mode.
    ///
    /// The `has_blocking` parameter controls whether a blocking prompt overlay is allocated.
    pub fn new(area: Rect) -> Self {
        Self::with_mode(area, LayoutMode::Cockpit, false)
    }

    pub fn with_mode(area: Rect, mode: LayoutMode, has_blocking: bool) -> Self {
        Self::with_options(area, mode, has_blocking, false)
    }

    pub fn with_options(area: Rect, mode: LayoutMode, has_blocking: bool, show_holodeck: bool) -> Self {
        match mode {
            LayoutMode::Cockpit => Self::cockpit_layout(area, has_blocking, show_holodeck),
            LayoutMode::Focused => Self::focused_layout(area, has_blocking, show_holodeck),
            LayoutMode::Monitor => Self::monitor_layout(area, has_blocking),
        }
    }

    fn cockpit_layout(area: Rect, has_blocking: bool, show_holodeck: bool) -> Self {
        // Vertical: status(1) | main | command(3)
        let vertical = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let status_bar = vertical[0];
        let main_area = vertical[1];
        let command_bar = vertical[2];

        // Main horizontal: agent_list(20%) | center(50%) | secondary(30%)
        let horizontal = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Percentage(20),
                Constraint::Percentage(50),
                Constraint::Percentage(30),
            ])
            .split(main_area);

        let agent_list = horizontal[0];
        let center = horizontal[1];
        let right_panel = horizontal[2];

        // Split right panel: holodeck viewport (top 50%) | secondary (bottom 50%)
        let (holodeck_viewport, secondary_panel) = if show_holodeck {
            let right_split = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Percentage(50),
                    Constraint::Percentage(50),
                ])
                .split(right_panel);
            (Some(right_split[0]), Some(right_split[1]))
        } else {
            (None, Some(right_panel))
        };

        // Center vertical: agent_detail(6) | thought_stream (or split with blocking)
        let detail_split = if has_blocking {
            Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(6),
                    Constraint::Percentage(60),
                    Constraint::Percentage(40),
                ])
                .split(center)
        } else {
            Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(6),
                    Constraint::Min(3),
                ])
                .split(center)
        };

        let agent_detail = detail_split[0];
        let thought_stream = detail_split[1];
        let blocking_prompt = if has_blocking {
            Some(detail_split[2])
        } else {
            None
        };

        Self {
            status_bar,
            main_area,
            command_bar,
            agent_list,
            detail_area: center,
            agent_detail,
            thought_stream,
            secondary_panel,
            blocking_prompt,
            chat_area: None,
            notification_area: Self::notification_rect(area),
            holodeck_viewport,
        }
    }

    fn focused_layout(area: Rect, has_blocking: bool, show_holodeck: bool) -> Self {
        // Vertical: status(1) | main | command(3)
        let vertical = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let status_bar = vertical[0];
        let main_area = vertical[1];
        let command_bar = vertical[2];

        // In focused mode with holodeck: add a holodeck row above the thought stream
        let holodeck_viewport = if show_holodeck {
            let holo_split = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(12), // holodeck viewport height
                    Constraint::Min(5),
                ])
                .split(main_area);
            Some(holo_split[0])
        } else {
            None
        };

        let content_area = if show_holodeck {
            let holo_split = Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(12),
                    Constraint::Min(5),
                ])
                .split(main_area);
            holo_split[1]
        } else {
            main_area
        };

        // Full width: agent_detail(6) | thought_stream (or split with blocking/chat)
        let detail_split = if has_blocking {
            Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(6),
                    Constraint::Percentage(50),
                    Constraint::Percentage(25),
                    Constraint::Percentage(25),
                ])
                .split(content_area)
        } else {
            Layout::default()
                .direction(Direction::Vertical)
                .constraints([
                    Constraint::Length(6),
                    Constraint::Percentage(70),
                    Constraint::Percentage(30),
                ])
                .split(content_area)
        };

        let agent_detail = detail_split[0];
        let thought_stream = detail_split[1];
        let (blocking_prompt, chat_area) = if has_blocking {
            (Some(detail_split[2]), Some(detail_split[3]))
        } else {
            (None, Some(detail_split[2]))
        };

        Self {
            status_bar,
            main_area,
            command_bar,
            // No agent list in focused mode — use a zero-width rect
            agent_list: Rect::new(main_area.x, main_area.y, 0, main_area.height),
            detail_area: content_area,
            agent_detail,
            thought_stream,
            secondary_panel: None,
            blocking_prompt,
            chat_area,
            notification_area: Self::notification_rect(area),
            holodeck_viewport,
        }
    }

    fn monitor_layout(area: Rect, _has_blocking: bool) -> Self {
        // Vertical: status(1) | main | command(3)
        let vertical = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1),
                Constraint::Min(5),
                Constraint::Length(3),
            ])
            .split(area);

        let status_bar = vertical[0];
        let main_area = vertical[1];
        let command_bar = vertical[2];

        // Main: evenly split into columns (up to 4 agents shown)
        // Each column is one agent's detail + thoughts
        let columns = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Ratio(1, 4),
                Constraint::Ratio(1, 4),
                Constraint::Ratio(1, 4),
                Constraint::Ratio(1, 4),
            ])
            .split(main_area);

        // Use the first column for agent_detail+thought_stream split
        let first_col_split = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(6),
                Constraint::Min(3),
            ])
            .split(columns[0]);

        Self {
            status_bar,
            main_area,
            command_bar,
            // In monitor mode, agent_list is the full main area (columns are rendered by the app)
            agent_list: Rect::new(main_area.x, main_area.y, 0, main_area.height),
            detail_area: columns[0],
            agent_detail: first_col_split[0],
            thought_stream: first_col_split[1],
            secondary_panel: None,
            blocking_prompt: None,
            chat_area: None,
            notification_area: Self::notification_rect(area),
            holodeck_viewport: None, // No holodeck in monitor mode
        }
    }

    /// Notification area is always top-right of the full terminal area
    fn notification_rect(area: Rect) -> Rect {
        let width = 40.min(area.width);
        let height = 5.min(area.height.saturating_sub(4));
        Rect::new(
            area.width.saturating_sub(width),
            1,
            width,
            height,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // === Existing tests (backward-compatible) ===

    #[test]
    fn test_layout_80x24() {
        let area = Rect::new(0, 0, 80, 24);
        let layout = AppLayout::new(area);

        // Status bar is 1 row at the top
        assert_eq!(layout.status_bar.height, 1);
        assert_eq!(layout.status_bar.y, 0);

        // Command bar is 3 rows at the bottom
        assert_eq!(layout.command_bar.height, 3);

        // Agent list takes ~20% of width
        assert!(layout.agent_list.width > 0);
        assert!(layout.agent_list.width < 25);

        // Detail area (center pane) takes ~50% of width in cockpit mode
        assert!(layout.detail_area.width > 30);

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

    // === New Phase 2 tests ===

    #[test]
    fn test_cockpit_layout_produces_valid_rects() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_mode(area, LayoutMode::Cockpit, false);

        assert!(layout.status_bar.area() > 0);
        assert!(layout.main_area.area() > 0);
        assert!(layout.command_bar.area() > 0);
        assert!(layout.agent_list.area() > 0);
        assert!(layout.detail_area.area() > 0);
        assert!(layout.agent_detail.area() > 0);
        assert!(layout.thought_stream.area() > 0);
        assert!(layout.secondary_panel.is_some());
        assert!(layout.secondary_panel.unwrap().area() > 0);
        assert!(layout.notification_area.area() > 0);
    }

    #[test]
    fn test_cockpit_layout_with_blocking() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_mode(area, LayoutMode::Cockpit, true);

        assert!(layout.blocking_prompt.is_some());
        assert!(layout.blocking_prompt.unwrap().area() > 0);
    }

    #[test]
    fn test_cockpit_layout_without_blocking() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_mode(area, LayoutMode::Cockpit, false);

        assert!(layout.blocking_prompt.is_none());
    }

    #[test]
    fn test_focused_layout_expands_detail_full_width() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_mode(area, LayoutMode::Focused, false);

        // In focused mode, detail_area should be the full main_area width
        assert_eq!(layout.detail_area.width, layout.main_area.width);
        // Agent list has zero width
        assert_eq!(layout.agent_list.width, 0);
        // No secondary panel
        assert!(layout.secondary_panel.is_none());
        // Has chat area
        assert!(layout.chat_area.is_some());
        assert!(layout.chat_area.unwrap().area() > 0);
        // agent_detail and thought_stream are valid
        assert!(layout.agent_detail.area() > 0);
        assert!(layout.thought_stream.area() > 0);
    }

    #[test]
    fn test_monitor_layout_splits_evenly() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_mode(area, LayoutMode::Monitor, false);

        // Status and command bars present
        assert_eq!(layout.status_bar.height, 1);
        assert_eq!(layout.command_bar.height, 3);
        // Agent list has zero width (monitor mode shows columns instead)
        assert_eq!(layout.agent_list.width, 0);
        // Agent detail and thought stream are valid (for first column)
        assert!(layout.agent_detail.area() > 0);
        assert!(layout.thought_stream.area() > 0);
        // No secondary panel in monitor mode
        assert!(layout.secondary_panel.is_none());
    }

    #[test]
    fn test_focused_pane_next_cycles() {
        let pane = FocusedPane::AgentList;
        let pane = pane.next(); // PrimaryDetail
        assert_eq!(pane, FocusedPane::PrimaryDetail);
        let pane = pane.next(); // ThoughtStream
        assert_eq!(pane, FocusedPane::ThoughtStream);
        let pane = pane.next(); // Chat
        assert_eq!(pane, FocusedPane::Chat);
        let pane = pane.next(); // SnapshotDag
        assert_eq!(pane, FocusedPane::SnapshotDag);
        let pane = pane.next(); // DiffViewer
        assert_eq!(pane, FocusedPane::DiffViewer);
        let pane = pane.next(); // McpPanel
        assert_eq!(pane, FocusedPane::McpPanel);
        let pane = pane.next(); // HolodeckViewport
        assert_eq!(pane, FocusedPane::HolodeckViewport);
        let pane = pane.next(); // CommandBar
        assert_eq!(pane, FocusedPane::CommandBar);
        let pane = pane.next(); // AgentList (wraps)
        assert_eq!(pane, FocusedPane::AgentList);
    }

    #[test]
    fn test_focused_pane_prev_cycles() {
        let pane = FocusedPane::AgentList;
        let pane = pane.prev(); // CommandBar
        assert_eq!(pane, FocusedPane::CommandBar);
        let pane = pane.prev(); // HolodeckViewport
        assert_eq!(pane, FocusedPane::HolodeckViewport);
        let pane = pane.prev(); // McpPanel
        assert_eq!(pane, FocusedPane::McpPanel);
        let pane = pane.prev(); // DiffViewer
        assert_eq!(pane, FocusedPane::DiffViewer);
        let pane = pane.prev(); // SnapshotDag
        assert_eq!(pane, FocusedPane::SnapshotDag);
        let pane = pane.prev(); // Chat
        assert_eq!(pane, FocusedPane::Chat);
        let pane = pane.prev(); // ThoughtStream
        assert_eq!(pane, FocusedPane::ThoughtStream);
        let pane = pane.prev(); // PrimaryDetail
        assert_eq!(pane, FocusedPane::PrimaryDetail);
        let pane = pane.prev(); // AgentList (wraps)
        assert_eq!(pane, FocusedPane::AgentList);
    }

    #[test]
    fn test_focused_pane_next_special_panes() {
        assert_eq!(FocusedPane::BlockingPrompt.next(), FocusedPane::AgentList);
        assert_eq!(FocusedPane::Chat.next(), FocusedPane::SnapshotDag);
        assert_eq!(FocusedPane::SecondaryPanel.next(), FocusedPane::CommandBar);
    }

    #[test]
    fn test_focused_pane_prev_special_panes() {
        assert_eq!(FocusedPane::BlockingPrompt.prev(), FocusedPane::ThoughtStream);
        assert_eq!(FocusedPane::Chat.prev(), FocusedPane::ThoughtStream);
        assert_eq!(FocusedPane::SecondaryPanel.prev(), FocusedPane::ThoughtStream);
    }

    #[test]
    fn test_notification_rect_position() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::new(area);

        // Notification area in top-right corner
        assert_eq!(layout.notification_area.y, 1);
        assert_eq!(
            layout.notification_area.x + layout.notification_area.width,
            area.width
        );
        assert!(layout.notification_area.width <= 40);
    }

    #[test]
    fn test_layout_mode_default() {
        assert_eq!(LayoutMode::default(), LayoutMode::Cockpit);
    }

    #[test]
    fn test_focused_pane_default() {
        assert_eq!(FocusedPane::default(), FocusedPane::AgentList);
    }

    // === Holodeck viewport layout tests ===

    #[test]
    fn test_cockpit_layout_with_holodeck() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_options(area, LayoutMode::Cockpit, false, true);

        assert!(layout.holodeck_viewport.is_some());
        let hv = layout.holodeck_viewport.unwrap();
        assert!(hv.area() > 0);
        // Secondary panel should also exist (below holodeck)
        assert!(layout.secondary_panel.is_some());
        assert!(layout.secondary_panel.unwrap().area() > 0);
    }

    #[test]
    fn test_cockpit_layout_without_holodeck() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_options(area, LayoutMode::Cockpit, false, false);

        assert!(layout.holodeck_viewport.is_none());
        assert!(layout.secondary_panel.is_some());
    }

    #[test]
    fn test_focused_layout_with_holodeck() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_options(area, LayoutMode::Focused, false, true);

        assert!(layout.holodeck_viewport.is_some());
        let hv = layout.holodeck_viewport.unwrap();
        assert!(hv.area() > 0);
        assert!(layout.agent_detail.area() > 0);
        assert!(layout.thought_stream.area() > 0);
    }

    #[test]
    fn test_monitor_layout_no_holodeck() {
        let area = Rect::new(0, 0, 120, 40);
        let layout = AppLayout::with_options(area, LayoutMode::Monitor, false, true);

        // Monitor mode never shows holodeck
        assert!(layout.holodeck_viewport.is_none());
    }

    #[test]
    fn test_holodeck_viewport_pane_cycle() {
        assert_eq!(FocusedPane::McpPanel.next(), FocusedPane::HolodeckViewport);
        assert_eq!(FocusedPane::HolodeckViewport.next(), FocusedPane::CommandBar);
        assert_eq!(FocusedPane::CommandBar.prev(), FocusedPane::HolodeckViewport);
        assert_eq!(FocusedPane::HolodeckViewport.prev(), FocusedPane::McpPanel);
    }
}
