//! Status Spine: Dead Space-inspired health bar behind each agent.
//!
//! 8 thin cuboid segments stacked vertically behind the agent sphere,
//! colored by cognitive load / token usage metrics.

use bevy::prelude::*;

use crate::shaders::agent_shell_material::{AgentShellMaterial, AgentShellUniforms};
use crate::state::components::*;

const SEGMENT_COUNT: usize = 8;
const SEGMENT_WIDTH: f32 = 0.08;
const SEGMENT_HEIGHT: f32 = 0.1;
const SEGMENT_DEPTH: f32 = 0.04;
const SEGMENT_GAP: f32 = 0.02;
const SPINE_X_OFFSET: f32 = -0.85;

/// Build 8 spine segments as children of an agent entity.
pub fn build_spine(
    commands: &mut Commands,
    parent: Entity,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<AgentShellMaterial>,
) {
    let segment_mesh = meshes.add(Cuboid::new(SEGMENT_WIDTH, SEGMENT_HEIGHT, SEGMENT_DEPTH));
    let total_height = SEGMENT_COUNT as f32 * (SEGMENT_HEIGHT + SEGMENT_GAP) - SEGMENT_GAP;
    let start_y = -total_height / 2.0;

    let spine_entity = commands
        .spawn((
            Transform::from_translation(Vec3::new(SPINE_X_OFFSET, 0.0, 0.0)),
            Visibility::default(),
            StatusSpine,
        ))
        .id();

    for i in 0..SEGMENT_COUNT {
        let y = start_y + i as f32 * (SEGMENT_HEIGHT + SEGMENT_GAP);
        let color = segment_color(i, SEGMENT_COUNT, 0.5);

        let mat = materials.add(AgentShellMaterial {
            uniforms: AgentShellUniforms {
                base_color: color,
                glow_intensity: 0.3,
                fresnel_power: 2.0,
                scanline_freq: 0.0,
                scanline_speed: 0.0,
                flicker_amount: 0.0,
                _padding1: 0.0,
                _padding2: 0.0,
                _padding3: 0.0,
            },
        });

        let segment = commands
            .spawn((
                Mesh3d(segment_mesh.clone()),
                MeshMaterial3d(mat),
                Transform::from_translation(Vec3::new(0.0, y, 0.0)),
                SpineSegment {
                    index: i,
                    health_value: 0.5,
                },
            ))
            .id();

        commands.entity(spine_entity).add_child(segment);
    }

    commands.entity(parent).add_child(spine_entity);
}

/// Update spine segment colors based on agent metrics.
pub fn update_spine_system(
    metrics: Res<AgentMetrics>,
    agents: Query<(&AgentNode, &Children)>,
    spines: Query<&Children, With<StatusSpine>>,
    mut segments: Query<(&SpineSegment, &MeshMaterial3d<AgentShellMaterial>)>,
    mut materials: ResMut<Assets<AgentShellMaterial>>,
) {
    for (agent, children) in agents.iter() {
        let metric_value = metrics
            .metrics
            .get(&agent.agent_id)
            .map(|m| m.cognitive_load)
            .unwrap_or(0.5);

        // Find the StatusSpine child
        for &child in children.iter() {
            if let Ok(spine_children) = spines.get(child) {
                let lit_count = (metric_value * SEGMENT_COUNT as f32).ceil() as usize;

                for &seg_entity in spine_children.iter() {
                    if let Ok((segment, mat_handle)) = segments.get_mut(seg_entity) {
                        if let Some(mat) = materials.get_mut(&mat_handle.0) {
                            let is_lit = segment.index < lit_count;
                            let color = if is_lit {
                                segment_color(segment.index, SEGMENT_COUNT, metric_value)
                            } else {
                                LinearRgba::new(0.1, 0.1, 0.12, 1.0)
                            };
                            mat.uniforms.base_color = color;
                            mat.uniforms.glow_intensity = if is_lit { 2.0 } else { 0.2 };
                        }
                    }
                }
            }
        }
    }
}

/// Automatically attach spine to agents that don't have one yet.
pub fn attach_spine_to_agents(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<AgentShellMaterial>>,
    agents_without_spine: Query<Entity, (With<AgentNode>, Without<AgentCompound>)>,
) {
    for entity in agents_without_spine.iter() {
        build_spine(&mut commands, entity, &mut meshes, &mut materials);
        commands.entity(entity).insert(AgentCompound);
    }
}

/// Color gradient: green (low segments) -> yellow (mid) -> red (high).
fn segment_color(index: usize, total: usize, _intensity: f32) -> LinearRgba {
    let t = index as f32 / (total - 1) as f32;
    if t < 0.375 {
        // Green zone (segments 0-2)
        LinearRgba::new(0.1, 0.8, 0.2, 1.0)
    } else if t < 0.75 {
        // Yellow zone (segments 3-5)
        let blend = (t - 0.375) / 0.375;
        LinearRgba::new(
            0.1 + 0.9 * blend,
            0.8 - 0.1 * blend,
            0.2 - 0.1 * blend,
            1.0,
        )
    } else {
        // Red zone (segments 6-7)
        LinearRgba::new(0.9, 0.15, 0.1, 1.0)
    }
}
