import { type Component, For, Show, createMemo, createSignal } from "solid-js";
import { agentStore, type Thought } from "../stores/agents";
import type { IntegrationEvent } from "../api/types";
import EmptyState from "./EmptyState";

interface TimelineEntry {
  id: string;
  timestamp: number;
  type: "thought" | "event";
  subtype: string;
  agentId?: string;
  content: string;
}

const TimelineView: Component = () => {
  const [agentFilter, setAgentFilter] = createSignal("");
  const [typeFilter, setTypeFilter] = createSignal<"all" | "thought" | "event">("all");
  const [subtypeFilter, setSubtypeFilter] = createSignal("");
  const [searchText, setSearchText] = createSignal("");

  const allEntries = createMemo<TimelineEntry[]>(() => {
    const items: TimelineEntry[] = [];

    for (const t of agentStore.thoughts()) {
      items.push({
        id: t.id,
        timestamp: t.timestamp,
        type: "thought",
        subtype: t.type,
        agentId: t.agentId,
        content: t.content,
      });
    }

    for (const e of agentStore.events()) {
      items.push({
        id: e.id,
        timestamp: e.timestamp,
        type: "event",
        subtype: e.type,
        agentId: e.agentId ?? undefined,
        content: e.data ? String(e.data).slice(0, 200) : e.type,
      });
    }

    items.sort((a, b) => b.timestamp - a.timestamp);
    return items;
  });

  const uniqueSubtypes = createMemo(() => {
    const set = new Set<string>();
    for (const e of allEntries()) set.add(e.subtype);
    return [...set].sort();
  });

  const entries = createMemo<TimelineEntry[]>(() => {
    let items = allEntries();
    const agent = agentFilter();
    const type = typeFilter();
    const subtype = subtypeFilter();
    const search = searchText().toLowerCase();

    if (agent) items = items.filter(e => e.agentId === agent);
    if (type !== "all") items = items.filter(e => e.type === type);
    if (subtype) items = items.filter(e => e.subtype === subtype);
    if (search) items = items.filter(e => e.content.toLowerCase().includes(search));

    return items.slice(0, 200);
  });

  const formatTime = (ts: number) => {
    const d = new Date(ts);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  const subtypeColor = (entry: TimelineEntry) => {
    if (entry.type === "thought") {
      switch (entry.subtype) {
        case "observation": return "var(--signal)";
        case "decision": return "var(--warm)";
        case "action": return "var(--emerge)";
        case "reflection": return "var(--purple)";
      }
    }
    if (entry.subtype.includes("error")) return "var(--danger)";
    if (entry.subtype.includes("state")) return "var(--warm)";
    return "var(--text-muted)";
  };

  return (
    <div class="timeline-view">
      <div class="timeline-header">
        <h2 class="timeline-title">Timeline</h2>
        <span class="timeline-count">{entries().length} entries</span>
      </div>

      <div class="timeline-filters">
        <div class="timeline-filter-group">
          <span class="timeline-filter-label">Agent</span>
          <select
            class="timeline-filter-select"
            value={agentFilter()}
            onChange={e => setAgentFilter(e.currentTarget.value)}
          >
            <option value="">All</option>
            <For each={agentStore.agents()}>
              {(a) => <option value={a.id}>{a.name || a.id}</option>}
            </For>
          </select>
        </div>

        <div class="timeline-filter-group">
          <span class="timeline-filter-label">Type</span>
          <button
            class="timeline-filter-btn"
            classList={{ "timeline-filter-active": typeFilter() === "all" }}
            onClick={() => setTypeFilter("all")}
          >All</button>
          <button
            class="timeline-filter-btn"
            classList={{ "timeline-filter-active": typeFilter() === "thought" }}
            onClick={() => setTypeFilter("thought")}
          >Thoughts</button>
          <button
            class="timeline-filter-btn"
            classList={{ "timeline-filter-active": typeFilter() === "event" }}
            onClick={() => setTypeFilter("event")}
          >Events</button>
        </div>

        <div class="timeline-filter-group">
          <span class="timeline-filter-label">Subtype</span>
          <select
            class="timeline-filter-select"
            value={subtypeFilter()}
            onChange={e => setSubtypeFilter(e.currentTarget.value)}
          >
            <option value="">All</option>
            <For each={uniqueSubtypes()}>
              {(s) => <option value={s}>{s}</option>}
            </For>
          </select>
        </div>

        <div class="timeline-filter-group">
          <input
            class="timeline-search"
            type="text"
            placeholder="Search..."
            value={searchText()}
            onInput={e => setSearchText(e.currentTarget.value)}
          />
        </div>
      </div>

      <div class="timeline-scroll">
        <Show when={entries().length > 0} fallback={
          <EmptyState
            icon="radar"
            title="No Events"
            description="Events and thoughts will appear here as agents run."
          />
        }>
          <For each={entries()}>
            {(entry) => (
              <div class="timeline-entry">
                <div class="timeline-entry-time">{formatTime(entry.timestamp)}</div>
                <div class="timeline-entry-dot" style={{ background: subtypeColor(entry) }} />
                <div class="timeline-entry-body">
                  <div class="timeline-entry-header">
                    <span
                      class="timeline-entry-type"
                      style={{ color: subtypeColor(entry) }}
                    >
                      {entry.subtype}
                    </span>
                    <Show when={entry.agentId}>
                      <span class="timeline-entry-agent">
                        <button
                          class="link-btn"
                          onClick={() => agentStore.selectAgent(entry.agentId!)}
                        >
                          {entry.agentId}
                        </button>
                      </span>
                    </Show>
                  </div>
                  <div class="timeline-entry-content">{entry.content}</div>
                </div>
              </div>
            )}
          </For>
        </Show>
      </div>
    </div>
  );
};

export default TimelineView;
