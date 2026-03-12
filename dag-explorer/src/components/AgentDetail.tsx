import { type Component, Show, createMemo, createSignal, onMount, onCleanup } from "solid-js";
import { agentStore } from "../stores/agents";
import { activityStore } from "../stores/activity";
import { holodeckStore } from "../stores/holodeck";
import { setCurrentView } from "../lib/commands";
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

            <Show when={holodeckStore.entityCount() > 0}>
              <div style={{ padding: "0 16px 8px" }}>
                <button
                  class="btn-secondary"
                  style={{ "font-size": "11px", padding: "4px 10px" }}
                  onClick={() => {
                    holodeckStore.focusOnAgent(a().id);
                    setCurrentView("holodeck");
                  }}
                >
                  Show in 3D
                </button>
              </div>
            </Show>

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

              <AgentActivitySection agentId={a().id} />

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

const AgentActivitySection: Component<{ agentId: string }> = (props) => {
  const [now, setNow] = createSignal(Date.now());

  let timer: ReturnType<typeof setInterval>;
  onMount(() => {
    timer = setInterval(() => setNow(Date.now()), 1000);
  });
  onCleanup(() => clearInterval(timer));

  const activity = createMemo(() => {
    return activityStore.activities().get(props.agentId) ?? null;
  });

  const toolDuration = () => {
    const a = activity();
    if (!a?.currentTool || !a.toolStartTime) return null;
    const elapsed = Math.floor((now() - a.toolStartTime) / 1000);
    if (elapsed < 60) return `${elapsed}s`;
    const m = Math.floor(elapsed / 60);
    return `${m}m ${elapsed % 60}s`;
  };

  const idleTime = () => {
    const a = activity();
    if (!a || a.currentTool || !a.lastActive || a.lastActive === 0) return null;
    const idle = Math.floor((now() - a.lastActive) / 1000);
    if (idle <= 0) return null;
    if (idle < 60) return `${idle}s`;
    const m = Math.floor(idle / 60);
    if (m < 60) return `${m}m ${idle % 60}s`;
    const h = Math.floor(m / 60);
    return `${h}h ${m % 60}m`;
  };

  return (
    <Show when={activity()}>
      {(a) => (
        <div class="agent-detail-section">
          <h3>Activity</h3>
          <dl class="agent-detail-dl">
            <Show when={a().currentTool}>
              <dt>Current Tool</dt>
              <dd>
                <span class="agent-activity-tool">{a().currentTool}</span>
                <Show when={toolDuration()}>
                  <span class="agent-activity-tool-duration"> ({toolDuration()})</span>
                </Show>
              </dd>
            </Show>
            <Show when={!a().currentTool && idleTime()}>
              <dt>Status</dt>
              <dd>
                <span class={a().state === "long-idle" ? "text-danger" : "text-dim"}>
                  Idle for {idleTime()}
                </span>
              </dd>
            </Show>
            <Show when={a().totalCost > 0}>
              <dt>Cost</dt>
              <dd>${a().totalCost.toFixed(4)}</dd>
            </Show>
            <Show when={a().callCount > 0}>
              <dt>API Calls</dt>
              <dd>{a().callCount}</dd>
            </Show>
            <Show when={a().tokens > 0}>
              <dt>Tokens</dt>
              <dd>{a().tokens.toLocaleString()}</dd>
            </Show>
          </dl>
        </div>
      )}
    </Show>
  );
};

export default AgentDetail;
