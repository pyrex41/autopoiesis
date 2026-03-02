/** Core snapshot node in the DAG */
export interface Snapshot {
  id: string;
  timestamp: number;
  parent: string | null;
  hash: string | null;
  metadata: Record<string, unknown> | null;
  agentState?: string | null;
}

/** Named branch pointing at a snapshot head */
export interface Branch {
  name: string;
  head: string | null;
  created: number;
}

/** Agent summary */
export interface Agent {
  id: string;
  name: string;
  state: string;
  capabilities: string[];
  parent: string | null;
  children: string[];
  thoughtCount: number;
}

/** Diff result between two snapshots */
export interface SnapshotDiff {
  from: string;
  to: string;
  diff: string;
}

/** Integration event */
export interface IntegrationEvent {
  id: string;
  type: string;
  source: string;
  agentId: string | null;
  data: string | null;
  timestamp: number;
}

// ── Layout types ──────────────────────────────────────────────────

/** A node after dagre layout has been computed */
export interface LayoutNode {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
  snapshot: Snapshot;
  depth: number;
  childCount: number;
  branchNames: string[];
  isRoot: boolean;
  isBranchHead: boolean;
  collapsed: boolean;
}

/** An edge after layout */
export interface LayoutEdge {
  source: string;
  target: string;
  points: Array<{ x: number; y: number }>;
}

/** Complete laid-out graph */
export interface LayoutGraph {
  nodes: Map<string, LayoutNode>;
  edges: LayoutEdge[];
  width: number;
  height: number;
}

// ── UI state types ────────────────────────────────────────────────

export type ColorScheme = "branch" | "agent" | "depth" | "time" | "mono";
export type LayoutDirection = "TB" | "LR";

export interface ViewState {
  translateX: number;
  translateY: number;
  scale: number;
}

export interface SelectionState {
  primary: string | null;
  secondary: string | null;
  highlighted: Set<string>;
}
