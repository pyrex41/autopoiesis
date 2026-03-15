import type { Snapshot, Branch, Agent, SnapshotDiff, IntegrationEvent, Task, TaskUpdate, ContextWindow, CapabilityDetail, CapabilityInvocationResult } from "./types";

const BASE = "/api";

async function get<T>(path: string): Promise<T> {
  const res = await fetch(`${BASE}${path}`);
  if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`);
  return res.json();
}

async function post<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`);
  return res.json();
}

// ── Snapshot endpoints ────────────────────────────────────────────

export async function listSnapshots(opts?: {
  rootOnly?: boolean;
  parentId?: string;
}): Promise<Snapshot[]> {
  const params = new URLSearchParams();
  if (opts?.rootOnly) params.set("root_only", "true");
  if (opts?.parentId) params.set("parent_id", opts.parentId);
  const qs = params.toString();
  return get<Snapshot[]>(`/snapshots${qs ? `?${qs}` : ""}`);
}

export async function getSnapshot(id: string): Promise<Snapshot> {
  return get<Snapshot>(`/snapshots/${id}`);
}

export async function getSnapshotChildren(id: string): Promise<Snapshot[]> {
  return get<Snapshot[]>(`/snapshots/${id}/children`);
}

export async function diffSnapshots(
  idA: string,
  idB: string
): Promise<SnapshotDiff> {
  return get<SnapshotDiff>(`/snapshots/${idA}/diff/${idB}`);
}

// ── Branch endpoints ──────────────────────────────────────────────

export async function listBranches(): Promise<Branch[]> {
  return get<Branch[]>("/branches");
}

export async function createBranch(
  name: string,
  fromSnapshot?: string
): Promise<Branch> {
  return post<Branch>("/branches", { name, from_snapshot: fromSnapshot });
}

export async function checkoutBranch(name: string): Promise<Branch> {
  return post<Branch>(`/branches/${name}/checkout`);
}

// ── Agent endpoints ───────────────────────────────────────────────

export async function listAgents(): Promise<Agent[]> {
  return get<Agent[]>("/agents");
}

export async function getAgent(id: string): Promise<Agent> {
  return get<Agent>(`/agents/${id}`);
}

export async function getAgentSnapshots(id: string): Promise<Snapshot[]> {
  return get<Snapshot[]>(`/agents/${id}/snapshots`);
}

// ── Event endpoints ───────────────────────────────────────────────

export async function getEvents(opts?: {
  limit?: number;
  type?: string;
}): Promise<IntegrationEvent[]> {
  const params = new URLSearchParams();
  if (opts?.limit) params.set("limit", String(opts.limit));
  if (opts?.type) params.set("type", opts.type);
  const qs = params.toString();
  return get<IntegrationEvent[]>(`/events${qs ? `?${qs}` : ""}`);
}

// ── SSE subscription ──────────────────────────────────────────────

export function subscribeEvents(
  onEvent: (type: string, data: unknown) => void
): () => void {
  const source = new EventSource(`${BASE}/events`);
  source.onmessage = (e) => {
    try {
      const parsed = JSON.parse(e.data);
      onEvent(parsed.type ?? "unknown", parsed);
    } catch {
      // ignore malformed events
    }
  };
  source.onerror = () => {
    // EventSource auto-reconnects
  };
  return () => source.close();
}

// ── System info ───────────────────────────────────────────────────

export interface SystemInfo {
  version: string;
  platform: string;
  agentCount: number;
  runningAgents: number;
  branchCount: number;
  pendingRequests: number;
  snapshotStore: string;
}

export async function getSystemInfo(): Promise<SystemInfo> {
  return get<SystemInfo>("/system");
}

// ── Task endpoints ──────────────────────────────────────────────────

export async function listTasks(): Promise<Task[]> {
  return get<Task[]>("/tasks");
}

export async function getTask(id: string): Promise<Task> {
  return get<Task>(`/tasks/${id}`);
}

export async function updateTaskStatus(id: string, update: TaskUpdate): Promise<{ message: string; taskId: string }> {
  return post<{ message: string; taskId: string }>(`/tasks/${id}/status`, update);
}

// ── Context window ───────────────────────────────────────────────

export async function getAgentContext(id: string): Promise<ContextWindow | null> {
  try {
    return await get<ContextWindow>(`/agents/${id}/context`);
  } catch {
    return null;
  }
}

// ── Agent introspection endpoints ────────────────────────────────

export async function getAgentEvents(agentId: string, opts?: {
  limit?: number;
  type?: string;
}): Promise<IntegrationEvent[]> {
  const params = new URLSearchParams();
  params.set("agent_id", agentId);
  if (opts?.limit) params.set("limit", String(opts.limit));
  if (opts?.type) params.set("type", opts.type);
  return get<IntegrationEvent[]>(`/events?${params.toString()}`);
}

export async function getAgentCapabilities(agentId: string): Promise<CapabilityDetail[]> {
  return get<CapabilityDetail[]>(`/agents/${agentId}/capabilities`);
}

export async function invokeCapability(
  agentId: string,
  capability: string,
  args?: Record<string, unknown>
): Promise<CapabilityInvocationResult> {
  return post<CapabilityInvocationResult>(`/agents/${agentId}/invoke`, { capability, args });
}

export async function takeAgentSnapshot(agentId: string): Promise<Snapshot> {
  return post<Snapshot>(`/agents/${agentId}/snapshot`);
}
