use std::path::PathBuf;

/// Voice operating mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VoiceMode {
    #[default]
    Disabled,
    PushToTalk,
    VoiceActivated,
}

/// Commands sent from TUI to VoiceManager
#[derive(Debug, Clone)]
pub enum VoiceCmd {
    StartRecording,
    StopRecording,
    Speak(String),
    StopSpeaking,
    SetMode(VoiceMode),
    Shutdown,
}

/// Events emitted by VoiceManager to TUI
#[derive(Debug, Clone)]
pub enum VoiceEvent {
    RecordingStarted,
    RecordingStopped,
    TranscriptionPartial(String),
    TranscriptionComplete(String),
    SpeechStarted,
    SpeechFinished,
    ModelLoaded { model_type: String },
    ModelMissing { model_type: String, searched_paths: Vec<PathBuf> },
    Error(String),
}

/// Which STT model variant
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MoonshineVariant {
    Small,  // 123M params, ~148ms latency
    Medium, // 245M params, ~258ms latency
}

impl MoonshineVariant {
    pub fn model_name(&self) -> &str {
        match self {
            Self::Small => "moonshine-small-streaming-en",
            Self::Medium => "moonshine-medium-streaming-en",
        }
    }
}

/// Streaming config loaded from streaming_config.json
#[derive(Debug, Clone, serde::Deserialize)]
pub struct StreamingConfig {
    pub encoder_dim: usize,
    pub decoder_dim: usize,
    pub depth: usize,
    pub nheads: usize,
    pub head_dim: usize,
    pub vocab_size: usize,
    pub bos_id: i64,
    pub eos_id: i64,
    pub frame_len: usize,
    pub total_lookahead: usize,
}
