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
  org: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="4.5" y="1" width="5" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="0.5" y="9" width="4" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="9.5" y="9" width="4" height="3" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <path d="M7 4v2M7 6H2.5V9M7 6h4.5V9" stroke="currentColor" stroke-width="1.2"/>
    </svg>
  ),
  budget: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <circle cx="7" cy="7" r="5.5" stroke="currentColor" stroke-width="1.3"/>
      <path d="M7 3.5v7M5 5.5h3a1 1 0 010 2H5.5a1 1 0 000 2H9" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
    </svg>
  ),
  approvals: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="2" width="12" height="10" rx="1.5" stroke="currentColor" stroke-width="1.3"/>
      <path d="M4 7l2 2 4-4" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ),
  evolution: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M2 10c1-3 3-5 5-5s3.5 1 5 4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
      <circle cx="4" cy="4" r="1.5" stroke="currentColor" stroke-width="1.2"/>
      <circle cx="10" cy="3" r="1.5" stroke="currentColor" stroke-width="1.2"/>
      <path d="M5.5 4h3" stroke="currentColor" stroke-width="1" stroke-dasharray="1 1"/>
    </svg>
  ),
  audit: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="2" y="1" width="10" height="12" rx="1.5" stroke="currentColor" stroke-width="1.3"/>
      <path d="M4.5 4h5M4.5 7h5M4.5 10h3" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
    </svg>
  ),
  widgets: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="8" y="1" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="1" y="8" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <rect x="8" y="8" width="5" height="5" rx="1" stroke="currentColor" stroke-width="1.3"/>
      <circle cx="3.5" cy="3.5" r="1" fill="currentColor" opacity="0.5"/>
      <circle cx="10.5" cy="3.5" r="1" fill="currentColor" opacity="0.5"/>
    </svg>
  ),
  eval: () => (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <rect x="1" y="1" width="12" height="12" rx="1.5" stroke="currentColor" stroke-width="1.3"/>
      <path d="M1 5h12M5 1v12" stroke="currentColor" stroke-width="0.9" opacity="0.5"/>
      <path d="M8 8l2 2M8 10l2-2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/>
    </svg>
  ),
};

const observeViews: { id: ViewId; label: string; shortcut: string }[] = [
  { id: "dashboard", label: "Dashboard", shortcut: "1" },
  { id: "dag", label: "DAG", shortcut: "2" },
  { id: "timeline", label: "Timeline", shortcut: "3" },
  { id: "tasks", label: "Tasks", shortcut: "4" },
  { id: "holodeck", label: "Holodeck", shortcut: "5" },
  { id: "constellation", label: "Constellation", shortcut: "6" },
];

const manageViews: { id: ViewId; label: string; shortcut: string }[] = [
  { id: "org", label: "Org", shortcut: "7" },
  { id: "budget", label: "Budget", shortcut: "8" },
  { id: "approvals", label: "Approvals", shortcut: "9" },
  { id: "evolution", label: "Evolution", shortcut: "0" },
  { id: "audit", label: "Audit", shortcut: "-" },
  { id: "widgets", label: "Widgets", shortcut: "=" },
  { id: "eval", label: "Eval Lab", shortcut: "[" },
];

const ViewSwitcher: Component = () => {
  return (
    <div class="view-switcher">
      <For each={observeViews}>
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
      <div class="view-tab-divider" />
      <For each={manageViews}>
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
