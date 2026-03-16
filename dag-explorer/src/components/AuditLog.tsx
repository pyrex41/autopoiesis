import { type Component, onMount } from "solid-js";
import { auditStore } from "../stores/audit";

const AuditLog: Component = () => {
  onMount(() => auditStore.init());

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">ENTRIES</span>
            <span class="sys-indicator-value">{auditStore.entries().length}</span>
          </div>
        </div>
      </div>
      <div class="dashboard-panels">
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">Audit Log</h3>
          </div>
          <div class="dash-standby">
            <span class="dash-standby-text">Audit log placeholder — Phase 5</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AuditLog;
