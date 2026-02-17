use bevy::prelude::*;
use bevy::render::render_resource::{AsBindGroup, ShaderRef, ShaderType};

#[derive(ShaderType, Debug, Clone)]
pub struct AgentShellUniforms {
    pub base_color: LinearRgba,
    pub glow_intensity: f32,
    pub fresnel_power: f32,
    pub scanline_freq: f32,
    pub scanline_speed: f32,
    pub flicker_amount: f32,
    pub _padding1: f32,
    pub _padding2: f32,
    pub _padding3: f32,
}

impl Default for AgentShellUniforms {
    fn default() -> Self {
        Self {
            base_color: LinearRgba::new(0.0, 0.533, 1.0, 1.0),
            glow_intensity: 1.5,
            fresnel_power: 3.0,
            scanline_freq: 30.0,
            scanline_speed: 2.0,
            flicker_amount: 0.05,
            _padding1: 0.0,
            _padding2: 0.0,
            _padding3: 0.0,
        }
    }
}

#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct AgentShellMaterial {
    #[uniform(0)]
    pub uniforms: AgentShellUniforms,
}

impl Default for AgentShellMaterial {
    fn default() -> Self {
        Self {
            uniforms: AgentShellUniforms::default(),
        }
    }
}

impl Material for AgentShellMaterial {
    fn fragment_shader() -> ShaderRef {
        "shaders/agent_shell.wgsl".into()
    }

    fn alpha_mode(&self) -> AlphaMode {
        AlphaMode::Blend
    }
}
