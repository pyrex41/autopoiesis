/**
 * DischargeView — renders a Shen-Backpressure discharge report: the
 * substance layer of the AETHER cockpit. Header + summary strip +
 * per-rule cards (spec excerpt, premise table, counter-examples).
 *
 * Slice 1 of the SB-cockpit pivot: prove the substance layer on real
 * `sb` output before wiring the live iteration loop.
 */
import { type Component, onMount, createSignal, Show, For } from "solid-js";
import { dischargeStore, type Rule, type Premise } from "../stores/discharge";

// A sensible default so the page shows real data on first load.
const DEFAULT_REPORT =
  "/Users/reuben/projects/Shen-Backpressure/examples/multi-tenant-api/transcript/discharge_report.json";

function shortHash(h: string | undefined, n = 10): string {
  if (!h) return "—";
  return h.length > n ? h.slice(0, n) + "…" : h;
}

function statusGlyph(status: string): string {
  return status === "discharged" ? "✓" : status === "violated" ? "✕" : "?";
}

function dischargeBadge(d: string): { label: string; cls: string } {
  if (d === "static") return { label: "static", cls: "d-static" };
  if (d === "runtime-sample") return { label: "sampled", cls: "d-sampled" };
  return { label: d || "unproven", cls: "d-unproven" };
}

