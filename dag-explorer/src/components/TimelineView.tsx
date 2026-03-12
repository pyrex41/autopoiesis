import { type Component, For, Show, createMemo } from "solid-js";
import { agentStore, type Thought } from "../stores/agents";
import type { IntegrationEvent } from "../api/types";

interface TimelineEntry {
  id: string;
  timestamp: number;
  type: "thought" | "event";
  subtype: string;
  agentId?: string;
  content: string;
}

const TimelineView: Component = () => {
  const entries = createMemo<TimelineEntry[]>(() => {
    const items: TimelineEntry[] = [];

    // Thoughts
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

    // Events
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

    // Sort newest first
    items.sort((a, b) => b.timestamp - a.timestamp);
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

      <div class="timeline-scroll">
        <Show when={entries().length > 0} fallback={
          <div class="timeline-empty">
            No events or thoughts recorded yet.
            <br />
            Start an agent to see activity here.
          </div>
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
