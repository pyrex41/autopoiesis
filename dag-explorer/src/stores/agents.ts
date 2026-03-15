import { createSignal, createMemo, batch } from "solid-js";
import type { Agent, IntegrationEvent, CapabilityDetail, Snapshot } from "../api/types";
import * as api from "../api/client";
import { wsStore, type ServerMessage } from "./ws";
import { audioEngine } from "../lib/audio";
import { toastStore } from "./toast";

// ── Types ────────────────────────────────────────────────────────

export interface Thought {
  id: string;
  agentId: string;
  type: "observation" | "decision" | "action" | "reflection";
  content: string;
  timestamp: number;
  // Structured fields (optional, type-specific)
  confidence?: number;
  alternatives?: string[];
  chosen?: string;
  rationale?: string;
  source?: string;
  capability?: string;
  result?: unknown;
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

// Context window
const [contextWindow, setContextWindow] = createSignal<{ used: number; total: number } | null>(null);

// Agent introspection
const [agentEvents, setAgentEvents] = createSignal<IntegrationEvent[]>([]);
const [agentEventsLoading, setAgentEventsLoading] = createSignal(false);
const [agentCapabilities, setAgentCapabilities] = createSignal<CapabilityDetail[]>([]);
const [agentCapabilitiesLoading, setAgentCapabilitiesLoading] = createSignal(false);
const [agentSnapshots, setAgentSnapshots] = createSignal<Snapshot[]>([]);
const [agentSnapshotsLoading, setAgentSnapshotsLoading] = createSignal(false);

// Per-agent chat — separate history per agent/jarvis
const [chatHistories, setChatHistories] = createSignal<Record<string, ChatMessage[]>>({});
const [chatLoading, setChatLoading] = createSignal(false);
const [streamingText, setStreamingText] = createSignal<string | null>(null);
let activeChatAgentId: string | null = null;
let streamingMessageId: string | null = null;

// Derived: chat messages for the currently selected agent (or "jarvis")
const chatMessages = () => {
  const id = selectedId() ?? "jarvis";
  return chatHistories()[id] ?? [];
};

// Action feedback
const [pendingAction, setPendingAction] = createSignal<string | null>(null);

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
    setAgents(list ?? []);
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
  } finally {
    setLoading(false);
  }
}

async function loadEvents() {
  try {
    const list = await api.getEvents({ limit: 100 });
    setEvents(list ?? []);
  } catch {
    // Non-critical
  }
}

// Fix 7: Subscribe to per-agent thought channels + load historical data
function selectAgent(id: string | null) {
  const prev = selectedId();
  if (prev) wsStore.unsubscribe(`agent:${prev}`);
  setSelectedId(id);
  if (id) {
    wsStore.subscribe(`agent:${id}`);
    // Load historical thoughts for this agent
    loadAgentThoughts(id);
    // Load context window
    loadAgentContext(id);
    // Load agent events and capabilities
    loadAgentEvents(id);
    loadAgentCapabilities(id);
  } else {
    // Clear introspection data
    setAgentEvents([]);
    setAgentCapabilities([]);
    setAgentSnapshots([]);
  }
}

async function loadAgentEvents(agentId: string) {
  setAgentEventsLoading(true);
  try {
    const list = await api.getAgentEvents(agentId, { limit: 100 });
    setAgentEvents(list ?? []);
  } catch {
    // Non-critical
  } finally {
    setAgentEventsLoading(false);
  }
}

async function loadAgentCapabilities(agentId: string) {
  setAgentCapabilitiesLoading(true);
  try {
    const list = await api.getAgentCapabilities(agentId);
    setAgentCapabilities(list ?? []);
  } catch {
    // Non-critical — will fall back to string badges
  } finally {
    setAgentCapabilitiesLoading(false);
  }
}

async function loadAgentSnapshots(agentId: string) {
  setAgentSnapshotsLoading(true);
  try {
    const list = await api.getAgentSnapshots(agentId);
    setAgentSnapshots(list ?? []);
  } catch {
    // Non-critical
  } finally {
    setAgentSnapshotsLoading(false);
  }
}

async function loadAgentThoughts(agentId: string) {
  try {
    const result = await fetch(`/api/agents/${agentId}/thoughts?limit=50`);
    if (result.ok) {
      const data = await result.json();
      if (Array.isArray(data)) {
        // Merge with existing thoughts, dedup by id
        const existing = new Set(thoughts().filter(t => t.agentId === agentId).map(t => t.id));
        const newThoughts: Thought[] = data
          .filter((t: any) => !existing.has(t.id))
          .map((t: any) => ({
            id: t.id ?? `hist-${t.timestamp}-${Math.random().toString(36).slice(2)}`,
            agentId: agentId,
            type: t.type ?? "observation",
            content: t.content ?? (typeof t === "string" ? t : JSON.stringify(t)),
            timestamp: t.timestamp ?? Date.now(),
            confidence: t.confidence,
            alternatives: t.alternatives,
            chosen: t.chosen,
            rationale: t.rationale,
            source: t.source,
            capability: t.capability,
            result: t.result,
          }));
        if (newThoughts.length > 0) {
          setThoughts(prev => [...newThoughts, ...prev].slice(-500));
        }
      }
    }
  } catch {
    // Non-critical — thoughts will arrive via WS
  }
}

