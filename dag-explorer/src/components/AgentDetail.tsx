import { type Component, Show, For, createMemo, createSignal, onMount, onCleanup } from "solid-js";
import { agentStore } from "../stores/agents";
import { activityStore } from "../stores/activity";
import AgentActions from "./AgentActions";
import ThoughtStream from "./ThoughtStream";
import ContextGauge from "./ContextGauge";
import CapabilityInspector from "./CapabilityInspector";
import EventLog from "./EventLog";
import SnapshotTimeline from "./SnapshotTimeline";


const AgentDetail: Component = () => {
  const agent = () => agentStore.selectedAgent();
  const [collapsed, setCollapsed] = createSignal(false);

  return (
    <div class="agent-detail-panel" classList={{ "agent-detail-collapsed": collapsed() }}>
      <button
        class="agent-detail-toggle"
        onClick={() => setCollapsed(!collapsed())}
        title={collapsed() ? "Expand panel" : "Collapse panel"}
      >
        {collapsed() ? "\u25C0" : "\u25B6"}
      </button>
      <Show when={collapsed()}>
        <div class="agent-detail-collapsed-strip">
          {agent()?.name ?? "Agent Detail"}
        </div>
      </Show>
      <Show when={!collapsed()}>
        <Show
          when={agent()}
          fallback={
            <div class="agent-detail-empty">
              <div class="agent-detail-empty-icon">
                <svg width="40" height="40" viewBox="0 0 40 40" fill="none">
                  <rect x="8" y="8" width="24" height="24" rx="4" stroke="var(--border-hi)" stroke-width="1.5" stroke-dasharray="4 3"/>
                  <circle cx="20" cy="18" r="4" stroke="var(--border-hi)" stroke-width="1.2"/>
                  <path d="M13 28c0-3.87 3.13-7 7-7s7 3.13 7 7" stroke="var(--border-hi)" stroke-width="1.2"/>
                </svg>
              </div>
              <p class="agent-detail-empty-title">No Agent Selected</p>
              <p class="agent-detail-empty-hint">
                Select an agent from the roster, or press <kbd>n</kbd> to deploy one
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
                  <span class="agent-detail-state" classList={{
                    "state-running": a().state === "running",
                    "state-paused": a().state === "paused",
                    "state-stopped": a().state === "stopped",
                  }}>
                    {a().state === "running" ? "RUN" :
                     a().state === "paused" ? "HOLD" :
                     a().state === "stopped" ? "STOP" :
                     a().state?.toUpperCase().slice(0, 4) ?? "—"}
                  </span>
                </div>
                <div class="agent-detail-meta">
                  <span class="agent-detail-id" title={a().id}>
                    {a().id.slice(0, 8)}...
                  </span>
                  <Show when={agentStore.contextWindow()}>
                    {(ctx) => (
                      <ContextGauge used={ctx().used} total={ctx().total} />
                    )}
                  </Show>
                </div>
              </div>

              <AgentActions agent={a()} />

              <div class="agent-detail-sections">
                {/* Capabilities — interactive inspector */}
                <div class="agent-detail-section">
                  <h3 class="agent-section-title">Capabilities</h3>
                  <CapabilityInspector capabilities={a().capabilities} />
                </div>

                <Show when={a().parent}>
                  <div class="agent-detail-section">
                    <h3 class="agent-section-title">Lineage</h3>
                    <dl class="agent-detail-dl">
                      <dt>Parent</dt>
                      <dd>
                        <button
                          class="link-btn"
                          onClick={() => agentStore.selectAgent(a().parent!)}
                        >
                          {a().parent!.slice(0, 8)}...
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

                <PendingRequestsSection agentId={a().id} />

                <div class="agent-detail-section">
                  <h3 class="agent-section-title">Event Log</h3>
                  <EventLog />
                </div>

                <div class="agent-detail-section">
                  <h3 class="agent-section-title">Snapshots</h3>
                  <SnapshotTimeline />
                </div>

                <div class="agent-detail-section">
                  <h3 class="agent-section-title">Thought Stream</h3>
                  <ThoughtStream />
                </div>
              </div>
            </>
          )}
        </Show>
      </Show>
    </div>
  );
};

