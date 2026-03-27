import { type Component } from "solid-js";
import { audioEngine } from "../lib/audio";

const AudioToggle: Component = () => {
  return (
    <button
      class="audio-toggle"
      onClick={() => audioEngine.toggle()}
      title={audioEngine.isEnabled() ? "Mute audio cues" : "Enable audio cues"}
    >
      {audioEngine.isEnabled() ? "\u{1F50A}" : "\u{1F507}"}
    </button>
  );
};

export default AudioToggle;
