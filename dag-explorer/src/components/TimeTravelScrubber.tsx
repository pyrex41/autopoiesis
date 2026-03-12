import { type Component, Show, For, onCleanup } from "solid-js";
import { timeTravelStore } from "../stores/timetravel";
import "../styles/timetravel.css";

const TimeTravelScrubber: Component = () => {
  const snaps = () => timeTravelStore.sortedSnapshots();
  const total = () => snaps().length;
  const idx = () => timeTravelStore.currentIdx();

  const playheadPct = () => total() > 1 ? (idx() / (total() - 1)) * 100 : 0;

  const currentSnap = () => snaps()[idx()];

  const formatTime = (ts: number) => {
    const d = new Date(ts);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  onCleanup(() => timeTravelStore.pause());

  return (
    <div class="timetravel-scrubber">
      <div class="timetravel-controls">
        <button
          class="timetravel-play-btn"
          onClick={() => timeTravelStore.playing() ? timeTravelStore.pause() : timeTravelStore.play()}
          title={timeTravelStore.playing() ? "Pause" : "Play"}
        >
          {timeTravelStore.playing() ? "⏸" : "▶"}
        </button>
        <button
          class="timetravel-speed"
          onClick={() => timeTravelStore.toggleSpeed()}
          title="Playback speed"
        >
          {timeTravelStore.playbackSpeed()}x
        </button>
      </div>

      <div class="timetravel-track-wrap">
        <div class="timetravel-track">
          <For each={snaps()}>
            {(snap, i) => (
              <div
                class="timetravel-marker"
                classList={{ active: i() === idx() }}
                style={{ left: `${total() > 1 ? (i() / (total() - 1)) * 100 : 0}%` }}
                onClick={() => timeTravelStore.seek(i())}
                title={snap.id}
              />
            )}
          </For>
          <div
            class="timetravel-playhead"
            style={{ left: `${playheadPct()}%` }}
          />
        </div>
        <input
          class="timetravel-range"
          type="range"
          min={0}
          max={Math.max(0, total() - 1)}
          value={idx()}
          onInput={(e) => timeTravelStore.seek(parseInt(e.currentTarget.value))}
        />
      </div>

      <div class="timetravel-info">
        <Show when={currentSnap()}>
          {(snap) => (
            <>
              {idx() + 1}/{total()} {formatTime(snap().timestamp)}
            </>
          )}
        </Show>
      </div>
    </div>
  );
};

export default TimeTravelScrubber;
