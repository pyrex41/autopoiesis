import { type Component, Show, For } from "solid-js";
import { holodeckStore, type CameraPreset } from "../stores/holodeck";
import { cameraPresetFns } from "./HolodeckView";

const phaseClass = (phase: string) => {
  const valid = ["observe", "reason", "decide", "act", "reflect"];
  return valid.includes(phase) ? `hud-phase-${phase}` : "hud-phase-default";
};

const HolodeckHUD: Component = () => {
  return (
    <Show when={holodeckStore.hudVisible()}>
      <div class="holodeck-hud holodeck-hud-overlay">
        {/* Top-left: FPS + stats */}
        <div class="hud-top-left">
          <div class="hud-stat-panel">
            <span class="hud-stat-label">FPS</span>
            <span class="hud-stat-value">{holodeckStore.fps()}</span>
          </div>
          <div class="hud-stat-panel">
            <span class="hud-stat-label">Entities</span>
            <span class="hud-stat-value">{holodeckStore.entityCount()}</span>
          </div>
          <div class="hud-stat-panel">
            <span class="hud-stat-label">Connections</span>
            <span class="hud-stat-value">{holodeckStore.connectionCount()}</span>
          </div>
        </div>

        {/* Top-right: View mode */}
        <div class="hud-top-right">
          <div class="hud-stat-panel">
            <span class="hud-stat-label">Mode</span>
            <span class="hud-stat-value">{holodeckStore.viewMode()}</span>
          </div>
        </div>

        {/* Bottom-left: Selected entity info */}
        <Show when={holodeckStore.selectedEntity()}>
          {(entity) => (
            <div class="hud-bottom-left">
              <div class="hud-stat-panel hud-stat-panel-wide">
                <div class="hud-entity-header">
                  <span class="hud-entity-kind">{entity().kind}</span>
                  <span class="hud-entity-name">{entity().label || `#${entity().id}`}</span>
                </div>
                <Show when={entity().agentId}>
                  <div class="hud-entity-row">
                    <span class="hud-stat-label">Agent</span>
                    <span class="hud-small-value">{entity().agentId}</span>
                  </div>
                </Show>
                <Show when={entity().cognitivePhase}>
                  <div class="hud-entity-row">
                    <span class="hud-stat-label">Phase</span>
                    <span class={phaseClass(entity().cognitivePhase!)}>{entity().cognitivePhase}</span>
                  </div>
                </Show>
                <div class="hud-entity-row">
                  <span class="hud-stat-label">Position</span>
                  <span class="hud-small-value">
                    {entity().position.map((v) => v.toFixed(1)).join(", ")}
                  </span>
                </div>
              </div>
            </div>
          )}
        </Show>

        {/* Bottom-right: Camera presets */}
        <div class="hud-presets">
          <For each={["orbital", "ground", "follow", "cinematic"] as CameraPreset[]}>
            {(preset) => (
              <button
                class="hud-preset-btn"
                classList={{ "hud-preset-active": holodeckStore.cameraPreset() === preset }}
                onClick={() => cameraPresetFns[preset]()}
              >
                {preset.charAt(0).toUpperCase() + preset.slice(1)}
              </button>
            )}
          </For>
        </div>
      </div>
    </Show>
  );
};

export default HolodeckHUD;
