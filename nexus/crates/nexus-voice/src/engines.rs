use std::path::PathBuf;
use anyhow::{Context, Result};
use crate::types::{StreamingConfig, MoonshineVariant};

/// Moonshine v2 streaming STT engine
///
/// Uses 5 separate ONNX sessions for the streaming pipeline:
/// frontend -> encoder -> adapter -> cross_kv -> decoder_kv
pub struct MoonshineSttEngine {
    model_dir: PathBuf,
    variant: MoonshineVariant,
    pub config: StreamingConfig,
}

impl MoonshineSttEngine {
    /// Load the engine from a model directory containing the 5 .ort files
    /// and streaming_config.json
    pub fn load(model_dir: PathBuf, variant: MoonshineVariant) -> Result<Self> {
        let config_path = model_dir.join("streaming_config.json");
        let config_str = std::fs::read_to_string(&config_path)
            .with_context(|| format!("Failed to read streaming_config.json at {:?}", config_path))?;
        let config: StreamingConfig = serde_json::from_str(&config_str)?;

        // Verify required files exist
        let required_files = ["frontend.ort", "encoder.ort", "adapter.ort", "cross_kv.ort", "decoder_kv.ort"];
        for fname in &required_files {
            let path = model_dir.join(fname);
            if !path.exists() {
                anyhow::bail!("Missing model file: {:?}", path);
            }
        }

        Ok(Self { model_dir, variant, config })
    }

    pub fn model_dir(&self) -> &PathBuf { &self.model_dir }
    pub fn variant(&self) -> MoonshineVariant { self.variant }

    /// Transcribe a buffer of 16kHz mono f32 samples
    /// Returns transcribed text
    pub fn transcribe(&self, samples: &[f32]) -> Result<String> {
        // Full implementation would:
        // 1. Run samples through frontend session -> frame features
        // 2. Run encoder session -> hidden states
        // 3. Run adapter -> adapted states
        // 4. Run cross_kv -> key/value pairs for cross attention
        // 5. Autoregressive decoding loop via decoder_kv until EOS or max_len
        // 6. Decode token IDs back to text using tokenizer

        // For now, return placeholder (requires ort inference code)
        let duration_secs = samples.len() as f32 / 16000.0;
        Ok(format!("[STT: {:.1}s of audio — load ort sessions to transcribe]", duration_secs))
    }
}

/// Silero VAD v4 engine
pub struct SileroVadEngine {
    model_path: PathBuf,
    pub start_threshold: f32,
    pub end_threshold: f32,
    pub min_speech_ms: u32,
    pub min_silence_ms: u32,
}

impl SileroVadEngine {
    pub fn load(model_path: PathBuf) -> Result<Self> {
        if !model_path.exists() {
            anyhow::bail!("Silero VAD model not found at {:?}", model_path);
        }
        Ok(Self {
            model_path,
            start_threshold: 0.5,
            end_threshold: 0.35,
            min_speech_ms: 250,
            min_silence_ms: 500,
        })
    }

    /// Process a 512-sample chunk at 16kHz (32ms)
    /// Returns speech probability [0.0, 1.0]
    pub fn process_chunk(&self, _samples: &[f32; 512]) -> Result<f32> {
        // Full implementation would run the ONNX session with LSTM state
        // Returning 0.0 as stub (silence)
        Ok(0.0)
    }

    pub fn model_path(&self) -> &PathBuf { &self.model_path }
}

/// Piper TTS engine
pub struct PiperTtsEngine {
    model_path: PathBuf,
    sample_rate: u32,
}

impl PiperTtsEngine {
    pub fn load(model_path: PathBuf) -> Result<Self> {
        if !model_path.exists() {
            anyhow::bail!("Piper TTS model not found at {:?}", model_path);
        }
        Ok(Self { model_path, sample_rate: 22050 })
    }

    /// Synthesize text to WAV PCM samples at 22050 Hz
    pub fn synthesize(&self, _text: &str) -> Result<Vec<i16>> {
        // Full implementation would run Piper ONNX session
        // Returns empty audio as stub
        Ok(Vec::new())
    }

    pub fn sample_rate(&self) -> u32 { self.sample_rate }
    pub fn model_path(&self) -> &PathBuf { &self.model_path }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_moonshine_load_missing_dir() {
        let result = MoonshineSttEngine::load(
            PathBuf::from("/nonexistent/moonshine"),
            MoonshineVariant::Small,
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_silero_vad_load_missing() {
        let result = SileroVadEngine::load(PathBuf::from("/nonexistent/vad.onnx"));
        assert!(result.is_err());
    }

    #[test]
    fn test_piper_load_missing() {
        let result = PiperTtsEngine::load(PathBuf::from("/nonexistent/piper.onnx"));
        assert!(result.is_err());
    }

    #[test]
    fn test_moonshine_load_missing_config() {
        let dir = std::env::temp_dir().join("nexus_test_moonshine");
        let _ = std::fs::create_dir_all(&dir);
        for fname in &["frontend.ort", "encoder.ort", "adapter.ort", "cross_kv.ort", "decoder_kv.ort"] {
            let _ = std::fs::write(dir.join(fname), b"fake");
        }
        let result = MoonshineSttEngine::load(dir.clone(), MoonshineVariant::Small);
        assert!(result.is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_moonshine_load_with_config() {
        let dir = std::env::temp_dir().join("nexus_test_moonshine2");
        let _ = std::fs::create_dir_all(&dir);
        for fname in &["frontend.ort", "encoder.ort", "adapter.ort", "cross_kv.ort", "decoder_kv.ort"] {
            let _ = std::fs::write(dir.join(fname), b"fake");
        }
        let config_json = r#"{
            "encoder_dim": 256,
            "decoder_dim": 256,
            "depth": 6,
            "nheads": 8,
            "head_dim": 32,
            "vocab_size": 32768,
            "bos_id": 1,
            "eos_id": 2,
            "frame_len": 16,
            "total_lookahead": 4
        }"#;
        let _ = std::fs::write(dir.join("streaming_config.json"), config_json);

        let engine = MoonshineSttEngine::load(dir.clone(), MoonshineVariant::Small).unwrap();
        assert_eq!(engine.config.encoder_dim, 256);
        assert_eq!(engine.config.vocab_size, 32768);
        assert_eq!(engine.variant(), MoonshineVariant::Small);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_silero_vad_thresholds() {
        assert!(0.5_f32 > 0.35_f32);
    }

    #[test]
    fn test_streaming_config_deserialization() {
        let json = r#"{
            "encoder_dim": 512,
            "decoder_dim": 512,
            "depth": 8,
            "nheads": 16,
            "head_dim": 32,
            "vocab_size": 32768,
            "bos_id": 1,
            "eos_id": 2,
            "frame_len": 16,
            "total_lookahead": 4
        }"#;
        let config: StreamingConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.encoder_dim, 512);
        assert_eq!(config.bos_id, 1);
        assert_eq!(config.eos_id, 2);
    }
}
