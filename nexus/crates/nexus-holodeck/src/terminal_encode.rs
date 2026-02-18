use std::env;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TerminalProtocol {
    Kitty,
    Sixel,
    HalfBlock,
    None,
}

impl Default for TerminalProtocol {
    fn default() -> Self {
        Self::None
    }
}

impl TerminalProtocol {
    /// Detect terminal graphics protocol from environment variables.
    pub fn from_env() -> Self {
        detect_terminal_graphics()
    }

    /// Whether this protocol supports inline graphics (Kitty or Sixel).
    pub fn supports_graphics(&self) -> bool {
        matches!(self, Self::Kitty | Self::Sixel)
    }
}

/// Maximum bytes of base64 payload per Kitty graphics chunk.
const KITTY_CHUNK_SIZE: usize = 4096;

pub fn detect_terminal_graphics() -> TerminalProtocol {
    // Definitive Kitty check
    if env::var("KITTY_WINDOW_ID").is_ok() {
        return TerminalProtocol::Kitty;
    }

    // Ghostty check
    if env::var("GHOSTTY_RESOURCES_DIR").is_ok() {
        return TerminalProtocol::Kitty;
    }

    let term_program = env::var("TERM_PROGRAM").unwrap_or_default();
    let _term_version = env::var("TERM_PROGRAM_VERSION").unwrap_or_default();
    let term = env::var("TERM").unwrap_or_default();

    // Known Kitty-capable terminals
    if term_program.contains("WezTerm") || term_program.contains("iTerm") {
        return TerminalProtocol::Kitty;
    }

    // xterm-kitty is Kitty's own TERM value
    if term == "xterm-kitty" {
        return TerminalProtocol::Kitty;
    }

    // Sixel-capable terminals
    if term_program.contains("mlterm")
        || term.contains("sixel")
        || term_program.contains("foot")
    {
        return TerminalProtocol::Sixel;
    }

    // tmux can pass through sixel
    if term.starts_with("tmux") || term.starts_with("screen") {
        return TerminalProtocol::Sixel;
    }

    // Any terminal with color support gets halfblock
    if term.contains("color") || term.contains("256color") || !term.is_empty() {
        return TerminalProtocol::HalfBlock;
    }

    TerminalProtocol::None
}

/// Encodes an RGBA frame into Kitty graphics protocol escape sequences with chunking.
///
/// The Kitty protocol limits each transmission chunk to 4096 bytes of base64 payload.
/// This function properly chunks the data using `m=1` (more data) / `m=0` (final).
pub fn encode_frame_kitty(rgba: &[u8], width: u32, height: u32, image_id: u32) -> Vec<u8> {
    use base64::{engine::general_purpose, Engine as _};

    let expected_len = (width as usize) * (height as usize) * 4;
    if rgba.len() != expected_len || width == 0 || height == 0 {
        return Vec::new();
    }

    let payload = general_purpose::STANDARD.encode(rgba);
    let payload_bytes = payload.as_bytes();

    let mut result = Vec::with_capacity(payload_bytes.len() + 256);

    if payload_bytes.len() <= KITTY_CHUNK_SIZE {
        // Single chunk — m=0 (no more data)
        result.extend_from_slice(b"\x1b_G");
        result.extend_from_slice(
            format!(
                "a=T,f=32,s={},v={},i={},q=2,m=0",
                width, height, image_id
            )
            .as_bytes(),
        );
        result.push(b';');
        result.extend_from_slice(payload_bytes);
        result.extend_from_slice(b"\x1b\\");
    } else {
        // Multi-chunk transmission
        let chunks: Vec<&[u8]> = payload_bytes.chunks(KITTY_CHUNK_SIZE).collect();
        let last_idx = chunks.len() - 1;

        for (i, chunk) in chunks.iter().enumerate() {
            result.extend_from_slice(b"\x1b_G");
            if i == 0 {
                // First chunk includes full control data
                result.extend_from_slice(
                    format!(
                        "a=T,f=32,s={},v={},i={},q=2,m=1",
                        width, height, image_id
                    )
                    .as_bytes(),
                );
            } else if i == last_idx {
                // Final chunk
                result.extend_from_slice(b"m=0");
            } else {
                // Middle chunks
                result.extend_from_slice(b"m=1");
            }
            result.push(b';');
            result.extend_from_slice(chunk);
            result.extend_from_slice(b"\x1b\\");
        }
    }

    result
}

