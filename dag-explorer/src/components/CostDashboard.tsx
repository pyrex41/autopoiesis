import { type Component, For, Show, createMemo } from "solid-js";
import { activityStore } from "../stores/activity";

const CostDashboard: Component = () => {
  const maxCost = createMemo(() => {
    const agents = activityStore.costByAgent();
    if (agents.length === 0) return 1;
    return Math.max(...agents.map((a) => a.cost), 0.0001);
  });

  return (
    <div class="cost-dashboard">
      <h3 class="dashboard-section-title">Cost Tracking</h3>

      {/* Summary cards */}
      <div class="cost-summary-cards">
        <div class="cost-summary-card">
          <div class="cost-summary-value" style={{ color: "var(--warm)" }}>
            ${activityStore.totalCost().toFixed(4)}
          </div>
          <div class="cost-summary-label">Total Cost</div>
        </div>
        <div class="cost-summary-card">
          <div class="cost-summary-value" style={{ color: "var(--signal)" }}>
            {formatTokens(activityStore.totalTokens())}
          </div>
          <div class="cost-summary-label">Total Tokens</div>
        </div>
        <div class="cost-summary-card">
          <div class="cost-summary-value" style={{ color: "var(--purple)" }}>
            {activityStore.totalCalls()}
          </div>
          <div class="cost-summary-label">API Calls</div>
        </div>
      </div>

      {/* Per-agent breakdown */}
      <Show
        when={activityStore.costByAgent().length > 0}
        fallback={<div class="dashboard-empty">No cost data yet</div>}
      >
        <div class="cost-agent-list">
          <For each={activityStore.costByAgent()}>
            {(agent) => (
              <div class="cost-agent-row">
                <div class="cost-agent-info">
                  <span class="cost-agent-name">{agent.agentName}</span>
                  <span class="cost-agent-detail">
                    {formatTokens(agent.tokens)} tokens / {agent.calls} calls
                  </span>
                </div>
                <div class="cost-agent-bar-wrap">
                  <div
                    class="cost-agent-bar"
                    style={{ width: `${Math.max((agent.cost / maxCost()) * 100, 2)}%` }}
                  />
                </div>
                <span class="cost-agent-amount">${agent.cost.toFixed(4)}</span>
              </div>
            )}
          </For>
        </div>
      </Show>
    </div>
  );
};

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

export default CostDashboard;
