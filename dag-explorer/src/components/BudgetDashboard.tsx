import { type Component, For, Show, createSignal, onMount } from "solid-js";
import { budgetStore } from "../stores/budget";
import { activityStore } from "../stores/activity";

const BudgetDashboard: Component = () => {
  onMount(() => {
    activityStore.init();
    budgetStore.init();
  });

  const [sortBy, setSortBy] = createSignal<"name" | "spent" | "pct">("spent");

  const sortedBudgets = () => {
    const items = [...budgetStore.mergedBudgets()];
    switch (sortBy()) {
      case "name": return items.sort((a, b) => (a.agentName ?? "").localeCompare(b.agentName ?? ""));
      case "pct": return items.sort((a, b) => b.pctUsed - a.pctUsed);
      default: return items; // already sorted by spent
    }
  };

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">TOTAL SPEND</span>
            <span class="sys-indicator-value">${budgetStore.totalSpend().toFixed(4)}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">TOTAL BUDGET</span>
            <span class="sys-indicator-value">
              {budgetStore.totalLimit() > 0 ? `$${budgetStore.totalLimit().toFixed(2)}` : "No limits set"}
            </span>
          </div>
          <Show when={budgetStore.totalLimit() > 0}>
            <div class="sys-indicator">
              <span class="sys-indicator-label">UTILIZATION</span>
              <span class="sys-indicator-value" classList={{
                "sys-warn": budgetStore.totalSpend() / budgetStore.totalLimit() > 0.8,
                "sys-fault": budgetStore.totalSpend() / budgetStore.totalLimit() > 1,
              }}>
                {((budgetStore.totalSpend() / budgetStore.totalLimit()) * 100).toFixed(1)}%
              </span>
            </div>
          </Show>
          <div class="sys-indicator">
            <span class="sys-indicator-label">TRACKED</span>
            <span class="sys-indicator-value">{budgetStore.mergedBudgets().length}</span>
          </div>
        </div>
        <div class="sys-strip-actions">
          <select class="budget-sort-select" onChange={(e) => setSortBy(e.currentTarget.value as any)}>
            <option value="spent">Sort: Spend</option>
            <option value="pct">Sort: % Used</option>
            <option value="name">Sort: Name</option>
          </select>
        </div>
      </div>

      <div class="dashboard-panels">
        <div class="dash-panel budget-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <circle cx="7" cy="7" r="5.5" stroke="currentColor" stroke-width="1.2"/>
                <path d="M7 3.5v7M5 5.5h3a1 1 0 010 2H5.5a1 1 0 000 2H9" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
              </svg>
              Per-Agent Budgets
            </h3>
            <span class="dash-panel-count">{sortedBudgets().length}</span>
          </div>
          <Show when={sortedBudgets().length > 0} fallback={
            <div class="dash-standby">
              <span class="dash-standby-text">No cost data yet -- start an agent to begin tracking</span>
            </div>
          }>
            <div class="budget-list">
              <For each={sortedBudgets()}>
                {(b) => <BudgetRow budget={b} />}
              </For>
            </div>
          </Show>
        </div>
      </div>
    </div>
  );
};

const BudgetRow: Component<{ budget: { entityId: string; agentName?: string; spent: number; limit: number | null; currency: string; pctUsed: number } }> = (props) => {
  const [editing, setEditing] = createSignal(false);
  const [limitInput, setLimitInput] = createSignal("");

  const barWidth = () => {
    if (!props.budget.limit) return 0;
    return Math.min(100, props.budget.pctUsed);
  };

  const barColor = () => {
    if (!props.budget.limit) return "var(--signal)";
    if (props.budget.pctUsed >= 100) return "var(--danger)";
    if (props.budget.pctUsed >= 80) return "var(--warm)";
    return "var(--emerge)";
  };

  async function saveLimit() {
    const val = parseFloat(limitInput());
    if (!isNaN(val) && val > 0) {
      await budgetStore.setLimit(props.budget.entityId, val);
    }
    setEditing(false);
  }

  return (
    <div class="budget-row">
      <div class="budget-row-header">
        <span class="budget-agent-name">{props.budget.agentName ?? props.budget.entityId.slice(0, 8)}</span>
        <span class="budget-spent">${props.budget.spent.toFixed(4)}</span>
        <Show when={props.budget.limit !== null}>
          <span class="budget-separator">/</span>
          <span class="budget-limit">${props.budget.limit!.toFixed(2)}</span>
          <span class="budget-pct" classList={{
            "budget-warn": props.budget.pctUsed >= 80 && props.budget.pctUsed < 100,
            "budget-exceeded": props.budget.pctUsed >= 100,
          }}>
            {props.budget.pctUsed.toFixed(1)}%
          </span>
        </Show>
        <Show when={!editing()} fallback={
          <div class="budget-edit-form">
            <input
              type="number"
              class="budget-edit-input"
              placeholder="Limit"
              value={limitInput()}
              onInput={(e) => setLimitInput(e.currentTarget.value)}
              onKeyDown={(e) => { if (e.key === "Enter") saveLimit(); if (e.key === "Escape") setEditing(false); }}
            />
            <button class="budget-edit-save" onClick={saveLimit}>Set</button>
          </div>
        }>
          <button class="budget-set-limit-btn" onClick={() => {
            setLimitInput(props.budget.limit?.toString() ?? "");
            setEditing(true);
          }}>
            {props.budget.limit !== null ? "Edit" : "Set Limit"}
          </button>
        </Show>
      </div>
      <div class="budget-bar-track">
        <div
          class="budget-bar-fill"
          style={{
            width: `${props.budget.limit ? barWidth() : 100}%`,
            background: barColor(),
            opacity: props.budget.limit ? 1 : 0.3,
          }}
        />
        <Show when={props.budget.limit}>
          <div class="budget-bar-threshold budget-bar-80" style={{ left: "80%" }} />
        </Show>
      </div>
    </div>
  );
};

export default BudgetDashboard;
