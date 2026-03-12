import { type Component, Show } from "solid-js";
import { wsStore } from "../stores/ws";
import { agentStore } from "../stores/agents";
import ConnectionIndicator from "./ConnectionIndicator";

const StatusBar: Component = () => {
  return (
    <div class="status-bar">
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
      </div>
    </div>
  );
};

export default StatusBar;
