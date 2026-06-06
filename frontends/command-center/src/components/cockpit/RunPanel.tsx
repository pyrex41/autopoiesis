/**
 * RunPanel — live view of an `sb loop` run: iteration, phase, the gate strip
 * (parsed from sb's PASS/FAIL stderr — the per-gate view deferred since
 * slice 1), and a tail of the loop's output. Stop while running; dismiss when
 * terminal.
 */
import { type Component, Show, For } from "solid-js";
import { runsStore, type GateResult } from "../../stores/runs";

function statusLabel(s: string): string {
  return s === "running"
    ? "running"
    : s === "converged"
      ? "✓ converged"
      : s === "failed"
        ? "✕ failed"
        : s === "stopped"
          ? "■ stopped"
          : s === "error"
            ? "! error"
            : s;
}

const RunPanel: Component = () => {
  const r = () => runsStore.run()!;
  const running = () => r().status === "running";

  function gateChip(g: GateResult) {
    const ok = g.passed === true;
    return (
      <span class={`gate-chip ${ok ? "pass" : "fail"}`} title={`${g.name} ${g.duration}`}>
        {ok ? "✓" : "✕"} {g.name}
        <span class="gate-dur">{g.duration}</span>
      </span>
    );
  }

  return (
    <Show when={runsStore.run()}>
      <div class={`run-panel status-${r().status}`}>
        <div class="run-head">
          <span class={`run-status iter-${r().status === "converged" ? "discharged" : r().status === "failed" ? "violated" : "unproven"}`}>
            {statusLabel(r().status)}
          </span>
          <span class="run-iter">
            iteration {r().iteration}{r().max_iter ? ` / ${r().max_iter}` : ""}
          </span>
          <Show when={running()}>
            <span class="run-phase">{r().phase === "harness" ? "calling harness…" : "running gates…"}</span>
          </Show>
          <span class="run-cwd" title={r().cwd}>{r().cwd}</span>
          <div class="run-actions">
            <Show
              when={running()}
              fallback={<button class="run-btn" onClick={() => runsStore.clearRun()}>dismiss</button>}
            >
              <button class="run-btn stop" onClick={() => runsStore.stopRun()}>■ stop</button>
            </Show>
          </div>
        </div>

        <Show when={r().gates.length > 0}>
          <div class="gate-strip">
            <For each={r().gates}>{gateChip}</For>
          </div>
        </Show>

        <Show when={runsStore.runError()}>
          <div class="dr-msg dr-err">{runsStore.runError()}</div>
        </Show>
        <Show when={r().error}>
          <div class="dr-msg dr-err">{r().error}</div>
        </Show>

        <Show when={r().log.length > 0}>
          <pre class="run-log">{r().log.join("\n")}</pre>
        </Show>
      </div>
    </Show>
  );
};

export default RunPanel;
