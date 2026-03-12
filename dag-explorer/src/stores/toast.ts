import { createSignal } from "solid-js";
import { audioEngine } from "../lib/audio";

export type ToastType = "info" | "success" | "warning" | "error";

export interface Toast {
  id: number;
  message: string;
  type: ToastType;
  exiting?: boolean;
}

let nextId = 0;
const MAX_VISIBLE = 5;

const [toasts, setToasts] = createSignal<Toast[]>([]);

function removeToast(id: number) {
  // Mark as exiting for animation, then remove after animation completes
  setToasts((prev) => prev.map((t) => (t.id === id ? { ...t, exiting: true } : t)));
  setTimeout(() => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, 300);
}

function addToast(message: string, type: ToastType = "info", duration = 4000) {
  audioEngine.notification();
  const id = nextId++;
  setToasts((prev) => {
    const next = [...prev, { id, message, type }];
    // Evict oldest if over max
    if (next.length > MAX_VISIBLE) {
      return next.slice(next.length - MAX_VISIBLE);
    }
    return next;
  });
  if (duration > 0) {
    setTimeout(() => removeToast(id), duration);
  }
  return id;
}

export const toastStore = {
  toasts,
  addToast,
  removeToast,
};
