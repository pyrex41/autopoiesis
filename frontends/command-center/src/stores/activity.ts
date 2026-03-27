import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";

// ── Types ────────────────────────────────────────────────────────

export interface ActivityData {
  agentId: string;
  agentName: string;
  state: "active" | "idle" | "long-idle";
  currentTool: string | null;
  toolStartTime: number | null;
  duration: number;
  totalCost: number;
  tokens: number;
  callCount: number;
  lastActive: number;
}

// ── Signals ──────────────────────────────────────────────────────

const [activities, setActivities] = createSignal<Map<string, ActivityData>>(new Map());

// ── Derived ──────────────────────────────────────────────────────

const activeAgents = createMemo(() => {
  const all = [...activities().values()];
  return all.filter((a) => a.state === "active");
});

const totalCost = createMemo(() => {
  let sum = 0;
  for (const a of activities().values()) {
    sum += a.totalCost;
  }
  return sum;
});

const totalCalls = createMemo(() => {
  let sum = 0;
  for (const a of activities().values()) {
    sum += a.callCount;
  }
  return sum;
});

const totalTokens = createMemo(() => {
  let sum = 0;
  for (const a of activities().values()) {
    sum += a.tokens;
  }
  return sum;
});

const costByAgent = createMemo(() => {
  const result: Array<{ agentId: string; agentName: string; cost: number; tokens: number; calls: number }> = [];
  for (const a of activities().values()) {
    result.push({
      agentId: a.agentId,
      agentName: a.agentName,
      cost: a.totalCost,
      tokens: a.tokens,
      calls: a.callCount,
    });
  }
  return result.sort((a, b) => b.cost - a.cost);
});

// ── Helpers ──────────────────────────────────────────────────────

function parseActivityData(raw: any): ActivityData {
  const lastActive = raw.lastActive ?? raw.last_active ?? Date.now();
  const idleSec = (Date.now() - lastActive) / 1000;
  const hasTool = !!(raw.currentTool ?? raw.current_tool);

  let state: ActivityData["state"] = "idle";
  if (hasTool) {
    state = "active";
  } else if (idleSec > 300) {
    state = "long-idle";
  }

  return {
    agentId: raw.agentId ?? raw.agent_id ?? "",
    agentName: raw.agentName ?? raw.agent_name ?? raw.agentId ?? raw.agent_id ?? "",
    state,
    currentTool: raw.currentTool ?? raw.current_tool ?? null,
    toolStartTime: raw.toolStartTime ?? raw.tool_start_time ?? null,
    duration: raw.duration ?? 0,
    totalCost: raw.totalCost ?? raw.total_cost ?? 0,
    tokens: raw.tokens ?? 0,
    callCount: raw.callCount ?? raw.call_count ?? 0,
    lastActive,
  };
}

// ── WS Handling ──────────────────────────────────────────────────

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "activities": {
      // Initial load response
      const data = msg.data as any;
      const list: any[] = data?.activities ?? (Array.isArray(data) ? data : []);
      const map = new Map<string, ActivityData>();
      for (const raw of list) {
        const activity = parseActivityData(raw);
        if (activity.agentId) {
          map.set(activity.agentId, activity);
        }
      }
      setActivities(map);
      break;
    }

    case "activity_update": {
      // Real-time update for a single agent
      const raw = msg.data as any;
      const activity = parseActivityData(raw);
      if (activity.agentId) {
        setActivities((prev) => {
          const next = new Map(prev);
          next.set(activity.agentId, activity);
          return next;
        });
      }
      break;
    }

    case "cost_summary": {
      // Cost summary response — merge cost data into activities
      const data = msg.data as any;
      const perAgent = data?.perAgent ?? data?.per_agent ?? {};
      setActivities((prev) => {
        const next = new Map(prev);
        for (const [agentId, costs] of Object.entries(perAgent)) {
          const c = costs as any;
          const existing = next.get(agentId);
          if (existing) {
            next.set(agentId, {
              ...existing,
              totalCost: c.cost ?? c.totalCost ?? existing.totalCost,
              tokens: c.tokens ?? existing.tokens,
              callCount: c.calls ?? c.callCount ?? existing.callCount,
            });
          } else {
            next.set(agentId, {
              agentId,
              agentName: c.agentName ?? c.agent_name ?? agentId,
              state: "idle",
              currentTool: null,
              toolStartTime: null,
              duration: 0,
              totalCost: c.cost ?? c.totalCost ?? 0,
              tokens: c.tokens ?? 0,
              callCount: c.calls ?? c.callCount ?? 0,
              lastActive: 0,
            });
          }
        }
        return next;
      });
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.subscribe("activity");
  wsStore.send({ type: "get_activities" } as any);
}

// ── Export ────────────────────────────────────────────────────────

export const activityStore = {
  activities,
  activeAgents,
  totalCost,
  totalCalls,
  totalTokens,
  costByAgent,
  init,
};
