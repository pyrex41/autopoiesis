//! System: build/update snapshot tree geometry.

use std::collections::HashMap;
use bevy::prelude::*;
use crate::protocol::events::*;
use crate::rendering::materials;
use crate::state::components::SnapshotNode;
use crate::state::resources::SnapshotTree;

#[derive(Resource, Default, Debug)]
pub struct SnapshotEntityMap(pub HashMap<String, Entity>);

const TREE_OFFSET: Vec3 = Vec3::new(25.0, 0.0, 0.0);
const LAYER_HEIGHT: f32 = 2.0;
const SIBLING_SPACING: f32 = 2.5;

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
    for _ev in ev_list.read() { needs_rebuild = true; }
    for ev in ev_created.read() {
        if !entity_map.0.contains_key(&ev.snapshot.id) { needs_rebuild = true; }
    }
    if !needs_rebuild { return; }

    let mut depth_map: HashMap<String, usize> = HashMap::new();
    let mut children_map: HashMap<Option<String>, Vec<String>> = HashMap::new();
    for (id, snap) in &snapshot_tree.snapshots {
        children_map.entry(snap.parent.clone()).or_default().push(id.clone());
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

    let mesh = meshes.add(Sphere::new(0.3));
    for (id, snap) in &snapshot_tree.snapshots {
        if entity_map.0.contains_key(id) { continue; }
        let depth = depth_map.get(id).copied().unwrap_or(0);
        let index = depth_indices.get(id).copied().unwrap_or(0);
        let count_at_depth = depth_counts.get(&depth).copied().unwrap_or(1);
        let x = (index as f32 - (count_at_depth as f32 - 1.0) / 2.0) * SIBLING_SPACING;
        let y = 1.0 + depth as f32 * LAYER_HEIGHT;
        let pos = TREE_OFFSET + Vec3::new(x, y, 0.0);
        let material = mats.add(materials::snapshot_node_material(false));
        let entity = commands.spawn((
            Mesh3d(mesh.clone()),
            MeshMaterial3d(material),
            Transform::from_translation(pos),
            SnapshotNode {
                snapshot_id: id.clone(),
                parent: snap.parent.clone(),
                hash: snap.hash.clone(),
                metadata: snap.metadata.clone(),
                timestamp: snap.timestamp,
            },
        )).id();
        entity_map.0.insert(id.clone(), entity);
    }
}
