import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";
import { activityStore } from "./activity";
import type { Budget } from "../api/types";
import * as api from "../api/client";

const [budgets, setBudgets] = createSignal<Budget[]>([]);

const budgetByAgent = createMemo(() => {
  const map = new Map<string, Budget>();
  for (const b of budgets()) {
    if (b.entityType === "agent") {
      map.set(b.entityId, b);
    }
  }
  return map;
});

const mergedBudgets = createMemo(() => {
  const result: Array<Budget & { agentName?: string; pctUsed: number }> = [];
  const costData = activityStore.costByAgent();
  const limitMap = budgetByAgent();

  for (const c of costData) {
    const budget = limitMap.get(c.agentId);
    const limit = budget?.limit ?? null;
    const spent = c.cost;
    result.push({
      entityId: c.agentId,
      entityType: "agent",
      limit,
      spent,
      currency: budget?.currency ?? "USD",
      agentName: c.agentName,
      pctUsed: limit ? (spent / limit) * 100 : 0,
    });
  }
  return result.sort((a, b) => b.spent - a.spent);
});

const totalSpend = createMemo(() => {
  return mergedBudgets().reduce((sum, b) => sum + b.spent, 0);
});

const totalLimit = createMemo(() => {
  return mergedBudgets().reduce((sum, b) => sum + (b.limit ?? 0), 0);
});

async function loadBudgets() {
  try {
    const data = await api.listBudgets();
    setBudgets(Array.isArray(data) ? data : []);
  } catch { /* non-critical */ }
}

async function setLimit(entityId: string, limit: number | null, currency?: string) {
  try {
    const updated = await api.updateBudget(entityId, { limit, currency });
    setBudgets((prev) => {
      const idx = prev.findIndex((b) => b.entityId === entityId);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = updated;
        return next;
      }
      return [...prev, updated];
    });
  } catch { /* ignore */ }
}

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "budgets": {
      const list = (msg as any).budgets;
      if (Array.isArray(list)) setBudgets(list);
      break;
    }
    case "budget_updated": {
      const budget = (msg as any).budget as Budget;
      if (budget) {
        setBudgets((prev) => {
          const idx = prev.findIndex((b) => b.entityId === budget.entityId);
          if (idx >= 0) {
            const next = [...prev];
            next[idx] = budget;
            return next;
          }
          return [...prev, budget];
        });
      }
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  loadBudgets();
}

export const budgetStore = {
  budgets,
  budgetByAgent,
  mergedBudgets,
  totalSpend,
  totalLimit,
  init,
  loadBudgets,
  setLimit,
};
