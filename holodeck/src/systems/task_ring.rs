//! System: task progress ring around agents.
//!
//! Displays a torus ring below each agent, filled proportionally to task
//! completion. On reaching 1.0, triggers a scale animation + gold flash.

use std::time::Duration;

use bevy::prelude::*;
use bevy_tweening::lens::*;
use bevy_tweening::*;

use crate::state::components::{AgentCompound, AgentMetrics, TaskRing};
use crate::systems::agents::AgentEntityMap;

// --- Ring geometry constants ---
const RING_MINOR_RADIUS: f32 = 0.07;
const RING_MAJOR_RADIUS: f32 = 1.07;
const RING_Y_OFFSET: f32 = -0.3;

/// Amber color for the progress ring (#FFD166).
const RING_COLOR: Color = Color::srgb(1.0, 0.82, 0.4);

/// Pre-built torus mesh handle for task rings.
#[derive(Resource)]
pub struct TaskRingMeshes {
    pub torus: Handle<Mesh>,
}

/// Startup system: generate the torus mesh.
pub fn init_task_ring_meshes(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
) {
    let torus = meshes.add(
        Torus::new(RING_MINOR_RADIUS, RING_MAJOR_RADIUS)
    );
    commands.insert_resource(TaskRingMeshes { torus });
}

/// Spawn a task ring as a child of a given agent entity.
pub fn spawn_task_ring(
    commands: &mut Commands,
    parent_entity: Entity,
    ring_meshes: &TaskRingMeshes,
    materials: &mut Assets<StandardMaterial>,
) {
    let mat = materials.add(ring_material(0.0));
    commands.entity(parent_entity).with_children(|parent| {
        parent.spawn((
            Mesh3d(ring_meshes.torus.clone()),
            MeshMaterial3d(mat),
            Transform::from_translation(Vec3::new(0.0, RING_Y_OFFSET, 0.0)),
            TaskRing {
                progress: 0.0,
                task_name: String::new(),
            },
        ));
    });
}

/// Create a ring material with alpha/emissive modulated by progress.
fn ring_material(progress: f32) -> StandardMaterial {
    let linear = RING_COLOR.to_linear();
    let alpha = if progress < 0.01 { 0.0 } else { 0.4 + progress * 0.6 };
    let emissive_mult = 1.0 + progress * 3.0;
    StandardMaterial {
        base_color: RING_COLOR.with_alpha(alpha),
        emissive: LinearRgba::new(
            linear.red * emissive_mult,
            linear.green * emissive_mult,
            linear.blue * emissive_mult,
            1.0,
        ),
        perceptual_roughness: 0.3,
        metallic: 0.8,
        alpha_mode: AlphaMode::Blend,
        ..default()
    }
}

/// Automatically attach task ring to agents that don't have one yet.
pub fn attach_task_ring_to_agents(
    mut commands: Commands,
    ring_meshes: Option<Res<TaskRingMeshes>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    agents_without_ring: Query<Entity, (With<AgentCompound>, Without<Children>)>,
    agents_with_children: Query<(Entity, &Children), With<AgentCompound>>,
    ring_check: Query<&TaskRing>,
) {
    let Some(ring_meshes) = ring_meshes else { return };

    // Check agents that have children but no task ring
    for (entity, children) in agents_with_children.iter() {
        let has_ring = children.iter().any(|c: &Entity| ring_check.get(*c).is_ok());
        if !has_ring {
            spawn_task_ring(&mut commands, entity, &ring_meshes, &mut materials);
        }
    }

    // Agents without any children yet
    for entity in agents_without_ring.iter() {
        spawn_task_ring(&mut commands, entity, &ring_meshes, &mut materials);
    }
}

/// Update task ring visuals based on AgentMetrics.
pub fn update_task_ring(
    metrics: Res<AgentMetrics>,
    entity_map: Res<AgentEntityMap>,
    children_query: Query<&Children>,
    mut ring_query: Query<(&mut TaskRing, &MeshMaterial3d<StandardMaterial>)>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    for (&agent_id, &entity) in entity_map.0.iter() {
        let progress = metrics
            .metrics
            .get(&agent_id)
            .map(|m| m.task_progress)
            .unwrap_or(0.0);

        // Find the TaskRing child
        let Ok(children) = children_query.get(entity) else { continue };
        for &child in children.iter() {
            let Ok((mut ring, mat_handle)) = ring_query.get_mut(child) else { continue };
            if (ring.progress - progress).abs() > 0.001 {
                ring.progress = progress;
                if let Some(mat) = materials.get_mut(&mat_handle.0) {
                    *mat = ring_material(progress);
                }
            }
        }
    }
}

/// On task completion (progress reaches 1.0), trigger a scale pop animation.
pub fn task_completion_burst(
    mut commands: Commands,
    ring_query: Query<(Entity, &TaskRing), Changed<TaskRing>>,
) {
    for (entity, ring) in ring_query.iter() {
        if ring.progress >= 1.0 {
            // Scale animation: 1.0 -> 1.3 -> 1.0 over 400ms
            let tween = Tween::new(
                EaseFunction::CubicInOut,
                Duration::from_millis(200),
                TransformScaleLens {
                    start: Vec3::splat(1.0),
                    end: Vec3::splat(1.3),
                },
            )
            .then(Tween::new(
                EaseFunction::CubicInOut,
                Duration::from_millis(200),
                TransformScaleLens {
                    start: Vec3::splat(1.3),
                    end: Vec3::splat(1.0),
                },
            ));

            commands.entity(entity).insert(Animator::new(tween));
        }
    }
}