const AgentActivitySection: Component<{ agentId: string }> = (props) => {
  const [now, setNow] = createSignal(Date.now());
  let timer: ReturnType<typeof setInterval>;
  onMount(() => { timer = setInterval(() => setNow(Date.now()), 1000); });
  onCleanup(() => clearInterval(timer));

  const activity = createMemo(() => activityStore.activities().get(props.agentId) ?? null);

  const toolDuration = () => {
    const a = activity();
    if (!a?.currentTool || !a.toolStartTime) return null;
    const elapsed = Math.floor((now() - a.toolStartTime) / 1000);
    if (elapsed < 60) return `${elapsed}s`;
    return `${Math.floor(elapsed / 60)}m ${elapsed % 60}s`;
  };

  const idleTime = () => {
    const a = activity();
    if (!a || a.currentTool || !a.lastActive || a.lastActive === 0) return null;
    const idle = Math.floor((now() - a.lastActive) / 1000);
    if (idle <= 0) return null;
    if (idle < 60) return `${idle}s`;
    const m = Math.floor(idle / 60);
    if (m < 60) return `${m}m ${idle % 60}s`;
    return `${Math.floor(m / 60)}h ${m % 60}m`;
  };

  return (
    <Show when={activity()}>
      {(a) => (
        <div class="agent-detail-section">
          <h3 class="agent-section-title">Activity</h3>
          <dl class="agent-detail-dl">
            <Show when={a().currentTool}>
              <dt>Tool</dt>
              <dd>
                <span class="agent-activity-tool">{a().currentTool}</span>
                <Show when={toolDuration()}>
                  <span class="agent-activity-tool-duration"> {toolDuration()}</span>
                </Show>
              </dd>
            </Show>
            <Show when={!a().currentTool && idleTime()}>
              <dt>Status</dt>
              <dd>
                <span classList={{ "text-danger": a().state === "long-idle", "text-dim": a().state !== "long-idle" }}>
                  Idle {idleTime()}
                </span>
              </dd>
            </Show>
            <Show when={a().totalCost > 0}>
              <dt>Cost</dt>
              <dd>${a().totalCost.toFixed(4)}</dd>
            </Show>
            <Show when={a().callCount > 0}>
              <dt>Calls</dt>
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

interface PendingRequest {
  id: string;
  prompt: string;
  type: string;
  timestamp: number;
}

const PendingRequestsSection: Component<{ agentId: string }> = (props) => {
  const [requests, setRequests] = createSignal<PendingRequest[]>([]);
  const [respondingTo, setRespondingTo] = createSignal<string | null>(null);
  const [responseText, setResponseText] = createSignal("");

  // Poll for pending requests
  const loadPending = async () => {
    try {
      const res = await fetch(`/api/agents/${props.agentId}/pending`);
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data)) setRequests(data);
      }
    } catch { /* non-critical */ }
  };

  // Load on mount and periodically
  let timer: ReturnType<typeof setInterval>;
  onMount(() => {
    loadPending();
    timer = setInterval(loadPending, 5000);
  });
  onCleanup(() => clearInterval(timer));

  async function respond(requestId: string) {
    const text = responseText().trim();
    if (!text) return;
    try {
      await fetch(`/api/pending/${requestId}/respond`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ response: text }),
      });
      setRespondingTo(null);
      setResponseText("");
      loadPending();
    } catch { /* ignore */ }
  }

  return (
    <Show when={requests().length > 0}>
      <div class="agent-detail-section">
        <h3 class="agent-section-title" style={{ color: "var(--warm)" }}>
          Awaiting Input ({requests().length})
        </h3>
        <For each={requests()}>
          {(req) => (
            <div class="pending-request">
              <div class="pending-prompt">{req.prompt || "Human input requested"}</div>
              <Show when={respondingTo() === req.id} fallback={
                <button
                  class="pending-respond-btn"
                  onClick={() => setRespondingTo(req.id)}
                >
                  Respond
                </button>
              }>
                <div class="pending-response-form">
                  <input
                    type="text"
                    class="pending-response-input"
                    placeholder="Type your response..."
                    value={responseText()}
                    onInput={(e) => setResponseText(e.currentTarget.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") respond(req.id); }}
                  />
                  <button class="pending-send-btn" onClick={() => respond(req.id)}>Send</button>
                </div>
              </Show>
            </div>
          )}
        </For>
      </div>
    </Show>
  );
};

export default AgentDetail;
