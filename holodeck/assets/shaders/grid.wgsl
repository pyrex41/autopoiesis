#import bevy_pbr::forward_io::VertexOutput

struct GridUniforms {
    grid_color: vec4<f32>,
    line_color: vec4<f32>,
    grid_spacing: f32,
    fade_start: f32,
    fade_end: f32,
    _padding: f32,
};

@group(2) @binding(0)
var<uniform> material: GridUniforms;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // TODO: Implement procedural grid with anti-aliased lines and distance fade
    let world_pos = in.world_position.xz;
    let grid = material.grid_spacing;

    // Grid line detection using fwidth for anti-aliasing
    let coord = world_pos / grid;
    let line = abs(fract(coord - 0.5) - 0.5);
    let edge = fwidth(coord);
    let grid_line = 1.0 - smoothstep(0.0, edge.x * 1.5, line.x) *
                          smoothstep(0.0, edge.y * 1.5, line.y);

    // Distance fade
    let dist = length(world_pos);
    let fade = 1.0 - smoothstep(material.fade_start, material.fade_end, dist);

    // Mix grid color with line color
    let color = mix(material.grid_color, material.line_color, grid_line);
    return vec4<f32>(color.rgb, color.a * fade * grid_line);
}
