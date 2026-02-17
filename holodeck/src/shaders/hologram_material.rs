use bevy::prelude::*;
use bevy::render::render_resource::{AsBindGroup, ShaderRef, ShaderType};

#[derive(ShaderType, Debug, Clone)]
pub struct HologramUniforms {
    pub tint_color: LinearRgba,
    pub edge_glow_intensity: f32,
    pub scanline_intensity: f32,
    pub aberration_amount: f32,
    pub alpha: f32,
}

impl Default for HologramUniforms {
    fn default() -> Self {
        Self {
            tint_color: LinearRgba::new(0.0, 0.7, 0.85, 1.0),
            edge_glow_intensity: 2.0,
            scanline_intensity: 0.3,
            aberration_amount: 0.005,
            alpha: 0.25,
        }
    }
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct HologramMaterial {
    #[uniform(0)]
    pub uniforms: HologramUniforms,
}

impl Default for HologramMaterial {
    fn default() -> Self {
        Self {
            uniforms: HologramUniforms::default(),
        }
    }
}

impl Material for HologramMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/hologram.wgsl".into()
    }

    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Blend
    }
}
