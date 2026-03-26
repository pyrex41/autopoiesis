import { type Component, Show, For, createSignal, createMemo, onMount } from "solid-js";
import { evalStore } from "../stores/eval";
import type { EvalScenario, EvalRun, EvalHarness } from "../api/types";

// ── Helpers ──────────────────────────────────────────────────────

function fmtDuration(ms: number | null): string {
  if (ms === null) return "—";
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

function fmtCost(dollars: number | null): string {
  if (dollars === null) return "—";
  if (dollars < 0.001) return `$${(dollars * 1000).toFixed(3)}m`;
  return `$${dollars.toFixed(4)}`;
}

function fmtPct(rate: number): string {
  return `${(rate * 100).toFixed(0)}%`;
}

function passRateColor(rate: number): string {
  if (rate >= 0.8) return "var(--emerge)";
  if (rate >= 0.5) return "var(--warm)";
  return "var(--danger)";
}

function statusColor(status: string): string {
  switch (status) {
    case "complete": return "var(--emerge)";
    case "running": return "var(--signal)";
    case "failed": return "var(--danger)";
    case "cancelled": return "var(--text-dim)";
    default: return "var(--warm)";
  }
}

const DOMAINS = ["coding", "reasoning", "writing", "analysis", "math", "tool-use", "general"];

// ── Main Component ───────────────────────────────────────────────

const EvalLab: Component = () => {
  onMount(() => evalStore.init());

  // Panel tabs
  const [activeTab, setActiveTab] = createSignal<"scenarios" | "run" | "results">("scenarios");

  // Scenario creation form state
  const [showCreateForm, setShowCreateForm] = createSignal(false);
  const [newName, setNewName] = createSignal("");
  const [newDescription, setNewDescription] = createSignal("");
  const [newPrompt, setNewPrompt] = createSignal("");
  const [newDomain, setNewDomain] = createSignal("general");
  const [creating, setCreating] = createSignal(false);

  // Run configuration state
  const [selectedScenarios, setSelectedScenarios] = createSignal<Set<number>>(new Set());
  const [selectedHarnesses, setSelectedHarnesses] = createSignal<Set<string>>(new Set());
  const [trialsPerCombo, setTrialsPerCombo] = createSignal(3);
  const [useJudge, setUseJudge] = createSignal(false);
  const [runName, setRunName] = createSignal("");
  const [launching, setLaunching] = createSignal(false);

  const state = () => evalStore.evalState();
  const run = () => evalStore.activeRun();
  const progress = createMemo(() => Math.round(evalStore.trialProgress() * 100));

  const isRunning = createMemo(() => run()?.status === "running");

  const completedRuns = createMemo(() =>
    state().runs.filter((r) => r.status === "complete")
  );

  // ── Scenario creation ────────────────────────────────────────

  async function handleCreateScenario() {
    if (!newName().trim() || !newPrompt().trim()) return;
    setCreating(true);
    await evalStore.createScenario({
      name: newName().trim(),
      description: newDescription().trim(),
      prompt: newPrompt().trim(),
      domain: newDomain(),
    });
    setCreating(false);
    setNewName("");
    setNewDescription("");
    setNewPrompt("");
    setNewDomain("general");
    setShowCreateForm(false);
  }

  // ── Run launch ───────────────────────────────────────────────

  async function handleStartRun() {
    const scenarios = [...selectedScenarios()];
    const harnesses = [...selectedHarnesses()];
    if (scenarios.length === 0 || harnesses.length === 0) return;
    const name = runName().trim() || `Run ${new Date().toLocaleTimeString()}`;
    setLaunching(true);
    const newRun = await evalStore.startRun({
      name,
      scenarios,
      harnesses,
      trials: trialsPerCombo(),
      judge: useJudge(),
    });
    setLaunching(false);
    if (newRun) {
      setRunName("");
      setActiveTab("results");
    }
  }

  function toggleScenario(id: number) {
    setSelectedScenarios((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleHarness(name: string) {
    setSelectedHarnesses((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }

  function selectAllScenarios() {
    setSelectedScenarios(new Set(state().scenarios.map((s) => s.id)));
  }

  function selectAllHarnesses() {
    setSelectedHarnesses(new Set(state().harnesses.map((h) => h.name)));
  }

  return (
    <div class="dashboard">
      {/* ── Status Strip ─────────────────────────────────────── */}
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">SCENARIOS</span>
            <span class="sys-indicator-value">{state().scenarios.length}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">HARNESSES</span>
            <span class="sys-indicator-value">{state().harnesses.length}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">RUNS</span>
            <span class="sys-indicator-value">{state().runs.length}</span>
          </div>
          <Show when={run()}>
            <div class="sys-indicator">
              <span class="sys-indicator-label">STATUS</span>
              <span
                class="sys-indicator-value"
                style={{ color: statusColor(run()!.status) }}
              >
                {run()!.status.toUpperCase()}
              </span>
            </div>
            <Show when={isRunning()}>
              <div class="sys-indicator">
                <span class="sys-indicator-label">PROGRESS</span>
                <span class="sys-indicator-value sys-active">
                  {run()!.completedTrials} / {run()!.totalTrials}
                </span>
              </div>
            </Show>
          </Show>
        </div>
        <div class="sys-strip-actions">
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": activeTab() === "scenarios" }}
            onClick={() => setActiveTab("scenarios")}
          >
            Scenarios
          </button>
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": activeTab() === "run" }}
            onClick={() => setActiveTab("run")}
          >
            Run
          </button>
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": activeTab() === "results" }}
            onClick={() => setActiveTab("results")}
          >
            Results
          </button>
        </div>
      </div>

      {/* ── Active run progress bar ───────────────────────────── */}
      <Show when={isRunning()}>
        <div class="eval-run-progress-track">
          <div
            class="eval-run-progress-fill"
            style={{ width: `${progress()}%` }}
          />
        </div>
      </Show>

      <div class="dashboard-panels">

        {/* ── Scenarios Panel ───────────────────────────────────── */}
        <Show when={activeTab() === "scenarios"}>
          <div class="dash-panel">
            <div class="dash-panel-header">
              <h3 class="dash-panel-title">
                <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                  <rect x="1.5" y="1.5" width="11" height="11" rx="2" stroke="currentColor" stroke-width="1.2"/>
                  <path d="M4 5h6M4 7.5h4" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
                </svg>
                Eval Scenarios
              </h3>
              <div style={{ display: "flex", "align-items": "center", gap: "8px" }}>
                <span class="dash-panel-count">{state().scenarios.length}</span>
                <button
                  class="eval-add-btn"
                  onClick={() => setShowCreateForm((v) => !v)}
                >
                  {showCreateForm() ? "Cancel" : "+ New"}
                </button>
              </div>
            </div>

            {/* Create form */}
            <Show when={showCreateForm()}>
              <div class="eval-create-form">
                <div class="eval-form-row">
                  <label class="eval-form-label">Name</label>
                  <input
                    type="text"
                    class="eval-form-input"
                    placeholder="Scenario name..."
                    value={newName()}
                    onInput={(e) => setNewName(e.currentTarget.value)}
                  />
                </div>
                <div class="eval-form-row">
                  <label class="eval-form-label">Domain</label>
                  <select
                    class="eval-form-select"
                    value={newDomain()}
                    onChange={(e) => setNewDomain(e.currentTarget.value)}
                  >
                    <For each={DOMAINS}>
                      {(d) => <option value={d}>{d}</option>}
                    </For>
                  </select>
                </div>
                <div class="eval-form-row">
                  <label class="eval-form-label">Description</label>
                  <input
                    type="text"
                    class="eval-form-input"
                    placeholder="Brief description..."
                    value={newDescription()}
                    onInput={(e) => setNewDescription(e.currentTarget.value)}
                  />
                </div>
                <div class="eval-form-col">
                  <label class="eval-form-label">Prompt</label>
                  <textarea
                    class="eval-form-textarea"
                    placeholder="The eval prompt sent to the agent..."
                    value={newPrompt()}
                    onInput={(e) => setNewPrompt(e.currentTarget.value)}
                    rows="4"
                  />
                </div>
                <div class="eval-form-actions">
                  <button
                    class="eval-primary-btn"
                    disabled={!newName().trim() || !newPrompt().trim() || creating()}
                    onClick={handleCreateScenario}
                  >
                    {creating() ? "Creating..." : "Create Scenario"}
                  </button>
                </div>
              </div>
            </Show>

            {/* Scenario list */}
            <Show
              when={state().scenarios.length > 0}
              fallback={
                <div class="dash-standby">
                  <div class="dash-standby-scan" />
                  <span class="dash-standby-text">No scenarios yet — create one above</span>
                </div>
              }
            >
              <div class="eval-scenario-list">
                <For each={state().scenarios}>
                  {(scenario) => <ScenarioRow scenario={scenario} />}
                </For>
              </div>
            </Show>
          </div>
        </Show>

        {/* ── Run Control Panel ─────────────────────────────────── */}
        <Show when={activeTab() === "run"}>
          <div class="dash-panel">
            <div class="dash-panel-header">
              <h3 class="dash-panel-title">
                <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                  <polygon points="3,1.5 13,7 3,12.5" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>
                </svg>
                Launch Eval Run
              </h3>
            </div>

            <div class="eval-run-config">
              {/* Run name */}
              <div class="eval-config-section">
                <div class="eval-config-label">Run Name</div>
                <input
                  type="text"
                  class="eval-form-input"
                  placeholder={`Run ${new Date().toLocaleDateString()}`}
                  value={runName()}
                  onInput={(e) => setRunName(e.currentTarget.value)}
                  disabled={isRunning()}
                />
              </div>

              {/* Scenario selection */}
              <div class="eval-config-section">
                <div class="eval-config-section-header">
                  <div class="eval-config-label">
                    Scenarios
                    <span class="eval-selected-count">
                      {selectedScenarios().size} selected
                    </span>
                  </div>
                  <button class="eval-select-all-btn" onClick={selectAllScenarios} disabled={isRunning()}>
                    Select All
                  </button>
                </div>
                <Show
                  when={state().scenarios.length > 0}
                  fallback={<div class="eval-empty-note">No scenarios available</div>}
                >
                  <div class="eval-check-list">
                    <For each={state().scenarios}>
                      {(scenario) => (
                        <label class="eval-check-row">
                          <input
                            type="checkbox"
                            class="eval-checkbox"
                            checked={selectedScenarios().has(scenario.id)}
                            onChange={() => toggleScenario(scenario.id)}
                            disabled={isRunning()}
                          />
                          <span class="eval-check-name">{scenario.name}</span>
                          <Show when={scenario.domain}>
                            <span class="eval-check-tag">{scenario.domain}</span>
                          </Show>
                        </label>
                      )}
                    </For>
                  </div>
                </Show>
              </div>

              {/* Harness selection */}
              <div class="eval-config-section">
                <div class="eval-config-section-header">
                  <div class="eval-config-label">
                    Harnesses
                    <span class="eval-selected-count">
                      {selectedHarnesses().size} selected
                    </span>
                  </div>
                  <button class="eval-select-all-btn" onClick={selectAllHarnesses} disabled={isRunning()}>
                    Select All
                  </button>
                </div>
                <Show
                  when={state().harnesses.length > 0}
                  fallback={<div class="eval-empty-note">No harnesses available</div>}
                >
                  <div class="eval-check-list">
                    <For each={state().harnesses}>
                      {(harness) => (
                        <label class="eval-check-row">
                          <input
                            type="checkbox"
                            class="eval-checkbox"
                            checked={selectedHarnesses().has(harness.name)}
                            onChange={() => toggleHarness(harness.name)}
                            disabled={isRunning()}
                          />
                          <span class="eval-check-name">{harness.name}</span>
                          <span class="eval-check-tag">{harness.type}</span>
                        </label>
                      )}
                    </For>
                  </div>
                </Show>
              </div>

              {/* Run parameters */}
              <div class="eval-config-section">
                <div class="eval-config-label">Parameters</div>
                <div class="eval-param-grid">
                  <div class="eval-param-row">
                    <label class="eval-param-label">Trials per combination</label>
                    <input
                      type="number"
                      class="eval-param-input"
                      value={trialsPerCombo()}
                      onInput={(e) => setTrialsPerCombo(parseInt(e.currentTarget.value) || 1)}
                      min="1"
                      max="20"
                      disabled={isRunning()}
                    />
                  </div>
                  <div class="eval-param-row">
                    <label class="eval-param-label">LLM judge scoring</label>
                    <label class="eval-toggle">
                      <input
                        type="checkbox"
                        checked={useJudge()}
                        onChange={(e) => setUseJudge(e.currentTarget.checked)}
                        disabled={isRunning()}
                      />
                      <span class="eval-toggle-track" />
                    </label>
                  </div>
                </div>
              </div>

              {/* Estimated info */}
              <Show when={selectedScenarios().size > 0 && selectedHarnesses().size > 0}>
                <div class="eval-estimate">
                  <span class="eval-estimate-label">Est. trials</span>
                  <span class="eval-estimate-value">
                    {selectedScenarios().size} scenarios × {selectedHarnesses().size} harnesses × {trialsPerCombo()} = {selectedScenarios().size * selectedHarnesses().size * trialsPerCombo()}
                  </span>
                </div>
              </Show>

              {/* Launch controls */}
              <div class="eval-launch-row">
                <Show
                  when={!isRunning()}
                  fallback={
                    <button
                      class="eval-cancel-btn"
                      onClick={() => run() && evalStore.cancelRun(run()!.id)}
                    >
                      Cancel Run
                    </button>
                  }
                >
                  <button
                    class="eval-primary-btn"
                    disabled={
                      selectedScenarios().size === 0 ||
                      selectedHarnesses().size === 0 ||
                      launching()
                    }
                    onClick={handleStartRun}
                  >
                    {launching() ? "Launching..." : "Start Eval Run"}
                  </button>
                </Show>
                <Show when={isRunning()}>
                  <div class="eval-run-live">
                    <span class="eval-live-dot" />
                    <span class="eval-live-label">
                      {run()!.name} — {progress()}%
                    </span>
                  </div>
                </Show>
              </div>
            </div>
          </div>

          {/* Recent runs list */}
          <Show when={state().runs.length > 0}>
            <div class="dash-panel">
              <div class="dash-panel-header">
                <h3 class="dash-panel-title">
                  <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                    <circle cx="7" cy="7" r="5.5" stroke="currentColor" stroke-width="1.2"/>
                    <path d="M7 4v3.5l2 1.5" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
                  </svg>
                  Recent Runs
                </h3>
                <span class="dash-panel-count">{state().runs.length}</span>
              </div>
              <div class="eval-runs-list">
                <For each={[...state().runs].reverse()}>
                  {(r) => (
                    <button
                      class="eval-run-row"
                      classList={{ "eval-run-row-active": state().activeRunId === r.id }}
                      onClick={() => {
                        evalStore.selectRun(r.id);
                        setActiveTab("results");
                      }}
                    >
                      <span class="eval-run-dot" style={{ background: statusColor(r.status) }} />
                      <span class="eval-run-name">{r.name}</span>
                      <span class="eval-run-meta">
                        {r.completedTrials}/{r.totalTrials} trials
                      </span>
                      <span class="eval-run-status" style={{ color: statusColor(r.status) }}>
                        {r.status}
                      </span>
                    </button>
                  )}
                </For>
              </div>
            </div>
          </Show>
        </Show>

        {/* ── Results Panel ─────────────────────────────────────── */}
        <Show when={activeTab() === "results"}>
          <Show
            when={completedRuns().length > 0 || run()}
            fallback={
              <div class="dash-panel">
                <div class="dash-standby">
                  <div class="dash-standby-scan" />
                  <span class="dash-standby-text">No completed runs yet — start a run to see results</span>
                </div>
              </div>
            }
          >
            {/* Run selector */}
            <div class="eval-results-selector">
              <span class="eval-results-selector-label">View run:</span>
              <select
                class="eval-form-select"
                value={state().activeRunId ?? ""}
                onChange={(e) => {
                  const id = parseInt(e.currentTarget.value);
                  if (!isNaN(id)) evalStore.selectRun(id);
                }}
              >
                <option value="">— select run —</option>
                <For each={[...state().runs].reverse()}>
                  {(r) => (
                    <option value={r.id}>
                      {r.name} ({r.status})
                    </option>
                  )}
                </For>
              </select>
            </div>

            <Show when={state().comparison}>
              {(cmp) => <ComparisonMatrix comparison={cmp()} />}
            </Show>

            <Show when={state().activeRunId && !state().comparison}>
              <div class="dash-panel">
                <div class="dash-standby dash-standby-compact">
                  <span class="dash-standby-text">
                    {run()?.status === "running"
                      ? `Run in progress — ${progress()}% complete`
                      : "Loading comparison data..."}
                  </span>
                </div>
              </div>
            </Show>
          </Show>
        </Show>

      </div>
    </div>
  );
};

// ── Sub-components ────────────────────────────────────────────────

const ScenarioRow: Component<{ scenario: EvalScenario }> = (props) => {
  const [expanded, setExpanded] = createSignal(false);

  return (
    <div class="eval-scenario-row-wrap">
      <button
        class="eval-scenario-row"
        classList={{ "eval-scenario-row-expanded": expanded() }}
        onClick={() => setExpanded((v) => !v)}
      >
        <span class="eval-scenario-name">{props.scenario.name}</span>
        <Show when={props.scenario.domain}>
          <span class="eval-scenario-domain">{props.scenario.domain}</span>
        </Show>
        <span class="eval-scenario-meta">
          <Show when={props.scenario.hasRubric}>
            <span class="eval-scenario-badge eval-badge-rubric">rubric</span>
          </Show>
          <Show when={props.scenario.hasVerifier}>
            <span class="eval-scenario-badge eval-badge-verifier">verifier</span>
          </Show>
        </span>
        <span class="eval-scenario-chevron">{expanded() ? "▲" : "▼"}</span>
      </button>
      <Show when={expanded()}>
        <div class="eval-scenario-detail">
          <Show when={props.scenario.description}>
            <div class="eval-detail-row">
              <span class="eval-detail-label">Description</span>
              <span class="eval-detail-value">{props.scenario.description}</span>
            </div>
          </Show>
          <div class="eval-detail-row">
            <span class="eval-detail-label">Prompt</span>
            <pre class="eval-detail-pre">{props.scenario.prompt}</pre>
          </div>
          <div class="eval-detail-row">
            <span class="eval-detail-label">Created</span>
            <span class="eval-detail-value eval-dim">
              {new Date(props.scenario.createdAt).toLocaleString()}
            </span>
          </div>
        </div>
      </Show>
    </div>
  );
};

interface ComparisonProps {
  comparison: NonNullable<ReturnType<typeof evalStore.evalState>["comparison"]>;
}

const ComparisonMatrix: Component<ComparisonProps> = (props) => {
  const harnesses = createMemo(() => {
    const names = new Set<string>();
    for (const row of props.comparison.scenarios) {
      for (const hr of row.harnessResults) names.add(hr.harness);
    }
    return [...names];
  });

  return (
    <>
      <div class="dash-panel">
        <div class="dash-panel-header">
          <h3 class="dash-panel-title">
            <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
              <rect x="1" y="1" width="12" height="12" rx="1.5" stroke="currentColor" stroke-width="1.2"/>
              <path d="M1 5h12M5 1v12" stroke="currentColor" stroke-width="0.9" opacity="0.6"/>
            </svg>
            Comparison Matrix — {props.comparison.runName}
          </h3>
          <span class="dash-panel-count">{props.comparison.scenarios.length} scenarios</span>
        </div>

        <div class="eval-matrix-wrap">
          <table class="eval-matrix">
            <thead>
              <tr>
                <th class="eval-matrix-th eval-matrix-scenario-col">Scenario</th>
                <For each={harnesses()}>
                  {(h) => <th class="eval-matrix-th eval-matrix-harness-col">{h}</th>}
                </For>
              </tr>
            </thead>
            <tbody>
              <For each={props.comparison.scenarios}>
                {(row) => (
                  <tr class="eval-matrix-row">
                    <td class="eval-matrix-td eval-matrix-scenario-name">{row.scenarioName}</td>
                    <For each={harnesses()}>
                      {(harnessName) => {
                        const result = row.harnessResults.find((hr) => hr.harness === harnessName);
                        return (
                          <td class="eval-matrix-td eval-matrix-cell">
                            <Show
                              when={result}
                              fallback={<span class="eval-matrix-empty">—</span>}
                            >
                              <MatrixCell result={result!} />
                            </Show>
                          </td>
                        );
                      }}
                    </For>
                  </tr>
                )}
              </For>

              {/* Aggregate row */}
              <Show when={props.comparison.aggregate.length > 0}>
                <tr class="eval-matrix-row eval-matrix-agg-row">
                  <td class="eval-matrix-td eval-matrix-scenario-name eval-agg-label">AGGREGATE</td>
                  <For each={harnesses()}>
                    {(harnessName) => {
                      const agg = props.comparison.aggregate.find((a) => a.harness === harnessName);
                      return (
                        <td class="eval-matrix-td eval-matrix-cell">
                          <Show when={agg} fallback={<span class="eval-matrix-empty">—</span>}>
                            <div class="eval-cell-passrate" style={{ color: passRateColor(agg!.overallPassRate) }}>
                              {fmtPct(agg!.overallPassRate)}
                            </div>
                            <div class="eval-cell-sub">
                              {fmtDuration(agg!.avgDuration)}
                            </div>
                            <Show when={agg!.totalCost !== null}>
                              <div class="eval-cell-sub eval-cell-cost">
                                {fmtCost(agg!.totalCost)}
                              </div>
                            </Show>
                          </Show>
                        </td>
                      );
                    }}
                  </For>
                </tr>
              </Show>
            </tbody>
          </table>
        </div>

        {/* Legend */}
        <div class="eval-matrix-legend">
          <span class="eval-legend-item">
            <span class="eval-legend-dot" style={{ background: "var(--emerge)" }} />
            Pass rate ≥ 80%
          </span>
          <span class="eval-legend-item">
            <span class="eval-legend-dot" style={{ background: "var(--warm)" }} />
            50–79%
          </span>
          <span class="eval-legend-item">
            <span class="eval-legend-dot" style={{ background: "var(--danger)" }} />
            {"< 50%"}
          </span>
        </div>
      </div>

      {/* Per-harness aggregate table */}
      <Show when={props.comparison.aggregate.length > 0}>
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <path d="M1 12L4 8l3 2 3-5 3-2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
              Aggregate by Harness
            </h3>
          </div>
          <div class="eval-agg-table">
            <div class="eval-agg-header">
              <span>Harness</span>
              <span>Pass Rate</span>
              <span>Avg Duration</span>
              <span>Total Cost</span>
              <span>Avg Score</span>
              <span>Trials</span>
            </div>
            <For each={props.comparison.aggregate}>
              {(agg) => (
                <div class="eval-agg-row">
                  <span class="eval-agg-harness">{agg.harness}</span>
                  <span class="eval-agg-pass" style={{ color: passRateColor(agg.overallPassRate) }}>
                    {fmtPct(agg.overallPassRate)}
                  </span>
                  <span class="eval-agg-dur">{fmtDuration(agg.avgDuration)}</span>
                  <span class="eval-agg-cost">{fmtCost(agg.totalCost)}</span>
                  <span class="eval-agg-score">
                    {agg.avgScore !== null ? agg.avgScore.toFixed(2) : "—"}
                  </span>
                  <span class="eval-agg-trials eval-dim">{agg.totalTrials}</span>
                </div>
              )}
            </For>
          </div>
        </div>
      </Show>
    </>
  );
};

interface MatrixCellProps {
  result: {
    harness: string;
    passRate: number;
    avgDuration: number | null;
    avgCost: number | null;
    avgScore: number | null;
    totalTrials: number;
  };
}

const MatrixCell: Component<MatrixCellProps> = (props) => {
  return (
    <div class="eval-cell">
      <div
        class="eval-cell-passrate"
        style={{ color: passRateColor(props.result.passRate) }}
      >
        {fmtPct(props.result.passRate)}
      </div>
      <div class="eval-cell-bar-track">
        <div
          class="eval-cell-bar-fill"
          style={{
            width: `${props.result.passRate * 100}%`,
            background: passRateColor(props.result.passRate),
          }}
        />
      </div>
      <div class="eval-cell-sub">{fmtDuration(props.result.avgDuration)}</div>
      <Show when={props.result.avgCost !== null}>
        <div class="eval-cell-sub eval-cell-cost">{fmtCost(props.result.avgCost)}</div>
      </Show>
    </div>
  );
};

export default EvalLab;