const DischargeView: Component = () => {
  const [pathInput, setPathInput] = createSignal(DEFAULT_REPORT);

  onMount(() => {
    // Allow ?report=… in the URL to override the default.
    const url = new URL(window.location.href);
    const p = url.searchParams.get("report") || DEFAULT_REPORT;
    setPathInput(p);
    dischargeStore.load(p);
  });

  function premiseRow(p: Premise) {
    const b = dischargeBadge(p.discharge);
    return (
      <tr class="prem-row">
        <td class="prem-expr">{p.expression}</td>
        <td>
          <span class={`prem-badge ${b.cls}`}>{b.label}</span>
        </td>
        <td class="prem-basis" title={p.rationale}>
          {p.discharge_basis}
        </td>
        <td class="prem-refs">
          <For each={p.code_references ?? []}>
            {(ref) => <span class="code-ref" title={ref}>{ref}</span>}
          </For>
          <Show when={p.discharge === "runtime-sample"}>
            <span class="prem-samples">
              {p.samples_passed}/{p.samples_passed + p.samples_failed} passed
              <Show when={p.sample_seed}> · seed {p.sample_seed}</Show>
            </span>
          </Show>
        </td>
      </tr>
    );
  }

  function ruleCard(rule: Rule) {
    return (
      <div class={`rule-card status-${rule.status}`}>
        <div class="rule-head">
          <span class={`rule-status status-${rule.status}`}>{statusGlyph(rule.status)}</span>
          <span class="rule-name">{rule.name}</span>
          <span class="rule-kind">{rule.kind}</span>
          <span class="rule-prem-count">
            {rule.premises.length} premise{rule.premises.length === 1 ? "" : "s"}
          </span>
        </div>
        <Show when={rule.human_description}>
          <div class="rule-desc">{rule.human_description}</div>
        </Show>
        <pre class="rule-spec">{rule.spec_excerpt}</pre>
        <table class="prem-table">
          <thead>
            <tr>
              <th>premise</th>
              <th>discharge</th>
              <th>basis</th>
              <th>evidence</th>
            </tr>
          </thead>
          <tbody>
            <For each={rule.premises}>{premiseRow}</For>
          </tbody>
        </table>
        <Show when={rule.counter_examples.length > 0}>
          <div class="ce-block">
            <div class="ce-title">{rule.counter_examples.length} counter-example(s)</div>
            <For each={rule.counter_examples}>
              {(ce) => (
                <div class="ce-item">
                  <div class="ce-row"><span class="ce-k">case</span><span class="ce-v">{ce.case_id ?? ce.id ?? "?"}</span></div>
                  <Show when={ce.spec_output}><div class="ce-row"><span class="ce-k">spec</span><span class="ce-v">{ce.spec_output}</span></div></Show>
                  <Show when={ce.impl_output}><div class="ce-row"><span class="ce-k">impl</span><span class="ce-v">{ce.impl_output}</span></div></Show>
                  <Show when={ce.repro ?? ce.reproduction}>
                    <pre class="ce-repro">{ce.repro ?? ce.reproduction}</pre>
                  </Show>
                </div>
              )}
            </For>
          </div>
        </Show>
      </div>
    );
  }

  return (
    <div class="dr-root">
      <div class="dr-loadbar">
        <span class="dr-loadlabel">discharge report</span>
        <input
          class="dr-pathinput"
          value={pathInput()}
          onInput={(e) => setPathInput(e.currentTarget.value)}
          onKeyDown={(e) => { if (e.key === "Enter") dischargeStore.load(pathInput()); }}
          spellcheck={false}
        />
        <button class="dr-loadbtn" onClick={() => dischargeStore.load(pathInput())}>load</button>
      </div>

      <Show when={dischargeStore.loading()}>
        <div class="dr-msg">loading…</div>
      </Show>
      <Show when={dischargeStore.error()}>
        <div class="dr-msg dr-err">{dischargeStore.error()}</div>
      </Show>

      <Show when={dischargeStore.report()}>
        {(r) => (
          <>
            {/* Header */}
            <div class="dr-header">
              <div class="dr-row"><span class="k">spec</span><span class="v">{r().spec.files.map((f) => f.path).join(", ")}  ·  {shortHash(r().spec.files[0]?.sha256)}</span></div>
              <div class="dr-row"><span class="k">impl</span><span class="v">{shortHash(r().impl.git_commit)}{r().impl.git_dirty ? " (dirty)" : ""}  ·  {r().impl.target_languages.join(", ")}</span></div>
              <div class="dr-row"><span class="k">tools</span><span class="v">sb {r().tools.sb_version}{r().tools.shen_derive_version ? ` · shen-derive ${r().tools.shen_derive_version}` : ""}</span></div>
              <div class="dr-row"><span class="k">generated</span><span class="v">{r().generated_at}</span></div>
            </div>

            {/* Summary strip */}
            <div class="dr-summary">
              <div class={`stat ${r().summary.rules_violated > 0 ? "bad" : r().summary.rules_unproven > 0 ? "warn" : "good"}`}>
                <div class="stat-n">{r().summary.rules_discharged}/{r().summary.rule_count}</div>
                <div class="stat-l">rules discharged</div>
              </div>
              <div class={`stat ${r().summary.rules_violated > 0 ? "bad" : "dim"}`}>
                <div class="stat-n">{r().summary.rules_violated}</div>
                <div class="stat-l">violated</div>
              </div>
              <div class={`stat ${r().summary.rules_unproven > 0 ? "warn" : "dim"}`}>
                <div class="stat-n">{r().summary.rules_unproven}</div>
                <div class="stat-l">unproven</div>
              </div>
              <div class="stat dim">
                <div class="stat-n">{r().summary.premises_static}</div>
                <div class="stat-l">static premises</div>
              </div>
              <div class="stat dim">
                <div class="stat-n">{r().summary.premises_runtime_sampled}</div>
                <div class="stat-l">sampled premises</div>
              </div>
              <div class={`stat ${r().summary.premises_unproven > 0 ? "warn" : "dim"}`}>
                <div class="stat-n">{r().summary.premises_unproven}</div>
                <div class="stat-l">unproven premises</div>
              </div>
            </div>

            {/* Rules */}
            <div class="dr-rules">
              <For each={dischargeStore.sortedRules()}>{ruleCard}</For>
            </div>
          </>
        )}
      </Show>
    </div>
  );
};

export default DischargeView;
