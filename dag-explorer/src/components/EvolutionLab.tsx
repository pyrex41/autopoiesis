import { type Component, onMount } from "solid-js";
import { evolutionStore } from "../stores/evolution";

const EvolutionLab: Component = () => {
  onMount(() => evolutionStore.init());

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">STATUS</span>
            <span class="sys-indicator-value">{evolutionStore.evolution().running ? "RUNNING" : "IDLE"}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">GEN</span>
            <span class="sys-indicator-value">{evolutionStore.evolution().generation}</span>
          </div>
        </div>
      </div>
      <div class="dashboard-panels">
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">Evolution Lab</h3>
          </div>
          <div class="dash-standby">
            <span class="dash-standby-text">Evolution lab placeholder — Phase 5</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default EvolutionLab;
