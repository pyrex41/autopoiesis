import { type Component, onMount } from "solid-js";
import { budgetStore } from "../stores/budget";
import { activityStore } from "../stores/activity";

const BudgetDashboard: Component = () => {
  onMount(() => {
    activityStore.init();
    budgetStore.init();
  });

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">TOTAL SPEND</span>
            <span class="sys-indicator-value">${budgetStore.totalSpend().toFixed(2)}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">TOTAL LIMIT</span>
            <span class="sys-indicator-value">${budgetStore.totalLimit().toFixed(2)}</span>
          </div>
        </div>
      </div>
      <div class="dashboard-panels">
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">Budget Dashboard</h3>
          </div>
          <div class="dash-standby">
            <span class="dash-standby-text">Budget dashboard placeholder — Phase 3</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default BudgetDashboard;
