//! System: visual feedback for connection state changes.
//!
//! On disconnect: desaturate all agents (reduce glow to 0.2), show red vignette overlay.
//! On reconnect: restore glow, show green flash that fades over 500ms.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::protocol::events::{BackendConnected, BackendDisconnected};
use crate::state::components::AgentVisual;
use crate::state::resources::{ConnectionState, ConnectionStatus};

/// Resource tracking the connection overlay effect.
#[derive(Resource)]
pub struct ConnectionOverlay {
    /// Current overlay color (red for disconnect, green for reconnect).
    pub color: Color,
    /// Remaining overlay lifetime in seconds. 0 = no overlay.
    pub remaining: f32,
    /// Whether we are currently disconnected (persistent red vignette).
    pub disconnected: bool,
    /// Saved glow intensities per entity for restore on reconnect.
    saved_glow: Vec<(Entity, f32)>,
}

impl Default for ConnectionOverlay {
    fn default() -> Self {
        Self {
            color: Color::NONE,
            remaining: 0.0,
            disconnected: false,
            saved_glow: Vec::new(),
        }
    }
}

/// On disconnect: dim all agent glows, start red overlay.
pub fn on_disconnect(
    mut ev_disconnected: EventReader<BackendDisconnected>,
    mut query: Query<(Entity, &mut AgentVisual)>,
    mut overlay: ResMut<ConnectionOverlay>,
) {
    for _ev in ev_disconnected.read() {
        if overlay.disconnected {
            continue;
        }
        overlay.disconnected = true;
        overlay.color = Color::srgba(1.0, 0.1, 0.1, 0.15);
        overlay.remaining = f32::MAX; // Persistent until reconnect

        // Save current glow intensities and dim
        overlay.saved_glow.clear();
        for (entity, mut visual) in query.iter_mut() {
            overlay.saved_glow.push((entity, visual.glow_intensity));
            visual.glow_intensity = 0.2;
        }
    }
}

/// On reconnect: restore agent glows, show green flash.
pub fn on_reconnect(
    mut ev_connected: EventReader<BackendConnected>,
    mut query: Query<(Entity, &mut AgentVisual)>,
    mut overlay: ResMut<ConnectionOverlay>,
) {
    for _ev in ev_connected.read() {
        if !overlay.disconnected {
            continue;
        }
        overlay.disconnected = false;
        overlay.color = Color::srgba(0.1, 1.0, 0.3, 0.2);
        overlay.remaining = 0.5; // 500ms green flash

        // Restore saved glow intensities
        for (entity, saved_glow) in overlay.saved_glow.drain(..) {
            if let Ok((_, mut visual)) = query.get_mut(entity) {
                visual.glow_intensity = saved_glow;
            }
        }
    }
}

/// Fade and tick the overlay timer.
pub fn tick_overlay(time: Res<Time>, mut overlay: ResMut<ConnectionOverlay>) {
    if overlay.disconnected {
        // Red vignette stays up while disconnected
        return;
    }
    if overlay.remaining > 0.0 {
        overlay.remaining -= time.delta_secs();
        if overlay.remaining <= 0.0 {
            overlay.remaining = 0.0;
        }
    }
}

/// Render the connection state overlay as a full-screen egui vignette.
pub fn render_connection_overlay(mut contexts: EguiContexts, overlay: Res<ConnectionOverlay>) {
    if !overlay.disconnected && overlay.remaining <= 0.0 {
        return;
    }

    let alpha = if overlay.disconnected {
        // Pulsing red vignette
        0.15
    } else {
        // Fading green flash (linear fade from 0.2 to 0)
        (overlay.remaining / 0.5).clamp(0.0, 1.0) * 0.2
    };

    if alpha < 0.005 {
        return;
    }

    let linear = overlay.color.to_linear();
    let r = (linear.red * 255.0).min(255.0) as u8;
    let g = (linear.green * 255.0).min(255.0) as u8;
    let b = (linear.blue * 255.0).min(255.0) as u8;
    let a = (alpha * 255.0).min(255.0) as u8;

    let bg = egui::Color32::from_rgba_unmultiplied(r, g, b, a);

    egui::Area::new(egui::Id::new("connection_overlay"))
        .fixed_pos(egui::pos2(0.0, 0.0))
        .order(egui::Order::Background)
        .interactable(false)
        .show(contexts.ctx_mut(), |ui| {
            let screen_rect = ui.ctx().screen_rect();
            ui.painter().rect_filled(screen_rect, 0.0, bg);
        });
}
