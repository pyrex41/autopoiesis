import { type Component, For, Show, createSignal, createMemo, onMount } from "solid-js";
import { auditStore } from "../stores/audit";
import { agentStore } from "../stores/agents";
import type { AuditEntry } from "../api/types";

const AuditLog: Component = () => {
  onMount(() => auditStore.init());

  const [agentFilter, setAgentFilter] = createSignal("");
  const [typeFilter, setTypeFilter] = createSignal("");
  const [expandedId, setExpandedId] = createSignal<string | null>(null);
  const [autoRefresh, setAutoRefresh] = createSignal(false);

  // Auto-refresh timer
  let refreshTimer: ReturnType<typeof setInterval> | null = null;
  const toggleAutoRefresh = () => {
    const newVal = !autoRefresh();
    setAutoRefresh(newVal);
    if (newVal) {
      refreshTimer = setInterval(() => auditStore.loadEntries({
        agent: agentFilter() || undefined,
        type: typeFilter() || undefined,
      }), 5000);
    } else if (refreshTimer) {
      clearInterval(refreshTimer);
      refreshTimer = null;
    }
  };

  const filteredEntries = createMemo(() => {
    let entries = auditStore.entries();
    const agent = agentFilter();
    const type = typeFilter();
    if (agent) {
      entries = entries.filter((e) => e.agentId === agent || (e.agentId ?? "").includes(agent));
    }
    if (type) {
      entries = entries.filter((e) => e.type.includes(type));
    }
    return entries;
  });

  const uniqueTypes = createMemo(() => {
    const types = new Set<string>();
    for (const e of auditStore.entries()) {
      types.add(e.type);
    }
    return [...types].sort();
  });

  function handleFilter() {
    auditStore.loadEntries({
      agent: agentFilter() || undefined,
      type: typeFilter() || undefined,
    });
  }

  function exportJson() {
    const data = JSON.stringify(filteredEntries(), null, 2);
    const blob = new Blob([data], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `audit-log-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">ENTRIES</span>
            <span class="sys-indicator-value">{filteredEntries().length}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">TYPES</span>
            <span class="sys-indicator-value">{uniqueTypes().length}</span>
          </div>
        </div>
        <div class="sys-strip-actions">
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": autoRefresh() }}
            onClick={toggleAutoRefresh}
          >
            {autoRefresh() ? "Live" : "Auto-refresh"}
          </button>
          <button class="sys-action-btn" onClick={exportJson}>
            Export JSON
          </button>
        </div>
      </div>

      {/* Filter bar */}
      <div class="audit-filter-bar">
        <select
          class="audit-filter-select"
          onChange={(e) => { setAgentFilter(e.currentTarget.value); handleFilter(); }}
        >
          <option value="">All agents</option>
          <For each={agentStore.agents()}>
            {(a) => <option value={a.id}>{a.name}</option>}
          </For>
        </select>
        <select
          class="audit-filter-select"
          onChange={(e) => { setTypeFilter(e.currentTarget.value); handleFilter(); }}
        >
          <option value="">All types</option>
          <For each={uniqueTypes()}>
            {(t) => <option value={t}>{t}</option>}
          </For>
        </select>
        <button class="audit-reload-btn" onClick={handleFilter}>
          Reload
        </button>
      </div>

      <div class="dashboard-panels">
        <div class="dash-panel audit-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <rect x="2" y="1" width="10" height="12" rx="1.5" stroke="currentColor" stroke-width="1.2"/>
                <path d="M4.5 4h5M4.5 7h5M4.5 10h3" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
              </svg>
              Event History
            </h3>
            <span class="dash-panel-count">{filteredEntries().length}</span>
          </div>
          <Show when={filteredEntries().length > 0} fallback={
            <div class="dash-standby">
              <span class="dash-standby-text">No events match current filters</span>
            </div>
          }>
            {/* Table header */}
            <div class="audit-table-header">
              <span class="audit-col-time">Timestamp</span>
              <span class="audit-col-type">Type</span>
              <span class="audit-col-agent">Agent</span>
              <span class="audit-col-source">Source</span>
            </div>
            <div class="audit-table-body">
              <For each={filteredEntries()}>
                {(entry) => (
                  <div class="audit-row-wrapper">
                    <button
                      class="audit-row"
                      classList={{ "audit-row-expanded": expandedId() === entry.id }}
                      onClick={() => setExpandedId(expandedId() === entry.id ? null : entry.id)}
                    >
                      <span class="audit-col-time">
                        {new Date(entry.timestamp).toLocaleString([], {
                          hour: "2-digit", minute: "2-digit", second: "2-digit",
                          month: "short", day: "numeric",
                        })}
                      </span>
                      <span class="audit-col-type" classList={{
                        "audit-type-error": entry.type.includes("error"),
                        "audit-type-thought": entry.type.includes("thought"),
                        "audit-type-state": entry.type.includes("state"),
                      }}>
                        {entry.type}
                      </span>
                      <span class="audit-col-agent">
                        {entry.agentId ? entry.agentId.slice(0, 8) : "\u2014"}
                      </span>
                      <span class="audit-col-source">{entry.source}</span>
                    </button>
                    <Show when={expandedId() === entry.id}>
                      <div class="audit-detail">
                        <div class="audit-detail-row">
                          <span class="audit-detail-label">Full ID</span>
                          <span class="audit-detail-value">{entry.id}</span>
                        </div>
                        <Show when={entry.agentId}>
                          <div class="audit-detail-row">
                            <span class="audit-detail-label">Agent ID</span>
                            <span class="audit-detail-value">{entry.agentId}</span>
                          </div>
                        </Show>
                        <Show when={entry.data}>
                          <div class="audit-detail-row audit-detail-data">
                            <span class="audit-detail-label">Data</span>
                            <pre class="audit-detail-pre">{entry.data}</pre>
                          </div>
                        </Show>
                      </div>
                    </Show>
                  </div>
                )}
              </For>
            </div>
          </Show>
          <Show when={auditStore.hasMore()}>
            <button
              class="audit-load-more"
              disabled={auditStore.loading()}
              onClick={() => auditStore.loadEntries({ append: true })}
            >
              {auditStore.loading() ? "Loading..." : "Load More"}
            </button>
          </Show>
        </div>
      </div>
    </div>
  );
};

export default AuditLog;
