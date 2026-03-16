import { type Component, Show, For, createSignal, createMemo, onMount } from "solid-js";
import { evolutionStore } from "../stores/evolution";

const EvolutionLab: Component = () => {
  onMount(() => evolutionStore.init());

  const [generations, setGenerations] = createSignal(10);
  const [mutationRate, setMutationRate] = createSignal(0.1);
  const [populationSize, setPopulationSize] = createSignal(10);

  const evo = () => evolutionStore.evolution();

  function handleStart() {
    evolutionStore.startEvolution({
      generations: generations(),
      mutationRate: mutationRate(),
      populationSize: populationSize(),
    });
  }

  const progress = createMemo(() => {
    const e = evo();
    if (!e.totalGenerations) return 0;
    return (e.generation / e.totalGenerations) * 100;
  });

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">STATUS</span>
            <span class="sys-indicator-value" classList={{
              "sys-active": evo().running,
            }}>
              {evo().running ? "RUNNING" : "IDLE"}
            </span>
          </div>
          <Show when={evo().running}>
            <div class="sys-indicator">
              <span class="sys-indicator-label">GENERATION</span>
              <span class="sys-indicator-value">{evo().generation} / {evo().totalGenerations}</span>
            </div>
            <div class="sys-indicator">
              <span class="sys-indicator-label">POPULATION</span>
              <span class="sys-indicator-value">{evo().populationSize}</span>
            </div>
          </Show>
        </div>
        <div class="sys-strip-actions">
          <Show when={!evo().running} fallback={
            <button class="sys-action-btn evo-stop-btn" onClick={() => evolutionStore.stopEvolution()}>
              Stop Evolution
            </button>
          }>
            <button class="sys-action-btn" onClick={handleStart}>
              Start Evolution
            </button>
          </Show>
        </div>
      </div>

      <div class="dashboard-panels">
        {/* Controls */}
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <path d="M2 10c1-3 3-5 5-5s3.5 1 5 4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
                <circle cx="4" cy="4" r="1.5" stroke="currentColor" stroke-width="1.1"/>
                <circle cx="10" cy="3" r="1.5" stroke="currentColor" stroke-width="1.1"/>
              </svg>
              Evolution Parameters
            </h3>
          </div>
          <div class="evo-controls">
            <div class="evo-control-row">
              <label class="evo-label">Generations</label>
              <input
                type="number"
                class="evo-input"
                value={generations()}
                onInput={(e) => setGenerations(parseInt(e.currentTarget.value) || 10)}
                disabled={evo().running}
                min="1"
                max="1000"
              />
            </div>
            <div class="evo-control-row">
              <label class="evo-label">Mutation Rate</label>
              <input
                type="number"
                class="evo-input"
                value={mutationRate()}
                onInput={(e) => setMutationRate(parseFloat(e.currentTarget.value) || 0.1)}
                disabled={evo().running}
                min="0"
                max="1"
                step="0.05"
              />
            </div>
            <div class="evo-control-row">
              <label class="evo-label">Population Size</label>
              <input
                type="number"
                class="evo-input"
                value={populationSize()}
                onInput={(e) => setPopulationSize(parseInt(e.currentTarget.value) || 10)}
                disabled={evo().running}
                min="2"
                max="100"
              />
            </div>
          </div>
          <Show when={evo().running}>
            <div class="evo-progress-bar">
              <div class="evo-progress-fill" style={{ width: `${progress()}%` }} />
            </div>
          </Show>
        </div>

        {/* Fitness Chart */}
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <path d="M1 12L4 8l3 2 3-5 3-2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
              Fitness Over Generations
            </h3>
          </div>
          <Show when={evo().fitnessHistory.length > 0} fallback={
            <div class="dash-standby">
              <span class="dash-standby-text">Start evolution to see fitness trends</span>
            </div>
          }>
            <FitnessChart data={evo().fitnessHistory} />
          </Show>
        </div>

        {/* Fitness History Table */}
        <Show when={evo().fitnessHistory.length > 0}>
          <div class="dash-panel">
            <div class="dash-panel-header">
              <h3 class="dash-panel-title">Generation Log</h3>
              <span class="dash-panel-count">{evo().fitnessHistory.length}</span>
            </div>
            <div class="evo-history-table">
              <div class="evo-history-header">
                <span>Gen</span>
                <span>Best</span>
                <span>Avg</span>
                <span>Worst</span>
              </div>
              <For each={[...evo().fitnessHistory].reverse().slice(0, 20)}>
                {(entry) => (
                  <div class="evo-history-row">
                    <span class="evo-gen-num">{entry.generation}</span>
                    <span class="evo-fitness-best">{entry.best.toFixed(3)}</span>
                    <span class="evo-fitness-avg">{entry.avg.toFixed(3)}</span>
                    <span class="evo-fitness-worst">{entry.worst.toFixed(3)}</span>
                  </div>
                )}
              </For>
            </div>
          </div>
        </Show>
      </div>
    </div>
  );
};

