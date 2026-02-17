//! System: spawn thought particles, animate streams.
//!
//! When a thought arrives for an agent, we burst-emit short-lived particle
//! entities near that agent's position. Color and motion depend on thought type.

use bevy::prelude::*;
use uuid::Uuid;

use crate::protocol::events::ThoughtReceivedEvent;
use crate::protocol::types::ThoughtType;
use crate::state::components::*;
use crate::systems::agents::AgentEntityMap;

/// Number of particles to spawn per thought.
const PARTICLES_PER_THOUGHT: usize = 6;
/// Lifetime of each particle in seconds.
const PARTICLE_LIFETIME: f32 = 2.5;

/// Spawn particles when a thought is received.
pub fn spawn_thought_particles(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut ev_thought: EventReader<ThoughtReceivedEvent>,
    entity_map: Res<AgentEntityMap>,
    transforms: Query<&Transform>,
) {
    for ev in ev_thought.read() {
        // Find the agent's position
        let agent_pos = entity_map
            .0
            .get(&ev.agent_id)
            .and_then(|&e| transforms.get(e).ok())
            .map(|t| t.translation)
            .unwrap_or(Vec3::ZERO);

        let (color, velocity_fn): (Color, fn(usize) -> Vec3) = match ev.thought.thought_type {
            ThoughtType::Observation => (
                Color::srgb(0.2, 0.5, 1.0), // Blue
                |i| {
                    let angle = i as f32 * std::f32::consts::TAU / PARTICLES_PER_THOUGHT as f32;
                    Vec3::new(angle.cos() * 0.5, 1.5, angle.sin() * 0.5)
                },
            ),
            ThoughtType::Decision => (
                Color::srgb(1.0, 0.843, 0.0), // Gold
                |i| {
                    let angle = i as f32 * std::f32::consts::TAU / PARTICLES_PER_THOUGHT as f32;
                    Vec3::new(angle.cos() * 2.0, 0.5, angle.sin() * 2.0)
                },
            ),
            ThoughtType::Action => (
                Color::srgb(0.0, 1.0, 0.533), // Green
                |i| {
                    let spread = (i as f32 - PARTICLES_PER_THOUGHT as f32 / 2.0) * 0.3;
                    Vec3::new(spread, 0.3, 2.0)
                },
            ),
            ThoughtType::Reflection => (
                Color::srgb(0.6, 0.2, 1.0), // Purple
                |i| {
                    let angle = i as f32 * std::f32::consts::TAU / PARTICLES_PER_THOUGHT as f32;
                    Vec3::new(angle.cos() * 1.0, 0.2, angle.sin() * 1.0)
                },
            ),
        };

        let linear = color.to_linear();
        let mesh = meshes.add(Sphere::new(0.08));
        let material = mats.add(StandardMaterial {
            base_color: color,
            emissive: LinearRgba::new(
                linear.red * 6.0,
                linear.green * 6.0,
                linear.blue * 6.0,
                1.0,
            ),
            alpha_mode: AlphaMode::Add,
            ..default()
        });

        for i in 0..PARTICLES_PER_THOUGHT {
            let vel = velocity_fn(i);
            commands.spawn((
                Mesh3d(mesh.clone()),
                MeshMaterial3d(material.clone()),
                Transform::from_translation(agent_pos + Vec3::new(0.0, 1.0, 0.0))
                    .with_scale(Vec3::splat(1.0)),
                ThoughtParticle {
                    thought_id: ev.thought.id,
                    agent_id: ev.agent_id,
                    thought_type: ev.thought.thought_type.clone(),
                    lifetime: Timer::from_seconds(PARTICLE_LIFETIME, TimerMode::Once),
                    velocity: vel,
                },
            ));
        }
    }
}

/// Animate and despawn thought particles.
pub fn animate_thought_particles(
    mut commands: Commands,
    time: Res<Time>,
    mut query: Query<(Entity, &mut ThoughtParticle, &mut Transform)>,
) {
    for (entity, mut particle, mut transform) in query.iter_mut() {
        particle.lifetime.tick(time.delta());

        // Move particle
        let dt = time.delta_secs();
        transform.translation += particle.velocity * dt;

        // Dampen velocity
        particle.velocity *= 0.97;

        // Fade by shrinking
        let remaining = particle.lifetime.fraction_remaining();
        transform.scale = Vec3::splat(remaining.max(0.01));

        // Despawn when timer finishes
        if particle.lifetime.finished() {
            commands.entity(entity).despawn();
        }
    }
}
