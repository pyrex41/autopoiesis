//! System: spawn/despawn blocking request prompts with clickable response buttons.

use bevy::prelude::*;
use crate::protocol::events::*;
use crate::state::components::{BlockingOptionButton, BlockingPrompt};
use crate::state::events::SendRespondBlocking;

pub fn spawn_blocking_indicators(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut ev_blocking: EventReader<BlockingRequestEvent>,
    existing: Query<&BlockingPrompt>,
) {
    for ev in ev_blocking.read() {
        let index = existing.iter().count() as f32;
        let prompt_y = 3.0 + index * 2.0;
        let prompt_entity = commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(0.4, 0.4, 0.4))),
            MeshMaterial3d(mats.add(StandardMaterial {
                base_color: Color::srgb(1.0, 0.3, 0.1),
                emissive: LinearRgba::new(5.0, 1.5, 0.5, 1.0),
                ..default()
            })),
            Transform::from_translation(Vec3::new(0.0, prompt_y, 0.0)),
            BlockingPrompt {
                request_id: ev.request.id.clone(),
                prompt_text: ev.request.prompt.clone(),
                options: ev.request.options.clone(),
            },
        )).id();

        // Spawn clickable option buttons spread out around the prompt
        let option_mesh = meshes.add(Cuboid::new(0.3, 0.15, 0.3));
        for (i, option) in ev.request.options.iter().enumerate() {
            let offset_x = (i as f32 - (ev.request.options.len() as f32 - 1.0) / 2.0) * 0.8;
            commands.entity(prompt_entity).with_children(|parent| {
                parent.spawn((
                    Mesh3d(option_mesh.clone()),
                    MeshMaterial3d(mats.add(StandardMaterial {
                        base_color: Color::srgb(0.1, 0.6, 1.0),
                        emissive: LinearRgba::new(0.5, 2.0, 4.0, 1.0),
                        ..default()
                    })),
                    Transform::from_translation(Vec3::new(offset_x, -0.6, 0.0)),
                    BlockingOptionButton {
                        request_id: ev.request.id.clone(),
                        option_text: option.clone(),
                    },
                ));
            });
        }
    }
}

pub fn handle_blocking_option_click(
    mut click_events: EventReader<Pointer<Click>>,
    buttons: Query<&BlockingOptionButton>,
    mut ev_respond: EventWriter<SendRespondBlocking>,
) {
    for event in click_events.read() {
        if let Ok(button) = buttons.get(event.target) {
            ev_respond.send(SendRespondBlocking {
                request_id: button.request_id.clone(),
                response: button.option_text.clone(),
            });
        }
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
                commands.entity(entity).despawn_recursive();
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
