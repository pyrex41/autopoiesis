//! Skybox, grid floor, fog, lighting setup.
//!
//! Creates the Tron-aesthetic environment: black void with a subtle
//! blue grid floor, dim blue-white directional light, and low ambient.

use bevy::prelude::*;

use crate::state::components::GridFloor;

/// Spawn the 3D environment: floor, lights, camera.
pub fn setup_environment(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // --- Grid floor ---
    // Large plane at y=0 with a subtle grid appearance.
    // A custom grid shader would be ideal; for now we use a scaled plane
    // with a semi-transparent dark material.
    commands.spawn((
        Mesh3d(meshes.add(Plane3d::default().mesh().size(200.0, 200.0))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: Color::srgba(0.02, 0.02, 0.06, 0.95),
            emissive: LinearRgba::new(0.0, 0.02, 0.08, 1.0),
            perceptual_roughness: 0.95,
            metallic: 0.0,
            alpha_mode: AlphaMode::Blend,
            ..default()
        })),
        Transform::from_translation(Vec3::ZERO),
        GridFloor,
    ));

    // --- Grid lines (simple approach: thin boxes as grid lines) ---
    let grid_line_material = materials.add(StandardMaterial {
        base_color: Color::srgba(0.0, 0.15, 0.35, 0.4),
        emissive: LinearRgba::new(0.0, 0.1, 0.25, 1.0),
        alpha_mode: AlphaMode::Blend,
        ..default()
    });
    let line_mesh = meshes.add(Cuboid::new(200.0, 0.005, 0.02));

    // Spawn grid lines along X and Z axes
    for i in -20..=20 {
        let pos = i as f32 * 5.0;
        // Lines along X axis
        commands.spawn((
            Mesh3d(line_mesh.clone()),
            MeshMaterial3d(grid_line_material.clone()),
            Transform::from_translation(Vec3::new(0.0, 0.001, pos)),
        ));
        // Lines along Z axis
        commands.spawn((
            Mesh3d(line_mesh.clone()),
            MeshMaterial3d(grid_line_material.clone()),
            Transform::from_translation(Vec3::new(pos, 0.001, 0.0))
                .with_rotation(Quat::from_rotation_y(std::f32::consts::FRAC_PI_2)),
        ));
    }

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
