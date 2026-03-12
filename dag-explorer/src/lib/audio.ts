import { createSignal } from "solid-js";

const STORAGE_KEY = "ap-audio-enabled";

const [enabled, setEnabled] = createSignal(
  localStorage.getItem(STORAGE_KEY) === "true"
);

let ctx: AudioContext | null = null;

function getContext(): AudioContext | null {
  if (!ctx) {
    try {
      ctx = new AudioContext();
    } catch {
      return null;
    }
  }
  if (ctx.state === "suspended") {
    ctx.resume();
  }
  return ctx;
}

function playTone(
  freq: number,
  duration: number,
  type: OscillatorType = "sine",
  volume = 0.1
) {
  if (!enabled()) return;
  const ac = getContext();
  if (!ac) return;

  const osc = ac.createOscillator();
  const gain = ac.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  gain.gain.value = volume;
  osc.connect(gain);
  gain.connect(ac.destination);

  const now = ac.currentTime;
  osc.start(now);
  osc.stop(now + duration / 1000);
}

function playTwoNote(f1: number, f2: number, ms: number, type: OscillatorType = "sine", vol = 0.1) {
  if (!enabled()) return;
  const ac = getContext();
  if (!ac) return;

  const osc = ac.createOscillator();
  const gain = ac.createGain();
  osc.type = type;
  osc.frequency.value = f1;
  gain.gain.value = vol;
  osc.connect(gain);
  gain.connect(ac.destination);

  const now = ac.currentTime;
  const dur = ms / 1000;
  osc.frequency.setValueAtTime(f1, now);
  osc.frequency.setValueAtTime(f2, now + dur);
  osc.start(now);
  osc.stop(now + dur * 2);
}

export const audioEngine = {
  isEnabled: enabled,

  toggle() {
    const next = !enabled();
    setEnabled(next);
    localStorage.setItem(STORAGE_KEY, String(next));
    // Init context on first enable (requires user gesture)
    if (next) getContext();
  },

  /** Ascending C5 -> E5 */
  agentStart() {
    playTwoNote(523, 659, 100);
  },

  /** Descending E5 -> C5 */
  agentStop() {
    playTwoNote(659, 523, 100);
  },

  /** Soft chime A5 */
  notification() {
    playTone(880, 150, "triangle", 0.08);
  },

  /** Subtle tick C6 */
  select() {
    playTone(1047, 30, "square", 0.03);
  },

  /** Low buzz A3 */
  error() {
    playTone(220, 200, "sawtooth", 0.08);
  },
};
