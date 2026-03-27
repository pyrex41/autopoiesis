import { type Component, For, Show, createSignal } from "solid-js";
import { formatSize } from "../../lib/format";

interface TreeEntry {
  type: "file" | "directory" | "symlink";
  path: string;
  hash?: string;
  size?: number;
  mode?: number;
  target?: string;
}

interface FileTreeData {
  root?: string;
  entries?: TreeEntry[];
  file_count?: number;
  total_size?: number;
  tree_hash?: string;
}

const FileTree: Component<{ data: FileTreeData }> = (props) => {
  const [expandedDirs, setExpandedDirs] = createSignal<Set<string>>(new Set());
  const entries = () => props.data.entries ?? [];

  // Build a nested structure from flat entries
  const tree = () => {
    const dirs = new Map<string, TreeEntry[]>();
    const topLevel: TreeEntry[] = [];

    for (const entry of entries()) {
      const parts = entry.path.split("/");
      if (parts.length <= 1) {
        topLevel.push(entry);
      } else {
        const dir = parts.slice(0, -1).join("/");
        if (!dirs.has(dir)) dirs.set(dir, []);
        dirs.get(dir)!.push(entry);
      }
    }

    return { topLevel, dirs };
  };

  const toggleDir = (path: string) => {
    setExpandedDirs(prev => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  };

  return (
    <div class="block-file-tree">
      <Show when={props.data.root}>
        <div class="block-file-tree-root">{props.data.root}</div>
      </Show>
      <div class="block-file-tree-meta">
        <Show when={props.data.file_count != null}>
          <span>{props.data.file_count} files</span>
        </Show>
        <Show when={props.data.total_size != null}>
          <span>{formatSize(props.data.total_size!)}</span>
        </Show>
        <Show when={props.data.tree_hash}>
          <span class="block-file-tree-hash" title={props.data.tree_hash}>
            {props.data.tree_hash!.slice(0, 12)}...
          </span>
        </Show>
      </div>
      <div class="block-file-tree-entries">
        <For each={entries().slice(0, 100)}>
          {(entry) => (
            <div
              class={`block-file-tree-entry block-file-tree-${entry.type}`}
              onClick={() => entry.type === "directory" && toggleDir(entry.path)}
            >
              <span class="block-file-tree-icon">
                {entry.type === "directory" ? (expandedDirs().has(entry.path) ? "\u25BE" : "\u25B8") :
                 entry.type === "symlink" ? "\u2192" : "\u2022"}
              </span>
              <span class="block-file-tree-path">{entry.path}</span>
              <Show when={entry.type === "file" && entry.size != null}>
                <span class="block-file-tree-size">{formatSize(entry.size!)}</span>
              </Show>
            </div>
          )}
        </For>
        <Show when={entries().length > 100}>
          <div class="block-file-tree-truncated">
            ... and {entries().length - 100} more entries
          </div>
        </Show>
      </div>
    </div>
  );
};

export default FileTree;
