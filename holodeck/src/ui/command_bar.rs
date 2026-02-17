//! egui: text input for commands.
//!
//! Bottom panel with a text input field. Press `/` or `Enter` to focus.
//! Supports simple commands:
//!   - `create agent <name>` → create_agent
//!   - `snapshot <agent> <label>` → create_snapshot
//!   - `step <agent>` → step_agent
//!   - Anything else → inject as observation to selected agent

use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};

use crate::state::events::*;
use crate::state::resources::*;

/// Local state for the command bar.
#[derive(Resource, Default)]
pub struct CommandBarState {
    pub input: String,
    pub should_focus: bool,
    pub history: Vec<String>,
    pub history_index: Option<usize>,
}

/// Bottom command bar panel.
pub fn command_bar(
    mut contexts: EguiContexts,
    mut state: ResMut<CommandBarState>,
    selected: Res<SelectedAgent>,
    agent_registry: Res<AgentRegistry>,
    mut ev_create_agent: EventWriter<SendCreateAgent>,
    mut ev_step_agent: EventWriter<SendStepAgent>,
    mut ev_create_snapshot: EventWriter<SendCreateSnapshot>,
    mut ev_inject: EventWriter<SendInjectThought>,
) {
    // Check for `/` key press to focus the command bar
    let ctx = contexts.ctx_mut();
    if ctx.input(|i| i.key_pressed(egui::Key::Slash)) && !ctx.wants_keyboard_input() {
        state.should_focus = true;
    }

    egui::TopBottomPanel::bottom("command_bar").show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label(
                egui::RichText::new(">")
                    .color(egui::Color32::from_rgb(0, 200, 255))
                    .size(14.0)
                    .strong(),
            );

            let response = ui.add(
                egui::TextEdit::singleline(&mut state.input)
                    .desired_width(ui.available_width() - 60.0)
                    .hint_text("Type a command... (/ to focus)")
                    .text_color(egui::Color32::from_rgb(220, 220, 240))
                    .font(egui::TextStyle::Monospace),
            );

            if state.should_focus {
                response.request_focus();
                state.should_focus = false;
            }

            let submitted = response.lost_focus()
                && ui.input(|i| i.key_pressed(egui::Key::Enter));

            if submitted && !state.input.is_empty() {
                let input = state.input.trim().to_string();
                state.history.push(input.clone());
                state.history_index = None;
                state.input.clear();

                execute_command(
                    &input,
                    &selected,
                    &agent_registry,
                    &mut ev_create_agent,
                    &mut ev_step_agent,
                    &mut ev_create_snapshot,
                    &mut ev_inject,
                );
            }
        });
    });
}

fn execute_command(
    input: &str,
    selected: &SelectedAgent,
    agent_registry: &AgentRegistry,
    ev_create_agent: &mut EventWriter<SendCreateAgent>,
    ev_step_agent: &mut EventWriter<SendStepAgent>,
    ev_create_snapshot: &mut EventWriter<SendCreateSnapshot>,
    ev_inject: &mut EventWriter<SendInjectThought>,
) {
    let parts: Vec<&str> = input.split_whitespace().collect();

    match parts.as_slice() {
        ["create", "agent", name, ..] => {
            ev_create_agent.send(SendCreateAgent {
                name: name.to_string(),
                capabilities: vec![],
            });
        }
        ["snapshot", label, ..] => {
            if let Some(agent_id) = selected.agent_id {
                ev_create_snapshot.send(SendCreateSnapshot {
                    agent_id,
                    label: label.to_string(),
                });
            }
        }
        ["step", ..] => {
            if let Some(agent_id) = selected.agent_id {
                ev_step_agent.send(SendStepAgent { agent_id });
            }
        }
        _ => {
            // Default: inject as observation to selected agent
            if let Some(agent_id) = selected.agent_id {
                ev_inject.send(SendInjectThought {
                    agent_id,
                    content: input.to_string(),
                    thought_type: "observation".into(),
                });
            }
        }
    }
}
