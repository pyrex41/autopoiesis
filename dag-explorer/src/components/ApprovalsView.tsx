import { type Component, For, Show, createSignal, onMount } from "solid-js";
import { approvalsStore } from "../stores/approvals";
import { auditStore } from "../stores/audit";
import type { Approval } from "../api/types";

const ApprovalsView: Component = () => {
  onMount(() => {
    approvalsStore.init();
    auditStore.init();
  });

  const [activeTab, setActiveTab] = createSignal<"pending" | "history">("pending");
  const [agentFilter, setAgentFilter] = createSignal("");

  const filteredApprovals = () => {
    const filter = agentFilter().toLowerCase();
    if (!filter) return approvalsStore.approvals();
    return approvalsStore.approvals().filter((a) =>
      (a.prompt ?? "").toLowerCase().includes(filter) ||
      (a.context ?? "").toLowerCase().includes(filter)
    );
  };

  const approvalHistory = () => {
    return auditStore.entries().filter((e) =>
      e.type.includes("blocking") || e.type.includes("approval")
    );
  };

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">PENDING</span>
            <span class="sys-indicator-value" classList={{
              "sys-warn": approvalsStore.pendingCount() > 0,
            }}>
              {approvalsStore.pendingCount()}
            </span>
          </div>
        </div>
        <div class="sys-strip-actions">
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": activeTab() === "pending" }}
            onClick={() => setActiveTab("pending")}
          >
            Pending
          </button>
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": activeTab() === "history" }}
            onClick={() => setActiveTab("history")}
          >
            History
          </button>
        </div>
      </div>

      <Show when={activeTab() === "pending"}>
        <div class="approvals-filter-bar">
          <input
            type="text"
            class="approvals-filter-input"
            placeholder="Filter approvals..."
            value={agentFilter()}
            onInput={(e) => setAgentFilter(e.currentTarget.value)}
          />
        </div>
        <div class="dashboard-panels">
          <div class="dash-panel approvals-panel">
            <div class="dash-panel-header">
              <h3 class="dash-panel-title">
                <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                  <rect x="1" y="2" width="12" height="10" rx="1.5" stroke="currentColor" stroke-width="1.2"/>
                  <path d="M4 7l2 2 4-4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
                Pending Approvals
              </h3>
              <span class="dash-panel-count">{filteredApprovals().length}</span>
            </div>
            <Show when={filteredApprovals().length > 0} fallback={
              <div class="dash-standby">
                <div class="dash-standby-scan" />
                <span class="dash-standby-text">No pending approvals</span>
              </div>
            }>
              <div class="approvals-list">
                <For each={filteredApprovals()}>
                  {(approval) => <ApprovalCard approval={approval} />}
                </For>
              </div>
            </Show>
          </div>
        </div>
      </Show>

      <Show when={activeTab() === "history"}>
        <div class="dashboard-panels">
          <div class="dash-panel">
            <div class="dash-panel-header">
              <h3 class="dash-panel-title">Approval History</h3>
              <span class="dash-panel-count">{approvalHistory().length}</span>
            </div>
            <Show when={approvalHistory().length > 0} fallback={
              <div class="dash-standby dash-standby-compact">
                <span class="dash-standby-text">No approval history</span>
              </div>
            }>
              <div class="approvals-history">
                <For each={approvalHistory()}>
                  {(entry) => (
                    <div class="approval-history-row">
                      <span class="approval-history-time">
                        {new Date(entry.timestamp).toLocaleString()}
                      </span>
                      <span class="approval-history-type">{entry.type}</span>
                      <Show when={entry.agentId}>
                        <span class="approval-history-agent">{entry.agentId}</span>
                      </Show>
                    </div>
                  )}
                </For>
              </div>
            </Show>
          </div>
        </div>
      </Show>
    </div>
  );
};

const ApprovalCard: Component<{ approval: Approval }> = (props) => {
  const [responding, setResponding] = createSignal(false);
  const [responseText, setResponseText] = createSignal("");
  const [rejectReason, setRejectReason] = createSignal("");

  const age = () => {
    const ms = Date.now() - props.approval.createdAt;
    const secs = Math.floor(ms / 1000);
    if (secs < 60) return `${secs}s ago`;
    const mins = Math.floor(secs / 60);
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    return `${hrs}h ${mins % 60}m ago`;
  };

  async function handleApprove() {
    await approvalsStore.approve(props.approval.id, responseText() || undefined);
    setResponding(false);
    setResponseText("");
  }

  async function handleReject() {
    await approvalsStore.reject(props.approval.id, rejectReason() || undefined);
    setResponding(false);
    setRejectReason("");
  }

  return (
    <div class="approval-card">
      <div class="approval-card-header">
        <span class="approval-card-age">{age()}</span>
        <span class="approval-card-status">{props.approval.status.toUpperCase()}</span>
      </div>
      <div class="approval-card-prompt">{props.approval.prompt || "Human input requested"}</div>
      <Show when={props.approval.context}>
        <div class="approval-card-context">{props.approval.context}</div>
      </Show>
      <Show when={props.approval.options && props.approval.options.length > 0}>
        <div class="approval-card-options">
          <For each={props.approval.options}>
            {(opt) => (
              <button
                class="approval-option-btn"
                onClick={() => approvalsStore.approve(props.approval.id, opt)}
              >
                {opt}
              </button>
            )}
          </For>
        </div>
      </Show>
      <Show when={!responding()} fallback={
        <div class="approval-respond-form">
          <div class="approval-respond-row">
            <input
              type="text"
              class="approval-respond-input"
              placeholder="Response (optional)..."
              value={responseText()}
              onInput={(e) => setResponseText(e.currentTarget.value)}
              onKeyDown={(e) => { if (e.key === "Enter") handleApprove(); }}
            />
            <button class="approval-approve-btn" onClick={handleApprove}>Approve</button>
          </div>
          <div class="approval-respond-row">
            <input
              type="text"
              class="approval-reject-input"
              placeholder="Rejection reason..."
              value={rejectReason()}
              onInput={(e) => setRejectReason(e.currentTarget.value)}
              onKeyDown={(e) => { if (e.key === "Enter") handleReject(); }}
            />
            <button class="approval-reject-btn" onClick={handleReject}>Reject</button>
          </div>
          <button class="approval-cancel-btn" onClick={() => setResponding(false)}>Cancel</button>
        </div>
      }>
        <div class="approval-card-actions">
          <button class="approval-approve-btn" onClick={handleApprove}>Approve</button>
          <button class="approval-respond-btn" onClick={() => setResponding(true)}>Respond</button>
          <button class="approval-reject-btn" onClick={handleReject}>Reject</button>
        </div>
      </Show>
    </div>
  );
};

export default ApprovalsView;
