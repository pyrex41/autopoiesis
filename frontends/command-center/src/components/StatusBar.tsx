import { type Component, Show, createMemo } from "solid-js";
import { wsStore } from "../stores/ws";
import { agentStore } from "../stores/agents";
import { conductorStore } from "../stores/conductor";
import { activityStore } from "../stores/activity";
import ConnectionIndicator from "./ConnectionIndicator";
import AudioToggle from "./AudioToggle";

const StatusBar: Component = () => {
  const pulseIntensity = createMemo(() => {
    const activeCount = activityStore.activeAgents().length;
    const metrics = conductorStore.metrics();
    const eventsProcessed = metrics?.eventsProcessed ?? 0;
    let intensity = 0.1;
    if (activeCount >= 4) intensity = 0.8;
    else if (activeCount >= 1) intensity = 0.4;
    if (eventsProcessed > 100) intensity = Math.max(intensity, 1.0);
    return intensity;
  });

  return (
    <div class="status-bar" style={{ "--pulse-intensity": pulseIntensity() }}>
      <div class="status-bar-left">
        <span class="status-bar-brand">AUTOPOIESIS</span>
        <div class="status-bar-sep" />
        <ConnectionIndicator />
        <Show when={agentStore.error()}>
          <span class="status-bar-error" title={agentStore.error()!}>
            {agentStore.error()!.slice(0, 50)}
          </span>
        </Show>
      </div>
      <div class="status-bar-right">
        <div class="status-bar-metrics">
          <span class="status-metric">
            <span class="status-metric-val">{agentStore.stats().total}</span>
            <span class="status-metric-label">agents</span>
          </span>
          <span class="status-metric">
            <span class="status-metric-val stat-running">{agentStore.stats().running}</span>
            <span class="status-metric-label">running</span>
          </span>
          <Show when={agentStore.stats().paused > 0}>
            <span class="status-metric">
              <span class="status-metric-val stat-paused">{agentStore.stats().paused}</span>
              <span class="status-metric-label">paused</span>
            </span>
          </Show>
          <span class="status-metric">
            <span class="status-metric-val">{agentStore.events().length}</span>
            <span class="status-metric-label">events</span>
          </span>
        </div>
        <AudioToggle />
      </div>
    </div>
  );
};

export default StatusBar;
