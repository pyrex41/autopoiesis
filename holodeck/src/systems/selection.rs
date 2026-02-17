//! System: handle pick events, update selection state.
//! Uses Bevy 0.15 built-in picking.

use bevy::prelude::*;
use crate::protocol::types::ClientMessage;
use crate::state::components::*;
use crate::state::events::{SendGetThoughts, DeselectEvent};
use crate::state::resources::*;
use crate::systems::agents::AgentEntityMap;

pub fn handle_agent_click(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut click_events: EventReader<Pointer<Click>>,
    agents: Query<&AgentNode, With<Selectable>>,
    mut selected_agent: ResMut<SelectedAgent>,
    old_rings: Query<Entity, With<SelectionRing>>,
    mut ev_get_thoughts: EventWriter<SendGetThoughts>,
    ws_outbound: Res<WsOutbound>,
) {
    for event in click_events.read() {
        let clicked_entity = event.target;
        if let Ok(agent_node) = agents.get(clicked_entity) {
            for ring_entity in old_rings.iter() { commands.entity(ring_entity).despawn(); }
            if let Some(old_entity) = selected_agent.entity {
                commands.entity(old_entity).remove::<Selected>();
            }
            commands.entity(clicked_entity).insert(Selected);
            let ring_mesh = meshes.add(Torus::new(0.9, 1.1));
            let ring_material = mats.add(crate::rendering::materials::selection_ring_material());
            commands.entity(clicked_entity).with_children(|parent| {
                parent.spawn((
                    Mesh3d(ring_mesh),
                    MeshMaterial3d(ring_material),
                    Transform::from_rotation(Quat::from_rotation_x(std::f32::consts::FRAC_PI_2)),
                    SelectionRing,
                ));
            });
            selected_agent.agent_id = Some(agent_node.agent_id);
            selected_agent.entity = Some(clicked_entity);
            ev_get_thoughts.send(SendGetThoughts { agent_id: agent_node.agent_id, limit: 50 });
            let _ = ws_outbound.0.send(ClientMessage::Subscribe {
                channel: format!("thoughts:{}", agent_node.agent_id),
            });
        }
    }
}

pub fn handle_deselect(
    mut commands: Commands,
    mut ev_deselect: EventReader<DeselectEvent>,
    mut selected_agent: ResMut<SelectedAgent>,
    rings: Query<Entity, With<SelectionRing>>,
) {
    for _ev in ev_deselect.read() {
        for ring_entity in rings.iter() { commands.entity(ring_entity).despawn(); }
        if let Some(old_entity) = selected_agent.entity {
            commands.entity(old_entity).remove::<Selected>();
        }
        selected_agent.agent_id = None;
        selected_agent.entity = None;
    }
}

pub fn deselect_on_escape(
    mut commands: Commands,
    keyboard: Res<ButtonInput<KeyCode>>,
    mut selected_agent: ResMut<SelectedAgent>,
    rings: Query<Entity, With<SelectionRing>>,
) {
    if keyboard.just_pressed(KeyCode::Escape) && selected_agent.agent_id.is_some() {
        for ring_entity in rings.iter() {
            commands.entity(ring_entity).despawn();
        }
        if let Some(old_entity) = selected_agent.entity {
            commands.entity(old_entity).remove::<Selected>();
        }
        selected_agent.agent_id = None;
        selected_agent.entity = None;
    }
}
