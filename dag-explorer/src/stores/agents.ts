import { createSignal, createMemo, batch } from "solid-js";
import type { Agent, IntegrationEvent } from "../api/types";
import * as api from "../api/client";
import { wsStore, type ServerMessage } from "./ws";

// ── Types ────────────────────────────────────────────────────────

export interface Thought {
  id: string;
  agentId: string;
  type: "observation" | "decision" | "action" | "reflection";
  content: string;
  timestamp: number;
}

export interface ChatMessage {
  id: string;
  sender: "user" | "jarvis";
  content: string;
  timestamp: number;
}

// ── Signals ──────────────────────────────────────────────────────

const [agents, setAgents] = createSignal<Agent[]>([]);
const [selectedId, setSelectedId] = createSignal<string | null>(null);
const [thoughts, setThoughts] = createSignal<Thought[]>([]);
const [events, setEvents] = createSignal<IntegrationEvent[]>([]);
const [loading, setLoading] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);

// Jarvis chat
const [chatMessages, setChatMessages] = createSignal<ChatMessage[]>([]);
const [chatLoading, setChatLoading] = createSignal(false);

// ── Derived ──────────────────────────────────────────────────────

const selectedAgent = createMemo(() => {
  const id = selectedId();
  if (!id) return null;
  return agents().find((a) => a.id === id) ?? null;
});

const agentThoughts = createMemo(() => {
  const id = selectedId();
  if (!id) return [];
  return thoughts().filter((t) => t.agentId === id);
});

const agentsByState = createMemo(() => {
  const map: Record<string, Agent[]> = {};
  for (const a of agents()) {
    (map[a.state] ??= []).push(a);
  }
  return map;
});

const stats = createMemo(() => {
  const all = agents();
  return {
    total: all.length,
    running: all.filter((a) => a.state === "running").length,
    paused: all.filter((a) => a.state === "paused").length,
    stopped: all.filter((a) => a.state === "stopped").length,
  };
});

// ── Actions ──────────────────────────────────────────────────────

async function loadAgents() {
  setLoading(true);
  setError(null);
  try {
    const list = await api.listAgents();
    setAgents(list);
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
  } finally {
    setLoading(false);
  }
}

async function loadEvents() {
  try {
    const list = await api.getEvents({ limit: 100 });
    setEvents(list);
  } catch {
    // Non-critical
  }
}

function selectAgent(id: string | null) {
  setSelectedId(id);
}

// Agent lifecycle actions — these POST to the API
async function agentAction(action: string, agentId?: string) {
  const id = agentId ?? selectedId();
  if (!id) return;
  try {
    wsStore.send({ type: "agent_action", action, agent_id: id });
    // Also try REST as fallback
    await fetch(`/api/agents/${id}/${action}`, { method: "POST" });
    await loadAgents(); // Refresh
  } catch (e) {
    console.error(`Agent action ${action} failed:`, e);
  }
}

async function createAgent(name: string, capabilities: string[]) {
  try {
    await fetch("/api/agents", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, capabilities }),
    });
    await loadAgents();
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
  }
}

async function startAgent(id?: string) { return agentAction("start", id); }
async function stopAgent(id?: string) { return agentAction("stop", id); }
async function pauseAgent(id?: string) { return agentAction("pause", id); }
async function stepAgent(id?: string) { return agentAction("step", id); }
async function forkAgent(id?: string) { return agentAction("fork", id); }
async function upgradeAgent(id?: string) { return agentAction("upgrade", id); }

// Jarvis chat
function sendChatMessage(content: string) {
  const msg: ChatMessage = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
    sender: "user",
    content,
    timestamp: Date.now(),
  };
  setChatMessages((prev) => [...prev, msg]);
  setChatLoading(true);

  wsStore.send({ type: "chat_prompt", content });
}

// Handle incoming WS messages
function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "agent_list":
    case "agents_updated":
      if (Array.isArray(msg.data)) {
        setAgents(msg.data as Agent[]);
      } else {
        loadAgents();
      }
      break;

    case "thought_added": {
      const thought = msg.data as Thought;
      setThoughts((prev) => [...prev.slice(-499), thought]);
      break;
    }

    case "agent_state_changed": {
      const update = msg.data as { agentId: string; state: string };
      setAgents((prev) =>
        prev.map((a) => (a.id === update.agentId ? { ...a, state: update.state } : a))
      );
      break;
    }

    case "event": {
      const event = msg.data as IntegrationEvent;
      setEvents((prev) => [...prev.slice(-199), event]);
      break;
    }

    case "chat_response": {
      const data = msg.data as { content: string };
      const reply: ChatMessage = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        sender: "jarvis",
        content: data.content,
        timestamp: Date.now(),
      };
      setChatMessages((prev) => [...prev, reply]);
      setChatLoading(false);
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.connect();
  wsStore.subscribe("agents");
  wsStore.subscribe("events");
  wsStore.subscribe("thoughts");
  loadAgents();
  loadEvents();
}

// ── Export ────────────────────────────────────────────────────────

export const agentStore = {
  // Data
  agents,
  selectedId,
  selectedAgent,
  thoughts,
  agentThoughts,
  events,
  loading,
  error,
  stats,
  agentsByState,

  // Chat
  chatMessages,
  chatLoading,
  sendChatMessage,

  // Actions
  init,
  loadAgents,
  loadEvents,
  selectAgent,
  createAgent,
  startAgent,
  stopAgent,
  pauseAgent,
  stepAgent,
  forkAgent,
  upgradeAgent,
};
