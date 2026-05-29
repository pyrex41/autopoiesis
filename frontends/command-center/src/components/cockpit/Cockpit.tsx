/**
 * Cockpit — the primary app surface for the Shen-Backpressure paradigm.
 * Home is a project picker; selecting a project opens its iteration
 * lineage (slice-2 sidebar) + the discharge report (slice-1 view).
 *
 * Engine vs cockpit: `sb` runs the loop and writes the artifacts; this
 * observes them. Live loop driving (the [run] button) is a later slice —
 * shown disabled for now.
 */
import { type Component, onMount, createSignal, Show, For } from "solid-js";
import { projectsStore, type ProjectEntry } from "../../stores/projects";
import { dischargeStore } from "../../stores/discharge";
import DischargeView from "../../pages/DischargeView";
import ProjectPicker from "./ProjectPicker";

const Cockpit: Component = () => {
  const [selected, setSelected] = createSignal<ProjectEntry | null>(null);

  // Open a project: load its lineage, then its newest report. Reflect in URL.
  async function selectProject(p: ProjectEntry) {
    setSelected(p);
    const url = new URL(window.location.href);
    url.searchParams.set("project", p.path);
    window.history.replaceState(null, "", url.toString());
    await dischargeStore.loadHistory(p.path);
    const first = dischargeStore.history()[0];
    if (first) dischargeStore.load(first.path);
  }

  function goHome() {
    setSelected(null);
    const url = new URL(window.location.href);
    url.searchParams.delete("project");
    window.history.replaceState(null, "", url.toString());
  }

  onMount(async () => {
    await projectsStore.loadProjects();
    // Deep link: ?project=<abs .sb/history dir> opens straight into it.
    const wanted = new URL(window.location.href).searchParams.get("project");
    if (wanted) {
      const match = projectsStore.projects().find((p) => p.path === wanted);
      void selectProject(match ?? { name: wanted, path: wanted, iteration_count: 0, latest_status: null, latest_timestamp: null });
    }
  });

  // Spec / impl summary for the top bar, from the loaded report.
  const specLabel = () => {
    const r = dischargeStore.report();
    return r?.spec?.files?.[0]?.path ?? "—";
  };
  const implSha = () => {
    const c = dischargeStore.report()?.impl?.git_commit;
    return c ? c.slice(0, 7) : "—";
  };
  const reportStatus = () => {
    const s = dischargeStore.report()?.summary;
    if (!s) return null;
    return s.rules_violated > 0 ? "violated" : s.rules_unproven > 0 ? "unproven" : "discharged";
  };

  return (
    <div class="cp-shell">
      <header class="cp-topbar">
        <button class="cp-brand" onClick={goHome} title="Back to projects">
          <span class="cp-brand-mark">◆</span> SB COCKPIT
        </button>

        <Show when={selected()}>
          <div class="cp-project">
            <select
              class="cp-project-select"
              onChange={(e) => {
                const p = projectsStore.projects().find((x) => x.path === e.currentTarget.value);
                if (p) void selectProject(p);
              }}
            >
              <For each={projectsStore.projects()}>
                {(p) => (
                  <option value={p.path} selected={p.path === selected()?.path}>
                    {p.name}
                  </option>
                )}
              </For>
            </select>
          </div>

          <div class="cp-meta">
            <span class="cp-meta-k">spec</span>
            <span class="cp-meta-v">{specLabel()}</span>
            <span class="cp-meta-k">impl</span>
            <span class="cp-meta-v">{implSha()}</span>
            <Show when={reportStatus()}>
              <span class={`cp-status iter-${reportStatus()}`}>
                <span class="dl-glyph">{reportStatus() === "discharged" ? "✓" : reportStatus() === "violated" ? "✕" : "?"}</span>
                {reportStatus()}
              </span>
            </Show>
          </div>
        </Show>

        <div class="cp-topbar-right">
          <button class="cp-run" disabled title="Live sb loop driving — coming in a later slice">▶ run</button>
          <a class="cp-legacy" href="/app.html" title="The original 9-tab dashboard">legacy ↗</a>
        </div>
      </header>

      <div class="cp-body">
        <Show when={selected()} fallback={<ProjectPicker onSelect={selectProject} />}>
          <DischargeView embedded />
        </Show>
      </div>
    </div>
  );
};

export default Cockpit;
