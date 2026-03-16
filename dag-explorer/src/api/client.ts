import type { Snapshot, Branch, Agent, SnapshotDiff, IntegrationEvent, Task, TaskUpdate, ContextWindow, CapabilityDetail, CapabilityInvocationResult, Department, Goal, Budget, AuditEntry, Approval } from "./types";

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

async function put<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method: "PUT",
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

// ── Department endpoints ─────────────────────────────────────────

export async function listDepartments(): Promise<Department[]> {
  return get<Department[]>("/departments");
}

export async function createDepartment(data: { name: string; parent?: number; description?: string; budgetLimit?: number; currency?: string }): Promise<Department> {
  return post<Department>("/departments", data);
}

export async function updateDepartment(id: number, data: Partial<Department>): Promise<Department> {
  return put<Department>(`/departments/${id}`, data);
}

// ── Goal endpoints ───────────────────────────────────────────────

export async function listGoals(opts?: { department?: number; agent?: string; status?: string }): Promise<Goal[]> {
  const params = new URLSearchParams();
  if (opts?.department) params.set("department", String(opts.department));
  if (opts?.agent) params.set("agent", opts.agent);
  if (opts?.status) params.set("status", opts.status);
  const qs = params.toString();
  return get<Goal[]>(`/goals${qs ? `?${qs}` : ""}`);
}

export async function createGoal(data: { title: string; department?: number; agent?: string; status?: string; parent?: number; description?: string }): Promise<Goal> {
  return post<Goal>("/goals", data);
}

export async function updateGoal(id: number, data: Partial<Goal>): Promise<Goal> {
  return put<Goal>(`/goals/${id}`, data);
}

// ── Budget endpoints ─────────────────────────────────────────────

export async function listBudgets(): Promise<Budget[]> {
  return get<Budget[]>("/budgets");
}

export async function getBudget(entityId: string): Promise<Budget> {
  return get<Budget>(`/budgets/${entityId}`);
}

export async function updateBudget(entityId: string, data: { limit: number | null; currency?: string }): Promise<Budget> {
  return put<Budget>(`/budgets/${entityId}`, data);
}

// ── Audit endpoints ──────────────────────────────────────────────

export async function getAuditLog(opts?: { agent?: string; type?: string; limit?: number }): Promise<AuditEntry[]> {
  const params = new URLSearchParams();
  if (opts?.agent) params.set("agent", opts.agent);
  if (opts?.type) params.set("type", opts.type);
  if (opts?.limit) params.set("limit", String(opts.limit));
  const qs = params.toString();
  return get<AuditEntry[]>(`/audit${qs ? `?${qs}` : ""}`);
}

// ── Approval endpoints ───────────────────────────────────────────

export async function listApprovals(): Promise<Approval[]> {
  return get<Approval[]>("/approvals");
}

export async function approveRequest(id: string, response?: string): Promise<{ approved: boolean }> {
  return post<{ approved: boolean }>(`/approvals/${id}/approve`, { response: response ?? "approved" });
}

export async function rejectRequest(id: string, reason?: string): Promise<{ rejected: boolean }> {
  return post<{ rejected: boolean }>(`/approvals/${id}/reject`, { reason: reason ?? "rejected" });
}

// ── Agent scheduling ─────────────────────────────────────────────

export async function scheduleAgent(agentId: string, data: { message: string; delaySeconds?: number; recurring?: boolean; intervalSeconds?: number }): Promise<{ scheduled: boolean }> {
  return post<{ scheduled: boolean }>(`/agents/${agentId}/schedule`, data);
}
