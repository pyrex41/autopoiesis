import { type Component, createSignal, onMount, onCleanup, For, Show } from "solid-js";
import { agentStore } from "../stores/agents";

interface CapabilityDef {
  id: string;
  label: string;
  desc: string;
  group: "cognitive" | "action" | "social";
}

const CAPABILITIES: CapabilityDef[] = [
  { id: "observe", label: "Observe", desc: "Perceive environment state", group: "cognitive" },
  { id: "reason", label: "Reason", desc: "Analyze and infer", group: "cognitive" },
  { id: "decide", label: "Decide", desc: "Choose among alternatives", group: "cognitive" },
  { id: "reflect", label: "Reflect", desc: "Self-evaluate performance", group: "cognitive" },
  { id: "act", label: "Act", desc: "Execute decisions", group: "action" },
  { id: "learn", label: "Learn", desc: "Adapt from experience", group: "action" },
  { id: "tool-use", label: "Tool Use", desc: "Invoke external tools", group: "action" },
  { id: "self-modify", label: "Self-Modify", desc: "Alter own behavior", group: "action" },
  { id: "communicate", label: "Communicate", desc: "Exchange with agents", group: "social" },
  { id: "collaborate", label: "Collaborate", desc: "Coordinate in teams", group: "social" },
];

interface Preset {
  name: string;
  caps: string[];
  desc: string;
}

const PRESETS: Preset[] = [
  { name: "Observer", caps: ["observe", "reason", "reflect"], desc: "Monitor and report" },
  { name: "Worker", caps: ["observe", "reason", "decide", "act", "tool-use"], desc: "Execute tasks with tools" },
  { name: "Researcher", caps: ["observe", "reason", "decide", "reflect", "learn", "communicate"], desc: "Investigate and learn" },
  { name: "Autonomous", caps: ["observe", "reason", "decide", "act", "reflect", "learn", "tool-use", "self-modify"], desc: "Full self-directed agent" },
];

const CreateAgentDialog: Component = () => {
  let inputRef!: HTMLInputElement;
  let taskRef!: HTMLTextAreaElement;
  const [open, setOpen] = createSignal(false);
  const [name, setName] = createSignal("");
  const [task, setTask] = createSignal("");
  const [selectedCaps, setSelectedCaps] = createSignal<Set<string>>(new Set(["observe", "reason", "decide", "act"]));

  function handleOpen() {
    setOpen(true);
    setName("");
    setTask("");
    setSelectedCaps(new Set(["observe", "reason", "decide", "act"]));
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

  function applyPreset(preset: Preset) {
    setSelectedCaps(new Set(preset.caps));
  }

  async function handleCreate() {
    const n = name().trim();
    if (!n) return;
    const t = task().trim();
    await agentStore.createAgent(n, [...selectedCaps()], t || undefined);
    handleClose();
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") handleClose();
    if (e.key === "Enter" && e.target === inputRef) handleCreate();
  }

  onMount(() => {
    window.addEventListener("ap:create-agent", handleOpen);
  });

  onCleanup(() => {
    window.removeEventListener("ap:create-agent", handleOpen);
  });

  const groupedCaps = () => {
    const groups = { cognitive: [] as CapabilityDef[], action: [] as CapabilityDef[], social: [] as CapabilityDef[] };
    for (const cap of CAPABILITIES) groups[cap.group].push(cap);
    return groups;
  };

  return (
    <>
      {open() && (
        <div class="palette-overlay" onClick={handleClose}>
          <div class="create-agent-dialog" onClick={(e) => e.stopPropagation()} onKeyDown={handleKeyDown}>
            <div class="create-dialog-header">
              <h2 class="create-dialog-title">Deploy Agent</h2>
              <span class="create-dialog-subtitle">Configure capabilities and assign a task</span>
            </div>

            <div class="create-field">
              <label class="create-label">Designation</label>
              <input
                ref={inputRef!}
                type="text"
                class="create-name-input"
                placeholder="e.g. sentinel, researcher, builder"
                value={name()}
                onInput={(e) => setName(e.currentTarget.value)}
              />
            </div>

            <div class="create-field">
              <label class="create-label">Mission <span class="create-label-hint">optional</span></label>
              <textarea
                ref={taskRef!}
                class="create-task-input"
                placeholder="Describe what this agent should do..."
                value={task()}
                onInput={(e) => setTask(e.currentTarget.value)}
                rows="2"
              />
            </div>

            <div class="create-field">
              <div class="create-caps-header">
                <label class="create-label">Capabilities</label>
                <div class="create-presets">
                  <For each={PRESETS}>
                    {(preset) => (
                      <button
                        class="create-preset-btn"
                        onClick={() => applyPreset(preset)}
                        title={preset.desc}
                      >
                        {preset.name}
                      </button>
                    )}
                  </For>
                </div>
              </div>

              {(["cognitive", "action", "social"] as const).map((group) => (
                <div class="create-cap-group">
                  <span class="create-cap-group-label">{group}</span>
                  <div class="create-caps-row">
                    <For each={groupedCaps()[group]}>
                      {(cap) => (
                        <button
                          class="create-cap-btn"
                          classList={{ "create-cap-active": selectedCaps().has(cap.id) }}
                          onClick={() => toggleCap(cap.id)}
                          title={cap.desc}
                        >
                          <span class="create-cap-name">{cap.label}</span>
                        </button>
                      )}
                    </For>
                  </div>
                </div>
              ))}
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
                {task().trim() ? "Deploy & Run" : "Deploy Agent"}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

export default CreateAgentDialog;
