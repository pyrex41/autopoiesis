import { type Component, createSignal, onMount, onCleanup, For, Show, createMemo } from "solid-js";
import { agentStore } from "../stores/agents";
import { teamStore } from "../stores/teams";

const STRATEGIES = [
  "leader-worker",
  "parallel",
  "pipeline",
  "debate",
  "consensus",
  "hierarchical-leader-worker",
  "leader-parallel",
  "rotating-leader",
  "debate-consensus",
];

const CreateTeamDialog: Component = () => {
  let nameRef!: HTMLInputElement;
  const [open, setOpen] = createSignal(false);
  const [name, setName] = createSignal("");
  const [strategy, setStrategy] = createSignal("leader-worker");
  const [selectedMembers, setSelectedMembers] = createSignal<Set<string>>(new Set());
  const [leader, setLeader] = createSignal("");
  const [task, setTask] = createSignal("");

  const isLeaderStrategy = createMemo(() => {
    const s = strategy();
    return s.includes("leader");
  });

  const membersList = createMemo(() => [...selectedMembers()]);

  function handleOpen() {
    setOpen(true);
    setName("");
    setStrategy("leader-worker");
    setSelectedMembers(new Set<string>());
    setLeader("");
    setTask("");
    setTimeout(() => nameRef?.focus(), 50);
  }

  function handleClose() {
    setOpen(false);
  }

  function toggleMember(agentName: string) {
    setSelectedMembers((prev) => {
      const next = new Set(prev);
      if (next.has(agentName)) {
        next.delete(agentName);
        // Clear leader if removed
        if (leader() === agentName) setLeader("");
      } else {
        next.add(agentName);
      }
      return next;
    });
  }

  function handleCreate() {
    const n = name().trim();
    if (!n) return;
    const members = membersList();
    teamStore.createTeam(
      n,
      strategy(),
      members.length > 0 ? members : undefined,
      leader() || undefined,
      task().trim() || undefined,
    );
    handleClose();
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") handleClose();
    if (e.key === "Enter" && !(e.target instanceof HTMLTextAreaElement)) handleCreate();
  }

  onMount(() => {
    window.addEventListener("ap:create-team", handleOpen);
  });

  onCleanup(() => {
    window.removeEventListener("ap:create-team", handleOpen);
  });

  return (
    <>
      {open() && (
        <div class="palette-overlay" onClick={handleClose}>
          <div
            class="create-agent-dialog"
            onClick={(e) => e.stopPropagation()}
            onKeyDown={handleKeyDown}
            style={{ width: "480px" }}
          >
            <h2 class="create-dialog-title">Create Team</h2>

            <div class="create-field">
              <label>Team Name</label>
              <input
                ref={nameRef!}
                type="text"
                class="create-name-input"
                placeholder="e.g. research-squad, build-team..."
                value={name()}
                onInput={(e) => setName(e.currentTarget.value)}
              />
            </div>

            <div class="create-field">
              <label>Strategy</label>
              <select
                style={selectStyle}
                value={strategy()}
                onChange={(e) => setStrategy(e.currentTarget.value)}
              >
                <For each={STRATEGIES}>
                  {(s) => <option value={s}>{s}</option>}
                </For>
              </select>
            </div>

            <div class="create-field">
              <label>Members</label>
              <Show
                when={agentStore.agents().length > 0}
                fallback={<div style={hintStyle}>No agents available</div>}
              >
                <div class="create-caps-grid">
                  <For each={agentStore.agents()}>
                    {(agent) => (
                      <button
                        class="create-cap-btn"
                        classList={{ "create-cap-active": selectedMembers().has(agent.name) }}
                        onClick={() => toggleMember(agent.name)}
                      >
                        {agent.name}
                      </button>
                    )}
                  </For>
                </div>
              </Show>
            </div>

            <Show when={isLeaderStrategy() && membersList().length > 0}>
              <div class="create-field">
                <label>Leader</label>
                <select
                  style={selectStyle}
                  value={leader()}
                  onChange={(e) => setLeader(e.currentTarget.value)}
                >
                  <option value="">Select leader...</option>
                  <For each={membersList()}>
                    {(m) => <option value={m}>{m}</option>}
                  </For>
                </select>
              </div>
            </Show>

            <div class="create-field">
              <label>Task (optional)</label>
              <textarea
                style={textareaStyle}
                placeholder="Describe the team's task..."
                value={task()}
                onInput={(e) => setTask(e.currentTarget.value)}
                rows={3}
              />
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
                Create Team
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

// ── Styles ───────────────────────────────────────────────────────

const selectStyle: Record<string, string> = {
  width: "100%",
  padding: "10px 12px",
  background: "var(--surface)",
  border: "1px solid var(--border)",
  "border-radius": "var(--radius)",
  color: "var(--text)",
  "font-family": "var(--font-mono)",
  "font-size": "12px",
  outline: "none",
  cursor: "pointer",
};

const textareaStyle: Record<string, string> = {
  width: "100%",
  padding: "10px 12px",
  background: "var(--surface)",
  border: "1px solid var(--border)",
  "border-radius": "var(--radius)",
  color: "var(--text)",
  "font-family": "var(--font-mono)",
  "font-size": "12px",
  outline: "none",
  resize: "vertical",
};

const hintStyle: Record<string, string> = {
  color: "var(--text-dim)",
  "font-size": "11px",
  "font-style": "italic",
};

export default CreateTeamDialog;
