//! Bundles environment + rendering setup.
//!
//! Sets up the 3D scene: grid floor, lighting, camera with bloom.
//! Also registers camera mode systems (follow, overview, orbit).

use bevy::prelude::*;

use crate::rendering::{environment, postprocessing};
use crate::systems::camera;

/// Plugin for the 3D scene environment.
pub struct ScenePlugin;

impl Plugin for ScenePlugin {
    fn build(&self, app: &mut App) {
        app
            .insert_resource(ClearColor(Color::srgb(0.01, 0.01, 0.03)))
            .init_resource::<camera::CameraMode>()
            .init_resource::<camera::SavedCameraState>()
            .add_systems(Startup, (
                environment::setup_environment,
                postprocessing::setup_camera,
            ))
            .add_systems(Update, (
                camera::camera_mode_input,
                camera::camera_follow_agent,
                camera::camera_follow_deselect_guard,
            ));
    }
}
