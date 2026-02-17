//! Bloom and ambient occlusion configuration.
//!
//! Bloom makes emissive materials glow — the key to the Tron aesthetic.

use bevy::core_pipeline::bloom::Bloom;
use bevy::prelude::*;
use bevy_panorbit_camera::PanOrbitCamera;

/// Spawn the main camera with bloom post-processing and orbit controls.
pub fn setup_camera(mut commands: Commands) {
    commands.spawn((
        // Camera
        Camera3d::default(),
        Camera {
            hdr: true,
            ..default()
        },
        Transform::from_translation(Vec3::new(0.0, 15.0, 25.0))
            .looking_at(Vec3::ZERO, Vec3::Y),
        // Bloom — low intensity, wide radius for soft neon glow
        Bloom {
            intensity: 0.15,
            low_frequency_boost: 0.6,
            low_frequency_boost_curvature: 0.4,
            high_pass_frequency: 0.8,
            ..default()
        },
        // Orbit camera controls
        PanOrbitCamera {
            focus: Vec3::ZERO,
            radius: Some(30.0),
            yaw: Some(0.0),
            pitch: Some(-0.5),
            ..default()
        },
    ));
}
