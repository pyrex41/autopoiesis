//! Custom materials: glow, hologram, energy beam.
//!
//! Agent spheres use `AgentShellMaterial` (custom WGSL shader with fresnel,
//! scanlines, flicker). Other entities still use `StandardMaterial` with high
//! emissive values to trigger bloom.

use bevy::prelude::*;

use crate::shaders::agent_shell_material::{AgentShellMaterial, AgentShellUniforms};

/// Create a custom agent shell material with fresnel, scanlines, and flicker.
///
/// The shader outputs HDR values > 1.0 to trigger Bevy's bloom
/// post-processing, giving the Tron-aesthetic neon glow.
pub fn agent_shell_material(color: Color) -> AgentShellMaterial {
    let linear = color.to_linear();
    AgentShellMaterial {
        uniforms: AgentShellUniforms {
            base_color: linear,
            glow_intensity: 1.5,
            fresnel_power: 3.0,
            scanline_freq: 30.0,
            scanline_speed: 2.0,
            flicker_amount: 0.05,
            _padding1: 0.0,
            _padding2: 0.0,
            _padding3: 0.0,
        },
    }
}

/// Legacy emissive StandardMaterial for non-agent entities that still need it.
pub fn agent_material(color: Color) -> StandardMaterial {
    let linear = color.to_linear();
    StandardMaterial {
        base_color: color,
        emissive: LinearRgba::new(linear.red * 4.0, linear.green * 4.0, linear.blue * 4.0, 1.0),
        perceptual_roughness: 0.3,
        metallic: 0.8,
        ..default()
    }
}

/// Create a subtle material for the grid floor.
pub fn grid_floor_material() -> StandardMaterial {
    StandardMaterial {
        base_color: Color::srgba(0.05, 0.05, 0.1, 0.9),
        emissive: LinearRgba::new(0.0, 0.05, 0.15, 1.0),
        perceptual_roughness: 0.9,
        metallic: 0.1,
        alpha_mode: AlphaMode::Blend,
        ..default()
    }
}

/// Create a material for the selection ring.
pub fn selection_ring_material() -> StandardMaterial {
    StandardMaterial {
        base_color: Color::srgba(0.0, 0.8, 1.0, 0.6),
        emissive: LinearRgba::new(0.0, 3.0, 4.0, 1.0),
        perceptual_roughness: 0.1,
        metallic: 1.0,
        alpha_mode: AlphaMode::Blend,
        ..default()
    }
}

/// Create a material for connection beams between entities.
pub fn beam_material(color: Color) -> StandardMaterial {
    let linear = color.to_linear();
    StandardMaterial {
        base_color: color,
        emissive: LinearRgba::new(linear.red * 2.0, linear.green * 2.0, linear.blue * 2.0, 1.0),
        perceptual_roughness: 0.1,
        metallic: 1.0,
        alpha_mode: AlphaMode::Add,
        ..default()
    }
}

/// Create a material for snapshot tree nodes.
pub fn snapshot_node_material(is_current_branch: bool) -> StandardMaterial {
    let (base, emissive_mult) = if is_current_branch {
        (Color::srgb(1.0, 0.843, 0.0), 3.0) // Gold
    } else {
        (Color::srgb(0.4, 0.4, 0.6), 1.0) // Muted blue-grey
    };
    let linear = base.to_linear();
    StandardMaterial {
        base_color: base,
        emissive: LinearRgba::new(
            linear.red * emissive_mult,
            linear.green * emissive_mult,
            linear.blue * emissive_mult,
            1.0,
        ),
        perceptual_roughness: 0.5,
        metallic: 0.6,
        ..default()
    }
}
