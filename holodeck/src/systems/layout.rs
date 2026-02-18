//! System: force-directed positioning of agent nodes.

use crate::state::components::{AgentNode, ConnectionBeam, ForceNode};
use bevy::prelude::*;

const REPULSION_K: f32 = 50.0;
const REPULSION_CAP: f32 = 10.0;
const ATTRACTION_K: f32 = 0.5;
const REST_LENGTH: f32 = 5.0;
const DAMPING: f32 = 0.92;
const FLOOR_Y: f32 = 1.5;

pub fn force_directed_layout(
    mut query: Query<(Entity, &mut Transform, &mut ForceNode, &AgentNode)>,
    connections: Query<&ConnectionBeam>,
) {
    let nodes: Vec<(Entity, Vec3, bool)> = query
        .iter()
        .map(|(e, t, f, _)| (e, t.translation, f.pinned))
        .collect();
    let n = nodes.len();
    if n < 2 {
        return;
    }

    // Build entity-to-index lookup
    let entity_to_idx: std::collections::HashMap<Entity, usize> = nodes
        .iter()
        .enumerate()
        .map(|(i, (e, _, _))| (*e, i))
        .collect();

    let mut forces: Vec<Vec3> = vec![Vec3::ZERO; n];
    for i in 0..n {
        if nodes[i].2 {
            continue;
        }
        for j in (i + 1)..n {
            let diff = nodes[i].1 - nodes[j].1;
            let dist_sq = diff.length_squared().max(0.5);
            let dist = dist_sq.sqrt();
            let dir = diff / dist;
            let repulsion = (REPULSION_K / dist_sq).min(REPULSION_CAP);
            forces[i] += dir * repulsion;
            if !nodes[j].2 {
                forces[j] -= dir * repulsion;
            }
        }
        let to_center = -nodes[i].1 * 0.02;
        forces[i] += Vec3::new(to_center.x, 0.0, to_center.z);
    }

    // Attraction: spring force between connected agents
    for beam in connections.iter() {
        let Some(&idx_a) = entity_to_idx.get(&beam.from) else {
            continue;
        };
        let Some(&idx_b) = entity_to_idx.get(&beam.to) else {
            continue;
        };
        let diff = nodes[idx_b].1 - nodes[idx_a].1;
        let dist = diff.length().max(0.01);
        let dir = diff / dist;
        let spring_force = ATTRACTION_K * (dist - REST_LENGTH);
        if !nodes[idx_a].2 {
            forces[idx_a] += dir * spring_force;
        }
        if !nodes[idx_b].2 {
            forces[idx_b] -= dir * spring_force;
        }
    }

    let mut idx = 0;
    for (_entity, mut transform, mut force_node, _agent) in query.iter_mut() {
        if force_node.pinned {
            idx += 1;
            continue;
        }
        let mass = force_node.mass;
        force_node.velocity += forces[idx] / mass;
        force_node.velocity *= DAMPING;
        let speed = force_node.velocity.length();
        if speed > 5.0 {
            force_node.velocity = force_node.velocity.normalize() * 5.0;
        }
        transform.translation += force_node.velocity * (1.0 / 60.0);
        if transform.translation.y < FLOOR_Y {
            transform.translation.y = FLOOR_Y;
            force_node.velocity.y = force_node.velocity.y.max(0.0);
        }
        idx += 1;
    }
}
