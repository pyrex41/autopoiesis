use bevy::prelude::*;

use crate::shaders::agent_shell_material::AgentShellMaterial;
use crate::shaders::energy_beam_material::EnergyBeamMaterial;
use crate::shaders::grid_material::GridMaterial;
use crate::shaders::hologram_material::HologramMaterial;

/// Registers all custom material plugins for shader-based rendering.
pub struct ShaderPlugin;

impl Plugin for ShaderPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((
            MaterialPlugin::<GridMaterial>::default(),
            MaterialPlugin::<AgentShellMaterial>::default(),
            MaterialPlugin::<EnergyBeamMaterial>::default(),
            MaterialPlugin::<HologramMaterial>::default(),
        ));
    }
}
