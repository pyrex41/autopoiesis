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
import CommandPalette from "./CommandPalette";
import CreateAgentDialog from "./CreateAgentDialog";
import CreateTeamDialog from "./CreateTeamDialog";
import ToastContainer from "./Toast";
import CrystallizePulse from "./CrystallizePulse";
import Breadcrumb from "./Breadcrumb";
import ThoughtModal from "./ThoughtModal";
import { RadarLoader } from "./LoadingStates";
import Dashboard from "./Dashboard";
import TimelineView from "./TimelineView";
import CommandView from "./CommandView";
import EvalLab from "./EvalLab";
import TasksView from "./TasksView";
import ApprovalsView from "./ApprovalsView";
import ConductorDashboard from "./ConductorDashboard";
import OrgChart from "./OrgChart";
import BudgetDashboard from "./BudgetDashboard";
import AuditLog from "./AuditLog";
import WidgetsView from "./WidgetsView";

// Only lazy-load heavy views
const DAGView = lazy(() => import("./DAGView"));

const ConstellationView = lazy(() => import("./ConstellationView"));
const HolodeckView = lazy(() => import("./HolodeckView"));
const EvolutionLab = lazy(() => import("./EvolutionLab"));

const LazyDAG: Component = () => (
  <Suspense fallback={<RadarLoader label="Initializing Graph" />}>
    <DAGView />
  </Suspense>
);

const LazyConstellation: Component = () => (
  <Suspense fallback={<RadarLoader label="Loading Constellation" />}>
    <ConstellationView />
  </Suspense>
);

const LazyHolodeck: Component = () => (
  <Suspense fallback={<RadarLoader label="Loading Holodeck" />}>
    <HolodeckView />
  </Suspense>
);

const LazyEvolution: Component = () => (
  <Suspense fallback={<RadarLoader label="Loading Evolution" />}>
    <EvolutionLab />
  </Suspense>
);

const viewComponents: Record<ViewId, Component> = {
  command: CommandView,
  dag: LazyDAG,
  timeline: TimelineView,
  dashboard: Dashboard,
  tasks: TasksView,
  constellation: LazyConstellation,
  holodeck: LazyHolodeck,
  org: OrgChart,
  budget: BudgetDashboard,
  approvals: ApprovalsView,
  evolution: LazyEvolution,
  eval: EvalLab,
  audit: AuditLog,
  conductor: ConductorDashboard,
  widgets: WidgetsView,
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
      "1": { view: "command", label: "Command" },
      "2": { view: "dag", label: "Graph" },
      "3": { view: "timeline", label: "Stream" },
      "4": { view: "dashboard", label: "Dashboard" },
      "5": { view: "tasks", label: "Tasks" },
      "6": { view: "constellation", label: "Constellation" },
      "7": { view: "holodeck", label: "Holodeck" },
      "8": { view: "org", label: "Org Chart" },
      "9": { view: "eval", label: "Eval Lab" },
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

  // Command view is full-width (no sidebars)
  const isCommandView = createMemo(() => currentView() === "command");

  return (
    <div class="app-shell">
      <StatusBar />
      <ViewSwitcher />
      <Breadcrumb />

      <div class="app-body">
        {/* Left sidebar — hidden in Command view */}
        <Show when={!isCommandView()}>
          <div class="left-sidebar">
            <AgentList />
            <TeamPanel />
          </div>
        </Show>

        {/* Main content */}
        <div class="app-content" classList={{ transitioning: transitioning(), "app-content-full": isCommandView() }}>
          <Dynamic component={activeComponent()} />
        </div>

        {/* Right panel — hidden in Command view */}
        <Show when={!isCommandView()}>
          <AgentDetail />
        </Show>
      </div>

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
