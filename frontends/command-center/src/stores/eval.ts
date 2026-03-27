import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";
import type { EvalScenario, EvalRun, EvalTrial, EvalHarness, EvalComparison } from "../api/types";
import * as api from "../api/client";

interface EvalState {
  scenarios: EvalScenario[];
  harnesses: EvalHarness[];
  runs: EvalRun[];
  activeRunId: number | null;
  trials: EvalTrial[];
  comparison: EvalComparison | null;
}

const [evalState, setEvalState] = createSignal<EvalState>({
  scenarios: [],
  harnesses: [],
  runs: [],
  activeRunId: null,
  trials: [],
  comparison: null,
});

const activeRun = createMemo(() => {
  const id = evalState().activeRunId;
  if (id === null) return null;
  return evalState().runs.find((r) => r.id === id) ?? null;
});

const completedTrials = createMemo(() =>
  evalState().trials.filter((t) => t.status === "complete" || t.status === "failed")
);

const trialProgress = createMemo(() => {
  const run = activeRun();
  if (!run) return 0;
  const total = evalState().trials.length;
  if (total === 0) return 0;
  return completedTrials().length / total;
});

// ── Data loading ────────────────────────────────────────────────

async function loadScenarios() {
  try {
    const data = await api.listEvalScenarios();
    setEvalState((prev) => ({ ...prev, scenarios: Array.isArray(data) ? data : [] }));
  } catch { /* ignore */ }
}

async function loadHarnesses() {
  try {
    const data = await api.listEvalHarnesses();
    setEvalState((prev) => ({ ...prev, harnesses: Array.isArray(data) ? data : [] }));
  } catch { /* ignore */ }
}

async function loadRuns() {
  try {
    const data = await api.listEvalRuns();
    setEvalState((prev) => ({ ...prev, runs: Array.isArray(data) ? data : [] }));
  } catch { /* ignore */ }
}

async function loadTrials(runId: number) {
  try {
    const data = await api.getEvalTrials(runId);
    setEvalState((prev) => ({ ...prev, trials: Array.isArray(data) ? data : [] }));
  } catch { /* ignore */ }
}

async function loadComparison(runId: number) {
  try {
    const data = await api.getEvalComparison(runId);
    setEvalState((prev) => ({ ...prev, comparison: data }));
  } catch { /* ignore */ }
}

// ── Actions ─────────────────────────────────────────────────────

async function createScenario(data: { name: string; description: string; prompt: string; domain?: string; rubric?: string }) {
  try {
    const scenario = await api.createEvalScenario(data);
    if (scenario) {
      setEvalState((prev) => ({ ...prev, scenarios: [...prev.scenarios, scenario] }));
    }
    return scenario;
  } catch { return null; }
}

async function startRun(data: { name: string; scenarios: number[]; harnesses: string[]; trials?: number; judge?: boolean }) {
  try {
    const { judge, ...runData } = data;
    const run = await api.createEvalRun(runData);
    if (run) {
      setEvalState((prev) => ({
        ...prev,
        runs: [...prev.runs, run],
        activeRunId: run.id,
        trials: [],
        comparison: null,
      }));
      await api.executeEvalRun(run.id, { judge });
      return run;
    }
  } catch { /* ignore */ }
  return null;
}

async function cancelRun(runId: number) {
  try {
    await api.cancelEvalRun(runId);
    setEvalState((prev) => ({
      ...prev,
      runs: prev.runs.map((r) => (r.id === runId ? { ...r, status: "cancelled" } : r)),
    }));
  } catch { /* ignore */ }
}

function selectRun(runId: number | null) {
  setEvalState((prev) => ({ ...prev, activeRunId: runId, trials: [], comparison: null }));
  if (runId !== null) {
    loadTrials(runId);
    loadComparison(runId);
  }
}

// ── WebSocket handlers ──────────────────────────────────────────

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "eval_scenarios": {
      const list = (msg as any).scenarios;
      if (Array.isArray(list)) setEvalState((prev) => ({ ...prev, scenarios: list }));
      break;
    }
    case "eval_scenario_created": {
      const s = (msg as any).scenario as EvalScenario;
      if (s) setEvalState((prev) => ({ ...prev, scenarios: [...prev.scenarios, s] }));
      break;
    }
    case "eval_runs": {
      const list = (msg as any).runs;
      if (Array.isArray(list)) setEvalState((prev) => ({ ...prev, runs: list }));
      break;
    }
    case "eval_run_started": {
      const run = (msg as any).run as EvalRun;
      if (run) {
        setEvalState((prev) => ({
          ...prev,
          runs: prev.runs.some((r) => r.id === run.id)
            ? prev.runs.map((r) => (r.id === run.id ? run : r))
            : [...prev.runs, run],
          activeRunId: run.id,
        }));
      }
      break;
    }
    case "eval_trial_complete": {
      const trial = (msg as any).trial as EvalTrial;
      if (trial) {
        setEvalState((prev) => ({
          ...prev,
          trials: prev.trials.some((t) => t.id === trial.id)
            ? prev.trials.map((t) => (t.id === trial.id ? trial : t))
            : [...prev.trials, trial],
        }));
      }
      break;
    }
    case "eval_run_cancelled": {
      const runId = (msg as any).runId as number;
      if (runId) {
        setEvalState((prev) => ({
          ...prev,
          runs: prev.runs.map((r) => (r.id === runId ? { ...r, status: "cancelled" } : r)),
        }));
      }
      break;
    }
    case "eval_run_failed": {
      const runId = (msg as any).runId as number;
      if (runId) {
        setEvalState((prev) => ({
          ...prev,
          runs: prev.runs.map((r) => (r.id === runId ? { ...r, status: "failed" } : r)),
        }));
      }
      break;
    }
    case "eval_harnesses": {
      const list = (msg as any).harnesses;
      if (Array.isArray(list)) setEvalState((prev) => ({ ...prev, harnesses: list }));
      break;
    }
  }
}

// ── Init ────────────────────────────────────────────────────────

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.subscribe("eval");
  loadScenarios();
  loadHarnesses();
  loadRuns();
}

export const evalStore = {
  evalState,
  activeRun,
  completedTrials,
  trialProgress,
  init,
  loadScenarios,
  loadHarnesses,
  loadRuns,
  loadTrials,
  loadComparison,
  createScenario,
  startRun,
  cancelRun,
  selectRun,
};
