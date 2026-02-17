//! Camera modes: orbit (default), follow selected agent, and overview.
//!
//! - `F` key: Follow mode -- locks camera focus on the selected agent
//! - `O` key: Overview mode -- bird's-eye view at Y=40 looking straight down
//! - `Escape`: Return to free orbit mode
//!
//! Transitions use PanOrbitCamera's built-in `target_*` fields for smooth
//! interpolation (orbit_smoothness controls the speed).

use bevy::prelude::*;
use bevy_panorbit_camera::PanOrbitCamera;

use crate::state::components::AgentNode;
use crate::state::resources::SelectedAgent;

/// The active camera mode.
#[derive(Resource, Debug, Clone, PartialEq)]
pub enum CameraMode {
    /// Free orbit -- user controls camera via mouse.
    Orbit,
    /// Follow the selected agent -- camera focus tracks agent position.
    Follow,
    /// Bird's-eye overview looking straight down.
    Overview,
}

impl Default for CameraMode {
    fn default() -> Self {
        CameraMode::Orbit
    }
}

/// Saved camera state for restoring orbit mode after follow/overview.
#[derive(Resource, Debug, Clone)]
pub struct SavedCameraState {
    pub focus: Vec3,
    pub yaw: f32,
    pub pitch: f32,
    pub radius: f32,
}

impl Default for SavedCameraState {
    fn default() -> Self {
        Self {
            focus: Vec3::ZERO,
            yaw: 0.0,
            pitch: -0.5,
            radius: 30.0,
        }
    }
}

/// Handle keyboard input to switch camera modes.
pub fn camera_mode_input(
    keys: Res<ButtonInput<KeyCode>>,
    mut mode: ResMut<CameraMode>,
    mut saved: ResMut<SavedCameraState>,
    selected: Res<SelectedAgent>,
    mut camera: Query<&mut PanOrbitCamera>,
) {
    let Ok(mut cam) = camera.get_single_mut() else {
        return;
    };

    if keys.just_pressed(KeyCode::KeyF) {
        if selected.entity.is_some() && *mode != CameraMode::Follow {
            // Save current state before switching
            if *mode == CameraMode::Orbit {
                saved.focus = cam.target_focus;
                saved.yaw = cam.target_yaw;
                saved.pitch = cam.target_pitch;
                saved.radius = cam.target_radius;
            }
            *mode = CameraMode::Follow;
            // Bring camera a bit closer for follow mode
            cam.target_radius = 15.0;
            cam.target_pitch = -0.4;
        }
    }

    if keys.just_pressed(KeyCode::KeyO) {
        if *mode != CameraMode::Overview {
            // Save current state before switching
            if *mode == CameraMode::Orbit {
                saved.focus = cam.target_focus;
                saved.yaw = cam.target_yaw;
                saved.pitch = cam.target_pitch;
                saved.radius = cam.target_radius;
            }
            *mode = CameraMode::Overview;
            // Bird's-eye: straight down, high up
            cam.target_focus = Vec3::ZERO;
            cam.target_pitch = -std::f32::consts::FRAC_PI_2 + 0.01; // Nearly -90 deg
            cam.target_radius = 40.0;
            cam.target_yaw = 0.0;
        }
    }

    if keys.just_pressed(KeyCode::Escape) {
        if *mode != CameraMode::Orbit {
            *mode = CameraMode::Orbit;
            // Restore saved orbit state
            cam.target_focus = saved.focus;
            cam.target_yaw = saved.yaw;
            cam.target_pitch = saved.pitch;
            cam.target_radius = saved.radius;
            cam.enabled = true;
        }
    }
}

/// In follow mode, continuously update camera focus to track the selected agent.
pub fn camera_follow_agent(
    mode: Res<CameraMode>,
    selected: Res<SelectedAgent>,
    agents: Query<&Transform, With<AgentNode>>,
    mut camera: Query<&mut PanOrbitCamera>,
) {
    if *mode != CameraMode::Follow {
        return;
    }

    let Some(entity) = selected.entity else {
        return;
    };

    let Ok(agent_transform) = agents.get(entity) else {
        return;
    };

    let Ok(mut cam) = camera.get_single_mut() else {
        return;
    };

    // Update target_focus to agent position -- PanOrbitCamera smooths the transition
    cam.target_focus = agent_transform.translation;
}

/// If follow mode is active but no agent is selected, revert to orbit.
pub fn camera_follow_deselect_guard(
    mut mode: ResMut<CameraMode>,
    selected: Res<SelectedAgent>,
    saved: Res<SavedCameraState>,
    mut camera: Query<&mut PanOrbitCamera>,
) {
    if *mode == CameraMode::Follow && selected.entity.is_none() {
        *mode = CameraMode::Orbit;
        if let Ok(mut cam) = camera.get_single_mut() {
            cam.target_focus = saved.focus;
            cam.target_yaw = saved.yaw;
            cam.target_pitch = saved.pitch;
            cam.target_radius = saved.radius;
        }
    }
}
