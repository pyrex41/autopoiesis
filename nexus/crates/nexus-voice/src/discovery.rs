use std::path::PathBuf;
use crate::types::MoonshineVariant;

/// Search for Moonshine model files.
/// Priority:
///   1. ~/Library/Application Support/com.pais.handy/models/<variant>/
///   2. ~/.nexus/models/<variant>/
pub fn find_moonshine_model(variant: MoonshineVariant) -> Option<PathBuf> {
    let model_name = variant.model_name();

    let search_paths = moonshine_search_paths(model_name);

    for path in &search_paths {
        if path.exists() && path.join("encoder.ort").exists() {
            return Some(path.clone());
        }
    }
    None
}

pub fn moonshine_search_paths(model_name: &str) -> Vec<PathBuf> {
    let mut paths = Vec::new();

    // 1. Handy.app location (macOS)
    if let Some(home) = home_dir() {
        paths.push(
            home.join("Library")
                .join("Application Support")
                .join("com.pais.handy")
                .join("models")
                .join(model_name),
        );
        // 2. ~/.nexus/models/
        paths.push(home.join(".nexus").join("models").join(model_name));
    }

    paths
}

/// Search for Piper TTS model
pub fn find_piper_model(voice_name: &str) -> Option<PathBuf> {
    let search_paths = piper_search_paths(voice_name);
    for path in &search_paths {
        if path.with_extension("onnx").exists() {
            return Some(path.with_extension("onnx"));
        }
    }
    None
}

pub fn piper_search_paths(voice_name: &str) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(home) = home_dir() {
        paths.push(home.join(".nexus").join("models").join("piper").join(voice_name));
    }
    paths
}

/// Search for Silero VAD model
pub fn find_silero_vad() -> Option<PathBuf> {
    if let Some(home) = home_dir() {
        let path = home.join(".nexus").join("models").join("silero_vad_v4.onnx");
        if path.exists() {
            return Some(path);
        }
    }
    None
}

fn home_dir() -> Option<PathBuf> {
    std::env::var("HOME").ok().map(PathBuf::from)
}

/// Check what's available on this system
pub struct ModelInventory {
    pub moonshine_small: Option<PathBuf>,
    pub moonshine_medium: Option<PathBuf>,
    pub piper: Option<PathBuf>,
    pub silero_vad: Option<PathBuf>,
}

impl ModelInventory {
    pub fn scan() -> Self {
        Self {
            moonshine_small: find_moonshine_model(MoonshineVariant::Small),
            moonshine_medium: find_moonshine_model(MoonshineVariant::Medium),
            piper: find_piper_model("en_US-lessac-medium"),
            silero_vad: find_silero_vad(),
        }
    }

    pub fn has_stt(&self) -> bool {
        self.moonshine_small.is_some() || self.moonshine_medium.is_some()
    }

    pub fn has_tts(&self) -> bool {
        self.piper.is_some()
    }

    pub fn has_vad(&self) -> bool {
        self.silero_vad.is_some()
    }

    pub fn best_stt_model(&self) -> Option<(MoonshineVariant, &PathBuf)> {
        // Prefer medium, fall back to small
        if let Some(ref path) = self.moonshine_medium {
            return Some((MoonshineVariant::Medium, path));
        }
        if let Some(ref path) = self.moonshine_small {
            return Some((MoonshineVariant::Small, path));
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_moonshine_search_paths_not_empty() {
        let paths = moonshine_search_paths("moonshine-small-streaming-en");
        assert!(!paths.is_empty());
        assert!(paths.len() >= 1);
    }

    #[test]
    fn test_moonshine_search_paths_includes_handy() {
        let paths = moonshine_search_paths("moonshine-small-streaming-en");
        let has_handy = paths.iter().any(|p| p.to_string_lossy().contains("handy"));
        if std::env::var("HOME").is_ok() {
            assert!(has_handy);
        }
    }

    #[test]
    fn test_piper_search_paths_not_empty() {
        let paths = piper_search_paths("en_US-lessac-medium");
        assert!(!paths.is_empty());
    }

    #[test]
    fn test_model_inventory_scan_no_panic() {
        let _ = ModelInventory::scan();
    }

    #[test]
    fn test_find_moonshine_missing() {
        let result = find_moonshine_model(MoonshineVariant::Small);
        let _ = result;
    }

    #[test]
    fn test_moonshine_variant_names() {
        assert_eq!(MoonshineVariant::Small.model_name(), "moonshine-small-streaming-en");
        assert_eq!(MoonshineVariant::Medium.model_name(), "moonshine-medium-streaming-en");
    }
}
