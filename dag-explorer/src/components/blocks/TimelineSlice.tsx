import { type Component, For, Show } from "solid-js";
import { navigateTo } from "../../lib/commands";

interface TimelineEntry {
  id?: string;
  timestamp: number | string;
  type: string;
  label?: string;
  sandbox_id?: string;
  snapshot_id?: string;
  details?: string;
}

interface TimelineSliceData {
  entries: TimelineEntry[];
  title?: string;
}

const TimelineSlice: Component<{ data: TimelineSliceData }> = (props) => {
  const entries = () => props.data.entries ?? [];

  const formatTime = (ts: number | string) => {
    const d = typeof ts === "number" ? new Date(ts * 1000) : new Date(ts);
    return d.toLocaleString(undefined, {
      month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit",
    });
  };

  const typeColor = (type: string) => {
    switch (type) {
      case "snapshot": return "var(--color-cyan, #0ff)";
      case "exec": return "var(--color-green, #0f0)";
      case "fork": return "var(--color-amber, #fa0)";
      case "restore": return "var(--color-purple, #a0f)";
      case "error": return "var(--color-red, #f00)";
      default: return "var(--color-muted, #888)";
    }
  };

  const handleClick = (entry: TimelineEntry) => {
    if (entry.snapshot_id) {
      // Navigate to Graph view and select the snapshot
      navigateTo("dag", "Graph");
    }
  };

  return (
    <div class="block-timeline">
      <div class="block-timeline-entries">
        <For each={entries()}>
          {(entry) => (
            <div
              class="block-timeline-entry"
              classList={{ "block-timeline-clickable": !!entry.snapshot_id }}
              onClick={() => handleClick(entry)}
            >
              <div class="block-timeline-dot" style={{ background: typeColor(entry.type) }} />
              <div class="block-timeline-time">{formatTime(entry.timestamp)}</div>
              <div class="block-timeline-body">
                <span class="block-timeline-type">{entry.type}</span>
                <Show when={entry.label}>
                  <span class="block-timeline-label">{entry.label}</span>
                </Show>
                <Show when={entry.details}>
                  <span class="block-timeline-details">{entry.details}</span>
                </Show>
              </div>
            </div>
          )}
        </For>
      </div>
    </div>
  );
};

export default TimelineSlice;
