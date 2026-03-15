import { type Component, For, Show, createMemo, onMount } from "solid-js";
import { agentStore } from "../stores/agents";
import { activityStore } from "../stores/activity";
import { wsStore } from "../stores/ws";
import type { Agent, IntegrationEvent } from "../api/types";
import ConductorDashboard from "./ConductorDashboard";
import ActivityPanel from "./ActivityPanel";
import CostDashboard from "./CostDashboard";

const Dashboard: Component = () => {
  onMount(() => {
    activityStore.init();
  });

  const recentEvents = createMemo(() =>
    agentStore.events().slice(-20).reverse()
  );

  return (
    <div class="dashboard">
      {/* System status strip */}
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">LINK</span>
            <span class="sys-indicator-value" classList={{
              "sys-nominal": wsStore.connected(),
              "sys-fault": !wsStore.connected(),
            }}>
              {wsStore.connected() ? "UP" : "DOWN"}
            </span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">STATUS</span>
            <span class="sys-indicator-value sys-nominal">
              {wsStore.connected() ? "NOMINAL" : "OFFLINE"}
            </span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">AGENTS</span>
            <span class="sys-indicator-value">{agentStore.stats().total}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">ACTIVE</span>
            <span class="sys-indicator-value" classList={{
              "sys-active": agentStore.stats().running > 0,
            }}>{agentStore.stats().running}</span>
          </div>
          <Show when={agentStore.stats().paused > 0}>
            <div class="sys-indicator">
              <span class="sys-indicator-label">PAUSED</span>
              <span class="sys-indicator-value sys-warn">{agentStore.stats().paused}</span>
            </div>
          </Show>
          <div class="sys-indicator">
            <span class="sys-indicator-label">EVENTS</span>
            <span class="sys-indicator-value">{agentStore.events().length}</span>
          </div>
        </div>
        <div class="sys-strip-actions">
          <button
            class="sys-action-btn"
            onClick={() => window.dispatchEvent(new CustomEvent("ap:create-agent"))}
          >
            <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
              <path d="M5 1v8M1 5h8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>
            </svg>
            Deploy
          </button>
        </div>
      </div>

      {/* Scrollable panels */}
      <div class="dashboard-panels">
        {/* Agent roster */}
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <circle cx="7" cy="5" r="3" stroke="currentColor" stroke-width="1.2"/>
                <path d="M2 13c0-2.76 2.24-5 5-5s5 2.24 5 5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
              </svg>
              Agent Roster
            </h3>
            <span class="dash-panel-count">{agentStore.stats().total}</span>
          </div>
          <Show when={agentStore.agents().length > 0} fallback={
            <div class="dash-standby">
              <div class="dash-standby-icon">
                <svg width="28" height="28" viewBox="0 0 32 32" fill="none">
                  <circle cx="16" cy="16" r="12" stroke="var(--border-hi)" stroke-width="1" stroke-dasharray="4 4"/>
                  <circle cx="16" cy="16" r="4" fill="var(--border-hi)" opacity="0.4"/>
                </svg>
              </div>
              <span class="dash-standby-text">No agents deployed</span>
              <button class="dash-standby-action" onClick={() => window.dispatchEvent(new CustomEvent("ap:create-agent"))}>
                Deploy First Agent
              </button>
            </div>
          }>
            <div class="dash-agent-roster">
              <For each={agentStore.agents()}>
                {(agent) => <AgentRosterRow agent={agent} />}
              </For>
            </div>
          </Show>
        </div>

        {/* Event feed */}
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <path d="M7 1v4l2.5 1.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
                <circle cx="7" cy="7" r="6" stroke="currentColor" stroke-width="1.2"/>
              </svg>
              Event Feed
            </h3>
            <span class="dash-panel-count">{agentStore.events().length}</span>
          </div>
          <div class="dash-event-feed">
            <Show when={recentEvents().length > 0} fallback={
              <div class="dash-standby dash-standby-compact">
                <div class="dash-standby-scan" />
                <span class="dash-standby-text">Monitoring — no events captured</span>
              </div>
            }>
              <For each={recentEvents()}>
                {(event) => <EventRow event={event} />}
              </For>
            </Show>
          </div>
        </div>

        {/* Activity */}
        <div class="dash-panel">
          <ActivityPanel />
        </div>

        {/* Cost */}
        <div class="dash-panel">
          <CostDashboard />
        </div>

        {/* Platform health */}
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <rect x="1" y="5" width="3" height="8" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
                <rect x="5.5" y="3" width="3" height="10" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
                <rect x="10" y="1" width="3" height="12" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
              </svg>
              Platform
            </h3>
          </div>
          <ConductorDashboard />
        </div>
      </div>
    </div>
  );
};

const AgentRosterRow: Component<{ agent: Agent }> = (props) => {
  const stateColor = () => {
    switch (props.agent.state) {
      case "running": return "var(--emerge)";
      case "paused": return "var(--warm)";
      case "stopped": return "var(--danger)";
      default: return "var(--text-dim)";
    }
  };

  const stateLabel = () => {
    switch (props.agent.state) {
      case "running": return "RUN";
      case "paused": return "HOLD";
      case "stopped": return "STOP";
      case "initialized": return "INIT";
      default: return props.agent.state?.toUpperCase().slice(0, 4) ?? "—";
    }
  };

  return (
    <button
      class="dash-agent-row"
      onClick={() => agentStore.selectAgent(props.agent.id)}
    >
      <div class="dash-agent-state-pip" style={{ background: stateColor() }} />
      <span class="dash-agent-name">{props.agent.name}</span>
      <span class="dash-agent-state-label" style={{ color: stateColor() }}>{stateLabel()}</span>
      <span class="dash-agent-caps-count">{props.agent.capabilities.length} caps</span>
    </button>
  );
};

const EventRow: Component<{ event: IntegrationEvent }> = (props) => {
  const time = () => new Date(props.event.timestamp).toLocaleTimeString([], {
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });

  const typeColor = () => {
    if (props.event.type.includes("error")) return "var(--danger)";
    if (props.event.type.includes("thought")) return "var(--signal)";
    if (props.event.type.includes("state")) return "var(--warm)";
    return "var(--text-muted)";
  };

  return (
    <div class="event-row">
      <span class="event-time">{time()}</span>
      <span class="event-type" style={{ color: typeColor() }}>{props.event.type}</span>
      <Show when={props.event.agentId}>
        <span class="event-agent">{props.event.agentId}</span>
      </Show>
      <Show when={props.event.data}>
        <span class="event-data">{String(props.event.data).slice(0, 60)}</span>
      </Show>
    </div>
  );
};

export default Dashboard;
