//! egui: connection status, selected agent summary, minimap.
//!
//! Thin top bar showing connection state, server version, and agent count.
//! Minimap in bottom-left showing a top-down view of agent positions.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::state::components::AgentNode;
use crate::state::resources::*;

/// Top status bar showing connection info.
pub fn connection_status_bar(
    mut contexts: EguiContexts,
    status: Res<ConnectionStatus>,
) {
    egui::TopBottomPanel::top("connection_status").show(contexts.ctx_mut(), |ui| {
        ui.horizontal(|ui| {
            // Connection indicator dot
            let (color, label) = match &status.state {
                ConnectionState::Connected => (egui::Color32::from_rgb(0, 255, 136), "Connected"),
                ConnectionState::Disconnected => (egui::Color32::from_rgb(255, 51, 68), "Disconnected"),
                ConnectionState::Reconnecting { attempt } => {
                    (egui::Color32::from_rgb(255, 170, 0), "Reconnecting")
                }
            };

            // Colored dot
            let (rect, _) = ui.allocate_exact_size(egui::vec2(10.0, 10.0), egui::Sense::hover());
            ui.painter().circle_filled(rect.center(), 5.0, color);

            ui.label(
                egui::RichText::new(label)
                    .color(color)
                    .size(13.0),
            );

            ui.separator();

            if !status.server_version.is_empty() {
                ui.label(
                    egui::RichText::new(format!("v{}", status.server_version))
                        .color(egui::Color32::from_rgb(120, 140, 180))
                        .size(12.0),
                );
                ui.separator();
            }

            ui.label(
                egui::RichText::new(format!("{} agents", status.agent_count))
                    .color(egui::Color32::from_rgb(120, 140, 180))
                    .size(12.0),
            );

            // Push title to center
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(
                    egui::RichText::new("AUTOPOIESIS HOLODECK")
                        .color(egui::Color32::from_rgb(0, 136, 255))
                        .size(13.0)
                        .strong(),
                );
            });
        });
    });
}

/// Minimap: top-down view of agent positions in bottom-left.
pub fn minimap(
    mut contexts: EguiContexts,
    agents: Query<(&AgentNode, &Transform)>,
    selected: Res<SelectedAgent>,
) {
    egui::Window::new("Minimap")
        .anchor(egui::Align2::LEFT_BOTTOM, egui::vec2(10.0, -10.0))
        .resizable(false)
        .collapsible(true)
        .title_bar(false)
        .fixed_size(egui::vec2(150.0, 150.0))
        .show(contexts.ctx_mut(), |ui| {
            let (rect, _response) = ui.allocate_exact_size(
                egui::vec2(140.0, 140.0),
                egui::Sense::click(),
            );

            let painter = ui.painter_at(rect);
            painter.rect_filled(rect, 4.0, egui::Color32::from_rgba_premultiplied(10, 10, 30, 200));

            // Map world coords to minimap coords
            let world_range = 50.0; // ±50 units
            let map_center = rect.center();
            let map_scale = rect.width() / (world_range * 2.0);

            for (agent, transform) in agents.iter() {
                let x = map_center.x + transform.translation.x * map_scale;
                let y = map_center.y + transform.translation.z * map_scale; // top-down: Z → Y

                let is_selected = selected.agent_id == Some(agent.agent_id);
                let color = if is_selected {
                    egui::Color32::from_rgb(0, 255, 255)
                } else {
                    match agent.state {
                        crate::protocol::types::AgentState::Initialized => egui::Color32::from_rgb(0, 136, 255),
                        crate::protocol::types::AgentState::Running => egui::Color32::from_rgb(0, 255, 136),
                        crate::protocol::types::AgentState::Paused => egui::Color32::from_rgb(255, 170, 0),
                        crate::protocol::types::AgentState::Stopped => egui::Color32::from_rgb(255, 51, 68),
                    }
                };

                let radius = if is_selected { 4.0 } else { 3.0 };
                painter.circle_filled(egui::pos2(x, y), radius, color);
            }
        });
}
