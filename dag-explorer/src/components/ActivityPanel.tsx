import { type Component, For, Show, createMemo, createSignal, onMount, onCleanup } from "solid-js";
import { activityStore, type ActivityData } from "../stores/activity";
import { agentStore } from "../stores/agents";

const ActivityPanel: Component = () => {
  const [now, setNow] = createSignal(Date.now());

  // Tick every second to update durations
  let timer: ReturnType<typeof setInterval>;
  onMount(() => {
    timer = setInterval(() => setNow(Date.now()), 1000);
  });
  onCleanup(() => clearInterval(timer));

  const sortedActivities = createMemo(() => {
    const all = [...activityStore.activities().values()];
    // Active first, then idle, then long-idle
    const order = { active: 0, idle: 1, "long-idle": 2 };
    return all.sort((a, b) => order[a.state] - order[b.state]);
  });

  return (
    <div class="activity-panel">
      <div class="activity-panel-header">
        <h3 class="dashboard-section-title">Agent Activity</h3>
        <span class="activity-panel-count">
          {activityStore.activeAgents().length} active
        </span>
      </div>

      <Show
        when={sortedActivities().length > 0}
        fallback={<div class="dashboard-empty">No agent activity recorded</div>}
      >
        <div class="activity-table-wrap">
          <table class="activity-table">
            <thead>
              <tr>
                <th>Agent</th>
                <th>State</th>
                <th>Current Tool</th>
                <th>Duration</th>
                <th>Cost</th>
                <th>Calls</th>
              </tr>
            </thead>
            <tbody>
              <For each={sortedActivities()}>
                {(activity) => (
                  <ActivityRow activity={activity} now={now()} />
                )}
              </For>
            </tbody>
          </table>
        </div>
      </Show>
    </div>
  );
};

const ActivityRow: Component<{ activity: ActivityData; now: number }> = (props) => {
  const stateClass = () => {
    switch (props.activity.state) {
      case "active": return "activity-state-active";
      case "idle": return "activity-state-idle";
      case "long-idle": return "activity-state-long-idle";
    }
  };

  const duration = () => {
    if (props.activity.currentTool && props.activity.toolStartTime) {
      const elapsed = Math.floor((props.now - props.activity.toolStartTime) / 1000);
      return formatDuration(elapsed);
    }
    if (props.activity.duration > 0) {
      return formatDuration(Math.floor(props.activity.duration));
    }
    return "--";
  };

  const idleTime = () => {
    if (props.activity.lastActive > 0 && !props.activity.currentTool) {
      const idle = Math.floor((props.now - props.activity.lastActive) / 1000);
      if (idle > 0) return `${formatDuration(idle)} idle`;
    }
    return null;
  };

  const cost = () => {
    if (props.activity.totalCost > 0) {
      return `$${props.activity.totalCost.toFixed(4)}`;
    }
    return "--";
  };

  return (
    <tr
      class={`activity-row ${stateClass()}`}
      onClick={() => agentStore.selectAgent(props.activity.agentId)}
    >
      <td class="activity-agent-name">{props.activity.agentName}</td>
      <td>
        <span class={`activity-state-badge ${stateClass()}`}>
          {props.activity.state}
        </span>
      </td>
      <td class="activity-tool">
        <Show when={props.activity.currentTool} fallback={
          <span class="text-dim">{idleTime() ?? "--"}</span>
        }>
          <span class="activity-tool-name">{props.activity.currentTool}</span>
        </Show>
      </td>
      <td class="activity-duration">{duration()}</td>
      <td class="activity-cost">{cost()}</td>
      <td class="activity-calls">{props.activity.callCount || "--"}</td>
    </tr>
  );
};

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (m < 60) return `${m}m ${s}s`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m`;
}

export default ActivityPanel;
