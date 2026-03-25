import { type Component, For } from "solid-js";
import { currentView, setCurrentView, type ViewId } from "../lib/commands";

const viewIcons: Record<string, () => any> = {
  command: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M2 4l3 3-3 3" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M7 11h5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
    </svg>
  ),
  dag: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="2.5" r="1.8" stroke="currentColor" stroke-width="1.3"/>
      <circle cx="3.5" cy="11" r="1.8" stroke="currentColor" stroke-width="1.3"/>
      <circle cx="10.5" cy="11" r="1.8" stroke="currentColor" stroke-width="1.3"/>
      <path d="M6 4.2L4.2 9.2M8 4.2L9.8 9.2" stroke="currentColor" stroke-width="1.2"/>
    </svg>
  ),
  timeline: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M1 3h12M1 7h8M1 11h10" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
    </svg>
  ),
  dashboard: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="8" y="1" width="5" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="1" y="8" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="8" y="6" width="5" height="7" rx="1" stroke="currentColor" stroke-width="1.3"/>
    </svg>
  ),
};

const coreViews: { id: ViewId; label: string; shortcut: string }[] = [
  { id: "command", label: "Command", shortcut: "1" },
  { id: "dag", label: "Graph", shortcut: "2" },
  { id: "timeline", label: "Stream", shortcut: "3" },
  { id: "dashboard", label: "Dashboard", shortcut: "4" },
];

const ViewSwitcher: Component = () => {
  return (
    <div class="view-switcher">
      <For each={coreViews}>
        {(view) => (
          <button
            class="view-tab"
            classList={{ "view-tab-active": currentView() === view.id }}
            onClick={() => setCurrentView(view.id)}
            title={`${view.label} [${view.shortcut}]`}
          >
            <span class="view-tab-icon">{viewIcons[view.id]()}</span>
            <span class="view-tab-label">{view.label}</span>
            <kbd class="view-tab-kbd">{view.shortcut}</kbd>
          </button>
        )}
      </For>
    </div>
  );
};

export default ViewSwitcher;
