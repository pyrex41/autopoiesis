//! Tween lenses for smooth agent visual transitions.
//!
//! Uses bevy_tweening's `Lens` trait with `AssetAnimator<AgentShellMaterial>`
//! to interpolate shader uniforms over time (e.g., 300ms color transitions).

use bevy::prelude::*;
use bevy_tweening::lens::*;
use bevy_tweening::*;

use crate::shaders::agent_shell_material::AgentShellMaterial;

/// Lens that lerps the `base_color` uniform of an `AgentShellMaterial`.
#[derive(Debug, Copy, Clone)]
pub struct AgentColorLens {
    /// Starting color.
    pub start: LinearRgba,
    /// Target color.
    pub end: LinearRgba,
}

impl Lens<AgentShellMaterial> for AgentColorLens {
    fn lerp(&mut self, target: &mut dyn Targetable<AgentShellMaterial>, ratio: f32) {
        target.uniforms.base_color = self.start.mix(&self.end, ratio);
    }
}

/// Lens that lerps the `glow_intensity` uniform of an `AgentShellMaterial`.
#[derive(Debug, Copy, Clone)]
pub struct AgentGlowLens {
    /// Starting glow intensity.
    pub start: f32,
    /// Target glow intensity.
    pub end: f32,
}

impl Lens<AgentShellMaterial> for AgentGlowLens {
    fn lerp(&mut self, target: &mut dyn Targetable<AgentShellMaterial>, ratio: f32) {
        target.uniforms.glow_intensity = self.start + (self.end - self.start) * ratio;
    }
}