async function loadAgentContext(agentId: string) {
  try {
    const ctx = await api.getAgentContext(agentId);
    if (ctx) setContextWindow(ctx);
    else setContextWindow(null);
  } catch {
    setContextWindow(null);
  }
}

// Fix 3: Map frontend action names to backend REST paths
const restPathMap: Record<string, string> = {
  step: "cycle",
  start: "start",
  stop: "stop",
  pause: "pause",
};

// Agent lifecycle actions
async function agentAction(action: string, agentId?: string) {
  const id = agentId ?? selectedId();
  if (!id) return;
  setPendingAction(action);
  try {
    // Fix 2: Use camelCase field names
    wsStore.send({ type: "agent_action", agentId: id, action });
    // Fix 3: Use correct REST path; fork/upgrade have no REST endpoint
    const restPath = restPathMap[action];
    if (restPath) {
      await fetch(`/api/agents/${id}/${restPath}`, { method: "POST" });
    }
    await loadAgents(); // Refresh
    toastStore.addToast(`${action} sent`, "success", 2000);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    toastStore.addToast(`${action} failed: ${msg}`, "error");
    console.error(`Agent action ${action} failed:`, e);
  } finally {
    setPendingAction(null);
  }
}

// Create agent via WebSocket, REST as fallback.
// If task is provided, backend auto-starts the agent and sends the task.
async function createAgent(name: string, capabilities: string[], task?: string) {
  try {
    if (wsStore.connected()) {
      wsStore.send({ type: "create_agent", name, capabilities, ...(task ? { task } : {}) });
      // Wait for agent_created broadcast, then auto-select the new agent
      setTimeout(async () => {
        await loadAgents();
        // Find the newly created agent by name and select it
        const newAgent = agents().find((a) => a.name === name);
        if (newAgent) {
          selectAgent(newAgent.id);
          // Dispatch event to expand JarvisBar so user sees response
          window.dispatchEvent(new CustomEvent("ap:expand-jarvis"));
          // If task was provided, add it to chat history so user sees what was sent
          if (task) {
            addChatMessage(newAgent.id, {
              id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
              sender: "user",
              content: task,
              timestamp: Date.now(),
            });
            setChatLoading(true);
          }
        }
      }, 600);
    } else {
      await fetch("/api/agents", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, capabilities, ...(task ? { task } : {}) }),
      });
      await loadAgents();
    }
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

// Helper: add a message to a specific agent's chat history
function addChatMessage(agentId: string, msg: ChatMessage) {
  setChatHistories((prev) => ({
    ...prev,
    [agentId]: [...(prev[agentId] ?? []), msg],
  }));
}

// Fix 5: Jarvis chat with proper protocol
function sendChatMessage(content: string) {
  const agentId = selectedId() ?? "jarvis";

  // Check connection before sending
  if (!wsStore.connected()) {
    const sysMsg: ChatMessage = {
      id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
      sender: "jarvis",
      content: "Not connected to backend. Type `/` for offline CLI commands.",
      timestamp: Date.now(),
    };
    addChatMessage(agentId, sysMsg);
    return;
  }

  // Start chat session if not active for this agent
  if (activeChatAgentId !== agentId) {
    wsStore.send({ type: "start_chat", agentId });
    activeChatAgentId = agentId;
  }

  const msg: ChatMessage = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
    sender: "user",
    content,
    timestamp: Date.now(),
  };
  addChatMessage(agentId, msg);
  setChatLoading(true);

  // Fix 5: Send with correct field names (text, not content; include agentId)
  wsStore.send({ type: "chat_prompt", agentId, text: content });

  // Timeout: clear loading after 120s if no response (rho-cli may use tools)
  const timeoutAgentId = agentId;
  setTimeout(() => {
    if (chatLoading()) {
      setChatLoading(false);
      const errMsg: ChatMessage = {
        id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
        sender: "jarvis",
        content: "Response timed out. The backend may be busy or unreachable.",
        timestamp: Date.now(),
      };
      addChatMessage(timeoutAgentId, errMsg);
    }
  }, 120000);
}

