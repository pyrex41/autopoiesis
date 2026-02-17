use bevy::prelude::*;
use bevy::render::render_resource::{AsBindGroup, ShaderRef, ShaderType};

#[derive(ShaderType, Debug, Clone)]
pub struct EnergyBeamUniforms {
    pub base_color: LinearRgba,
    pub flow_speed: f32,
    pub pulse_speed: f32,
    pub wave_frequency: f32,
    pub intensity: f32,
}

impl Default for EnergyBeamUniforms {
    fn default() -> Self {
        Self {
            base_color: LinearRgba::new(0.0, 0.8, 1.0, 1.0),
            flow_speed: 3.0,
            pulse_speed: 2.0,
            wave_frequency: 8.0,
            intensity: 2.0,
        }
    }
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct EnergyBeamMaterial {
    #[uniform(0)]
    pub uniforms: EnergyBeamUniforms,
}

impl Default for EnergyBeamMaterial {
    fn default() -> Self {
        Self {
            uniforms: EnergyBeamUniforms::default(),
        }
    }
}

impl Material for EnergyBeamMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/energy_beam.wgsl".into()
    }

    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Add
    }
}
