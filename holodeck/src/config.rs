//! Configuration file loading from ~/.holodeck/config.toml.

use bevy::prelude::*;
use serde::Deserialize;

/// Top-level holodeck configuration.
#[derive(Deserialize, Resource, Clone, Debug)]
pub struct HolodeckConfig {
    #[serde(default = "default_window")]
    pub window: WindowConfig,
    #[serde(default = "default_rendering")]
    pub rendering: RenderingConfig,
    #[serde(default = "default_connection")]
    pub connection: ConnectionConfig,
    #[serde(default = "default_camera")]
    pub camera: CameraConfig,
}

#[derive(Deserialize, Clone, Debug)]
pub struct WindowConfig {
    #[serde(default = "default_width")]
    pub width: u32,
    #[serde(default = "default_height")]
    pub height: u32,
    #[serde(default = "default_title")]
    pub title: String,
}

#[derive(Deserialize, Clone, Debug)]
pub struct RenderingConfig {
    #[serde(default = "default_bloom_intensity")]
    pub bloom_intensity: f32,
    #[serde(default = "default_font_scale")]
    pub font_scale: f32,
    #[serde(default = "default_grid_spacing")]
    pub grid_spacing: f32,
}

#[derive(Deserialize, Clone, Debug)]
pub struct ConnectionConfig {
    #[serde(default = "default_ws_url")]
    pub ws_url: String,
}

#[derive(Deserialize, Clone, Debug)]
pub struct CameraConfig {
    #[serde(default = "default_camera_distance")]
    pub default_distance: f32,
    #[serde(default = "default_camera_pitch")]
    pub default_pitch: f32,
}

impl Default for HolodeckConfig {
    fn default() -> Self {
        Self {
            window: default_window(),
            rendering: default_rendering(),
            connection: default_connection(),
            camera: default_camera(),
        }
    }
}

fn default_window() -> WindowConfig {
    WindowConfig {
        width: default_width(),
        height: default_height(),
        title: default_title(),
    }
}

fn default_rendering() -> RenderingConfig {
    RenderingConfig {
        bloom_intensity: default_bloom_intensity(),
        font_scale: default_font_scale(),
        grid_spacing: default_grid_spacing(),
    }
}

fn default_connection() -> ConnectionConfig {
    ConnectionConfig {
        ws_url: default_ws_url(),
    }
}

fn default_camera() -> CameraConfig {
    CameraConfig {
        default_distance: default_camera_distance(),
        default_pitch: default_camera_pitch(),
    }
}

fn default_width() -> u32 {
    1600
}
fn default_height() -> u32 {
    900
}
fn default_title() -> String {
    "Autopoiesis Holodeck".to_string()
}
fn default_bloom_intensity() -> f32 {
    0.15
}
fn default_font_scale() -> f32 {
    1.0
}
fn default_grid_spacing() -> f32 {
    5.0
}
fn default_ws_url() -> String {
    "ws://localhost:8080/ws".to_string()
}
fn default_camera_distance() -> f32 {
    30.0
}
fn default_camera_pitch() -> f32 {
    -0.5
}

/// Load config from ~/.holodeck/config.toml, falling back to defaults.
pub fn load_config() -> HolodeckConfig {
    let config_path = dirs::home_dir().map(|h| h.join(".holodeck").join("config.toml"));

    match config_path {
        Some(path) if path.exists() => match std::fs::read_to_string(&path) {
            Ok(contents) => match toml::from_str::<HolodeckConfig>(&contents) {
                Ok(config) => {
                    tracing::info!("Loaded config from {}", path.display());
                    config
                }
                Err(e) => {
                    tracing::warn!("Failed to parse {}: {}, using defaults", path.display(), e);
                    HolodeckConfig::default()
                }
            },
            Err(e) => {
                tracing::warn!("Failed to read {}: {}, using defaults", path.display(), e);
                HolodeckConfig::default()
            }
        },
        _ => {
            tracing::info!("No config file found at ~/.holodeck/config.toml, using defaults");
            HolodeckConfig::default()
        }
    }
}
