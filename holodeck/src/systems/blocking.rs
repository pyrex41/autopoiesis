//! System: spawn/despawn blocking request prompts.

use bevy::prelude::*;
use crate::protocol::events::*;
use crate::state::components::BlockingPrompt;

pub fn spawn_blocking_indicators(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut ev_blocking: EventReader<BlockingRequestEvent>,
) {
    for ev in ev_blocking.read() {
        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(0.4, 0.4, 0.4))),
            MeshMaterial3d(mats.add(StandardMaterial {
                base_color: Color::srgb(1.0, 0.3, 0.1),
                emissive: LinearRgba::new(5.0, 1.5, 0.5, 1.0),
                ..default()
            })),
            Transform::from_translation(Vec3::new(0.0, 3.0, 0.0)),
            BlockingPrompt {
                request_id: ev.request.id.clone(),
                prompt_text: ev.request.prompt.clone(),
                options: ev.request.options.clone(),
            },
        ));
    }
}

pub fn despawn_blocking_indicators(
    mut commands: Commands,
    mut ev_responded: EventReader<BlockingRespondedEvent>,
    query: Query<(Entity, &BlockingPrompt)>,
) {
    for ev in ev_responded.read() {
        for (entity, prompt) in query.iter() {
            if prompt.request_id == ev.request_id {
                commands.entity(entity).despawn();
            }
        }
    }
}

pub fn animate_blocking_prompts(
    time: Res<Time>,
    mut query: Query<&mut Transform, With<BlockingPrompt>>,
) {
    let t = time.elapsed_secs();
    for mut transform in query.iter_mut() {
        let pulse = 1.0 + 0.15 * (t * 4.0).sin();
        transform.scale = Vec3::splat(pulse);
        transform.rotate_y(1.5 * time.delta_secs());
    }
}
