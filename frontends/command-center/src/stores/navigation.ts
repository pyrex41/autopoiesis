import { createSignal, createMemo } from "solid-js";
import { type ViewId, setCurrentView } from "../lib/commands";

export interface NavEntry {
  view: ViewId;
  agentId?: string;
  label: string;
  timestamp: number;
}

const MAX_HISTORY = 50;

const [history, setHistory] = createSignal<NavEntry[]>([
  { view: "dashboard", label: "Dashboard", timestamp: Date.now() },
]);

export const navigationStore = {
  history,

  current: createMemo(() => {
    const h = history();
    return h[h.length - 1];
  }),

  canGoBack: createMemo(() => history().length > 1),

  push(entry: NavEntry) {
    setHistory((prev) => {
      const next = [...prev, entry];
      return next.length > MAX_HISTORY ? next.slice(-MAX_HISTORY) : next;
    });
  },

  goBack() {
    const h = history();
    if (h.length <= 1) return;
    const prev = h[h.length - 2];
    setHistory(h.slice(0, -1));
    setCurrentView(prev.view);
  },
};
