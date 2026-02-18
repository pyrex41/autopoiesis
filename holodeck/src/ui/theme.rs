//! Holographic egui theme for the Holodeck UI.
//!
//! Applies a dark sci-fi aesthetic with cyan accents, amber highlights,
//! and sharp geometric styling to all egui panels.

use bevy::prelude::*;
use bevy_egui::egui::{self, Color32, CornerRadius, Stroke, Visuals};

// --- Holographic Palette ---

pub const VOID_BLACK: Color32 = Color32::from_rgb(5, 10, 15);
pub const HOLO_CYAN: Color32 = Color32::from_rgb(0, 180, 216);
pub const AMBER_FOCUS: Color32 = Color32::from_rgb(255, 209, 102);
pub const TEAL_SUCCESS: Color32 = Color32::from_rgb(6, 214, 160);
pub const RED_CRITICAL: Color32 = Color32::from_rgb(239, 35, 60);
pub const TEXT_PRIMARY: Color32 = Color32::from_rgb(232, 244, 248);
pub const TEXT_SECONDARY: Color32 = Color32::from_rgb(120, 160, 180);
pub const PANEL_BG: Color32 = Color32::from_rgba_premultiplied(8, 15, 22, 230);
pub const BORDER: Color32 = Color32::from_rgba_premultiplied(0, 100, 140, 180);

const HOLO_CYAN_DIM: Color32 = Color32::from_rgba_premultiplied(0, 120, 160, 60);
const AMBER_DIM: Color32 = Color32::from_rgba_premultiplied(180, 150, 70, 60);
const FAINT_BG: Color32 = Color32::from_rgb(10, 18, 28);

/// Apply the holographic theme to an egui context. Call once at startup.
pub fn apply_holographic_theme(ctx: &egui::Context) {
    let mut visuals = Visuals::dark();

    // Window and panel backgrounds
    visuals.window_fill = PANEL_BG;
    visuals.panel_fill = PANEL_BG;
    visuals.extreme_bg_color = VOID_BLACK;
    visuals.faint_bg_color = FAINT_BG;

    // Selection
    visuals.selection.bg_fill = HOLO_CYAN_DIM;
    visuals.selection.stroke = Stroke::new(1.0, HOLO_CYAN);

    // Hyperlinks
    visuals.hyperlink_color = HOLO_CYAN;

    // Window stroke (border)
    visuals.window_stroke = Stroke::new(1.0, BORDER);
    visuals.window_shadow = egui::Shadow::NONE;
    visuals.window_corner_radius = CornerRadius::same(2);

    // Widget styling: noninteractive
    visuals.widgets.noninteractive.bg_fill = Color32::TRANSPARENT;
    visuals.widgets.noninteractive.fg_stroke = Stroke::new(1.0, TEXT_SECONDARY);
    visuals.widgets.noninteractive.bg_stroke = Stroke::new(0.5, BORDER);
    visuals.widgets.noninteractive.corner_radius = CornerRadius::same(2);

    // Widget styling: inactive (enabled but not hovered)
    visuals.widgets.inactive.bg_fill = Color32::from_rgba_premultiplied(15, 25, 35, 200);
    visuals.widgets.inactive.fg_stroke = Stroke::new(1.0, TEXT_PRIMARY);
    visuals.widgets.inactive.bg_stroke = Stroke::new(0.5, BORDER);
    visuals.widgets.inactive.corner_radius = CornerRadius::same(2);

    // Widget styling: hovered
    visuals.widgets.hovered.bg_fill = HOLO_CYAN_DIM;
    visuals.widgets.hovered.fg_stroke = Stroke::new(1.5, HOLO_CYAN);
    visuals.widgets.hovered.bg_stroke = Stroke::new(1.0, HOLO_CYAN);
    visuals.widgets.hovered.corner_radius = CornerRadius::same(2);

    // Widget styling: active (clicked)
    visuals.widgets.active.bg_fill = AMBER_DIM;
    visuals.widgets.active.fg_stroke = Stroke::new(1.5, AMBER_FOCUS);
    visuals.widgets.active.bg_stroke = Stroke::new(1.0, AMBER_FOCUS);
    visuals.widgets.active.corner_radius = CornerRadius::same(2);

    // Widget styling: open (e.g., combo box)
    visuals.widgets.open.bg_fill = Color32::from_rgba_premultiplied(10, 20, 30, 240);
    visuals.widgets.open.fg_stroke = Stroke::new(1.0, HOLO_CYAN);
    visuals.widgets.open.bg_stroke = Stroke::new(1.0, HOLO_CYAN);
    visuals.widgets.open.corner_radius = CornerRadius::same(2);

    // Popup shadow
    visuals.popup_shadow = egui::Shadow::NONE;

    // Resize and interaction stroke
    visuals.resize_corner_size = 8.0;

    ctx.set_visuals(visuals);

    // Spacing tweaks
    let mut style = (*ctx.style()).clone();
    style.spacing.item_spacing = egui::vec2(8.0, 4.0);
    style.spacing.window_margin = egui::Margin::same(8);
    style.spacing.button_padding = egui::vec2(8.0, 3.0);
    ctx.set_style(style);
}

/// System that applies the theme on the first frame.
pub fn apply_theme_system(mut contexts: bevy_egui::EguiContexts, mut applied: Local<bool>) {
    if !*applied {
        if let Some(ctx) = contexts.try_ctx_mut() {
            apply_holographic_theme(ctx);
            *applied = true;
        }
    }
}
