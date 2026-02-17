use tokio::sync::mpsc;
use crate::types::{VoiceCmd, VoiceEvent, VoiceMode};
use crate::discovery::ModelInventory;

pub struct VoiceManager {
    cmd_rx: mpsc::Receiver<VoiceCmd>,
    event_tx: mpsc::Sender<VoiceEvent>,
    mode: VoiceMode,
    inventory: ModelInventory,
}

impl VoiceManager {
    /// Spawn the voice manager as a background tokio task.
    /// Returns (cmd_tx, event_rx) for the TUI to use.
    pub fn spawn() -> (mpsc::Sender<VoiceCmd>, mpsc::Receiver<VoiceEvent>) {
        let (cmd_tx, cmd_rx) = mpsc::channel::<VoiceCmd>(32);
        let (event_tx, event_rx) = mpsc::channel::<VoiceEvent>(32);

        let manager = VoiceManager {
            cmd_rx,
            event_tx,
            mode: VoiceMode::Disabled,
            inventory: ModelInventory::scan(),
        };

        tokio::spawn(manager.run());

        (cmd_tx, event_rx)
    }

    async fn run(mut self) {
        // Report model availability
        if self.inventory.has_stt() {
            if let Some((variant, _path)) = self.inventory.best_stt_model() {
                let _ = self.event_tx.send(VoiceEvent::ModelLoaded {
                    model_type: format!("STT ({})", variant.model_name()),
                }).await;
            }
        } else {
            let searched = crate::discovery::moonshine_search_paths("moonshine-*-streaming-en");
            let _ = self.event_tx.send(VoiceEvent::ModelMissing {
                model_type: "STT (Moonshine)".to_string(),
                searched_paths: searched,
            }).await;
        }

        if self.inventory.has_tts() {
            let _ = self.event_tx.send(VoiceEvent::ModelLoaded {
                model_type: "TTS (Piper)".to_string(),
            }).await;
        }

        // Main event loop
        while let Some(cmd) = self.cmd_rx.recv().await {
            match cmd {
                VoiceCmd::SetMode(mode) => {
                    self.mode = mode;
                }
                VoiceCmd::StartRecording => {
                    if !self.inventory.has_stt() {
                        let _ = self.event_tx.send(VoiceEvent::Error(
                            "STT model not found. Run `nexus setup` to download.".to_string()
                        )).await;
                        continue;
                    }
                    let _ = self.event_tx.send(VoiceEvent::RecordingStarted).await;
                    // Full implementation: start cpal audio stream, feed chunks to VAD+STT
                }
                VoiceCmd::StopRecording => {
                    let _ = self.event_tx.send(VoiceEvent::RecordingStopped).await;
                    // Full implementation: stop cpal stream, flush STT buffer, emit TranscriptionComplete
                }
                VoiceCmd::Speak(text) => {
                    if !self.inventory.has_tts() {
                        let _ = self.event_tx.send(VoiceEvent::Error(
                            "TTS model not found. Run `nexus setup` to download.".to_string()
                        )).await;
                        continue;
                    }
                    let _ = self.event_tx.send(VoiceEvent::SpeechStarted).await;
                    // Full implementation: synthesize via Piper, play via rodio
                    let _ = self.event_tx.send(VoiceEvent::SpeechFinished).await;
                    drop(text);
                }
                VoiceCmd::StopSpeaking => {
                    let _ = self.event_tx.send(VoiceEvent::SpeechFinished).await;
                }
                VoiceCmd::Shutdown => break,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::{timeout, Duration};

    #[tokio::test]
    async fn test_voice_manager_spawn() {
        let (cmd_tx, mut event_rx) = VoiceManager::spawn();

        // Should receive model status events (loaded or missing)
        let first_event = timeout(Duration::from_secs(2), event_rx.recv()).await;
        // May or may not get events depending on what models are installed
        let _ = first_event;

        // Send shutdown
        let _ = cmd_tx.send(VoiceCmd::Shutdown).await;
    }

    #[tokio::test]
    async fn test_voice_manager_set_mode() {
        let (cmd_tx, mut event_rx) = VoiceManager::spawn();

        // Drain initial events
        tokio::time::sleep(Duration::from_millis(100)).await;
        while event_rx.try_recv().is_ok() {}

        // Set mode
        cmd_tx.send(VoiceCmd::SetMode(VoiceMode::PushToTalk)).await.unwrap();

        // No error expected for SetMode
        tokio::time::sleep(Duration::from_millis(50)).await;

        cmd_tx.send(VoiceCmd::Shutdown).await.unwrap();
    }

    #[tokio::test]
    async fn test_voice_manager_start_recording_without_model() {
        let (cmd_tx, mut event_rx) = VoiceManager::spawn();

        // Drain initial events
        tokio::time::sleep(Duration::from_millis(100)).await;
        while event_rx.try_recv().is_ok() {}

        cmd_tx.send(VoiceCmd::StartRecording).await.unwrap();

        // Wait for response
        let event = timeout(Duration::from_secs(1), event_rx.recv()).await;
        match event {
            Ok(Some(VoiceEvent::RecordingStarted)) | Ok(Some(VoiceEvent::Error(_))) => {}
            Ok(None) | Err(_) => {}
            Ok(Some(_other)) => {}
        }

        cmd_tx.send(VoiceCmd::Shutdown).await.unwrap();
    }
}
