import { dagStore } from "../stores/dag";
import { agentStore } from "../stores/agents";
import { teamStore } from "../stores/teams";
import { fitToView } from "../graph/globals";

export interface Command {
  id: string;
  name: string;
  description?: string;
  shortcut?: string;
  category: "agents" | "navigation" | "views" | "system";
  icon: string;
  requiresAgent?: boolean;
  handler: () => void;
}

export type ViewId = "dashboard" | "dag" | "timeline" | "tasks" | "holodeck";

// View state — managed here so commands + ViewSwitcher share it
import { createSignal } from "solid-js";
export const [currentView, setCurrentView] = createSignal<ViewId>("dashboard");

export const commands: Command[] = [
  // ── Agents ─────────────────────────────────────────────────
  {
    id: "agent.create",
    name: "Create Agent",
    description: "Create a new agent with capabilities",
    shortcut: "n",
    category: "agents",
    icon: "+",
    handler: () => {
      // Dispatched via event — CreateAgentDialog listens
      window.dispatchEvent(new CustomEvent("ap:create-agent"));
    },
  },
  {
    id: "agent.start",
    name: "Start Agent",
    description: "Start the selected agent's cognitive loop",
    shortcut: "r",
    category: "agents",
    icon: "▶",
    requiresAgent: true,
    handler: () => agentStore.startAgent(),
  },
  {
    id: "agent.stop",
    name: "Stop Agent",
    description: "Stop the selected agent",
    shortcut: "x",
    category: "agents",
    icon: "■",
    requiresAgent: true,
    handler: () => agentStore.stopAgent(),
  },
  {
    id: "agent.pause",
    name: "Pause Agent",
    description: "Pause the selected agent",
    category: "agents",
    icon: "⏸",
    requiresAgent: true,
    handler: () => agentStore.pauseAgent(),
  },
  {
    id: "agent.step",
    name: "Step Agent",
    description: "Execute one cognitive cycle",
    shortcut: "s",
    category: "agents",
    icon: "→",
    requiresAgent: true,
    handler: () => agentStore.stepAgent(),
  },
  {
    id: "agent.fork",
    name: "Fork Agent",
    description: "Create a branch of the selected agent",
    category: "agents",
    icon: "⑂",
    requiresAgent: true,
    handler: () => agentStore.forkAgent(),
  },
  {
    id: "agent.upgrade",
    name: "Upgrade to Dual Agent",
    description: "Upgrade to persistent dual-agent mode",
    category: "agents",
    icon: "⇑",
    requiresAgent: true,
    handler: () => agentStore.upgradeAgent(),
  },

  // ── Teams ──────────────────────────────────────────────────
  {
    id: "team.create",
    name: "Create Team",
    description: "Create a new agent team",
    category: "agents",
    icon: "\u2295",
    handler: () => {
      window.dispatchEvent(new CustomEvent("ap:create-team"));
    },
  },
  {
    id: "team.start",
    name: "Start Team",
    description: "Start the selected team's strategy",
    category: "agents",
    icon: "\u25B6",
    handler: () => {
      const id = teamStore.selectedTeamId();
      if (id) teamStore.startTeam(id);
    },
  },
  {
    id: "team.disband",
    name: "Disband Team",
    description: "Disband the selected team",
    category: "agents",
    icon: "\u2715",
    handler: () => {
      const id = teamStore.selectedTeamId();
      if (id) teamStore.disbandTeam(id);
    },
  },

  // ── Views ──────────────────────────────────────────────────
  {
    id: "view.dashboard",
    name: "Dashboard",
    description: "Agent overview and live events",
    shortcut: "1",
    category: "views",
    icon: "◫",
    handler: () => setCurrentView("dashboard"),
  },
  {
    id: "view.dag",
    name: "DAG Explorer",
    description: "Snapshot DAG visualization",
    shortcut: "2",
    category: "views",
    icon: "◇",
    handler: () => setCurrentView("dag"),
  },
  {
    id: "view.timeline",
    name: "Timeline",
    description: "Chronological event stream",
    shortcut: "3",
    category: "views",
    icon: "≡",
    handler: () => setCurrentView("timeline"),
  },
  {
    id: "view.tasks",
    name: "Tasks",
    description: "Task queue and scheduler",
    shortcut: "4",
    category: "views",
    icon: "☰",
    handler: () => setCurrentView("tasks"),
  },
  {
    id: "view.holodeck",
    name: "Holodeck",
    description: "3D agent visualization",
    shortcut: "5",
    category: "views",
    icon: "⬡",
    handler: () => setCurrentView("holodeck"),
  },

  // ── Navigation (DAG) ──────────────────────────────────────
  {
    id: "dag.fit",
    name: "Fit to View",
    description: "Fit the DAG graph to viewport",
    shortcut: "f",
    category: "navigation",
    icon: "⊞",
    handler: () => fitToView(),
  },
  {
    id: "dag.inspector",
    name: "Toggle Inspector",
    description: "Show/hide the detail panel",
    shortcut: "i",
    category: "navigation",
    icon: "ℹ",
    handler: () => dagStore.setDetailPanelOpen(!dagStore.detailPanelOpen()),
  },
  {
    id: "dag.diff",
    name: "Toggle Diff Mode",
    shortcut: "d",
    category: "navigation",
    icon: "±",
    handler: () => dagStore.setDiffMode(!dagStore.diffMode()),
  },
  {
    id: "nav.parent",
    name: "Navigate to Parent",
    shortcut: "h",
    category: "navigation",
    icon: "←",
    handler: () => dagStore.navigateToParent(),
  },
  {
    id: "nav.child",
    name: "Navigate to Child",
    shortcut: "l",
    category: "navigation",
    icon: "→",
    handler: () => dagStore.navigateToChild(),
  },
  {
    id: "nav.prev",
    name: "Previous Sibling",
    shortcut: "k",
    category: "navigation",
    icon: "↑",
    handler: () => dagStore.navigateToSibling(-1),
  },
  {
    id: "nav.next",
    name: "Next Sibling",
    shortcut: "j",
    category: "navigation",
    icon: "↓",
    handler: () => dagStore.navigateToSibling(1),
  },

  // ── System ─────────────────────────────────────────────────
  {
    id: "system.connect",
    name: "Connect to Live API",
    description: "Switch to live data from the server",
    category: "system",
    icon: "⚡",
    handler: () => dagStore.loadFromAPI(),
  },
  {
    id: "system.mock",
    name: "Load Mock Data",
    description: "Load generated test data",
    category: "system",
    icon: "◈",
    handler: () => dagStore.loadMockData(),
  },
  {
    id: "system.refresh",
    name: "Refresh Agents",
    description: "Reload agent list from server",
    category: "system",
    icon: "↻",
    handler: () => agentStore.loadAgents(),
  },
];

export function findCommand(id: string): Command | undefined {
  return commands.find((c) => c.id === id);
}

export function executeCommand(id: string) {
  const cmd = findCommand(id);
  if (cmd) cmd.handler();
}