/// Represents an RGBA color for palette operations.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct RgbaColor {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

impl RgbaColor {
    /// Squared Euclidean distance in RGB space (ignoring alpha).
    fn distance_sq(&self, other: &RgbaColor) -> u32 {
        let dr = self.r as i32 - other.r as i32;
        let dg = self.g as i32 - other.g as i32;
        let db = self.b as i32 - other.b as i32;
        (dr * dr + dg * dg + db * db) as u32
    }
}

/// Quantizes colors to a limited palette using frequency-based selection.
fn quantize_colors(rgba: &[u8], max_colors: usize) -> Vec<RgbaColor> {
    use std::collections::HashMap;

    let mut color_freq: HashMap<RgbaColor, u32> = HashMap::new();

    for chunk in rgba.chunks(4) {
        if chunk.len() == 4 {
            let color = RgbaColor {
                r: chunk[0],
                g: chunk[1],
                b: chunk[2],
                a: chunk[3],
            };
            *color_freq.entry(color).or_insert(0) += 1;
        }
    }

    let mut colors: Vec<_> = color_freq.into_iter().collect();
    colors.sort_by(|a, b| b.1.cmp(&a.1));

    colors
        .into_iter()
        .take(max_colors)
        .map(|(color, _)| color)
        .collect()
}

/// Generates Sixel color palette definitions.
fn generate_palette(colors: &[RgbaColor]) -> Vec<u8> {
    let mut palette = Vec::new();

    for (i, color) in colors.iter().enumerate() {
        let r_pct = (color.r as f32 / 255.0 * 100.0) as u32;
        let g_pct = (color.g as f32 / 255.0 * 100.0) as u32;
        let b_pct = (color.b as f32 / 255.0 * 100.0) as u32;

        palette.extend_from_slice(format!("#{};2;{};{};{}", i, r_pct, g_pct, b_pct).as_bytes());
    }

    palette
}

/// Maps RGBA pixels to nearest palette color using Euclidean distance in RGB space.
fn map_pixels_to_palette(rgba: &[u8], palette: &[RgbaColor]) -> Vec<Option<usize>> {
    if palette.is_empty() {
        return rgba.chunks(4).map(|_| None).collect();
    }

    rgba.chunks(4)
        .map(|chunk| {
            if chunk.len() == 4 {
                let pixel = RgbaColor {
                    r: chunk[0],
                    g: chunk[1],
                    b: chunk[2],
                    a: chunk[3],
                };

                // Skip fully transparent pixels
                if pixel.a == 0 {
                    return None;
                }

                // Find nearest color by squared Euclidean distance
                let mut best_idx = 0;
                let mut best_dist = u32::MAX;
                for (i, color) in palette.iter().enumerate() {
                    let dist = pixel.distance_sq(color);
                    if dist < best_dist {
                        best_dist = dist;
                        best_idx = i;
                    }
                }
                Some(best_idx)
            } else {
                None
            }
        })
        .collect()
}

/// Encodes pixel data into Sixel format with proper color handling.
fn encode_pixel_data(pixel_indices: &[Option<usize>], width: usize, height: usize, num_colors: usize) -> Vec<u8> {
    let mut data = Vec::new();

    // Process image in 6-pixel high strips
    for strip_y in (0..height).step_by(6) {
        let mut first_color_in_strip = true;

        for color_idx in 0..num_colors {
            let mut strip_data = Vec::new();
            let mut has_data = false;

            for x in 0..width {
                let mut sixel_value = 0u8;

                for bit in 0..6 {
                    let y = strip_y + bit;
                    if y >= height {
                        break;
                    }

                    let pixel_idx = y * width + x;
                    if let Some(pixel_color) = pixel_indices.get(pixel_idx).and_then(|&idx| idx) {
                        if pixel_color == color_idx {
                            sixel_value |= 1 << bit;
                            has_data = true;
                        }
                    }
                }

                // Sixel character: offset by 63 (0 = '?', 63 = '~')
                strip_data.push(sixel_value + 63);
            }

            if has_data {
                // Select color
                data.extend_from_slice(format!("#{}", color_idx).as_bytes());
                data.append(&mut strip_data);

                // Use Graphics Carriage Return ($) between colors in same strip
                if !first_color_in_strip {
                    // Actually $ goes before the color data to re-position
                }
                first_color_in_strip = false;

                // After each color pass in a strip, use $ to return to start of line
                data.push(b'$');
            }
        }

        // Graphics New Line (-) to advance to next strip
        data.push(b'-');
    }

    data
}

