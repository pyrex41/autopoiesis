use std::time::{Duration, Instant};

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Clear, Paragraph, Widget},
};

const NOTIFICATION_DURATION: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NotificationLevel {
    Info,
    Success,
    Warning,
    Error,
}

impl NotificationLevel {
    pub fn color(&self) -> Color {
        match self {
            Self::Info => Color::Rgb(100, 149, 237),
            Self::Success => Color::Rgb(0, 255, 136),
            Self::Warning => Color::Rgb(255, 170, 0),
            Self::Error => Color::Rgb(255, 51, 68),
        }
    }

    pub fn icon(&self) -> &'static str {
        match self {
            Self::Info => "i",
            Self::Success => "+",
            Self::Warning => "!",
            Self::Error => "x",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Notification {
    pub message: String,
    pub level: NotificationLevel,
    pub created_at: Instant,
}

impl Notification {
    pub fn new(message: impl Into<String>, level: NotificationLevel) -> Self {
        Self {
            message: message.into(),
            level,
            created_at: Instant::now(),
        }
    }

    pub fn is_expired(&self) -> bool {
        self.created_at.elapsed() > NOTIFICATION_DURATION
    }
}

/// Renders a stack of notifications in the given area (top-right corner).
pub struct NotificationStack<'a> {
    notifications: &'a [Notification],
}

impl<'a> NotificationStack<'a> {
    pub fn new(notifications: &'a [Notification]) -> Self {
        Self { notifications }
    }
}

impl<'a> Widget for NotificationStack<'a> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        // Filter to non-expired, take last 3
        let active: Vec<_> = self.notifications.iter().filter(|n| !n.is_expired()).collect();
        let to_show: Vec<_> = active.iter().rev().take(3).rev().cloned().collect();

        if to_show.is_empty() {
            return;
        }

        let mut y = area.y;
        for notif in &to_show {
            if y >= area.y + area.height {
                break;
            }

            let width = (notif.message.len() as u16 + 6).min(area.width);
            let rect = Rect::new(
                area.x + area.width.saturating_sub(width),
                y,
                width,
                1,
            );

            Clear.render(rect, buf);

            let color = notif.level.color();
            let icon = notif.level.icon();
            let line = Line::from(vec![
                Span::styled(
                    format!(" [{icon}] "),
                    Style::default()
                        .fg(color)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::styled(&notif.message, Style::default().fg(Color::White)),
                Span::raw(" "),
            ]);

            Paragraph::new(line)
                .style(Style::default().bg(Color::Rgb(30, 30, 50)))
                .render(rect, buf);

            y += 1;
        }
    }
}

/// Prune expired notifications from a list.
pub fn prune_expired(notifications: &mut Vec<Notification>) {
    notifications.retain(|n| !n.is_expired());
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    #[test]
    fn test_notification_expiry() {
        let notif = Notification {
            message: "test".to_string(),
            level: NotificationLevel::Info,
            created_at: Instant::now() - Duration::from_secs(10),
        };
        assert!(notif.is_expired());
    }

    #[test]
    fn test_notification_not_expired() {
        let notif = Notification::new("test", NotificationLevel::Info);
        assert!(!notif.is_expired());
    }

    #[test]
    fn test_notification_level_colors() {
        assert_ne!(NotificationLevel::Info.color(), NotificationLevel::Error.color());
        assert_ne!(
            NotificationLevel::Success.icon(),
            NotificationLevel::Warning.icon()
        );
    }

    #[test]
    fn test_prune_expired() {
        let mut notifs = vec![
            Notification {
                message: "old".to_string(),
                level: NotificationLevel::Info,
                created_at: Instant::now() - Duration::from_secs(10),
            },
            Notification::new("new", NotificationLevel::Success),
        ];
        prune_expired(&mut notifs);
        assert_eq!(notifs.len(), 1);
        assert_eq!(notifs[0].message, "new");
    }

    #[test]
    fn test_notification_stack_renders() {
        let backend = TestBackend::new(50, 5);
        let mut terminal = Terminal::new(backend).unwrap();
        let notifs = vec![
            Notification::new("Agent created", NotificationLevel::Success),
            Notification::new("Connection lost", NotificationLevel::Error),
        ];
        terminal
            .draw(|f| {
                f.render_widget(NotificationStack::new(&notifs), f.area());
            })
            .unwrap();
    }
}
