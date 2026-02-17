#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::mesh_view_bindings::globals
#import bevy_pbr::mesh_view_bindings::view

struct AgentShellUniforms {
    base_color: vec4<f32>,
    glow_intensity: f32,
    fresnel_power: f32,
    scanline_freq: f32,
    scanline_speed: f32,
    flicker_amount: f32,
    _padding1: f32,
    _padding2: f32,
    _padding3: f32,
};

@group(2) @binding(0)
var<uniform> material: AgentShellUniforms;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // TODO: Full implementation with fresnel, scanlines, flicker
    let time = globals.time;

    // View direction for fresnel
    let view_dir = normalize(view.world_position.xyz - in.world_position.xyz);
    let normal = normalize(in.world_normal);

    // Fresnel rim glow
    let fresnel = pow(1.0 - max(dot(normal, view_dir), 0.0), material.fresnel_power);
    let rim = fresnel * material.glow_intensity;

    // Scrolling scanlines
    let scanline = 0.85 + 0.15 * sin(in.world_position.y * material.scanline_freq + time * material.scanline_speed);

    // Subtle flicker
    let flicker = 1.0 + material.flicker_amount * sin(time * 13.7 + in.world_position.x * 5.0);

    // Combine
    let base = material.base_color.rgb;
    let lit = base * scanline * flicker * material.glow_intensity;
    let final_color = lit + vec3<f32>(rim) * base;

    // HDR output > 1.0 triggers bloom
    return vec4<f32>(final_color, material.base_color.a);
}
