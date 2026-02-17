//! egui: agent detail view, thought list, action buttons.
//!
//! Right-side panel showing details for the currently selected agent.
//! Includes: name, state, capabilities, thoughts, and control buttons.

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::protocol::types::ThoughtType;
use crate::state::events::*;
use crate::state::resources::*;
use crate::ui::thought_inspector::InspectedThought;

/// Local state for the inject-thought text input.
#[derive(Resource, Default)]
pub struct AgentPanelState {
    pub inject_text: String,
}

/// Right-side panel for the selected agent.
pub fn agent_detail_panel(
    mut contexts: EguiContexts,
    selected: Res<SelectedAgent>,
    agent_registry: Res<AgentRegistry>,
    thought_cache: Res<ThoughtCache>,
    mut panel_state: ResMut<AgentPanelState>,
    mut ev_action: EventWriter<SendAgentAction>,
    mut ev_step: EventWriter<SendStepAgent>,
    mut ev_inject: EventWriter<SendInjectThought>,
    mut inspected: ResMut<InspectedThought>,
) {
    let Some(agent_id) = selected.agent_id else {
        return;
    };

    let Some(agent) = agent_registry.get(&agent_id) else {
        return;
    };

    egui::SidePanel::right("agent_panel")
        .resizable(true)
        .min_width(250.0)
        .default_width(300.0)
        .show(contexts.ctx_mut(), |ui| {
            ui.heading(
                egui::RichText::new(&agent.name)
                    .color(egui::Color32::from_rgb(0, 200, 255))
                    .size(18.0),
            );

            ui.add_space(4.0);

            // State badge
            let (state_color, state_text) = match &agent.state {
                crate::protocol::types::AgentState::Initialized => {
                    (egui::Color32::from_rgb(0, 136, 255), "INITIALIZED")
                }
                crate::protocol::types::AgentState::Running => {
                    (egui::Color32::from_rgb(0, 255, 136), "RUNNING")
                }
                crate::protocol::types::AgentState::Paused => {
                    (egui::Color32::from_rgb(255, 170, 0), "PAUSED")
                }
                crate::protocol::types::AgentState::Stopped => {
                    (egui::Color32::from_rgb(255, 51, 68), "STOPPED")
                }
            };
            ui.label(
                egui::RichText::new(state_text)
                    .color(state_color)
                    .size(12.0)
                    .strong(),
            );
            ui.label(format!("ID: {}", agent.id));
            ui.label(format!("Thoughts: {}", agent.thought_count));

            ui.add_space(8.0);

            // Capabilities
            if !agent.capabilities.is_empty() {
                ui.label(
                    egui::RichText::new("Capabilities")
                        .color(egui::Color32::from_rgb(150, 160, 200))
                        .size(13.0),
                );
                for cap in &agent.capabilities {
                    ui.label(format!("  • {cap}"));
                }
                ui.add_space(8.0);
            }

            // Action buttons
            ui.horizontal(|ui| {
                if ui.button("▶ Start").clicked() {
                    ev_action.send(SendAgentAction {
                        agent_id,
                        action: "start".into(),
                    });
                }
                if ui.button("⏸ Pause").clicked() {
                    ev_action.send(SendAgentAction {
                        agent_id,
                        action: "pause".into(),
                    });
                }
                if ui.button("⏹ Stop").clicked() {
                    ev_action.send(SendAgentAction {
                        agent_id,
                        action: "stop".into(),
                    });
                }
            });

            ui.horizontal(|ui| {
                if ui.button("↻ Resume").clicked() {
                    ev_action.send(SendAgentAction {
                        agent_id,
                        action: "resume".into(),
                    });
                }
                if ui.button("⟳ Step").clicked() {
                    ev_step.send(SendStepAgent { agent_id });
                }
            });

            ui.add_space(8.0);

            // Inject thought
            ui.label(
                egui::RichText::new("Inject Thought")
                    .color(egui::Color32::from_rgb(150, 160, 200))
                    .size(13.0),
            );
            ui.horizontal(|ui| {
                let response = ui.text_edit_singleline(&mut panel_state.inject_text);
                if (response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)))
                    || ui.button("Send").clicked()
                {
                    if !panel_state.inject_text.is_empty() {
                        ev_inject.send(SendInjectThought {
                            agent_id,
                            content: panel_state.inject_text.clone(),
                            thought_type: "observation".into(),
                        });
                        panel_state.inject_text.clear();
                    }
                }
            });

            ui.add_space(8.0);

            // Thought list
            ui.label(
                egui::RichText::new("Recent Thoughts")
                    .color(egui::Color32::from_rgb(150, 160, 200))
                    .size(13.0),
            );

            egui::ScrollArea::vertical()
                .max_height(400.0)
                .show(ui, |ui| {
                    for thought in thought_cache.thoughts.iter().rev().take(50) {
                        let (type_color, type_label) = match thought.thought_type {
                            ThoughtType::Observation => {
                                (egui::Color32::from_rgb(80, 140, 255), "OBS")
                            }
                            ThoughtType::Decision => {
                                (egui::Color32::from_rgb(255, 215, 0), "DEC")
                            }
                            ThoughtType::Action => {
                                (egui::Color32::from_rgb(0, 255, 136), "ACT")
                            }
                            ThoughtType::Reflection => {
                                (egui::Color32::from_rgb(160, 80, 255), "REF")
                            }
                        };

                        let preview: String = thought
                            .content
                            .chars()
                            .take(80)
                            .collect();
                        let label_text = format!("[{type_label}] {preview}");
                        let is_selected = inspected.thought.as_ref()
                            .map_or(false, |t| t.id == thought.id);
                        let response = ui.selectable_label(
                            is_selected,
                            egui::RichText::new(label_text)
                                .color(if is_selected { type_color } else { egui::Color32::from_rgb(200, 200, 220) })
                                .size(11.0),
                        );
                        if response.clicked() {
                            inspected.thought = Some(thought.clone());
                        }
                    }
                });
        });
}
