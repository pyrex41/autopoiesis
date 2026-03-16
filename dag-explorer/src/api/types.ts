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

// ── Task types ──────────────────────────────────────────────────────

export type TaskStatus = "pending" | "in-progress" | "done" | "blocked" | "cancelled";
export type TaskPriority = "low" | "medium" | "high";
export type TaskAgentType = "builder" | "fast-builder";

export interface Task {
  id: string;
  title: string;
  description: string;
  status: TaskStatus;
  complexity: number;
  priority: TaskPriority;
  agent_type: TaskAgentType;
  dependencies: string[];
  subtasks?: string[];
  parent_id?: string;
  created_at: string;
  updated_at: string;
}

export interface TaskUpdate {
  status: TaskStatus;
}

/** Context window usage for an agent */
export interface ContextWindow {
  used: number;
  total: number;
  model?: string;
}

/** Detailed capability info from backend */
export interface CapabilityDetail {
  name: string;
  description: string;
  parameters: { name: string; type: string }[];
}

/** Result of invoking a capability */
export interface CapabilityInvocationResult {
  result: unknown;
  capability: string;
}

// ── Command Center types ──────────────────────────────────────────

export interface Department {
  id: number;
  name: string;
  parent: number | null;
  description: string | null;
  budgetLimit: number | null;
  currency: string | null;
  createdAt: number;
}

export interface Goal {
  id: number;
  title: string;
  description: string | null;
  department: number | null;
  agent: string | null;
  status: string;
  parent: number | null;
  createdAt: number;
}

export interface Budget {
  id?: number;
  entityId: string;
  entityType: string;
  limit: number | null;
  spent: number;
  currency: string;
  updatedAt?: number;
}

export interface AuditEntry {
  id: string;
  type: string;
  source: string;
  agentId: string | null;
  data: string | null;
  timestamp: number;
}

export interface Approval {
  id: string;
  prompt: string;
  context: string | null;
  options: string[];
  status: string;
  default: string | null;
  createdAt: number;
}
