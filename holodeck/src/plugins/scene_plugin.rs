//! Bundles environment + rendering setup.
//!
//! Sets up the 3D scene: grid floor, lighting, camera with bloom.

use bevy::prelude::*;

use crate::rendering::{environment, postprocessing};

/// Plugin for the 3D scene environment.
pub struct ScenePlugin;

impl Plugin for ScenePlugin {
    fn build(&self, app: &mut App) {
        app
            .insert_resource(ClearColor(Color::srgb(0.01, 0.01, 0.03)))
            .add_systems(Startup, (
                environment::setup_environment,
                postprocessing::setup_camera,
            ));
    }
}
