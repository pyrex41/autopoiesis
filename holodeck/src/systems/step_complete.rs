//! System: visual feedback when an agent completes a cognitive step.
//!
//! Spawns gold particle burst at agent position and pushes a toast notification.

use bevy::prelude::*;

use crate::protocol::events::StepCompleteEvent;
use crate::state::components::StepCompleteParticle;
use crate::systems::agents::AgentEntityMap;
use crate::ui::notifications::{Toast, ToastQueue};

/// On StepComplete: spawn gold particles at agent + toast.
pub fn on_step_complete(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut ev_step: EventReader<StepCompleteEvent>,
    entity_map: Res<AgentEntityMap>,
    transforms: Query<&Transform>,
    mut toast_queue: ResMut<ToastQueue>,
) {
    let particle_mesh = meshes.add(Sphere::new(0.06));
    let particle_mat = mats.add(StandardMaterial {
        base_color: Color::srgb(1.0, 0.84, 0.0),
        emissive: LinearRgba::new(8.0, 6.0, 0.0, 1.0),
        unlit: true,
        ..default()
    });

    for ev in ev_step.read() {
        // Find agent position
        let pos = entity_map.0.get(&ev.agent_id)
            .and_then(|&e| transforms.get(e).ok())
            .map(|t| t.translation)
            .unwrap_or(Vec3::ZERO);

        // Spawn 10 gold particles with upward+outward velocity
        for i in 0..10 {
            let angle = (i as f32 / 10.0) * std::f32::consts::TAU;
            let vel = Vec3::new(
                angle.cos() * 2.0,
                3.0 + (i as f32 % 3.0) * 0.5,
                angle.sin() * 2.0,
            );
            commands.spawn((
                Mesh3d(particle_mesh.clone()),
                MeshMaterial3d(particle_mat.clone()),
                Transform::from_translation(pos),
                StepCompleteParticle {
                    lifetime: Timer::from_seconds(1.0, TimerMode::Once),
                    velocity: vel,
                },
            ));
        }

        // Toast notification
        toast_queue.toasts.push(Toast::new(
            format!("Step complete: {}", ev.agent_id),
            bevy_egui::egui::Color32::from_rgb(255, 215, 0),
        ));
    }
}

/// Animate and despawn step-complete particles.
pub fn animate_step_complete_particles(
    mut commands: Commands,
    time: Res<Time>,
    mut query: Query<(Entity, &mut Transform, &mut StepCompleteParticle)>,
) {
    let dt = time.delta_secs();
    for (entity, mut transform, mut particle) in query.iter_mut() {
        particle.lifetime.tick(time.delta());
        if particle.lifetime.finished() {
            commands.entity(entity).despawn();
            continue;
        }
        // Apply velocity with gravity
        particle.velocity.y -= 5.0 * dt;
        transform.translation += particle.velocity * dt;
        // Shrink as lifetime expires
        let frac = particle.lifetime.fraction_remaining();
        transform.scale = Vec3::splat(frac);
    }
}
