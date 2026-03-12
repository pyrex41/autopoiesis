import { type Component } from "solid-js";
import { wsStore } from "../stores/ws";

const ConnectionIndicator: Component = () => {
  const statusText = () => {
    if (wsStore.connected()) return "Connected";
    if (wsStore.reconnecting()) return "Reconnecting...";
    return "Disconnected";
  };

  const statusClass = () => {
    if (wsStore.connected()) return "indicator-connected";
    if (wsStore.reconnecting()) return "indicator-reconnecting";
    return "indicator-disconnected";
  };

  return (
    <div class={`connection-indicator ${statusClass()}`}>
      <div class="indicator-dot" />
      <span class="indicator-text">{statusText()}</span>
    </div>
  );
};

export default ConnectionIndicator;
