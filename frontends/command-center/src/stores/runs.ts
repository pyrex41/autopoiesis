/**
 * Runs store — drives `sb loop` live (slice 3). Starts a run, then polls its
 * status ~1.5s while it's running (a loop iteration is seconds–minutes, so
 * polling is effectively live). `sb` has no stream mode; the backend parses
 * its stderr into iteration/phase/gate state and exposes it here.
 */
import { createSignal } from "solid-js";

export interface GateResult {
  name: string;
  passed: boolean | null; // true = pass; null/false = fail (cl-json has no false)
  duration: string;
}

export interface RunState {
  run_id: string;
  project: string;
  cwd: string;
  status: "running" | "converged" | "failed" | "stopped" | "error" | string;
  iteration: number;
  max_iter: number | null;
  phase: "gates" | "harness" | string;
  gates: GateResult[];
  history_count: number;
  log: string[];
  started_at: number;
  ended_at: number | null;
  error: string | null;
}

const POLL_MS = 1500;

const [run, setRun] = createSignal<RunState | null>(null);
const [starting, setStarting] = createSignal(false);
const [runError, setRunError] = createSignal<string | null>(null);

let pollTimer: number | undefined;
let prevHistoryCount = -1;
let historyGrewCb: (() => void) | null = null;

function stopPolling() {
  if (pollTimer !== undefined) {
    clearInterval(pollTimer);
    pollTimer = undefined;
  }
}

async function poll(id: string) {
  try {
    const res = await fetch(`/api/aether/sb-loop/${encodeURIComponent(id)}`);
    if (!res.ok) return;
    const data = (await res.json()) as RunState;
    setRun(data);
    // New discharge report landed → let the cockpit refresh the lineage.
    if (prevHistoryCount >= 0 && data.history_count > prevHistoryCount) {
      historyGrewCb?.();
    }
    prevHistoryCount = data.history_count;
    if (data.status !== "running") stopPolling();
  } catch {
    // transient; next tick retries
  }
}

/** Start `sb loop` in DIR (the project root). onHistoryGrew fires when a new
 *  discharge report appears, so the caller can refresh the lineage. */
async function startRun(
  dir: string,
  opts?: { maxIter?: number; onHistoryGrew?: () => void },
): Promise<void> {
  setRunError(null);
  setStarting(true);
  historyGrewCb = opts?.onHistoryGrew ?? null;
  prevHistoryCount = -1;
  try {
    const res = await fetch("/api/aether/sb-loop/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ dir, max_iter: opts?.maxIter }),
    });
    if (!res.ok) {
      throw new Error(`${res.status}: ${(await res.text()).slice(0, 200)}`);
    }
    const data = (await res.json()) as { run_id: string };
    stopPolling();
    await poll(data.run_id);
    pollTimer = window.setInterval(() => poll(data.run_id), POLL_MS);
  } catch (e) {
    setRunError(e instanceof Error ? e.message : String(e));
  } finally {
    setStarting(false);
  }
}

async function stopRun(): Promise<void> {
  const r = run();
  if (!r) return;
  try {
    await fetch(`/api/aether/sb-loop/${encodeURIComponent(r.run_id)}/stop`, {
      method: "POST",
    });
    await poll(r.run_id);
  } catch {
    // ignore
  }
}

/** Dismiss the run panel (does not stop a running process). */
function clearRun() {
  stopPolling();
  setRun(null);
  setRunError(null);
}

export const runsStore = {
  run,
  starting,
  runError,
  startRun,
  stopRun,
  clearRun,
};
