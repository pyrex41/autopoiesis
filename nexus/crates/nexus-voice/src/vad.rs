/// Voice Activity Detection state machine

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VadState {
    Silence,
    PossibleSpeech { frames: u32 },
    Speech,
    PossibleSilence { frames: u32 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VadEvent {
    Silence,
    SpeechStarted,
    SpeechContinuing,
    SpeechEnded,
}

pub struct VadStateMachine {
    state: VadState,
    pub start_threshold: f32,
    pub end_threshold: f32,
}

impl VadStateMachine {
    pub fn new() -> Self {
        Self {
            state: VadState::Silence,
            start_threshold: 0.5,
            end_threshold: 0.35,
        }
    }

    /// Process a speech probability and return a VAD event
    pub fn process(&mut self, probability: f32) -> VadEvent {
        match self.state {
            VadState::Silence => {
                if probability >= self.start_threshold {
                    self.state = VadState::PossibleSpeech { frames: 1 };
                }
                VadEvent::Silence
            }
            VadState::PossibleSpeech { frames } => {
                if probability >= self.start_threshold {
                    // Need ~250ms of speech before confirming (~7 * 32ms = ~225ms)
                    if frames >= 7 {
                        self.state = VadState::Speech;
                        VadEvent::SpeechStarted
                    } else {
                        self.state = VadState::PossibleSpeech { frames: frames + 1 };
                        VadEvent::Silence
                    }
                } else {
                    self.state = VadState::Silence;
                    VadEvent::Silence
                }
            }
            VadState::Speech => {
                if probability < self.end_threshold {
                    self.state = VadState::PossibleSilence { frames: 1 };
                }
                VadEvent::SpeechContinuing
            }
            VadState::PossibleSilence { frames } => {
                if probability < self.end_threshold {
                    // ~15 * 32ms = ~480ms silence needed to end speech
                    if frames >= 15 {
                        self.state = VadState::Silence;
                        VadEvent::SpeechEnded
                    } else {
                        self.state = VadState::PossibleSilence { frames: frames + 1 };
                        VadEvent::SpeechContinuing
                    }
                } else {
                    self.state = VadState::Speech;
                    VadEvent::SpeechContinuing
                }
            }
        }
    }

    pub fn state(&self) -> VadState { self.state }

    pub fn is_speech_active(&self) -> bool {
        matches!(self.state, VadState::Speech | VadState::PossibleSilence { .. })
    }

    pub fn reset(&mut self) { self.state = VadState::Silence; }
}

impl Default for VadStateMachine {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vad_starts_silent() {
        let machine = VadStateMachine::new();
        assert_eq!(machine.state(), VadState::Silence);
        assert!(!machine.is_speech_active());
    }

    #[test]
    fn test_vad_silence_below_threshold() {
        let mut machine = VadStateMachine::new();
        for _ in 0..20 {
            let event = machine.process(0.1);
            assert_eq!(event, VadEvent::Silence);
        }
        assert!(!machine.is_speech_active());
    }

    #[test]
    fn test_vad_speech_detection_after_frames() {
        let mut machine = VadStateMachine::new();
        let mut got_speech_started = false;
        for _ in 0..10 {
            let event = machine.process(0.9);
            if event == VadEvent::SpeechStarted {
                got_speech_started = true;
            }
        }
        assert!(got_speech_started);
        assert!(machine.is_speech_active());
    }

    #[test]
    fn test_vad_speech_to_silence() {
        let mut machine = VadStateMachine::new();
        for _ in 0..10 {
            machine.process(0.9);
        }
        assert!(machine.is_speech_active());

        let mut got_speech_ended = false;
        for _ in 0..20 {
            let event = machine.process(0.1);
            if event == VadEvent::SpeechEnded {
                got_speech_ended = true;
            }
        }
        assert!(got_speech_ended);
        assert!(!machine.is_speech_active());
    }

    #[test]
    fn test_vad_reset() {
        let mut machine = VadStateMachine::new();
        for _ in 0..10 { machine.process(0.9); }
        assert!(machine.is_speech_active());
        machine.reset();
        assert!(!machine.is_speech_active());
        assert_eq!(machine.state(), VadState::Silence);
    }

    #[test]
    fn test_vad_brief_silence_doesnt_end_speech() {
        let mut machine = VadStateMachine::new();
        // Get into speech
        for _ in 0..10 { machine.process(0.9); }
        // Brief silence (only 5 frames) -- not enough to end speech
        for _ in 0..5 { machine.process(0.1); }
        // Should still be in possible-silence or speech, not ended
        assert!(!matches!(machine.state(), VadState::Silence));
    }
}
