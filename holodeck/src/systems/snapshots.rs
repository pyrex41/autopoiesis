//! System: build/update snapshot tree geometry.

use crate::protocol::events::*;
use crate::rendering::materials;
use crate::state::components::{ConnectionBeam, SnapshotNode};
use crate::state::resources::SnapshotTree;
use bevy::prelude::*;
use std::collections::HashMap;

#[derive(Resource, Default, Debug)]
pub struct SnapshotEntityMap(pub HashMap<String, Entity>);

const TREE_OFFSET: Vec3 = Vec3::new(25.0, 0.0, 0.0);
const LAYER_HEIGHT: f32 = 2.0;
const SIBLING_SPACING: f32 = 2.5;
const BEAM_THICKNESS: f32 = 0.03;
const BEAM_COLOR: Color = Color::srgb(0.0, 0.6, 1.0);

pub fn build_snapshot_tree(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut mats: ResMut<Assets<StandardMaterial>>,
    mut ev_list: EventReader<SnapshotListReceived>,
    mut ev_created: EventReader<SnapshotCreatedEvent>,
    snapshot_tree: Res<SnapshotTree>,
    mut entity_map: ResMut<SnapshotEntityMap>,
) {
    let mut needs_rebuild = false;
    for _ev in ev_list.read() {
        needs_rebuild = true;
    }
    for ev in ev_created.read() {
        if !entity_map.0.contains_key(&ev.snapshot.id) {
            needs_rebuild = true;
        }
    }
    if !needs_rebuild {
        return;
    }

    let mut depth_map: HashMap<String, usize> = HashMap::new();
    let mut children_map: HashMap<Option<String>, Vec<String>> = HashMap::new();
    for (id, snap) in &snapshot_tree.snapshots {
        children_map
            .entry(snap.parent.clone())
            .or_default()
            .push(id.clone());
    }

    let mut queue: Vec<(Option<String>, usize)> = vec![(None, 0)];
    while let Some((parent, depth)) = queue.pop() {
        if let Some(kids) = children_map.get(&parent) {
            for kid in kids {
                depth_map.insert(kid.clone(), depth);
                queue.push((Some(kid.clone()), depth + 1));
            }
        }
    }

    let mut depth_counts: HashMap<usize, usize> = HashMap::new();
    let mut depth_indices: HashMap<String, usize> = HashMap::new();
    for (id, d) in &depth_map {
        let idx = depth_counts.entry(*d).or_default();
        depth_indices.insert(id.clone(), *idx);
        *depth_counts.entry(*d).or_default() += 1;
    }

    // Track positions for edge spawning
    let mut positions: HashMap<String, Vec3> = HashMap::new();

    let node_mesh = meshes.add(Sphere::new(0.3));
    for (id, snap) in &snapshot_tree.snapshots {
        let depth = depth_map.get(id).copied().unwrap_or(0);
        let index = depth_indices.get(id).copied().unwrap_or(0);
        let count_at_depth = depth_counts.get(&depth).copied().unwrap_or(1);
        let x = (index as f32 - (count_at_depth as f32 - 1.0) / 2.0) * SIBLING_SPACING;
        let y = 1.0 + depth as f32 * LAYER_HEIGHT;
        let pos = TREE_OFFSET + Vec3::new(x, y, 0.0);
        positions.insert(id.clone(), pos);

        if entity_map.0.contains_key(id) {
            continue;
        }

        // Stub 6 fix: highlight current branch
        let is_current = snapshot_tree.current_branch.as_deref() == Some(id.as_str());
        let material = mats.add(materials::snapshot_node_material(is_current));

        let entity = commands
            .spawn((
                Mesh3d(node_mesh.clone()),
                MeshMaterial3d(material),
                Transform::from_translation(pos),
                SnapshotNode {
                    snapshot_id: id.clone(),
                    parent: snap.parent.clone(),
                    hash: snap.hash.clone(),
                    metadata: snap.metadata.clone(),
                    timestamp: snap.timestamp,
                },
            ))
            .id();
        entity_map.0.insert(id.clone(), entity);
    }

    // Stub 7 fix: spawn tree edges between parent-child pairs
    let beam_mat = mats.add(materials::beam_material(BEAM_COLOR));
    for (id, snap) in &snapshot_tree.snapshots {
        let parent_id = match &snap.parent {
            Some(p) => p,
            None => continue,
        };
        let child_pos = match positions.get(id) {
            Some(&p) => p,
            None => continue,
        };
        let parent_pos = match positions.get(parent_id) {
            Some(&p) => p,
            None => continue,
        };
        let child_entity = match entity_map.0.get(id) {
            Some(&e) => e,
            None => continue,
        };
        let parent_entity = match entity_map.0.get(parent_id) {
            Some(&e) => e,
            None => continue,
        };

        let midpoint = (parent_pos + child_pos) / 2.0;
        let diff = child_pos - parent_pos;
        let length = diff.length();
        if length < f32::EPSILON {
            continue;
        }

        let direction = diff.normalize();
        let rotation = Quat::from_rotation_arc(Vec3::Y, direction);

        commands.spawn((
            Mesh3d(meshes.add(Cuboid::new(BEAM_THICKNESS, length, BEAM_THICKNESS))),
            MeshMaterial3d(beam_mat.clone()),
            Transform::from_translation(midpoint).with_rotation(rotation),
            ConnectionBeam {
                from: parent_entity,
                to: child_entity,
                color: BEAM_COLOR,
            },
        ));
    }
}
