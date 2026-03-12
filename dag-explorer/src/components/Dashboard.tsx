import { type Component, For, Show, createMemo, onMount } from "solid-js";
import { agentStore } from "../stores/agents";
import { activityStore } from "../stores/activity";
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
      {/* Stats cards */}
      <div class="dashboard-stats">
        <StatCard label="Total Agents" value={agentStore.stats().total} color="var(--signal)" />
        <StatCard label="Running" value={agentStore.stats().running} color="var(--emerge)" />
        <StatCard label="Paused" value={agentStore.stats().paused} color="var(--warm)" />
        <StatCard label="Events" value={agentStore.events().length} color="var(--purple)" />
      </div>

      <div class="dashboard-grid">
        {/* Agent grid */}
        <div class="dashboard-section">
          <h3 class="dashboard-section-title">Agent Overview</h3>
          <div class="dashboard-agent-grid">
            <Show when={agentStore.agents().length > 0} fallback={
              <div class="dashboard-empty">
                No agents. <button class="link-btn" onClick={() => window.dispatchEvent(new CustomEvent("ap:create-agent"))}>Create one</button>
              </div>
            }>
              <For each={agentStore.agents()}>
                {(agent) => <DashboardAgentCard agent={agent} />}
              </For>
            </Show>
          </div>
        </div>

        {/* Event feed */}
        <div class="dashboard-section">
          <h3 class="dashboard-section-title">Live Events</h3>
          <div class="dashboard-event-feed">
            <Show when={recentEvents().length > 0} fallback={
              <div class="dashboard-empty">No events yet</div>
            }>
              <For each={recentEvents()}>
                {(event) => <EventRow event={event} />}
              </For>
            </Show>
          </div>
        </div>

        {/* Platform Health */}
        <div class="dashboard-section">
          <h3 class="dashboard-section-title">Platform Health</h3>
          <ConductorDashboard />
        </div>
      </div>

      {/* Activity Panel — full width */}
      <div class="dashboard-section dashboard-section-full">
        <ActivityPanel />
      </div>

      {/* Cost Dashboard — full width */}
      <div class="dashboard-section dashboard-section-full">
        <CostDashboard />
      </div>
    </div>
  );
};

const StatCard: Component<{ label: string; value: number; color: string }> = (props) => (
  <div class="stat-card">
    <div class="stat-card-value" style={{ color: props.color }}>{props.value}</div>
    <div class="stat-card-label">{props.label}</div>
  </div>
);

const DashboardAgentCard: Component<{ agent: Agent }> = (props) => {
  const stateColor = () => {
    switch (props.agent.state) {
      case "running": return "var(--emerge)";
      case "paused": return "var(--warm)";
      case "stopped": return "var(--danger)";
      default: return "var(--signal)";
    }
  };

  return (
    <button
      class="dashboard-agent-card"
      onClick={() => agentStore.selectAgent(props.agent.id)}
    >
      <div class="dashboard-agent-header">
        <div class="agent-state-dot" style={{ background: stateColor() }} />
        <span class="dashboard-agent-name">{props.agent.name}</span>
      </div>
      <div class="dashboard-agent-state">{props.agent.state}</div>
      <Show when={props.agent.capabilities.length > 0}>
        <div class="dashboard-agent-caps">
          {props.agent.capabilities.slice(0, 3).join(", ")}
        </div>
      </Show>
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
