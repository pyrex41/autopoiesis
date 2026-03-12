import { createSignal } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";

export interface ConductorMetrics {
  running: boolean;
  tickCount: number;
  eventsProcessed: number;
  eventsFailed: number;
  timerErrors: number;
  tickErrors: number;
  taskRetries: number;
  pendingTimers: number;
  activeWorkers: number;
  triggersChecked?: number;
  crystallizations?: number;
}

// Ring buffer for sparkline history
const MAX_HISTORY = 60;

const [metrics, setMetrics] = createSignal<ConductorMetrics | null>(null);
const [tickHistory, setTickHistory] = createSignal<number[]>([]);
const [eventHistory, setEventHistory] = createSignal<number[]>([]);
const [loading, setLoading] = createSignal(false);

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "conductor_status": {
      setMetrics(msg as unknown as ConductorMetrics);
      break;
    }
    case "conductor_metrics": {
      const m = msg as unknown as ConductorMetrics;
      setMetrics(m);
      // Append to ring buffers
      setTickHistory(prev => [...prev.slice(-(MAX_HISTORY - 1)), m.tickCount]);
      setEventHistory(prev => [...prev.slice(-(MAX_HISTORY - 1)), m.eventsProcessed]);
      break;
    }
  }
}

function requestStatus() {
  wsStore.send({ type: "conductor_status" } as any);
}

function startConductor() {
  wsStore.send({ type: "conductor_start" } as any);
}

function stopConductor() {
  wsStore.send({ type: "conductor_stop" } as any);
}

function subscribe() {
  wsStore.subscribe("conductor");
  requestStatus();
}

function unsubscribe() {
  wsStore.unsubscribe("conductor");
}

function init() {
  wsStore.onMessage(handleWSMessage);
}

export const conductorStore = {
  metrics,
  tickHistory,
  eventHistory,
  loading,
  requestStatus,
  startConductor,
  stopConductor,
  subscribe,
  unsubscribe,
  init,
};