/// Encodes an RGBA frame into Sixel graphics protocol format.
///
/// Uses 64-color palette with nearest-neighbor color matching.
pub fn encode_frame_sixel(rgba: &[u8], width: u32, height: u32) -> Vec<u8> {
    let width = width as usize;
    let height = height as usize;

    if rgba.len() != width * height * 4 || width == 0 || height == 0 {
        return Vec::new();
    }

    // 64 colors for better quality
    let palette = quantize_colors(rgba, 64);
    let num_colors = palette.len();

    let mut result = Vec::new();

    // DCS introducer with raster attributes: ESC P 0;0;0 q "1;1;WIDTH;HEIGHT
    result.extend_from_slice(b"\x1bPq");
    result.extend_from_slice(format!("\"1;1;{};{}", width, height).as_bytes());

    // Palette definitions
    result.extend_from_slice(&generate_palette(&palette));

    // Map pixels to palette using nearest-neighbor
    let pixel_indices = map_pixels_to_palette(rgba, &palette);

    // Encode pixel data
    result.extend_from_slice(&encode_pixel_data(&pixel_indices, width, height, num_colors));

    // ST terminator
    result.extend_from_slice(b"\x1b\\");

    result
}

/// Encodes an RGBA frame into HalfBlock ASCII art for fallback rendering.
///
/// Uses Unicode half-block characters (▀ ▄ █) to display two pixel rows per terminal row.
/// Returns lines of styled cell data: Vec<(char, [u8;3], [u8;3])> = (char, fg_rgb, bg_rgb).
pub fn encode_frame_halfblock(rgba: &[u8], width: u32, height: u32) -> String {
    let width = width as usize;
    let height = height as usize;
    let expected_len = width * height * 4;
    if rgba.len() != expected_len || width == 0 || height == 0 {
        return String::new();
    }

    let mut output = String::new();
    let num_rows = (height + 1) / 2;
    for cy in 0..num_rows {
        let mut line = String::new();
        let upper_y = cy * 2;
        let lower_y = upper_y + 1;
        for x in 0..width {
            let get_dark = |y: usize| -> bool {
                if y >= height {
                    false
                } else {
                    let idx = (y * width + x) * 4;
                    if idx + 3 >= expected_len {
                        false
                    } else {
                        let r = rgba[idx] as f32 / 255.0;
                        let g = rgba[idx + 1] as f32 / 255.0;
                        let b = rgba[idx + 2] as f32 / 255.0;
                        let a = rgba[idx + 3] as f32 / 255.0;
                        let luma_rgb = 0.299 * r + 0.587 * g + 0.114 * b;
                        luma_rgb * a < 0.5
                    }
                }
            };
            let upper_dark = get_dark(upper_y);
            let lower_dark = get_dark(lower_y);
            let ch = match (upper_dark, lower_dark) {
                (false, false) => ' ',
                (true, false) => '▀',
                (false, true) => '▄',
                (true, true) => '█',
            };
            line.push(ch);
        }
        output.push_str(&line);
        output.push('\n');
    }
    output
}

/// Encodes an RGBA frame into colored HalfBlock cells for ratatui Buffer rendering.
///
/// Returns Vec of (upper_rgb, lower_rgb) pairs, row-major, where each pair
/// represents two pixel rows compressed into one terminal row using ▀ character
/// with fg=upper color, bg=lower color.
pub fn encode_frame_halfblock_colored(
    rgba: &[u8],
    width: u32,
    height: u32,
) -> Vec<([u8; 3], [u8; 3])> {
    let width = width as usize;
    let height = height as usize;
    let expected_len = width * height * 4;
    if rgba.len() != expected_len || width == 0 || height == 0 {
        return Vec::new();
    }

    let num_rows = (height + 1) / 2;
    let mut cells = Vec::with_capacity(num_rows * width);

    for cy in 0..num_rows {
        let upper_y = cy * 2;
        let lower_y = upper_y + 1;

        for x in 0..width {
            let get_rgb = |y: usize| -> [u8; 3] {
                if y >= height {
                    [0, 0, 0]
                } else {
                    let idx = (y * width + x) * 4;
                    if idx + 2 < expected_len {
                        [rgba[idx], rgba[idx + 1], rgba[idx + 2]]
                    } else {
                        [0, 0, 0]
                    }
                }
            };

            cells.push((get_rgb(upper_y), get_rgb(lower_y)));
        }
    }

    cells
}

