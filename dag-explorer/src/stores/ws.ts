import { createSignal, onCleanup } from "solid-js";

export interface ServerMessage {
  type: string;
  channel?: string;
  // All backend fields are at top level (no `data` wrapper)
  [key: string]: unknown;
}

export type ClientMessage =
  | { type: "subscribe"; channel: string }
  | { type: "unsubscribe"; channel: string }
  | { type: "start_chat"; agentId: string }
  | { type: "chat_prompt"; agentId: string; text: string }
  | { type: "stop_chat" }
  | { type: "agent_action"; agentId: string; action: string; params?: Record<string, unknown> }
  | { type: "create_agent"; name: string; capabilities: string[] }
  | { type: "step_agent"; agentId: string; environment?: Record<string, unknown> }
  | { type: "fork_agent"; agentId: string; name?: string }
  | { type: "upgrade_to_dual"; agentId: string }
  | { type: "conductor_status" }
  | { type: "conductor_start" }
  | { type: "conductor_stop" }
  | { type: "subscribe_conductor" }
  | { type: "holodeck_subscribe" }
  | { type: "holodeck_unsubscribe" }
  | { type: "holodeck_input"; key: string }
  | { type: "holodeck_select"; entityId: number };

type MessageHandler = (msg: ServerMessage) => void;

const WS_URL = `ws://${window.location.host}/ws`;
const RECONNECT_DELAY_MS = 2000;
const MAX_RECONNECT_DELAY_MS = 30000;

const [connected, setConnected] = createSignal(false);
const [reconnecting, setReconnecting] = createSignal(false);

let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let reconnectDelay = RECONNECT_DELAY_MS;
let handlers: MessageHandler[] = [];
let pendingSubscriptions: Set<string> = new Set();

function connect() {
  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    return;
  }

  try {
    socket = new WebSocket(WS_URL);
  } catch {
    scheduleReconnect();
    return;
  }

  socket.onopen = () => {
    setConnected(true);
    setReconnecting(false);
    reconnectDelay = RECONNECT_DELAY_MS;

    // Re-subscribe to channels
    for (const channel of pendingSubscriptions) {
      send({ type: "subscribe", channel });
    }
  };

  socket.onmessage = (event) => {
    try {
      const msg: ServerMessage = JSON.parse(event.data);
      for (const handler of handlers) {
        handler(msg);
      }
    } catch {
      // Ignore malformed messages
    }
  };

  socket.onclose = () => {
    setConnected(false);
    socket = null;
    scheduleReconnect();
  };

  socket.onerror = () => {
    // onclose will fire after this
  };
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  setReconnecting(true);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    reconnectDelay = Math.min(reconnectDelay * 1.5, MAX_RECONNECT_DELAY_MS);
    connect();
  }, reconnectDelay);
}

function disconnect() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (socket) {
    socket.close();
    socket = null;
  }
  setConnected(false);
  setReconnecting(false);
}

function send(msg: ClientMessage) {
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(msg));
  }
}

function subscribe(channel: string) {
  pendingSubscriptions.add(channel);
  send({ type: "subscribe", channel });
}

function unsubscribe(channel: string) {
  pendingSubscriptions.delete(channel);
  send({ type: "unsubscribe", channel });
}

function onMessage(handler: MessageHandler): () => void {
  handlers.push(handler);
  return () => {
    handlers = handlers.filter((h) => h !== handler);
  };
}

export const wsStore = {
  connected,
  reconnecting,
  connect,
  disconnect,
  send,
  subscribe,
  unsubscribe,
  onMessage,
};
