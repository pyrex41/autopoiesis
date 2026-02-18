//! System: spawn/despawn/update agent entities from backend state.
//!
//! When the backend reports agents, we create 3D entities (glowing icospheres)
//! to represent them in the scene. State changes update colors with smooth lerps.

use std::collections::HashMap;
use std::time::Duration;

use bevy::prelude::*;
use bevy_tweening::*;
use uuid::Uuid;

use crate::protocol::events::*;
use crate::rendering::materials;
use crate::shaders::agent_shell_material::AgentShellMaterial;
use crate::state::components::*;
use crate::state::resources::AgentRegistry;
use crate::systems::tweens::AgentColorLens;

/// Lookup table: agent UUID → Entity for quick mapping.
#[derive(Resource, Default, Debug)]
pub struct AgentEntityMap(pub HashMap<Uuid, Entity>);

/// Spawn agent entities when we receive the agent list from the backend.
pub fn spawn_agents_from_list(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<AgentShellMaterial>>,
    mut ev_list: EventReader<AgentListReceived>,
    mut entity_map: ResMut<AgentEntityMap>,
    existing: Query<&AgentNode>,
) {
    for ev in ev_list.read() {
        for agent_data in &ev.agents {
            // Skip if entity already exists
            if entity_map.0.contains_key(&agent_data.id) {
                // Update existing node data if needed
                continue;
            }

            let color = AgentVisual::color_for_state(&agent_data.state);
            let phase = rand_phase(&agent_data.id);

            // Position new agents in a ring around the origin
            let count = entity_map.0.len() as f32;
            let angle = count * std::f32::consts::TAU / 8.0;
            let radius = 8.0;
            let pos = Vec3::new(angle.cos() * radius, 2.0, angle.sin() * radius);

            let entity = commands
                .spawn((
                    // Mesh: icosphere
                    Mesh3d(meshes.add(Sphere::new(0.8).mesh().ico(3).unwrap())),
                    MeshMaterial3d(mats.add(materials::agent_shell_material(color))),
                    Transform::from_translation(pos),
                    // Agent data
                    AgentNode {
                        agent_id: agent_data.id,
                        name: agent_data.name.clone(),
                        state: agent_data.state.clone(),
                        capabilities: agent_data.capabilities.clone(),
                        thought_count: agent_data.thought_count,
                    },
                    AgentVisual {
                        base_color: color,
                        pulse_phase: phase,
                        glow_intensity: 1.0,
                    },
                    Selectable,
                    ForceNode::default(),
                ))
                .id();

            // Spawn point light and name label as children
            commands.entity(entity).with_children(|parent| {
                parent.spawn((
                    PointLight {
                        color,
                        intensity: 5000.0,
                        range: 15.0,
                        ..default()
                    },
                    Transform::from_translation(Vec3::new(0.0, 1.5, 0.0)),
                ));
                parent.spawn((
                    Text2d::new(&agent_data.name),
                    TextFont {
                        font_size: 14.0,
                        ..default()
                    },
                    TextColor(Color::srgba(0.0, 0.8, 1.0, 0.9)),
                    Transform::from_translation(Vec3::new(0.0, 2.5, 0.0)),
                    AgentLabel,
                ));
            });

            entity_map.0.insert(agent_data.id, entity);
        }
    }
}

/// Spawn agent entity for a newly created agent.
pub fn spawn_agent_on_created(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<AgentShellMaterial>>,
    mut ev_created: EventReader<AgentCreatedEvent>,
    mut entity_map: ResMut<AgentEntityMap>,
) {
    for ev in ev_created.read() {
        if entity_map.0.contains_key(&ev.agent.id) {
            continue;
        }

        let color = AgentVisual::color_for_state(&ev.agent.state);
        let phase = rand_phase(&ev.agent.id);

        let count = entity_map.0.len() as f32;
        let angle = count * std::f32::consts::TAU / 8.0;
        let radius = 8.0;
        let pos = Vec3::new(angle.cos() * radius, 2.0, angle.sin() * radius);

        let entity = commands
            .spawn((
                Mesh3d(meshes.add(Sphere::new(0.8).mesh().ico(3).unwrap())),
                MeshMaterial3d(mats.add(materials::agent_shell_material(color))),
                Transform::from_translation(pos),
                AgentNode {
                    agent_id: ev.agent.id,
                    name: ev.agent.name.clone(),
                    state: ev.agent.state.clone(),
                    capabilities: ev.agent.capabilities.clone(),
                    thought_count: ev.agent.thought_count,
                },
                AgentVisual {
                    base_color: color,
                    pulse_phase: phase,
                    glow_intensity: 1.0,
                },
                Selectable,
                ForceNode::default(),
            ))
            .id();

        commands.entity(entity).with_children(|parent| {
            parent.spawn((
                PointLight {
                    color,
                    intensity: 5000.0,
                    range: 15.0,
                    ..default()
                },
                Transform::from_translation(Vec3::new(0.0, 1.5, 0.0)),
            ));
            parent.spawn((
                Text2d::new(&ev.agent.name),
                TextFont {
                    font_size: 14.0,
                    ..default()
                },
                TextColor(Color::srgba(0.0, 0.8, 1.0, 0.9)),
                Transform::from_translation(Vec3::new(0.0, 2.5, 0.0)),
                AgentLabel,
            ));
        });

        entity_map.0.insert(ev.agent.id, entity);
    }
}

/// Update agent visuals when state changes.
///
/// Instead of instantly setting the new color, inserts an `AssetAnimator`
/// that smoothly tweens the shader's `base_color` over 300ms.
pub fn update_agent_state(
    mut commands: Commands,
    mut ev_state: EventReader<AgentStateChangedEvent>,
    entity_map: Res<AgentEntityMap>,
    mut query: Query<(&mut AgentNode, &mut AgentVisual)>,
    mats: Res<Assets<AgentShellMaterial>>,
    mat_handles: Query<&MeshMaterial3d<AgentShellMaterial>>,
) {
    for ev in ev_state.read() {
        if let Some(&entity) = entity_map.0.get(&ev.agent_id) {
            if let Ok((mut node, mut visual)) = query.get_mut(entity) {
                node.state = ev.state.clone();
                let new_color = AgentVisual::color_for_state(&ev.state);
                visual.base_color = new_color;

                // Read current color from the material to use as tween start
                let start_color = mat_handles
                    .get(entity)
                    .ok()
                    .and_then(|h| mats.get(&h.0))
                    .map(|mat| mat.uniforms.base_color)
                    .unwrap_or(new_color.to_linear());

                let tween = Tween::new(
                    EaseFunction::CubicInOut,
                    Duration::from_millis(300),
                    AgentColorLens {
                        start: start_color,
                        end: new_color.to_linear(),
                    },
                );

                // Insert (or replace) the asset animator on this entity
                commands.entity(entity).insert(AssetAnimator::new(tween));
            }
        }
    }
}

/// Deterministic but varied phase offset from UUID.
fn rand_phase(id: &Uuid) -> f32 {
    let bytes = id.as_bytes();
    let hash = bytes
        .iter()
        .fold(0u32, |acc, &b| acc.wrapping_add(b as u32));
    (hash as f32 / 255.0) * std::f32::consts::TAU
}
