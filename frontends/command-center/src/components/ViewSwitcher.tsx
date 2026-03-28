import { type Component, For, Show } from "solid-js";
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
  tasks: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="2" width="4" height="4" rx="0.5" stroke="currentColor" stroke-width="1.3"/>
      <rect x="1" y="8" width="4" height="4" rx="0.5" stroke="currentColor" stroke-width="1.3"/>
      <path d="M7 4h6M7 10h6" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
    </svg>
  ),
  constellation: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <circle cx="3" cy="3" r="1.5" stroke="currentColor" stroke-width="1.2"/>
      <circle cx="11" cy="5" r="1.5" stroke="currentColor" stroke-width="1.2"/>
      <circle cx="5" cy="11" r="1.5" stroke="currentColor" stroke-width="1.2"/>
      <path d="M4.2 4L9.8 4.6M4.5 4.8L5.2 9.5M10 6.3L6 10" stroke="currentColor" stroke-width="1" opacity="0.6"/>
    </svg>
  ),
  holodeck: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M7 1L13 4.5V9.5L7 13L1 9.5V4.5L7 1Z" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/>
      <path d="M7 1V13M1 4.5L13 9.5M13 4.5L1 9.5" stroke="currentColor" stroke-width="0.8" opacity="0.4"/>
    </svg>
  ),
  org: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="4.5" y="1" width="5" height="3" rx="0.8" stroke="currentColor" stroke-width="1.2"/>
      <rect x="0.5" y="9" width="4" height="3" rx="0.8" stroke="currentColor" stroke-width="1.2"/>
      <rect x="9.5" y="9" width="4" height="3" rx="0.8" stroke="currentColor" stroke-width="1.2"/>
      <path d="M7 4V7M7 7H2.5M7 7H11.5M2.5 7V9M11.5 7V9" stroke="currentColor" stroke-width="1.2"/>
    </svg>
  ),
  eval: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M5 1H9V5L10.5 13H3.5L5 5V1Z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>
      <path d="M5 5H9" stroke="currentColor" stroke-width="1.2"/>
    </svg>
  ),
  budget: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="7" width="3" height="6" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
      <rect x="5.5" y="4" width="3" height="9" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
      <rect x="10" y="1" width="3" height="12" rx="0.5" stroke="currentColor" stroke-width="1.2"/>
    </svg>
  ),
  approvals: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="5.5" stroke="currentColor" stroke-width="1.3"/>
      <path d="M4.5 7L6.5 9L10 5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  evolution: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M2 12C4 12 4 8 7 8C10 8 10 2 12 2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
      <path d="M2 8C4 8 5 5 7 5C9 5 10 6 12 6" stroke="currentColor" stroke-width="1" opacity="0.5" stroke-linecap="round"/>
    </svg>
  ),
  audit: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="2" y="1" width="10" height="12" rx="1" stroke="currentColor" stroke-width="1.2"/>
      <path d="M5 4.5H10M5 7H10M5 9.5H8" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/>
    </svg>
  ),
  conductor: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="4" r="2.5" stroke="currentColor" stroke-width="1.2"/>
      <path d="M3 13C3 10 5 8.5 7 8.5C9 8.5 11 10 11 13" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
      <path d="M10 2L12.5 0.5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
    </svg>
  ),
  widgets: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.2"/>
      <rect x="8" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.2"/>
      <rect x="1" y="8" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.2"/>
      <circle cx="10.5" cy="10.5" r="2.5" stroke="currentColor" stroke-width="1.2"/>
    </svg>
  ),
};

const coreViews: { id: ViewId; label: string; shortcut: string }[] = [
  { id: "command", label: "Command", shortcut: "1" },
  { id: "dag", label: "Graph", shortcut: "2" },
  { id: "timeline", label: "Stream", shortcut: "3" },
  { id: "dashboard", label: "Dashboard", shortcut: "4" },
  { id: "tasks", label: "Tasks", shortcut: "5" },
  { id: "constellation", label: "Constellation", shortcut: "6" },
  { id: "holodeck", label: "Holodeck", shortcut: "7" },
  { id: "org", label: "Org Chart", shortcut: "8" },
  { id: "eval", label: "Eval Lab", shortcut: "9" },
  { id: "budget", label: "Budget", shortcut: "" },
  { id: "approvals", label: "Approvals", shortcut: "" },
  { id: "evolution", label: "Evolution", shortcut: "" },
  { id: "audit", label: "Audit Log", shortcut: "" },
  { id: "conductor", label: "Conductor", shortcut: "" },
  { id: "widgets", label: "Widgets", shortcut: "" },
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
            title={view.shortcut ? `${view.label} [${view.shortcut}]` : view.label}
          >
            <span class="view-tab-icon">{viewIcons[view.id]()}</span>
            <span class="view-tab-label">{view.label}</span>
            <Show when={view.shortcut}>
              <kbd class="view-tab-kbd">{view.shortcut}</kbd>
            </Show>
          </button>
        )}
      </For>
    </div>
  );
};

export default ViewSwitcher;
