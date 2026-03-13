import { type Component, Show } from "solid-js";
import type { Agent } from "../api/types";
import { agentStore } from "../stores/agents";

const AgentActions: Component<{ agent: Agent }> = (props) => {
  const isRunning = () => props.agent.state === "running";
  const isPaused = () => props.agent.state === "paused";
  const isStopped = () => props.agent.state === "stopped" || props.agent.state === "initialized";
  const pending = () => !!agentStore.pendingAction();

  return (
    <div class="agent-actions">
      <Show when={isStopped() || isPaused()}>
        <button
          class="action-btn action-start"
          onClick={() => agentStore.startAgent(props.agent.id)}
          title="Start cognitive loop [r]"
          disabled={pending()}
        >
          <span class="action-icon">▶</span>
          <span class="action-label">Start</span>
          <kbd class="action-kbd">r</kbd>
        </button>
      </Show>

      <Show when={isRunning()}>
        <button
          class="action-btn action-pause"
          onClick={() => agentStore.pauseAgent(props.agent.id)}
          title="Pause agent"
          disabled={pending()}
        >
          <span class="action-icon">⏸</span>
          <span class="action-label">Pause</span>
        </button>
      </Show>

      <Show when={isRunning() || isPaused()}>
        <button
          class="action-btn action-stop"
          onClick={() => agentStore.stopAgent(props.agent.id)}
          title="Stop agent [x]"
          disabled={pending()}
        >
          <span class="action-icon">■</span>
          <span class="action-label">Stop</span>
          <kbd class="action-kbd">x</kbd>
        </button>
      </Show>

      <button
        class="action-btn action-step"
        onClick={() => agentStore.stepAgent(props.agent.id)}
        title="Step one cycle [s]"
        disabled={pending()}
      >
        <span class="action-icon">→</span>
        <span class="action-label">Step</span>
        <kbd class="action-kbd">s</kbd>
      </button>

      <button
        class="action-btn action-fork"
        onClick={() => agentStore.forkAgent(props.agent.id)}
        title="Fork agent"
        disabled={pending()}
      >
        <span class="action-icon">⑂</span>
        <span class="action-label">Fork</span>
      </button>

      <button
        class="action-btn action-upgrade"
        onClick={() => agentStore.upgradeAgent(props.agent.id)}
        title="Upgrade to dual agent"
        disabled={pending()}
      >
        <span class="action-icon">⇑</span>
        <span class="action-label">Upgrade</span>
      </button>
    </div>
  );
};

export default AgentActions;
