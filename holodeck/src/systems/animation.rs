//! System: pulse, glow, orbit animations.
//!
//! - Breathing pulse: sinusoidal scale oscillation on all `AgentVisual` entities.
//! - Thought spike: temporary glow boost that decays.
//! - Gentle rotation: agent spheres slowly rotate on Y axis.

use bevy::prelude::*;

use crate::protocol::events::ThoughtReceivedEvent;
use crate::state::components::*;
use crate::systems::agents::AgentEntityMap;

/// Breathing pulse and gentle rotation for all agent spheres.
pub fn animate_agents(
    time: Res<Time>,
    mut query: Query<(&AgentVisual, &mut Transform)>,
) {
    let t = time.elapsed_secs();

    for (visual, mut transform) in query.iter_mut() {
        // Breathing pulse: sinusoidal scale oscillation
        let pulse = 1.0 + 0.05 * (t * 2.0 + visual.pulse_phase).sin();
        transform.scale = Vec3::splat(pulse);

        // Gentle Y-axis rotation
        let rotation_speed = 0.15; // radians per second
        transform.rotate_y(rotation_speed * time.delta_secs());
    }
}

/// Boost glow intensity when a thought arrives for an agent.
pub fn thought_glow_spike(
    mut ev_thought: EventReader<ThoughtReceivedEvent>,
    entity_map: Res<AgentEntityMap>,
    mut query: Query<&mut AgentVisual>,
) {
    for ev in ev_thought.read() {
        if let Some(&entity) = entity_map.0.get(&ev.agent_id) {
            if let Ok(mut visual) = query.get_mut(entity) {
                visual.glow_intensity = 3.0; // Spike
            }
        }
    }
}

/// Decay glow intensity back to baseline over time.
pub fn decay_glow(
    time: Res<Time>,
    mut query: Query<&mut AgentVisual>,
) {
    let dt = time.delta_secs();
    let decay_rate = 4.0; // Per second — decays from 3.0 to ~1.0 in ~0.5s

    for mut visual in query.iter_mut() {
        if visual.glow_intensity > 1.0 {
            visual.glow_intensity -= decay_rate * dt;
            if visual.glow_intensity < 1.0 {
                visual.glow_intensity = 1.0;
            }
        }
    }
}

/// Animate the selection ring: slow rotation.
pub fn animate_selection_ring(
    time: Res<Time>,
    mut query: Query<&mut Transform, With<SelectionRing>>,
) {
    for mut transform in query.iter_mut() {
        transform.rotate_z(0.8 * time.delta_secs());
    }
}
