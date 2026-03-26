import { type Component, Show } from "solid-js";

interface SandboxData {
  id: string;
  status?: string;
  backend?: string;
  branch?: string;
  snapshot_count?: number;
  last_tree_hash?: string;
  created_at?: number | string;
}

const SandboxCard: Component<{ data: SandboxData }> = (props) => {
  const d = () => props.data;

  const statusColor = (status: string) => {
    switch (status) {
      case "ready": return "var(--color-green, #0f0)";
      case "creating": return "var(--color-amber, #fa0)";
      case "destroyed": return "var(--color-muted, #666)";
      default: return "var(--color-cyan, #0ff)";
    }
  };

  return (
    <div class="block-sandbox">
      <div class="block-sandbox-header">
        <span class="block-sandbox-id">{d().id}</span>
        <Show when={d().status}>
          <span class="block-sandbox-status" style={{ color: statusColor(d().status!) }}>
            {d().status}
          </span>
        </Show>
      </div>
      <div class="block-sandbox-meta">
        <Show when={d().backend}>
          <span class="block-sandbox-field">Backend: {d().backend}</span>
        </Show>
        <Show when={d().snapshot_count != null}>
          <span class="block-sandbox-field">Snapshots: {d().snapshot_count}</span>
        </Show>
        <Show when={d().last_tree_hash}>
          <span class="block-sandbox-field" title={d().last_tree_hash}>
            Tree: {d().last_tree_hash!.slice(0, 12)}...
          </span>
        </Show>
      </div>
    </div>
  );
};

export default SandboxCard;
