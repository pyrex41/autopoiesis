import { type Component, For } from "solid-js";
import { currentView, setCurrentView, type ViewId } from "../lib/commands";

const views: { id: ViewId; label: string; icon: string; shortcut: string }[] = [
  { id: "dashboard", label: "Dashboard", icon: "◫", shortcut: "1" },
  { id: "dag", label: "DAG", icon: "◇", shortcut: "2" },
  { id: "timeline", label: "Timeline", icon: "≡", shortcut: "3" },
  { id: "tasks", label: "Tasks", icon: "☰", shortcut: "4" },
  { id: "holodeck", label: "Holodeck", icon: "⬡", shortcut: "5" },
  { id: "constellation", label: "Constellation", icon: "✦", shortcut: "6" },
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
            <span class="view-tab-icon">{view.icon}</span>
            <span class="view-tab-label">{view.label}</span>
            <kbd class="view-tab-kbd">{view.shortcut}</kbd>
          </button>
        )}
      </For>
    </div>
  );
};

export default ViewSwitcher;