#[cfg(test)]
mod tests {
    use super::*;

    // === Protocol Detection Tests ===

    #[test]
    fn test_protocol_supports_graphics() {
        assert!(TerminalProtocol::Kitty.supports_graphics());
        assert!(TerminalProtocol::Sixel.supports_graphics());
        assert!(!TerminalProtocol::HalfBlock.supports_graphics());
        assert!(!TerminalProtocol::None.supports_graphics());
    }

    #[test]
    fn test_protocol_default() {
        assert_eq!(TerminalProtocol::default(), TerminalProtocol::None);
    }

    // === Kitty Encoding Tests ===

    #[test]
    fn test_kitty_small_image_single_chunk() {
        // 2x2 RGBA = 16 bytes, base64 = 24 bytes (well under 4096)
        let rgba = vec![
            255, 0, 0, 255,   // red
            0, 255, 0, 255,   // green
            0, 0, 255, 255,   // blue
            255, 255, 0, 255, // yellow
        ];
        let encoded = encode_frame_kitty(&rgba, 2, 2, 1);
        assert!(!encoded.is_empty());

        let s = String::from_utf8_lossy(&encoded);
        // Single chunk should have m=0
        assert!(s.contains("m=0"), "Single chunk should have m=0");
        assert!(s.contains("a=T,f=32,s=2,v=2,i=1"));
        assert!(s.contains("q=2"), "Should suppress terminal response");
        // Should start with ESC_G and end with ESC\
        assert!(encoded.starts_with(b"\x1b_G"));
        assert!(encoded.ends_with(b"\x1b\\"));
    }

    #[test]
    fn test_kitty_large_image_multi_chunk() {
        // Create an image large enough to require multiple chunks
        // 100x100 RGBA = 40000 bytes, base64 ~53334 bytes > 4096
        let rgba = vec![128u8; 100 * 100 * 4];
        let encoded = encode_frame_kitty(&rgba, 100, 100, 42);
        assert!(!encoded.is_empty());

        let s = String::from_utf8_lossy(&encoded);
        // Should have m=1 for first/middle chunks
        assert!(s.contains("m=1"), "Multi-chunk should have m=1 for continuation");
        // First chunk should have full control data
        assert!(s.contains("a=T,f=32,s=100,v=100,i=42"));
        // Should end with a m=0 chunk
        // Count occurrences of escape sequences
        let chunk_count = s.matches("\x1b_G").count();
        assert!(chunk_count > 1, "Should have multiple chunks, got {}", chunk_count);
    }

    #[test]
    fn test_kitty_invalid_input() {
        assert!(encode_frame_kitty(&[], 0, 0, 1).is_empty());
        assert!(encode_frame_kitty(&[0; 10], 2, 2, 1).is_empty()); // wrong size
        assert!(encode_frame_kitty(&[0; 16], 0, 4, 1).is_empty()); // zero width
    }

    // === Sixel Encoding Tests ===

    #[test]
    fn test_sixel_basic_encoding() {
        let rgba = vec![
            255, 0, 0, 255, // red
            0, 255, 0, 255, // green
            0, 0, 255, 255, // blue
            255, 255, 0, 255, // yellow
        ];
        let encoded = encode_frame_sixel(&rgba, 2, 2);
        assert!(!encoded.is_empty());
        // Should start with DCS and end with ST
        assert!(encoded.starts_with(b"\x1bPq"));
        assert!(encoded.ends_with(b"\x1b\\"));
    }

