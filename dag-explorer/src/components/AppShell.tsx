import { type Component, Show, lazy, Suspense, onMount, onCleanup, createMemo, createSignal } from "solid-js";
import { Dynamic } from "solid-js/web";
import { currentView, setCurrentView, commands, navigateTo, type ViewId } from "../lib/commands";
import { agentStore } from "../stores/agents";
import { teamStore } from "../stores/teams";
import { dagStore } from "../stores/dag";
import StatusBar from "./StatusBar";
import ViewSwitcher from "./ViewSwitcher";
import AgentList from "./AgentList";
import TeamPanel from "./TeamPanel";
import AgentDetail from "./AgentDetail";
import JarvisBar from "./JarvisBar";
import CommandPalette from "./CommandPalette";
import CreateAgentDialog from "./CreateAgentDialog";
import CreateTeamDialog from "./CreateTeamDialog";
import ToastContainer from "./Toast";
import CrystallizePulse from "./CrystallizePulse";
import Breadcrumb from "./Breadcrumb";
import ThoughtModal from "./ThoughtModal";
import { RadarLoader, MeshLoader } from "./LoadingStates";
import Dashboard from "./Dashboard";
import TimelineView from "./TimelineView";
import TasksView from "./TasksView";

// Only lazy-load the heavy DAG view (WebGL/Three.js)
const DAGView = lazy(() => import("./DAGView"));
const HolodeckView = lazy(() => import("./HolodeckView"));
const ConstellationView = lazy(() => import("./ConstellationView"));

const LazyDAG: Component = () => (
  <Suspense fallback={<RadarLoader label="Initializing DAG" />}>
    <DAGView />
  </Suspense>
);

const LazyHolodeck: Component = () => (
  <Suspense fallback={<MeshLoader label="Assembling Holodeck" />}>
    <HolodeckView />
  </Suspense>
);

const LazyConstellation: Component = () => (
  <Suspense fallback={<RadarLoader label="Mapping Constellation" />}>
    <ConstellationView />
  </Suspense>
);

const viewComponents: Record<ViewId, Component> = {
  dashboard: Dashboard,
  dag: LazyDAG,
  timeline: TimelineView,
  tasks: TasksView,
  holodeck: LazyHolodeck,
  constellation: LazyConstellation,
};

const AppShell: Component = () => {
  const [transitioning, setTransitioning] = createSignal(false);

  // Wrap navigateTo with transition animation
  const originalNavigateTo = navigateTo;
  const switchView = (view: ViewId, label: string, agentId?: string) => {
    if (view === currentView()) return;
    setTransitioning(true);
    setTimeout(() => {
      originalNavigateTo(view, label, agentId);
      setTimeout(() => setTransitioning(false), 50);
    }, 150);
  };

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
    const viewKeys: Record<string, { view: ViewId; label: string }> = {
      "1": { view: "dashboard", label: "Dashboard" },
      "2": { view: "dag", label: "DAG Explorer" },
      "3": { view: "timeline", label: "Timeline" },
      "4": { view: "tasks", label: "Tasks" },
      "5": { view: "holodeck", label: "Holodeck" },
      "6": { view: "constellation", label: "Constellation" },
    };
    if (viewKeys[e.key]) {
      e.preventDefault();
      switchView(viewKeys[e.key].view, viewKeys[e.key].label);
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
    teamStore.init();
    window.addEventListener("keydown", handleKeyDown);
  });

  onCleanup(() => {
    window.removeEventListener("keydown", handleKeyDown);
  });

  const activeComponent = createMemo(() => viewComponents[currentView()]);

  return (
    <div class="app-shell">
      <StatusBar />
      <ViewSwitcher />
      <Breadcrumb />

      <div class="app-body">
        {/* Left sidebar — Agent list + Teams */}
        <div class="left-sidebar">
          <AgentList />
          <TeamPanel />
        </div>

        {/* Main content */}
        <div class="app-content" classList={{ transitioning: transitioning() }}>
          <Dynamic component={activeComponent()} />
        </div>

        {/* Right panel — Agent detail */}
        <AgentDetail />
      </div>

      <JarvisBar />
      <CommandPalette />
      <CreateAgentDialog />
      <CreateTeamDialog />
      <ThoughtModal />
      <ToastContainer />
      <CrystallizePulse />
    </div>
  );
};

export default AppShell;
