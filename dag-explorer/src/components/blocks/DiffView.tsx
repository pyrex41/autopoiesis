import { type Component, For, Show, createSignal } from "solid-js";
import { formatSize } from "../../lib/format";

interface FileChange {
  path: string;
  type: "added" | "removed" | "modified";
  old_hash?: string;
  new_hash?: string;
  old_size?: number;
  new_size?: number;
}

interface DiffData {
  added?: number;
  removed?: number;
  modified?: number;
  files?: FileChange[];
}

const DiffView: Component<{ data: DiffData }> = (props) => {
  const [expanded, setExpanded] = createSignal(false);
  const files = () => props.data.files ?? [];
  const added = () => props.data.added ?? files().filter(f => f.type === "added").length;
  const removed = () => props.data.removed ?? files().filter(f => f.type === "removed").length;
  const modified = () => props.data.modified ?? files().filter(f => f.type === "modified").length;

  return (
    <div class="block-diff">
      <div class="block-diff-summary">
        <Show when={added() > 0}>
          <span class="block-diff-stat block-diff-added">+{added()} added</span>
        </Show>
        <Show when={removed() > 0}>
          <span class="block-diff-stat block-diff-removed">-{removed()} removed</span>
        </Show>
        <Show when={modified() > 0}>
          <span class="block-diff-stat block-diff-modified">~{modified()} modified</span>
        </Show>
        <Show when={files().length > 0}>
          <button class="block-diff-toggle" onClick={() => setExpanded(!expanded())}>
            {expanded() ? "Hide files" : `Show ${files().length} files`}
          </button>
        </Show>
      </div>
      <Show when={expanded() && files().length > 0}>
        <div class="block-diff-files">
          <For each={files()}>
            {(file) => (
              <div class={`block-diff-file block-diff-file-${file.type}`}>
                <span class="block-diff-file-icon">
                  {file.type === "added" ? "+" : file.type === "removed" ? "-" : "~"}
                </span>
                <span class="block-diff-file-path">{file.path}</span>
                <Show when={file.new_size != null}>
                  <span class="block-diff-file-size">{formatSize(file.new_size!)}</span>
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>
    </div>
  );
};

export default DiffView;
