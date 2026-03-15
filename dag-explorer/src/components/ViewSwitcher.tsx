import { type Component, For } from "solid-js";
import { currentView, setCurrentView, type ViewId } from "../lib/commands";

const viewIcons: Record<string, () => any> = {
  dashboard: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="8" y="1" width="5" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="1" y="8" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="8" y="6" width="5" height="7" rx="1" stroke="currentColor" stroke-width="1.3"/>
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
  tasks: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="1" width="12" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="1" y="5.5" width="12" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="1" y="10" width="12" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
    </svg>
  ),
  holodeck: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M7 1L12.5 4v6L7 13 1.5 10V4L7 1z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/>
      <path d="M7 1v12M1.5 4L12.5 10M12.5 4L1.5 10" stroke="currentColor" stroke-width="0.8" opacity="0.4"/>
    </svg>
  ),
  constellation: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <circle cx="3" cy="3" r="1.5" fill="currentColor" opacity="0.6"/>
      <circle cx="11" cy="4" r="1.5" fill="currentColor" opacity="0.6"/>
      <circle cx="7" cy="7" r="2" fill="currentColor"/>
      <circle cx="4" cy="12" r="1.5" fill="currentColor" opacity="0.6"/>
      <circle cx="12" cy="11" r="1" fill="currentColor" opacity="0.4"/>
      <path d="M3 3L7 7M11 4L7 7M7 7L4 12" stroke="currentColor" stroke-width="0.8" opacity="0.3"/>
    </svg>
  ),
};

const views: { id: ViewId; label: string; shortcut: string }[] = [
  { id: "dashboard", label: "Dashboard", shortcut: "1" },
  { id: "dag", label: "DAG", shortcut: "2" },
  { id: "timeline", label: "Timeline", shortcut: "3" },
  { id: "tasks", label: "Tasks", shortcut: "4" },
  { id: "holodeck", label: "Holodeck", shortcut: "5" },
  { id: "constellation", label: "Constellation", shortcut: "6" },
];

const ViewSwitcher: Component = () => {
  return (
    <div class="view-switcher">
      <For each={views}>
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
