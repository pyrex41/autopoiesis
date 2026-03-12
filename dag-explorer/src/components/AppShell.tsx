import { type Component, Show, lazy, Suspense, onMount, onCleanup } from "solid-js";
import { currentView, setCurrentView, commands, type ViewId } from "../lib/commands";
import { agentStore } from "../stores/agents";
import { dagStore } from "../stores/dag";
import StatusBar from "./StatusBar";
import ViewSwitcher from "./ViewSwitcher";
import AgentList from "./AgentList";
import AgentDetail from "./AgentDetail";
import JarvisBar from "./JarvisBar";
import CommandPalette from "./CommandPalette";
import CreateAgentDialog from "./CreateAgentDialog";

// Lazy-load heavy views
const Dashboard = lazy(() => import("./Dashboard"));
const DAGView = lazy(() => import("./DAGView"));
const TimelineView = lazy(() => import("./TimelineView"));
const TasksView = lazy(() => import("./TasksView"));

const AppShell: Component = () => {
  // Global keyboard shortcuts
  function handleKeyDown(e: KeyboardEvent) {
    // Don't intercept when typing in inputs
    const el = document.activeElement;
    if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || (el as HTMLElement).isContentEditable)) {
      return;
    }

    // Ctrl+K / Cmd+K — command palette
    if ((e.ctrlKey || e.metaKey) && e.key === "k") {
      e.preventDefault();
      dagStore.setShowCommandPalette(true);
      return;
    }

    // View switching: 1-4
    const viewKeys: Record<string, ViewId> = { "1": "dashboard", "2": "dag", "3": "timeline", "4": "tasks" };
    if (viewKeys[e.key]) {
      e.preventDefault();
      setCurrentView(viewKeys[e.key]);
      return;
    }

    // Agent actions on selected agent
    const cmd = commands.find((c) => c.shortcut === e.key);
    if (cmd) {
      if (cmd.requiresAgent && !agentStore.selectedId()) return;
      // Only handle non-view, non-conflicting shortcuts
      if (cmd.category === "agents" || cmd.category === "system") {
        e.preventDefault();
        cmd.handler();
      }
      // Navigation shortcuts only active in DAG view
      if (cmd.category === "navigation" && currentView() === "dag") {
        e.preventDefault();
        cmd.handler();
      }
    }
  }

  onMount(() => {
    agentStore.init();
    window.addEventListener("keydown", handleKeyDown);
  });

  onCleanup(() => {
    window.removeEventListener("keydown", handleKeyDown);
  });

  return (
    <div class="app-shell">
      <StatusBar />
      <ViewSwitcher />

      <div class="app-body">
        {/* Left panel — Agent list */}
        <AgentList />

        {/* Main content */}
        <div class="app-content">
          <Suspense fallback={<div class="view-loading">Loading...</div>}>
            <Show when={currentView() === "dashboard"}>
              <Dashboard />
            </Show>
            <Show when={currentView() === "dag"}>
              <DAGView />
            </Show>
            <Show when={currentView() === "timeline"}>
              <TimelineView />
            </Show>
            <Show when={currentView() === "tasks"}>
              <TasksView />
            </Show>
          </Suspense>
        </div>

        {/* Right panel — Agent detail */}
        <AgentDetail />
      </div>

      <JarvisBar />
      <CommandPalette />
      <CreateAgentDialog />
    </div>
  );
};

export default AppShell;
