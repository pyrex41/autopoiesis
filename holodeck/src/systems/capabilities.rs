//! System: orbiting capability module shapes around agent spheres.
//!
//! Each agent capability (observe, decide, act, reflect, learn) gets a small
//! icosphere child entity that orbits the agent. When a thought arrives whose
//! type matches a capability, that module briefly flares.

use bevy::prelude::*;

use crate::protocol::events::{AgentListReceived, AgentCreatedEvent, ThoughtReceivedEvent};
use crate::protocol::types::ThoughtType;
use crate::rendering::materials;
use crate::shaders::agent_shell_material::AgentShellMaterial;
use crate::state::components::*;
use crate::systems::agents::AgentEntityMap;

/// Color mapping for known capability names.
fn capability_color(name: &str) -> Color {
    match name.to_lowercase().as_str() {
        "observe" => Color::srgb(0.0, 0.533, 1.0),   // blue
        "decide" => Color::srgb(1.0, 0.843, 0.0),     // gold
        "act" => Color::srgb(0.0, 1.0, 0.533),         // green
        "reflect" => Color::srgb(0.6, 0.2, 1.0),       // purple
        "learn" => Color::srgb(0.0, 0.9, 0.9),         // cyan
        _ => Color::srgb(0.8, 0.8, 0.8),               // white-ish
    }
}

/// Spawn capability module child entities for agents from the agent list.
pub fn spawn_capability_modules_from_list(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<AgentShellMaterial>>,
    mut ev_list: EventReader<AgentListReceived>,
    entity_map: Res<AgentEntityMap>,
    existing_modules: Query<&CapabilityModule>,
    children_query: Query<&Children>,
) {
    for ev in ev_list.read() {
        for agent_data in &ev.agents {
            let Some(&agent_entity) = entity_map.0.get(&agent_data.id) else {
                continue;
            };

            // Skip if this agent already has capability modules
            if let Ok(children) = children_query.get(agent_entity) {
                if children.iter().any(|c| existing_modules.get(*c).is_ok()) {
                    continue;
                }
            }

            spawn_modules(
                &mut commands,
                &mut meshes,
                &mut mats,
                agent_entity,
                &agent_data.capabilities,
            );
        }
    }
}

/// Spawn capability module child entities for newly created agents.
pub fn spawn_capability_modules_on_created(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<AgentShellMaterial>>,
    mut ev_created: EventReader<AgentCreatedEvent>,
    entity_map: Res<AgentEntityMap>,
) {
    for ev in ev_created.read() {
        let Some(&agent_entity) = entity_map.0.get(&ev.agent.id) else {
            continue;
        };

        spawn_modules(
            &mut commands,
            &mut meshes,
            &mut mats,
            agent_entity,
            &ev.agent.capabilities,
        );
    }
}

/// Helper: spawn small orbiting icospheres for each capability.
fn spawn_modules(
    commands: &mut Commands,
    meshes: &mut ResMut<Assets<Mesh>>,
    mats: &mut ResMut<Assets<AgentShellMaterial>>,
    agent_entity: Entity,
    capabilities: &[String],
) {
    let mesh = meshes.add(Sphere::new(0.15).mesh().ico(1).unwrap());

    for (i, cap_name) in capabilities.iter().enumerate() {
        let color = capability_color(cap_name);
        let orbit_radius = 1.5 + 0.3 * i as f32;
        let orbit_phase = i as f32 * std::f32::consts::TAU / capabilities.len().max(1) as f32;
        let orbit_speed = 1.2 + 0.1 * i as f32;

        let mut mat = materials::agent_shell_material(color);
        mat.uniforms.glow_intensity = 1.0;
        mat.uniforms.fresnel_power = 2.0;
        mat.uniforms.scanline_freq = 50.0;

        commands.entity(agent_entity).with_children(|parent| {
            parent.spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(mats.add(mat)),
                Transform::from_translation(Vec3::new(orbit_radius, 0.0, 0.0)),
                CapabilityModule {
                    capability_name: cap_name.clone(),
                    orbit_radius,
                    orbit_phase,
                    orbit_speed,
                    is_active: false,
                },
            ));
        });
    }
}

/// Animate capability modules in circular orbits around their parent agent.
pub fn orbit_capabilities(
    time: Res<Time>,
    mut query: Query<(&CapabilityModule, &mut Transform)>,
) {
    let t = time.elapsed_secs();

    for (module, mut transform) in query.iter_mut() {
        let angle = t * module.orbit_speed + module.orbit_phase;
        let r = module.orbit_radius;
        transform.translation.x = r * angle.cos();
        transform.translation.z = r * angle.sin();
        // Slight vertical bobbing
        transform.translation.y = 0.1 * (t * 1.5 + module.orbit_phase).sin();
    }
}

/// On ThoughtReceivedEvent, flare the matching capability module.
///
/// Maps thought types to capability names:
/// Observation -> "observe", Decision -> "decide", Action -> "act", Reflection -> "reflect"
pub fn highlight_active_capability(
    mut ev_thought: EventReader<ThoughtReceivedEvent>,
    entity_map: Res<AgentEntityMap>,
    children_query: Query<&Children>,
    mut modules: Query<(&mut CapabilityModule, &MeshMaterial3d<AgentShellMaterial>)>,
    mut materials: ResMut<Assets<AgentShellMaterial>>,
) {
    for ev in ev_thought.read() {
        let Some(&agent_entity) = entity_map.0.get(&ev.agent_id) else {
            continue;
        };

        let target_cap = match ev.thought.thought_type {
            ThoughtType::Observation => "observe",
            ThoughtType::Decision => "decide",
            ThoughtType::Action => "act",
            ThoughtType::Reflection => "reflect",
        };

        let Ok(children) = children_query.get(agent_entity) else {
            continue;
        };

        for &child in children.iter() {
            if let Ok((mut module, mat_handle)) = modules.get_mut(child) {
                if module.capability_name.to_lowercase() == target_cap {
                    module.is_active = true;
                    if let Some(mat) = materials.get_mut(&mat_handle.0) {
                        mat.uniforms.glow_intensity = 3.0;
                    }
                }
            }
        }
    }
}

/// Decay active capability module glow back to baseline.
pub fn decay_capability_glow(
    time: Res<Time>,
    mut query: Query<(&mut CapabilityModule, &MeshMaterial3d<AgentShellMaterial>)>,
    mut materials: ResMut<Assets<AgentShellMaterial>>,
) {
    let dt = time.delta_secs();
    let decay_rate = 4.0;

    for (mut module, mat_handle) in query.iter_mut() {
        if module.is_active {
            if let Some(mat) = materials.get_mut(&mat_handle.0) {
                mat.uniforms.glow_intensity -= decay_rate * dt;
                if mat.uniforms.glow_intensity <= 1.0 {
                    mat.uniforms.glow_intensity = 1.0;
                    module.is_active = false;
                }
            }
        }
    }
}
