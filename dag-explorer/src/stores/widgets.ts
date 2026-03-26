import { createSignal } from "solid-js";
import type { WidgetPayload } from "./agents";
import { wsStore, type ServerMessage } from "./ws";

// ── Signals ──────────────────────────────────────────────────────

const [widgets, setWidgets] = createSignal<WidgetPayload[]>([]);
const [activeWidgetId, setActiveWidgetId] = createSignal<string | null>(null);

// ── Actions ──────────────────────────────────────────────────────

function addWidget(payload: WidgetPayload) {
  setWidgets((prev) => [...prev, payload]);
}

function removeWidget(id: string) {
  setWidgets((prev) => prev.filter((w) => w.id !== id));
  if (activeWidgetId() === id) setActiveWidgetId(null);
}

function pinFromChat(payload: WidgetPayload) {
  // Avoid duplicates
  if (widgets().some((w) => w.id === payload.id)) return;
  addWidget(payload);
}

function handleWSMessage(msg: ServerMessage) {
  // Widget gallery could receive direct widget_pin messages in the future
  if (msg.type === "widget_pin") {
    const widget: WidgetPayload = {
      id: (msg.widgetId as string) ?? `w-${Date.now()}`,
      source: msg.source as string,
      css: msg.css as string | undefined,
      title: msg.title as string | undefined,
      height: msg.height as number | undefined,
    };
    addWidget(widget);
  }
}

let initialized = false;

function init() {
  if (initialized) return;
  initialized = true;
  wsStore.onMessage(handleWSMessage);
}

// ── Export ────────────────────────────────────────────────────────

export const widgetStore = {
  widgets,
  activeWidgetId,
  setActiveWidgetId,
  addWidget,
  removeWidget,
  pinFromChat,
  init,
};
