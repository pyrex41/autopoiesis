import { type Component, createSignal, createMemo, For, Show, onMount, onCleanup } from "solid-js";
import { dagStore } from "../stores/dag";
import { fitToView } from "../graph/globals";

interface Command {
  id: string;
  label: string;
  shortcut?: string;
  action: () => void;
}

const CommandPalette: Component = () => {
  let inputRef!: HTMLInputElement;
  const [query, setQuery] = createSignal("");

  const commands = createMemo<Command[]>(() => [
    {
      id: "fit",
      label: "Fit graph to view",
      shortcut: "f",
      action: () => fitToView(),
    },
    {
      id: "toggle-inspector",
      label: "Toggle inspector panel",
      shortcut: "i",
      action: () => dagStore.setDetailPanelOpen(!dagStore.detailPanelOpen()),
    },
    {
      id: "toggle-diff",
      label: "Toggle diff mode",
      shortcut: "d",
      action: () => dagStore.setDiffMode(!dagStore.diffMode()),
    },
    {
      id: "clear-selection",
      label: "Clear selection",
      shortcut: "Escape",
      action: () => dagStore.clearSelection(),
    },
    {
      id: "layout-tb",
      label: "Layout: Top-Down",
      action: () => dagStore.setDirection("TB"),
    },
    {
      id: "layout-lr",
      label: "Layout: Left-Right",
      action: () => dagStore.setDirection("LR"),
    },
    {
      id: "color-branch",
      label: "Color by branch",
      action: () => dagStore.setColorScheme("branch"),
    },
    {
      id: "color-agent",
      label: "Color by agent",
      action: () => dagStore.setColorScheme("agent"),
    },
    {
      id: "color-depth",
      label: "Color by depth",
      action: () => dagStore.setColorScheme("depth"),
    },
    {
      id: "color-time",
      label: "Color by time",
      action: () => dagStore.setColorScheme("time"),
    },
    {
      id: "load-mock",
      label: "Load mock data",
      action: () => dagStore.loadMockData(),
    },
    {
      id: "load-live",
      label: "Connect to live API",
      action: () => dagStore.loadFromAPI(),
    },
    {
      id: "nav-parent",
      label: "Navigate to parent",
      shortcut: "h",
      action: () => dagStore.navigateToParent(),
    },
    {
      id: "nav-child",
      label: "Navigate to first child",
      shortcut: "l",
      action: () => dagStore.navigateToChild(),
    },
    {
      id: "nav-prev-sibling",
      label: "Navigate to previous sibling",
      shortcut: "k",
      action: () => dagStore.navigateToSibling(-1),
    },
    {
      id: "nav-next-sibling",
      label: "Navigate to next sibling",
      shortcut: "j",
      action: () => dagStore.navigateToSibling(1),
    },
    {
      id: "compute-diff",
      label: "Compute diff between selected nodes",
      action: () => dagStore.computeDiff(),
    },
  ]);

  const filtered = createMemo(() => {
    const q = query().toLowerCase();
    if (!q) return commands();
    return commands().filter((c) => c.label.toLowerCase().includes(q));
  });

  function execute(cmd: Command) {
    cmd.action();
    dagStore.setShowCommandPalette(false);
    setQuery("");
  }

  function onKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      dagStore.setShowCommandPalette(false);
      setQuery("");
    } else if (e.key === "Enter") {
      const first = filtered()[0];
      if (first) execute(first);
    }
  }

  onMount(() => {
    inputRef?.focus();
  });

  return (
    <Show when={dagStore.showCommandPalette()}>
      <div
        class="palette-overlay"
        onClick={() => dagStore.setShowCommandPalette(false)}
      >
        <div class="palette" onClick={(e) => e.stopPropagation()}>
          <input
            ref={inputRef!}
            type="text"
            class="palette-input"
            placeholder="Type a command..."
            value={query()}
            onInput={(e) => setQuery(e.currentTarget.value)}
            onKeyDown={onKeyDown}
          />
          <div class="palette-list">
            <For each={filtered()}>
              {(cmd) => (
                <button class="palette-item" onClick={() => execute(cmd)}>
                  <span class="palette-label">{cmd.label}</span>
                  <Show when={cmd.shortcut}>
                    <kbd class="palette-kbd">{cmd.shortcut}</kbd>
                  </Show>
                </button>
              )}
            </For>
          </div>
        </div>
      </div>
    </Show>
  );
};

export default CommandPalette;
