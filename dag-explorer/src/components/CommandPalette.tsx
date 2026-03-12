import { type Component, createSignal, createMemo, For, Show, onMount, onCleanup } from "solid-js";
import { dagStore } from "../stores/dag";
import { agentStore } from "../stores/agents";
import { commands, type Command } from "../lib/commands";

const categoryLabels: Record<string, string> = {
  agents: "Agents",
  views: "Views",
  navigation: "Navigation",
  system: "System",
};

const CommandPalette: Component = () => {
  let inputRef!: HTMLInputElement;
  const [query, setQuery] = createSignal("");
  const [selectedIdx, setSelectedIdx] = createSignal(0);

  const filtered = createMemo(() => {
    const q = query().toLowerCase();
    let results = commands;

    // Filter out agent-requiring commands if no agent selected
    if (!agentStore.selectedId()) {
      results = results.filter((c) => !c.requiresAgent);
    }

    if (q) {
      results = results.filter(
        (c) =>
          c.name.toLowerCase().includes(q) ||
          (c.description?.toLowerCase().includes(q) ?? false) ||
          c.category.includes(q)
      );
    }

    return results;
  });

  // Group by category
  const grouped = createMemo(() => {
    const groups: { category: string; label: string; commands: Command[] }[] = [];
    const seen = new Set<string>();
    for (const cmd of filtered()) {
      if (!seen.has(cmd.category)) {
        seen.add(cmd.category);
        groups.push({
          category: cmd.category,
          label: categoryLabels[cmd.category] ?? cmd.category,
          commands: [],
        });
      }
      groups.find((g) => g.category === cmd.category)!.commands.push(cmd);
    }
    return groups;
  });

  function execute(cmd: Command) {
    cmd.handler();
    close();
  }

  function close() {
    dagStore.setShowCommandPalette(false);
    setQuery("");
    setSelectedIdx(0);
  }

  function onKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      close();
    } else if (e.key === "Enter") {
      const all = filtered();
      const cmd = all[selectedIdx()];
      if (cmd) execute(cmd);
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIdx((i) => Math.min(i + 1, filtered().length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIdx((i) => Math.max(i - 1, 0));
    }
  }

  // Reset selection on filter change
  const _ = createMemo(() => {
    query();
    setSelectedIdx(0);
  });

  return (
    <Show when={dagStore.showCommandPalette()}>
      <div class="palette-overlay" onClick={close}>
        <div class="palette" onClick={(e) => e.stopPropagation()}>
          <input
            ref={inputRef!}
            type="text"
            class="palette-input"
            placeholder="Search commands..."
            value={query()}
            onInput={(e) => setQuery(e.currentTarget.value)}
            onKeyDown={onKeyDown}
            autofocus
          />
          <div class="palette-list">
            {(() => {
              let flatIdx = 0;
              return (
                <For each={grouped()}>
                  {(group) => (
                    <>
                      <div class="palette-category">{group.label}</div>
                      <For each={group.commands}>
                        {(cmd) => {
                          const idx = flatIdx++;
                          return (
                            <button
                              class="palette-item"
                              classList={{ "palette-item-selected": selectedIdx() === idx }}
                              onClick={() => execute(cmd)}
                              onMouseEnter={() => setSelectedIdx(idx)}
                            >
                              <span class="palette-icon">{cmd.icon}</span>
                              <div class="palette-item-text">
                                <span class="palette-label">{cmd.name}</span>
                                <Show when={cmd.description}>
                                  <span class="palette-desc">{cmd.description}</span>
                                </Show>
                              </div>
                              <Show when={cmd.shortcut}>
                                <kbd class="palette-kbd">{cmd.shortcut}</kbd>
                              </Show>
                            </button>
                          );
                        }}
                      </For>
                    </>
                  )}
                </For>
              );
            })()}
          </div>
        </div>
      </div>
    </Show>
  );
};

export default CommandPalette;
