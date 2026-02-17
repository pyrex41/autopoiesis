#import bevy_pbr::forward_io::VertexOutput
#import bevy_pbr::mesh_view_bindings::globals

struct HologramUniforms {
    tint_color: vec4<f32>,
    edge_glow_intensity: f32,
    scanline_intensity: f32,
    aberration_amount: f32,
    alpha: f32,
};

@group(2) @binding(0)
var<uniform> material: HologramUniforms;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let time = globals.time;

    // Edge glow: brighter near UV edges
    let uv_center = abs(in.uv * 2.0 - 1.0);
    let edge_dist = max(uv_center.x, uv_center.y);
    let edge_glow = smoothstep(0.7, 1.0, edge_dist) * material.edge_glow_intensity;

    // Scanlines
    let scanline = 1.0 - material.scanline_intensity * 0.5 *
        (1.0 + sin(in.uv.y * 200.0 + time * 1.5));

    // Chromatic aberration: offset R and B channels slightly
    let ab = material.aberration_amount;
    let uv_r = in.uv + vec2<f32>(ab, 0.0);
    let uv_b = in.uv - vec2<f32>(ab, 0.0);
    let edge_r = smoothstep(0.7, 1.0, max(abs(uv_r.x * 2.0 - 1.0), abs(uv_r.y * 2.0 - 1.0)));
    let edge_b = smoothstep(0.7, 1.0, max(abs(uv_b.x * 2.0 - 1.0), abs(uv_b.y * 2.0 - 1.0)));

    // Base color with scanlines
    let base = material.tint_color.rgb * scanline;

    // Apply chromatic aberration to edge glow
    let glow_r = edge_r * material.edge_glow_intensity;
    let glow_g = edge_glow;
    let glow_b = edge_b * material.edge_glow_intensity;
    let aberrated_glow = vec3<f32>(glow_r, glow_g, glow_b) * material.tint_color.rgb;

    // Subtle flicker
    let flicker = 0.95 + 0.05 * sin(time * 12.0 + sin(time * 3.7) * 2.0);

    let final_color = (base + aberrated_glow) * flicker;

    return vec4<f32>(final_color, material.alpha + edge_glow * 0.3);
}
