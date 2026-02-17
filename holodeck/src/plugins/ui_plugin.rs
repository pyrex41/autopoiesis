//! Bundles all egui UI systems.
//!
//! HUD, command bar, agent detail panel, notifications, thought inspector.

use bevy::prelude::*;

use crate::ui::{agent_panel, command_bar, hud, notifications, theme, thought_inspector};

/// Plugin for all egui-based UI.
pub struct UiPlugin;

impl Plugin for UiPlugin {
    fn build(&self, app: &mut App) {
        app
            // UI state resources
            .init_resource::<agent_panel::AgentPanelState>()
            .init_resource::<command_bar::CommandBarState>()
            .init_resource::<notifications::ToastQueue>()
            .init_resource::<thought_inspector::InspectedThought>()
            // Theme (applied on first frame)
            .add_systems(Update, theme::apply_theme_system)
            // HUD systems
            .add_systems(Update, (
                hud::connection_status_bar,
                hud::minimap,
            ))
            // Agent detail panel
            .add_systems(Update, agent_panel::agent_detail_panel)
            // Command bar
            .add_systems(Update, command_bar::command_bar)
            // Notifications
            .add_systems(Update, (
                notifications::collect_notifications,
                notifications::render_notifications.after(notifications::collect_notifications),
            ))
            // Thought inspector
            .add_systems(Update, thought_inspector::thought_inspector_window);
    }
}
