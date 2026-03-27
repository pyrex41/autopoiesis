import { type Component, For, Show, createSignal, createMemo } from "solid-js";
import { agentStore } from "../stores/agents";

type EventFilter = "all" | "tool" | "state" | "error";

const filterLabels: Record<EventFilter, string> = {
  all: "All",
  tool: "Tools",
  state: "State",
  error: "Errors",
};

function matchesFilter(type: string, filter: EventFilter): boolean {
  if (filter === "all") return true;
  const lower = type.toLowerCase();
  if (filter === "tool") return lower.includes("tool") || lower.includes("invoke") || lower.includes("capability");
  if (filter === "state") return lower.includes("state") || lower.includes("created") || lower.includes("started") || lower.includes("stopped");
  if (filter === "error") return lower.includes("error") || lower.includes("fail");
  return true;
}

function eventColor(type: string): string {
  const lower = type.toLowerCase();
  if (lower.includes("error") || lower.includes("fail")) return "var(--danger)";
  if (lower.includes("tool") || lower.includes("invoke")) return "var(--signal)";
  if (lower.includes("state") || lower.includes("start") || lower.includes("stop")) return "var(--warm)";
  return "var(--text-dim)";
}

function eventSummary(type: string, data: string | null): string {
  if (!data) return type;
  try {
    const parsed = JSON.parse(data);
    if (parsed.tool) return parsed.tool;
    if (parsed.capability) return parsed.capability;
    if (parsed.state) return `→ ${parsed.state}`;
    if (parsed.message) return parsed.message;
  } catch { /* not JSON */ }
  return data.length > 60 ? data.slice(0, 60) + "..." : data;
}

const EventLog: Component = () => {
  const [filter, setFilter] = createSignal<EventFilter>("all");
  const [expandedId, setExpandedId] = createSignal<string | null>(null);

  const filteredEvents = createMemo(() => {
    const f = filter();
    return agentStore.agentEvents().filter(e => matchesFilter(e.type, f));
  });

  return (
    <div class="event-log">
      <div class="event-log-filters">
        {(Object.keys(filterLabels) as EventFilter[]).map(f => (
          <button
            class="event-filter-pill"
            classList={{ "event-filter-active": filter() === f }}
            onClick={() => setFilter(f)}
          >
            {filterLabels[f]}
          </button>
        ))}
      </div>
      <Show when={agentStore.agentEventsLoading()}>
        <div class="event-log-loading">Loading events...</div>
      </Show>
      <div class="event-log-list">
        <Show when={filteredEvents().length > 0} fallback={
          <div class="event-log-empty">No events</div>
        }>
          <For each={filteredEvents()}>
            {(event) => {
              const color = eventColor(event.type);
              const isExpanded = () => expandedId() === event.id;
              return (
                <div
                  class="event-row"
                  classList={{ "event-row-expanded": isExpanded() }}
                  style={{ "border-left-color": color }}
                  onClick={() => setExpandedId(isExpanded() ? null : event.id)}
                >
                  <div class="event-row-header">
                    <span class="event-type-badge" style={{ color }}>{event.type}</span>
                    <span class="event-summary">{eventSummary(event.type, event.data)}</span>
                    <span class="event-time">
                      {new Date(event.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
                    </span>
                  </div>
                  <Show when={isExpanded() && event.data}>
                    <pre class="event-data">{(() => {
                      try { return JSON.stringify(JSON.parse(event.data!), null, 2); }
                      catch { return event.data; }
                    })()}</pre>
                  </Show>
                </div>
              );
            }}
          </For>
        </Show>
      </div>
    </div>
  );
};

export default EventLog;
