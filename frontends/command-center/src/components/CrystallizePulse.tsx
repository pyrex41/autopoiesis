import { type Component, Show, createSignal, createEffect, on } from "solid-js";
import { conductorStore } from "../stores/conductor";
import "../styles/crystallize.css";

const CrystallizePulse: Component = () => {
  const [pulsing, setPulsing] = createSignal(false);
  let prevCount = conductorStore.metrics()?.crystallizations ?? 0;

  createEffect(
    on(
      () => conductorStore.metrics()?.crystallizations,
      (count) => {
        if (count != null && count > prevCount) {
          setPulsing(true);
          setTimeout(() => setPulsing(false), 2000);
        }
        prevCount = count ?? 0;
      }
    )
  );

  return (
    <Show when={pulsing()}>
      <div class="crystallize-overlay">
        <div class="crystallize-pulse" />
        <div class="crystallize-ring" />
      </div>
    </Show>
  );
};

export default CrystallizePulse;
