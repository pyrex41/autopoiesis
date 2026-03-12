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

    // Base intensity from active agent count
    let intensity = 0.1; // idle glow
    if (activeCount >= 4) intensity = 0.8;
    else if (activeCount >= 1) intensity = 0.4;

    // Spike on high event throughput
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
        <span class="status-bar-stat">
          <span class="stat-value">{agentStore.stats().total}</span> agents
        </span>
        <span class="status-bar-stat">
          <span class="stat-value stat-running">{agentStore.stats().running}</span> running
        </span>
        <Show when={agentStore.stats().paused > 0}>
          <span class="status-bar-stat">
            <span class="stat-value stat-paused">{agentStore.stats().paused}</span> paused
          </span>
        </Show>
        <span class="status-bar-stat">
          <span class="stat-value">{agentStore.events().length}</span> events
        </span>
        <AudioToggle />
      </div>
    </div>
  );
};

export default StatusBar;
