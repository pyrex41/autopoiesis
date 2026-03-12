import { type Component, Show, onMount, onCleanup, createMemo } from "solid-js";
import { conductorStore } from "../stores/conductor";

// Simple sparkline component
const Sparkline: Component<{ data: number[]; color: string; width?: number; height?: number }> = (props) => {
  const w = () => props.width ?? 200;
  const h = () => props.height ?? 40;

  const path = createMemo(() => {
    const d = props.data;
    if (d.length < 2) return "";
    const max = Math.max(...d, 1);
    const min = Math.min(...d, 0);
    const range = max - min || 1;
    const xStep = w() / (d.length - 1);
    return d.map((v, i) => {
      const x = i * xStep;
      const y = h() - ((v - min) / range) * h();
      return `${i === 0 ? "M" : "L"}${x},${y}`;
    }).join(" ");
  });

  return (
    <svg width={w()} height={h()} class="sparkline">
      <path d={path()} fill="none" stroke={props.color} stroke-width="1.5" />
    </svg>
  );
};

const MetricCard: Component<{ label: string; value: number | string; color?: string }> = (props) => (
  <div class="conductor-metric">
    <div class="conductor-metric-value" style={{ color: props.color ?? "var(--signal)" }}>
      {props.value}
    </div>
    <div class="conductor-metric-label">{props.label}</div>
  </div>
);

const ConductorDashboard: Component = () => {
  onMount(() => {
    conductorStore.init();
    conductorStore.subscribe();
  });

  onCleanup(() => {
    conductorStore.unsubscribe();
  });

  const m = () => conductorStore.metrics();

  return (
    <div class="conductor-dashboard">
      <div class="conductor-header">
        <h3>Conductor</h3>
        <Show when={m()}>
          <div class="conductor-status" classList={{ running: m()!.running }}>
            {m()!.running ? "Running" : "Stopped"}
          </div>
        </Show>
        <div class="conductor-actions">
          <button class="btn-sm" onClick={() => conductorStore.startConductor()}>Start</button>
          <button class="btn-sm btn-danger" onClick={() => conductorStore.stopConductor()}>Stop</button>
        </div>
      </div>

      <Show when={m()} fallback={<div class="conductor-empty">Conductor not connected</div>}>
        <div class="conductor-metrics-grid">
          <MetricCard label="Ticks" value={m()!.tickCount} color="var(--signal)" />
          <MetricCard label="Events OK" value={m()!.eventsProcessed} color="var(--emerge)" />
          <MetricCard label="Events Failed" value={m()!.eventsFailed} color="var(--danger)" />
          <MetricCard label="Workers" value={m()!.activeWorkers} color="var(--warm)" />
          <MetricCard label="Pending Timers" value={m()!.pendingTimers} color="var(--purple)" />
          <MetricCard label="Task Retries" value={m()!.taskRetries} />
        </div>

        <Show when={conductorStore.tickHistory().length > 1}>
          <div class="conductor-sparklines">
            <div class="conductor-sparkline-group">
              <span class="conductor-sparkline-label">Ticks</span>
              <Sparkline data={conductorStore.tickHistory()} color="var(--signal)" />
            </div>
            <div class="conductor-sparkline-group">
              <span class="conductor-sparkline-label">Events</span>
              <Sparkline data={conductorStore.eventHistory()} color="var(--emerge)" />
            </div>
          </div>
        </Show>

        <Show when={m()!.triggersChecked != null}>
          <div class="conductor-section">
            <h4>Crystallization</h4>
            <MetricCard label="Triggers Checked" value={m()!.triggersChecked!} />
            <MetricCard label="Crystallizations" value={m()!.crystallizations ?? 0} />
          </div>
        </Show>
      </Show>
    </div>
  );
};

export default ConductorDashboard;
