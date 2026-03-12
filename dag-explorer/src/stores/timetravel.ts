import { createSignal, createMemo } from "solid-js";
import { dagStore } from "./dag";

const [currentIdx, setCurrentIdx] = createSignal(0);
const [playing, setPlaying] = createSignal(false);
const [playbackSpeed, setPlaybackSpeed] = createSignal<1 | 2 | 4>(1);

let playInterval: ReturnType<typeof setInterval> | null = null;

const sortedSnapshots = createMemo(() => {
  return [...dagStore.snapshots()].sort((a, b) => a.timestamp - b.timestamp);
});

function seek(idx: number) {
  const snaps = sortedSnapshots();
  if (snaps.length === 0) return;
  const clamped = Math.max(0, Math.min(snaps.length - 1, idx));
  setCurrentIdx(clamped);
  dagStore.selectNode(snaps[clamped].id);
}

function play() {
  if (playInterval) clearInterval(playInterval);
  setPlaying(true);
  playInterval = setInterval(() => {
    const snaps = sortedSnapshots();
    const next = currentIdx() + 1;
    if (next >= snaps.length) {
      pause();
      return;
    }
    seek(next);
  }, 1000 / playbackSpeed());
}

function pause() {
  setPlaying(false);
  if (playInterval) {
    clearInterval(playInterval);
    playInterval = null;
  }
}

function toggleSpeed() {
  const speeds: (1 | 2 | 4)[] = [1, 2, 4];
  const cur = speeds.indexOf(playbackSpeed());
  const next = speeds[(cur + 1) % speeds.length];
  setPlaybackSpeed(next);
  if (playing()) {
    pause();
    play();
  }
}

export const timeTravelStore = {
  currentIdx,
  playing,
  playbackSpeed,
  sortedSnapshots,
  seek,
  play,
  pause,
  toggleSpeed,
};
