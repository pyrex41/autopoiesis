/**
 * ProjectPicker — the cockpit home. A list of Shen-Backpressure projects
 * (repos with a .sb/history/ dir); click one to open its lineage.
 */
import { type Component, Show, For } from "solid-js";
import { projectsStore, type ProjectEntry } from "../../stores/projects";

function statusGlyph(s: string | null): string {
  return s === "discharged" ? "✓" : s === "violated" ? "✕" : s === "unproven" ? "?" : s === "unreadable" ? "!" : "·";
}

const ProjectPicker: Component<{ onSelect: (p: ProjectEntry) => void }> = (props) => {
  return (
    <div class="cp-picker">
      <div class="cp-picker-head">
        projects
        <span class="cp-picker-root">{projectsStore.root()}</span>
      </div>

      <Show when={projectsStore.loading()}>
        <div class="dr-msg">discovering projects…</div>
      </Show>
      <Show when={projectsStore.error()}>
        <div class="dr-msg dr-err">{projectsStore.error()}</div>
      </Show>
      <Show when={!projectsStore.loading() && !projectsStore.error() && projectsStore.projects().length === 0}>
        <div class="dr-msg">
          No projects found. Set <code>SB_PROJECTS_ROOT</code> or pass <code>?root=…</code> to point at a directory containing <code>.sb/history/</code> dirs.
        </div>
      </Show>

      <div class="cp-proj-list">
        <For each={projectsStore.projects()}>
          {(p) => (
            <button
              class={`proj-row iter-${p.latest_status ?? "unreadable"}`}
              onClick={() => props.onSelect(p)}
              title={p.path}
            >
              <span class="dl-glyph">{statusGlyph(p.latest_status)}</span>
              <span class="proj-name">{p.name}</span>
              <span class="proj-rel">{p.rel}</span>
              <span class="proj-iters">
                {p.iteration_count} iter{p.iteration_count === 1 ? "" : "s"}
              </span>
            </button>
          )}
        </For>
      </div>
    </div>
  );
};

export default ProjectPicker;
