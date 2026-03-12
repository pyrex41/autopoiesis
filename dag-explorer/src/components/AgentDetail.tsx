import { type Component, Show } from "solid-js";
import { agentStore } from "../stores/agents";
import AgentActions from "./AgentActions";
import ThoughtStream from "./ThoughtStream";

const AgentDetail: Component = () => {
  const agent = () => agentStore.selectedAgent();

  return (
    <div class="agent-detail-panel">
      <Show
        when={agent()}
        fallback={
          <div class="agent-detail-empty">
            <div class="empty-icon">◇</div>
            <p>Select an agent to inspect</p>
            <p class="empty-hint">
              Click an agent in the list, or press <kbd>n</kbd> to create one
            </p>
          </div>
        }
      >
        {(a) => (
          <>
            <div class="agent-detail-header">
              <div class="agent-detail-name-row">
                <div
                  class="agent-state-dot agent-state-dot-lg"
                  style={{
                    background:
                      a().state === "running" ? "var(--emerge)" :
                      a().state === "paused" ? "var(--warm)" :
                      a().state === "stopped" ? "var(--danger)" :
                      "var(--signal)",
                  }}
                />
                <h2 class="agent-detail-name">{a().name}</h2>
                <span class="agent-detail-state">{a().state}</span>
              </div>
              <div class="agent-detail-id">{a().id}</div>
            </div>

            <AgentActions agent={a()} />

            <div class="agent-detail-sections">
              <div class="agent-detail-section">
                <h3>Capabilities</h3>
                <Show when={a().capabilities.length > 0} fallback={
                  <span class="text-dim">None</span>
                }>
                  <div class="agent-caps-grid">
                    {a().capabilities.map((cap) => (
                      <span class="agent-cap-badge">{cap}</span>
                    ))}
                  </div>
                </Show>
              </div>

              <Show when={a().parent}>
                <div class="agent-detail-section">
                  <h3>Lineage</h3>
                  <dl class="agent-detail-dl">
                    <dt>Parent</dt>
                    <dd>
                      <button
                        class="link-btn"
                        onClick={() => agentStore.selectAgent(a().parent!)}
                      >
                        {a().parent}
                      </button>
                    </dd>
                    <Show when={a().children.length > 0}>
                      <dt>Children</dt>
                      <dd>{a().children.length} agent{a().children.length !== 1 ? "s" : ""}</dd>
                    </Show>
                  </dl>
                </div>
              </Show>

              <div class="agent-detail-section">
                <h3>Thought Stream</h3>
                <ThoughtStream />
              </div>
            </div>
          </>
        )}
      </Show>
    </div>
  );
};

export default AgentDetail;