    #[test]
    fn test_sixel_nearest_neighbor_matching() {
        // Create a palette with red and blue
        let palette = vec![
            RgbaColor { r: 255, g: 0, b: 0, a: 255 },   // red
            RgbaColor { r: 0, g: 0, b: 255, a: 255 },     // blue
        ];

        // A pixel close to red (but not exact) should map to red
        let near_red = vec![250, 10, 5, 255]; // almost red
        let indices = map_pixels_to_palette(&near_red, &palette);
        assert_eq!(indices[0], Some(0), "Near-red pixel should map to red (index 0)");

        // A pixel close to blue should map to blue
        let near_blue = vec![5, 10, 240, 255]; // almost blue
        let indices = map_pixels_to_palette(&near_blue, &palette);
        assert_eq!(indices[0], Some(1), "Near-blue pixel should map to blue (index 1)");
    }

    #[test]
    fn test_sixel_transparent_pixel_skipped() {
        let palette = vec![
            RgbaColor { r: 255, g: 0, b: 0, a: 255 },
        ];
        let transparent = vec![255, 0, 0, 0]; // fully transparent
        let indices = map_pixels_to_palette(&transparent, &palette);
        assert_eq!(indices[0], None, "Transparent pixels should be None");
    }

    #[test]
    fn test_sixel_invalid_input() {
        assert!(encode_frame_sixel(&[], 0, 0).is_empty());
        assert!(encode_frame_sixel(&[0; 10], 2, 2).is_empty());
    }

    // === HalfBlock Tests ===

    #[test]
    fn test_halfblock_basic() {
        // 2x2 white image
        let rgba = vec![255u8; 2 * 2 * 4];
        let output = encode_frame_halfblock(&rgba, 2, 2);
        assert!(!output.is_empty());
        // White pixels are not dark, so should be spaces
        assert!(output.contains(' '));
    }

    #[test]
    fn test_halfblock_dark_pixels() {
        // 2x2 black image
        let rgba = vec![0u8; 2 * 2 * 4];
        // Set alpha to 255
        let mut rgba = rgba;
        for i in (0..rgba.len()).step_by(4) {
            rgba[i + 3] = 255;
        }
        let output = encode_frame_halfblock(&rgba, 2, 2);
        assert!(output.contains('█'), "Black pixels should produce full blocks");
    }

    #[test]
    fn test_halfblock_colored() {
        let rgba = vec![
            255, 0, 0, 255,   // upper-left: red
            0, 255, 0, 255,   // upper-right: green
            0, 0, 255, 255,   // lower-left: blue
            255, 255, 0, 255, // lower-right: yellow
        ];
        let cells = encode_frame_halfblock_colored(&rgba, 2, 2);
        assert_eq!(cells.len(), 2); // 1 row of 2 cells
        assert_eq!(cells[0].0, [255, 0, 0]); // upper-left fg = red
        assert_eq!(cells[0].1, [0, 0, 255]); // lower-left bg = blue
        assert_eq!(cells[1].0, [0, 255, 0]); // upper-right fg = green
        assert_eq!(cells[1].1, [255, 255, 0]); // lower-right bg = yellow
    }

    #[test]
    fn test_halfblock_invalid_input() {
        assert!(encode_frame_halfblock(&[], 0, 0).is_empty());
        assert!(encode_frame_halfblock(&[0; 10], 2, 2).is_empty());
        assert!(encode_frame_halfblock_colored(&[], 0, 0).is_empty());
    }

    // === Color Distance Tests ===

    #[test]
    fn test_color_distance() {
        let red = RgbaColor { r: 255, g: 0, b: 0, a: 255 };
        let also_red = RgbaColor { r: 255, g: 0, b: 0, a: 255 };
        let blue = RgbaColor { r: 0, g: 0, b: 255, a: 255 };

        assert_eq!(red.distance_sq(&also_red), 0);
        assert!(red.distance_sq(&blue) > 0);

        // Near-red is closer to red than to blue
        let near_red = RgbaColor { r: 240, g: 10, b: 10, a: 255 };
        assert!(near_red.distance_sq(&red) < near_red.distance_sq(&blue));
    }

    // === Quantization Tests ===

    #[test]
    fn test_quantize_colors_respects_limit() {
        // Image with 3 distinct colors
        let rgba = vec![
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
        ];
        let palette = quantize_colors(&rgba, 2);
        assert!(palette.len() <= 2);
    }
}