const FitnessChart: Component<{ data: Array<{ generation: number; best: number; avg: number; worst: number }> }> = (props) => {
  const chartWidth = 500;
  const chartHeight = 200;
  const padding = { top: 20, right: 20, bottom: 30, left: 40 };
  const innerWidth = chartWidth - padding.left - padding.right;
  const innerHeight = chartHeight - padding.top - padding.bottom;

  const scales = createMemo(() => {
    const data = props.data;
    if (data.length === 0) return { xScale: (x: number) => x, yScale: (y: number) => y, maxY: 1, maxX: 1 };

    const maxX = Math.max(...data.map((d) => d.generation));
    const maxY = Math.max(...data.map((d) => d.best), 1);
    const minY = Math.min(...data.map((d) => d.worst), 0);
    const yRange = maxY - minY || 1;

    return {
      xScale: (x: number) => padding.left + (x / (maxX || 1)) * innerWidth,
      yScale: (y: number) => padding.top + innerHeight - ((y - minY) / yRange) * innerHeight,
      maxY,
      maxX,
    };
  });

  const linePath = (key: "best" | "avg" | "worst") => {
    const { xScale, yScale } = scales();
    return props.data
      .map((d, i) => `${i === 0 ? "M" : "L"}${xScale(d.generation).toFixed(1)},${yScale(d[key]).toFixed(1)}`)
      .join(" ");
  };

  return (
    <svg width="100%" viewBox={`0 0 ${chartWidth} ${chartHeight}`} class="evo-chart">
      {/* Grid lines */}
      <line x1={padding.left} y1={padding.top} x2={padding.left} y2={padding.top + innerHeight} stroke="var(--border)" stroke-width="0.5" />
      <line x1={padding.left} y1={padding.top + innerHeight} x2={padding.left + innerWidth} y2={padding.top + innerHeight} stroke="var(--border)" stroke-width="0.5" />

      {/* Lines */}
      <Show when={props.data.length > 1}>
        <path d={linePath("worst")} fill="none" stroke="var(--danger)" stroke-width="1" opacity="0.4" />
        <path d={linePath("avg")} fill="none" stroke="var(--warm)" stroke-width="1.5" opacity="0.7" />
        <path d={linePath("best")} fill="none" stroke="var(--emerge)" stroke-width="2" />
      </Show>

      {/* Data points for best */}
      <For each={props.data}>
        {(d) => (
          <circle
            cx={scales().xScale(d.generation)}
            cy={scales().yScale(d.best)}
            r="2.5"
            fill="var(--emerge)"
          />
        )}
      </For>

      {/* Legend */}
      <g transform={`translate(${padding.left + 10}, ${padding.top + 5})`}>
        <line x1="0" y1="0" x2="12" y2="0" stroke="var(--emerge)" stroke-width="2" />
        <text x="16" y="4" fill="var(--text-muted)" font-size="9">Best</text>
        <line x1="45" y1="0" x2="57" y2="0" stroke="var(--warm)" stroke-width="1.5" opacity="0.7" />
        <text x="61" y="4" fill="var(--text-muted)" font-size="9">Avg</text>
        <line x1="85" y1="0" x2="97" y2="0" stroke="var(--danger)" stroke-width="1" opacity="0.4" />
        <text x="101" y="4" fill="var(--text-muted)" font-size="9">Worst</text>
      </g>

      {/* Axis labels */}
      <text x={chartWidth / 2} y={chartHeight - 4} fill="var(--text-dim)" font-size="9" text-anchor="middle">Generation</text>
      <text x="4" y={chartHeight / 2} fill="var(--text-dim)" font-size="9" text-anchor="middle" transform={`rotate(-90, 4, ${chartHeight / 2})`}>Fitness</text>
    </svg>
  );
};

export default EvolutionLab;
