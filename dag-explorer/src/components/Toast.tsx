import { type Component, For } from "solid-js";
import { toastStore, type ToastType } from "../stores/toast";
import "../styles/toast.css";

const icons: Record<ToastType, string> = {
  info: "\u2139",
  success: "\u2713",
  warning: "\u26A0",
  error: "\u2717",
};

const ToastContainer: Component = () => {
  return (
    <div class="toast-container">
      <For each={toastStore.toasts()}>
        {(toast) => (
          <div
            class={`toast toast-${toast.type}`}
            classList={{ "toast-exiting": toast.exiting }}
          >
            <span class="toast-icon">{icons[toast.type]}</span>
            <span class="toast-message">{toast.message}</span>
            <button
              class="toast-close"
              onClick={() => toastStore.removeToast(toast.id)}
              aria-label="Dismiss"
            >
              &times;
            </button>
          </div>
        )}
      </For>
    </div>
  );
};

export default ToastContainer;
