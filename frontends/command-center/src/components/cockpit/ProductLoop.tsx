/**
 * ProductLoop — the team-owned builder's board, deliberation gate, and decision
 * provenance (Slice 3b). Reads /api/sb/*: a kanban board whose lanes are moved
 * via Linda take!, a gate where the team's inputs + the lead's resolution are
 * retained as queryable datoms (dissent shown), and a "why did we decide X"
 * panel backed by datalog. Action-driven refresh + a light poll.
 */
import { type Component, onMount, onCleanup, createSignal, For, Show } from "solid-js";
import { sbStore } from "../../stores/sbProduct";
import type { SbDecision } from "../../api/client";

const POLL_MS = 4000;

const ProductLoop: Component = () => {
  let poll: number | undefined;

  onMount(() => {
    void sbStore.refresh();
    poll = window.setInterval(() => void sbStore.refresh(), POLL_MS);
  });
  onCleanup(() => { if (poll !== undefined) clearInterval(poll); });

  const isEmpty = () => {
    const b = sbStore.board();
    return !b || b.lanes.every((l) => l.tickets.length === 0);
  };

  return (
    <div class="sb-loop">
      <div class="sb-head">
        <h3 class="sb-title">TEAM BOARD</h3>
        <div class="sb-actions">
          <Show when={isEmpty()}>
            <button class="sb-btn" disabled={sbStore.busy()} onClick={() => void sbStore.seed()}>seed demo</button>
          </Show>
          <button class="sb-btn" disabled={sbStore.busy()} onClick={() => void sbStore.refresh()}>refresh</button>
        </div>
      </div>
      <Show when={sbStore.error()}>
        <div class="sb-err">{sbStore.error()}</div>
      </Show>

      {/* ── Board lanes ──────────────────────────────────────────── */}
      <Show when={sbStore.board()}>
        {(b) => (
          <div class="sb-lanes">
            <For each={b().lanes}>
              {(lane) => (
                <div class={`sb-lane sb-lane-${lane.lane}`}>
                  <div class="sb-lane-head">
                    <span>{lane.lane}</span>
                    <Show when={lane.lane === "ai-ready" && lane.tickets.length > 0}>
                      <button
                        class="sb-claim"
                        disabled={sbStore.busy()}
                        title="Builder atomically claims the next ticket (take!)"
                        onClick={() => void sbStore.claim("ai-ready", "in-progress")}
                      >claim ▸</button>
                    </Show>
                  </div>
                  <For each={lane.tickets}>
                    {(t) => (
                      <div class="sb-card">
                        <div class="sb-card-title">{t.title}</div>
                        <div class="sb-card-id">{t.id}</div>
                      </div>
                    )}
                  </For>
                  <Show when={lane.tickets.length === 0}>
                    <div class="sb-lane-empty">—</div>
                  </Show>
                </div>
              )}
            </For>
          </div>
        )}
      </Show>

      {/* ── Deliberation gate ────────────────────────────────────── */}
      <h3 class="sb-title">DELIBERATION</h3>
      <div class="sb-decisions">
        <For each={sbStore.decisions()} fallback={<div class="sb-lane-empty">no decisions</div>}>
          {(d) => <DecisionCard d={d} />}
        </For>
      </div>

      {/* ── Provenance: why did we decide X ──────────────────────── */}
      <h3 class="sb-title">WHY (PROVENANCE)</h3>
      <div class="sb-why">
        <For each={sbStore.why()} fallback={<div class="sb-lane-empty">no resolved decisions</div>}>
          {(w) => (
            <div class="sb-why-row">
              <span class="sb-why-q">{w.question}</span>
              <span class="sb-why-arrow">→</span>
              <span class="sb-why-r">{w.resolution}</span>
              <span class="sb-why-by">by {w.resolved_by}</span>
            </div>
          )}
        </For>
      </div>
    </div>
  );
};

const DecisionCard: Component<{ d: SbDecision }> = (props) => {
  const [lead, setLead] = createSignal("lead");
  const [resolution, setResolution] = createSignal("");
  const resolved = () => props.d.status === "resolved";

  return (
    <div class={`sb-decision ${resolved() ? "sb-resolved" : "sb-open"}`}>
      <div class="sb-decision-q">{props.d.question}</div>
      <div class="sb-inputs">
        <For each={props.d.inputs}>
          {(i) => (
            <span class={`sb-input ${i.dissent ? "sb-dissent" : ""}`} title={i.dissent ? "dissented from the resolution" : ""}>
              <b>{i.user}</b>: {i.text}{i.dissent ? " ⚑" : ""}
            </span>
          )}
        </For>
      </div>
      <Show
        when={resolved()}
        fallback={
          <div class="sb-resolve">
            <input class="sb-in" value={lead()} onInput={(e) => setLead(e.currentTarget.value)} placeholder="lead" />
            <input class="sb-in sb-in-wide" value={resolution()} onInput={(e) => setResolution(e.currentTarget.value)} placeholder="resolution" />
            <button
              class="sb-btn"
              disabled={sbStore.busy() || !resolution()}
              onClick={() => void sbStore.resolve(props.d.id, lead(), resolution())}
            >resolve</button>
          </div>
        }
      >
        <div class="sb-decision-res">
          <span class="sb-res-badge">resolved</span>
          <b>{props.d.resolution}</b>
          <span class="sb-by">by {props.d.resolved_by}</span>
          <Show when={props.d.dissenters.length > 0}>
            <span class="sb-dissenters">⚑ dissent: {props.d.dissenters.join(", ")}</span>
          </Show>
        </div>
      </Show>
    </div>
  );
};

export default ProductLoop;
