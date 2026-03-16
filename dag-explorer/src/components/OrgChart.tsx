import { type Component, onMount } from "solid-js";
import { orgStore } from "../stores/org";

const OrgChart: Component = () => {
  onMount(() => orgStore.init());

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">DEPTS</span>
            <span class="sys-indicator-value">{orgStore.departments().length}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">GOALS</span>
            <span class="sys-indicator-value">{orgStore.goals().length}</span>
          </div>
        </div>
      </div>
      <div class="dashboard-panels">
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">Org Chart</h3>
          </div>
          <div class="dash-standby">
            <span class="dash-standby-text">Org chart placeholder — Phase 3</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default OrgChart;
