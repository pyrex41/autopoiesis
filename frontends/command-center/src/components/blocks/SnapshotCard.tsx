import { type Component, Show } from "solid-js";
import { navigateTo } from "../../lib/commands";

interface SnapshotData {
  id: string;
  tree_hash?: string;
  parent_id?: string;
  label?: string;
  timestamp?: number | string;
  file_count?: number;
  total_size?: number;
  sandbox_id?: string;
}

const SnapshotCard: Component<{ data: SnapshotData }> = (props) => {
  const d = () => props.data;

  const formatTime = (ts: number | string) => {
    const date = typeof ts === "number" ? new Date(ts * 1000) : new Date(ts);
    return date.toLocaleString();
  };

  return (
    <div class="block-snapshot" onClick={() => navigateTo("dag", "Graph")}>
      <div class="block-snapshot-header">
        <span class="block-snapshot-label">{d().label ?? "Snapshot"}</span>
        <span class="block-snapshot-id" title={d().id}>{d().id.slice(0, 8)}</span>
      </div>
      <div class="block-snapshot-meta">
        <Show when={d().timestamp}>
          <div class="block-snapshot-field">
            <span class="block-snapshot-key">Time</span>
            <span>{formatTime(d().timestamp!)}</span>
          </div>
        </Show>
        <Show when={d().tree_hash}>
          <div class="block-snapshot-field">
            <span class="block-snapshot-key">Merkle</span>
            <span class="block-snapshot-hash">{d().tree_hash!.slice(0, 16)}...</span>
          </div>
        </Show>
        <Show when={d().file_count != null}>
          <div class="block-snapshot-field">
            <span class="block-snapshot-key">Files</span>
            <span>{d().file_count}</span>
          </div>
        </Show>
        <Show when={d().parent_id}>
          <div class="block-snapshot-field">
            <span class="block-snapshot-key">Parent</span>
            <span>{d().parent_id!.slice(0, 8)}</span>
          </div>
        </Show>
      </div>
    </div>
  );
};

export default SnapshotCard;