// Handle incoming WS messages
function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    // Backend sends flat top-level fields (no `data` wrapper)
    case "agent_created": {
      const agent = msg.agent as Agent;
      if (agent) setAgents((prev) => [...prev, agent]);
      break;
    }

    case "agents":
    case "agents_updated": {
      const agents = msg.agents;
      if (Array.isArray(agents)) {
        setAgents(agents as Agent[]);
      } else {
        loadAgents();
      }
      break;
    }

    case "thought_added": {
      const thought = msg.thought as Thought;
      if (thought) {
        setThoughts((prev) => {
          // Dedup by ID — same thought may arrive via multiple subscription channels
          if (thought.id && prev.some((t) => t.id === thought.id)) return prev;
          return [...prev.slice(-499), thought];
        });
      }
      break;
    }

    case "agent_state_changed": {
      const agentId = msg.agentId as string;
      const state = msg.state as string;
      if (agentId && state) {
        setAgents((prev) =>
          prev.map((a) => (a.id === agentId ? { ...a, state } : a))
        );
        if (state === "running") audioEngine.agentStart();
        else if (state === "stopped") audioEngine.agentStop();
      }
      break;
    }

    case "event": {
      const event = msg as unknown as IntegrationEvent;
      setEvents((prev) => [...prev.slice(-199), event]);
      // Also append to agent-specific events if it matches the selected agent
      const selId = selectedId();
      if (selId && (event.agentId === selId || event.source === selId)) {
        setAgentEvents((prev) => [...prev.slice(-199), event]);
      }
      break;
    }

    case "context_update": {
      const data = msg.data as { used: number; total: number } | undefined;
      if (data) setContextWindow(data);
      break;
    }

    case "chat_stream_start": {
      // Begin streaming — create a placeholder message that we'll update
      // Ignore duplicate starts (can arrive via multiple subscription channels)
      if (streamingMessageId) break;
      const startAgentId = (msg.agentId as string) ?? activeChatAgentId ?? "jarvis";
      streamingMessageId = `stream-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      setStreamingText("");
      const placeholder: ChatMessage = {
        id: streamingMessageId,
        sender: "jarvis",
        content: "",
        timestamp: Date.now(),
      };
      addChatMessage(startAgentId, placeholder);
      break;
    }

    case "chat_stream_delta": {
      const delta = msg.delta as string;
      const deltaAgentId = (msg.agentId as string) ?? activeChatAgentId ?? "jarvis";
      if (delta && streamingMessageId) {
        const msgId = streamingMessageId;
        // Update streaming text and chat history atomically
        batch(() => {
          setStreamingText((prev) => (prev ?? "") + delta);
          setChatHistories((prev) => {
            const history = prev[deltaAgentId] ?? [];
            return {
              ...prev,
              [deltaAgentId]: history.map((m) =>
                m.id === msgId ? { ...m, content: m.content + delta } : m
              ),
            };
          });
        });
      }
      break;
    }

    case "chat_stream_end": {
      // Don't clear streamingMessageId here — chat_response needs it to
      // replace the placeholder with the final complete text.
      // streamingMessageId is cleared in the chat_response handler.
      setStreamingText(null);
      break;
    }

    case "chat_response": {
      const text = msg.text as string;
      const respAgentId = (msg.agentId as string) ?? activeChatAgentId ?? "jarvis";
      if (streamingMessageId) {
        // We were streaming — update the final message with complete text
        setChatHistories((prev) => {
          const history = prev[respAgentId] ?? [];
          return {
            ...prev,
            [respAgentId]: history.map((m) =>
              m.id === streamingMessageId ? { ...m, content: text ?? "" } : m
            ),
          };
        });
        streamingMessageId = null;
        setStreamingText(null);
      } else {
        // Non-streaming response — add as new message
        const reply: ChatMessage = {
          id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
          sender: "jarvis",
          content: text ?? "",
          timestamp: Date.now(),
        };
        addChatMessage(respAgentId, reply);
      }
      setChatLoading(false);
      break;
    }

    case "chat_prompt_accepted": {
      // Agent-routed chat — response will come via thought broadcast
      // Keep loading state, response arrives as thought_added + chat_response
      break;
    }

    case "snapshot_created": {
      // DAG live update — could trigger DAG refresh
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.connect();
  wsStore.subscribe("agents");
  wsStore.subscribe("events");
  wsStore.subscribe("snapshots");
  // Fix 7: Don't subscribe to global "thoughts" — per-agent subscriptions
  // happen in selectAgent()
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

  // Context
  contextWindow,

  // Introspection
  agentEvents,
  agentEventsLoading,
  agentCapabilities,
  agentCapabilitiesLoading,
  agentSnapshots,
  agentSnapshotsLoading,
  loadAgentSnapshots,

  // Chat
  chatMessages,
  chatLoading,
  streamingText,
  sendChatMessage,

  // Action feedback
  pendingAction,

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
