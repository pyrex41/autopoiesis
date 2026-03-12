import { type Component, createSignal, onMount, onCleanup, For } from "solid-js";
import { agentStore } from "../stores/agents";

const CAPABILITIES = [
  "observe", "reason", "decide", "act", "reflect",
  "learn", "communicate", "self-modify", "tool-use", "collaborate",
];

const CreateAgentDialog: Component = () => {
  let inputRef!: HTMLInputElement;
  const [open, setOpen] = createSignal(false);
  const [name, setName] = createSignal("");
  const [selectedCaps, setSelectedCaps] = createSignal<Set<string>>(new Set(["observe", "reason", "decide", "act"]));

  function handleOpen() {
    setOpen(true);
    setName("");
    setTimeout(() => inputRef?.focus(), 50);
  }

  function handleClose() {
    setOpen(false);
  }

  function toggleCap(cap: string) {
    setSelectedCaps((prev) => {
      const next = new Set(prev);
      if (next.has(cap)) next.delete(cap);
      else next.add(cap);
      return next;
    });
  }

  async function handleCreate() {
    const n = name().trim();
    if (!n) return;
    await agentStore.createAgent(n, [...selectedCaps()]);
    handleClose();
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") handleClose();
    if (e.key === "Enter") handleCreate();
  }

  onMount(() => {
    window.addEventListener("ap:create-agent", handleOpen);
  });

  onCleanup(() => {
    window.removeEventListener("ap:create-agent", handleOpen);
  });

  return (
    <>
      {open() && (
        <div class="palette-overlay" onClick={handleClose}>
          <div class="create-agent-dialog" onClick={(e) => e.stopPropagation()} onKeyDown={handleKeyDown}>
            <h2 class="create-dialog-title">Create Agent</h2>

            <div class="create-field">
              <label>Name</label>
              <input
                ref={inputRef!}
                type="text"
                class="create-name-input"
                placeholder="e.g. monitor, researcher, builder..."
                value={name()}
                onInput={(e) => setName(e.currentTarget.value)}
              />
            </div>

            <div class="create-field">
              <label>Capabilities</label>
              <div class="create-caps-grid">
                <For each={CAPABILITIES}>
                  {(cap) => (
                    <button
                      class="create-cap-btn"
                      classList={{ "create-cap-active": selectedCaps().has(cap) }}
                      onClick={() => toggleCap(cap)}
                    >
                      {cap}
                    </button>
                  )}
                </For>
              </div>
            </div>

            <div class="create-actions">
              <button class="btn-secondary" onClick={handleClose}>
                Cancel
              </button>
              <button
                class="btn-primary"
                onClick={handleCreate}
                disabled={!name().trim()}
              >
                Create Agent
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

export default CreateAgentDialog;
