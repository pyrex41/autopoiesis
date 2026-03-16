import { type Component, onMount } from "solid-js";
import { approvalsStore } from "../stores/approvals";

const ApprovalsView: Component = () => {
  onMount(() => approvalsStore.init());

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">PENDING</span>
            <span class="sys-indicator-value">{approvalsStore.pendingCount()}</span>
          </div>
        </div>
      </div>
      <div class="dashboard-panels">
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">Approvals</h3>
          </div>
          <div class="dash-standby">
            <span class="dash-standby-text">Approvals view placeholder — Phase 4</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ApprovalsView;
