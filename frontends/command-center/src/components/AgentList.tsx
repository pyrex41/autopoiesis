import { type Component, For, Show, createSignal } from "solid-js";
import { agentStore } from "../stores/agents";
import type { Agent } from "../api/types";

const stateColors: Record<string, string> = {
  running: "var(--emerge)",
  paused: "var(--warm)",
  stopped: "var(--danger)",
  initialized: "var(--signal)",
};

const AgentList: Component = () => {
  const [filter, setFilter] = createSignal("");

  const filteredAgents = () => {
    const q = filter().toLowerCase();
    if (!q) return agentStore.agents();
    return agentStore.agents().filter(
      (a) => a.name.toLowerCase().includes(q) || a.id.toLowerCase().includes(q)
    );
  };

  return (
    <div class="agent-list-panel">
      <div class="agent-list-header">
        <h2 class="agent-list-title">Agents</h2>
        <button
          class="btn-create-agent"
          onClick={() => window.dispatchEvent(new CustomEvent("ap:create-agent"))}
          title="Create agent [n]"
        >
          +
        </button>
      </div>

      <input
        type="text"
        class="agent-filter-input"
        placeholder="Filter agents..."
        value={filter()}
        onInput={(e) => setFilter(e.currentTarget.value)}
      />

      <div class="agent-list-scroll">
        <Show when={filteredAgents().length > 0} fallback={
          <div class="agent-list-empty">
            <Show when={agentStore.agents().length === 0} fallback="No matches">
              No agents yet.
              <br />
              <button
                class="link-btn"
                onClick={() => window.dispatchEvent(new CustomEvent("ap:create-agent"))}
              >
                Create one
              </button>
            </Show>
          </div>
        }>
          <For each={filteredAgents()}>
            {(agent) => (
              <AgentCard
                agent={agent}
                selected={agentStore.selectedId() === agent.id}
                onClick={() => agentStore.selectAgent(agent.id)}
              />
            )}
          </For>
        </Show>
      </div>
    </div>
  );
};

const AgentCard: Component<{
  agent: Agent;
  selected: boolean;
  onClick: () => void;
}> = (props) => {
  return (
    <button
      class="agent-card"
      classList={{ "agent-card-selected": props.selected }}
      onClick={props.onClick}
    >
      <div class="agent-card-header">
        <div
          class="agent-state-dot"
          style={{ background: stateColors[props.agent.state] ?? "var(--text-dim)" }}
        />
        <span class="agent-card-name">{props.agent.name}</span>
      </div>
      <div class="agent-card-meta">
        <span class="agent-card-state">{props.agent.state}</span>
        <Show when={props.agent.thoughtCount > 0}>
          <span class="agent-card-thoughts">{props.agent.thoughtCount} thoughts</span>
        </Show>
      </div>
      <Show when={props.agent.capabilities.length > 0}>
        <div class="agent-card-caps">
          <For each={props.agent.capabilities.slice(0, 3)}>
            {(cap) => <span class="agent-cap-tag">{cap}</span>}
          </For>
          <Show when={props.agent.capabilities.length > 3}>
            <span class="agent-cap-tag agent-cap-more">
              +{props.agent.capabilities.length - 3}
            </span>
          </Show>
        </div>
      </Show>
    </button>
  );
};

export default AgentList;
