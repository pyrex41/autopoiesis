//! egui: detailed thought view when clicking a particle or thought entry.
//!
//! Shows the full thought content, metadata, alternatives, and rationale.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::protocol::types::{ThoughtData, ThoughtType};

/// Resource holding the currently inspected thought (if any).
#[derive(Resource, Default)]
pub struct InspectedThought {
    pub thought: Option<ThoughtData>,
}

/// Render the thought inspector window.
pub fn thought_inspector_window(
    mut contexts: EguiContexts,
    mut inspected: ResMut<InspectedThought>,
) {
    let Some(thought) = inspected.thought.clone() else {
        return;
    };

    let mut open = true;

    egui::Window::new("Thought Inspector")
        .open(&mut open)
        .resizable(true)
        .default_width(400.0)
        .default_height(300.0)
        .show(contexts.ctx_mut(), |ui| {
            // Type badge
            let (type_color, type_label) = match thought.thought_type {
                ThoughtType::Observation => (egui::Color32::from_rgb(80, 140, 255), "OBSERVATION"),
                ThoughtType::Decision => (egui::Color32::from_rgb(255, 215, 0), "DECISION"),
                ThoughtType::Action => (egui::Color32::from_rgb(0, 255, 136), "ACTION"),
                ThoughtType::Reflection => (egui::Color32::from_rgb(160, 80, 255), "REFLECTION"),
            };

            ui.horizontal(|ui| {
                ui.label(
                    egui::RichText::new(type_label)
                        .color(type_color)
                        .size(14.0)
                        .strong(),
                );
                ui.label(
                    egui::RichText::new(format!("Confidence: {:.0}%", thought.confidence * 100.0))
                        .color(egui::Color32::from_rgb(150, 160, 200))
                        .size(12.0),
                );
            });

            ui.add_space(4.0);
            ui.label(
                egui::RichText::new(format!("ID: {}", thought.id))
                    .color(egui::Color32::from_rgb(100, 110, 140))
                    .size(10.0),
            );

            ui.add_space(8.0);

            // Content
            ui.label(
                egui::RichText::new("Content")
                    .color(egui::Color32::from_rgb(150, 160, 200))
                    .size(12.0),
            );
            egui::ScrollArea::vertical()
                .max_height(150.0)
                .show(ui, |ui| {
                    ui.label(
                        egui::RichText::new(&thought.content)
                            .color(egui::Color32::from_rgb(220, 220, 240))
                            .size(12.0)
                            .family(egui::FontFamily::Monospace),
                    );
                });

            // Rationale
            if let Some(ref rationale) = thought.rationale {
                ui.add_space(8.0);
                ui.label(
                    egui::RichText::new("Rationale")
                        .color(egui::Color32::from_rgb(150, 160, 200))
                        .size(12.0),
                );
                ui.label(
                    egui::RichText::new(rationale)
                        .color(egui::Color32::from_rgb(200, 200, 220))
                        .size(11.0),
                );
            }

            // Source
            if let Some(ref source) = thought.source {
                ui.add_space(4.0);
                ui.label(
                    egui::RichText::new(format!("Source: {source}"))
                        .color(egui::Color32::from_rgb(120, 130, 160))
                        .size(11.0),
                );
            }

            // Alternatives
            if !thought.alternatives.is_empty() {
                ui.add_space(8.0);
                ui.label(
                    egui::RichText::new("Alternatives")
                        .color(egui::Color32::from_rgb(150, 160, 200))
                        .size(12.0),
                );
                for alt in &thought.alternatives {
                    ui.label(
                        egui::RichText::new(format!("  • {alt}"))
                            .color(egui::Color32::from_rgb(180, 180, 200))
                            .size(11.0),
                    );
                }
            }
        });

    if !open {
        inspected.thought = None;
    }
}
