use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, StatefulWidget, Widget},
};

use crate::theme;
use nexus_holodeck::terminal_encode::{self, TerminalProtocol};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

/// Persistent state for the holodeck viewport, survives across renders.
pub struct HolodeckViewportState {
    /// Image ID for Kitty protocol (incremented per new frame).
    pub image_id: u32,
    /// Hash of the last rendered frame data to detect changes.
    pub last_frame_hash: u64,
    /// Detected terminal graphics protocol.
    pub protocol: TerminalProtocol,
    /// Encoded escape sequence bytes for Kitty/Sixel output (written after ratatui flush).
    pub pending_escape_output: Option<Vec<u8>>,
}

impl Default for HolodeckViewportState {
    fn default() -> Self {
        Self {
            image_id: 1,
            last_frame_hash: 0,
            protocol: TerminalProtocol::from_env(),
            pending_escape_output: None,
        }
    }
}

impl HolodeckViewportState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Check if there's pending escape sequence output to write after ratatui flush.
    pub fn take_pending_output(&mut self) -> Option<Vec<u8>> {
        self.pending_escape_output.take()
    }
}

/// The holodeck viewport widget. Renders 3D scene frames in the terminal.
///
/// For HalfBlock mode: renders colored cells directly into the ratatui Buffer.
/// For Kitty/Sixel mode: stores encoded escape sequences in state for post-flush output.
pub struct HolodeckViewport<'a> {
    connected: bool,
    frame_data: Option<&'a [u8]>,
    frame_width: u32,
    frame_height: u32,
}

impl<'a> HolodeckViewport<'a> {
    pub fn new(connected: bool) -> Self {
        Self {
            connected,
            frame_data: None,
            frame_width: 0,
            frame_height: 0,
        }
    }

    pub fn with_frame(mut self, data: &'a [u8], width: u32, height: u32) -> Self {
        self.frame_data = Some(data);
        self.frame_width = width;
        self.frame_height = height;
        self
    }
}

impl<'a> StatefulWidget for HolodeckViewport<'a> {
    type State = HolodeckViewportState;

