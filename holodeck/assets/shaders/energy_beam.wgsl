#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::mesh_view_bindings::globals

struct EnergyBeamUniforms {
    base_color: vec4<f32>,
    flow_speed: f32,
    pulse_speed: f32,
    wave_frequency: f32,
    intensity: f32,
};

@group(2) @binding(0)
var<uniform> material: EnergyBeamUniforms;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let time = globals.time;

    // Animated energy flow along UV.x
    let flow = sin(in.uv.x * material.wave_frequency - time * material.flow_speed) * 0.5 + 0.5;

    // Pulsing brightness
    let pulse = 0.8 + 0.2 * sin(time * material.pulse_speed);

    // Edge softness along UV.y (brighter in center)
    let edge = 1.0 - abs(in.uv.y * 2.0 - 1.0);
    let edge_soft = smoothstep(0.0, 0.4, edge);

    let brightness = flow * pulse * edge_soft * material.intensity;
    let color = material.base_color.rgb * brightness;

    return vec4<f32>(color, brightness * material.base_color.a);
}
