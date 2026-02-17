//! Skybox, grid floor, fog, lighting setup.
//!
//! Creates the Tron-aesthetic environment: black void with a procedural
//! shader-based grid floor, dim blue-white directional light, and low ambient.

use bevy::prelude::*;

use crate::shaders::grid_material::GridMaterial;
use crate::state::components::GridFloor;

/// Spawn the 3D environment: floor, lights, camera.
pub fn setup_environment(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut grid_materials: ResMut<Assets<GridMaterial>>,
) {
    // --- Grid floor (shader-based procedural grid) ---
    commands.spawn((
        Mesh3d(meshes.add(Plane3d::default().mesh().size(200.0, 200.0))),
        MeshMaterial3d(grid_materials.add(GridMaterial::default())),
        Transform::from_translation(Vec3::ZERO),
        GridFloor,
    ));

    // --- Directional light (dim, blue-white) ---
    commands.spawn((
        DirectionalLight {
            color: Color::srgb(0.7, 0.8, 1.0),
            illuminance: 800.0,
            shadows_enabled: true,
            ..default()
        },
        Transform::from_rotation(Quat::from_euler(EulerRot::XYZ, -0.8, 0.3, 0.0)),
    ));

    // --- Ambient light (very low) ---
    commands.insert_resource(AmbientLight {
        color: Color::srgb(0.1, 0.15, 0.3),
        brightness: 30.0,
    });
}