    fn render(self, area: Rect, buf: &mut Buffer, state: &mut Self::State) {
        let block = Block::default()
            .title(" Holodeck Viewport ")
            .borders(Borders::ALL)
            .border_style(Style::default().fg(theme::COLOR_BORDER));

        let inner = block.inner(area);
        block.render(area, buf);

        if !self.connected {
            let lines = vec![
                Line::from(vec![Span::styled(
                    " Holodeck Disconnected ",
                    Style::default().fg(Color::Red),
                )]),
                Line::from(vec![Span::styled(
                    " Press Space+d to launch holodeck ",
                    Style::default().fg(theme::COLOR_DIM),
                )]),
            ];
            Paragraph::new(lines).render(inner, buf);
            return;
        }

        let frame_data = match self.frame_data {
            Some(data) if !data.is_empty() => data,
            _ => {
                let lines = vec![
                    Line::from(vec![Span::styled(
                        " Holodeck Connected ",
                        Style::default().fg(Color::Green),
                    )]),
                    Line::from(vec![Span::styled(
                        " Waiting for first frame... ",
                        Style::default().fg(theme::COLOR_DIM),
                    )]),
                ];
                Paragraph::new(lines).render(inner, buf);
                return;
            }
        };

        // Hash the frame data to detect changes
        let mut hasher = DefaultHasher::new();
        frame_data.hash(&mut hasher);
        let frame_hash = hasher.finish();

        let frame_changed = frame_hash != state.last_frame_hash;
        if frame_changed {
            state.last_frame_hash = frame_hash;
        }

        match state.protocol {
            TerminalProtocol::Kitty => {
                if frame_changed {
                    state.image_id = state.image_id.wrapping_add(1);
                    let encoded = terminal_encode::encode_frame_kitty(
                        frame_data,
                        self.frame_width,
                        self.frame_height,
                        state.image_id,
                    );
                    if !encoded.is_empty() {
                        state.pending_escape_output = Some(encoded);
                    }
                }
                // Render a placeholder in the buffer area
                let status = if frame_changed { "Rendering..." } else { "Frame displayed" };
                let lines = vec![Line::from(vec![Span::styled(
                    format!(" [Kitty] {} ", status),
                    Style::default().fg(Color::Cyan),
                )])];
                Paragraph::new(lines).render(inner, buf);
            }
            TerminalProtocol::Sixel => {
                if frame_changed {
                    let encoded = terminal_encode::encode_frame_sixel(
                        frame_data,
                        self.frame_width,
                        self.frame_height,
                    );
                    if !encoded.is_empty() {
                        state.pending_escape_output = Some(encoded);
                    }
                }
                let status = if frame_changed { "Rendering..." } else { "Frame displayed" };
                let lines = vec![Line::from(vec![Span::styled(
                    format!(" [Sixel] {} ", status),
                    Style::default().fg(Color::Cyan),
                )])];
                Paragraph::new(lines).render(inner, buf);
            }
            TerminalProtocol::HalfBlock | TerminalProtocol::None => {
                // Render directly into ratatui buffer using colored halfblock cells
                if self.frame_width > 0 && self.frame_height > 0 {
                    let cells = terminal_encode::encode_frame_halfblock_colored(
                        frame_data,
                        self.frame_width,
                        self.frame_height,
                    );

                    let cell_cols = self.frame_width as u16;
                    let cell_rows = ((self.frame_height + 1) / 2) as u16;

                    let render_cols = cell_cols.min(inner.width);
                    let render_rows = cell_rows.min(inner.height);

                    for row in 0..render_rows {
                        for col in 0..render_cols {
                            let idx = (row as usize) * (cell_cols as usize) + (col as usize);
                            if let Some(&(fg_rgb, bg_rgb)) = cells.get(idx) {
                                let x = inner.x + col;
                                let y = inner.y + row;
                                if x < inner.x + inner.width && y < inner.y + inner.height {
                                    if let Some(cell) = buf.cell_mut((x, y)) {
                                        cell.set_char('▀')
                                            .set_fg(Color::Rgb(fg_rgb[0], fg_rgb[1], fg_rgb[2]))
                                            .set_bg(Color::Rgb(bg_rgb[0], bg_rgb[1], bg_rgb[2]));
                                    }
                                }
                            }
                        }
                    }
                } else {
                    let lines = vec![Line::from(vec![Span::styled(
                        " [HalfBlock] Waiting for frame data... ",
                        Style::default().fg(Color::Yellow),
                    )])];
                    Paragraph::new(lines).render(inner, buf);
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    fn make_state() -> crate::state::AppState {
        crate::state::AppState::default()
    }

    #[test]
    fn test_holodeck_viewport_disconnected() {
        let backend = TestBackend::new(50, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut vp_state = HolodeckViewportState::new();

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_stateful_widget(HolodeckViewport::new(false), area, &mut vp_state);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..5 {
            for x in 0..50 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("Holodeck Disconnected"));
        assert!(all_text.contains("Space+d"));
    }

    #[test]
    fn test_holodeck_viewport_connected_no_frame() {
        let backend = TestBackend::new(50, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut vp_state = HolodeckViewportState::new();

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_stateful_widget(HolodeckViewport::new(true), area, &mut vp_state);
            })
            .unwrap();

        let buf = terminal.backend().buffer().clone();
        let mut all_text = String::new();
        for y in 0..5 {
            for x in 0..50 {
                all_text.push_str(buf.cell((x, y)).unwrap().symbol());
            }
        }
        assert!(all_text.contains("Holodeck Connected"));
        assert!(all_text.contains("Waiting for first frame"));
    }

    #[test]
    fn test_holodeck_viewport_halfblock_rendering() {
        let backend = TestBackend::new(50, 10);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut vp_state = HolodeckViewportState::new();
        // Force HalfBlock protocol for testing
        vp_state.protocol = TerminalProtocol::HalfBlock;

        // 4x4 red image
        let mut rgba = vec![0u8; 4 * 4 * 4];
        for i in (0..rgba.len()).step_by(4) {
            rgba[i] = 255;     // R
            rgba[i + 1] = 0;   // G
            rgba[i + 2] = 0;   // B
            rgba[i + 3] = 255; // A
        }

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_stateful_widget(
                    HolodeckViewport::new(true).with_frame(&rgba, 4, 4),
                    area,
                    &mut vp_state,
                );
            })
            .unwrap();

        // Verify that halfblock chars were rendered
        let buf = terminal.backend().buffer().clone();
        let mut found_halfblock = false;
        for y in 0..10 {
            for x in 0..50 {
                if buf.cell((x, y)).unwrap().symbol() == "▀" {
                    found_halfblock = true;
                }
            }
        }
        assert!(found_halfblock, "Should render halfblock characters");
    }

    #[test]
    fn test_viewport_state_persists_image_id() {
        let mut state = HolodeckViewportState::new();
        assert_eq!(state.image_id, 1);

        // Simulate Kitty frame render
        state.protocol = TerminalProtocol::Kitty;
        let rgba = vec![255u8; 2 * 2 * 4];

        let backend = TestBackend::new(50, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        terminal
            .draw(|f| {
                let area = f.area();
                f.render_stateful_widget(
                    HolodeckViewport::new(true).with_frame(&rgba, 2, 2),
                    area,
                    &mut state,
                );
            })
            .unwrap();

        assert_eq!(state.image_id, 2, "Image ID should increment after frame");
        assert!(state.last_frame_hash != 0, "Frame hash should be set");
    }

    #[test]
    fn test_viewport_no_reencoding_same_frame() {
        let mut state = HolodeckViewportState::new();
        state.protocol = TerminalProtocol::Kitty;
        let rgba = vec![128u8; 2 * 2 * 4];

        let backend = TestBackend::new(50, 5);
        let mut terminal = Terminal::new(backend).unwrap();

        // First render
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_stateful_widget(
                    HolodeckViewport::new(true).with_frame(&rgba, 2, 2),
                    area,
                    &mut state,
                );
            })
            .unwrap();

        let id_after_first = state.image_id;
        let _ = state.take_pending_output(); // consume

        // Second render with same frame
        terminal
            .draw(|f| {
                let area = f.area();
                f.render_stateful_widget(
                    HolodeckViewport::new(true).with_frame(&rgba, 2, 2),
                    area,
                    &mut state,
                );
            })
            .unwrap();

        assert_eq!(state.image_id, id_after_first, "Should NOT re-encode same frame");
        assert!(state.pending_escape_output.is_none(), "No pending output for same frame");
    }
}
