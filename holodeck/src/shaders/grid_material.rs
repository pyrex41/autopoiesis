use bevy::prelude::*;
use bevy::render::render_resource::{AsBindGroup, ShaderRef, ShaderType};

#[derive(ShaderType, Debug, Clone)]
pub struct GridUniforms {
    pub grid_color: LinearRgba,
    pub line_color: LinearRgba,
    pub grid_spacing: f32,
    pub fade_start: f32,
    pub fade_end: f32,
    pub _padding: f32,
}

impl Default for GridUniforms {
    fn default() -> Self {
        Self {
            grid_color: LinearRgba::new(0.02, 0.02, 0.06, 0.95),
            line_color: LinearRgba::new(0.0, 0.15, 0.35, 0.4),
            grid_spacing: 5.0,
            fade_start: 40.0,
            fade_end: 100.0,
            _padding: 0.0,
        }
    }
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct GridMaterial {
    #[uniform(0)]
    pub uniforms: GridUniforms,
}

impl Default for GridMaterial {
    fn default() -> Self {
        Self {
            uniforms: GridUniforms::default(),
        }
    }
}

impl Material for GridMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/grid.wgsl".into()
    }

    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Blend
    }
}
