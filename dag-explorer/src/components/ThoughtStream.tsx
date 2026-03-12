import { type Component, For, Show, createEffect, createSignal } from "solid-js";
import { agentStore, type Thought } from "../stores/agents";

const typeColors: Record<string, { bg: string; fg: string; label: string }> = {
  observation: { bg: "rgba(79, 195, 247, 0.15)", fg: "var(--signal)", label: "OBS" },
  decision: { bg: "rgba(255, 171, 64, 0.15)", fg: "var(--warm)", label: "DEC" },
  action: { bg: "rgba(105, 240, 174, 0.15)", fg: "var(--emerge)", label: "ACT" },
  reflection: { bg: "rgba(179, 136, 255, 0.15)", fg: "var(--purple)", label: "REF" },
};

const ThoughtStream: Component = () => {
  let scrollRef!: HTMLDivElement;
  const [autoScroll, setAutoScroll] = createSignal(true);

  const thoughts = () => agentStore.agentThoughts();

  // Auto-scroll when new thoughts arrive
  createEffect(() => {
    const _ = thoughts().length;
    if (autoScroll() && scrollRef) {
      requestAnimationFrame(() => {
        scrollRef.scrollTop = scrollRef.scrollHeight;
      });
    }
  });

  function handleScroll() {
    if (!scrollRef) return;
    const atBottom = scrollRef.scrollHeight - scrollRef.scrollTop - scrollRef.clientHeight < 40;
    setAutoScroll(atBottom);
  }

  return (
    <div class="thought-stream" ref={scrollRef!} onScroll={handleScroll}>
      <Show
        when={thoughts().length > 0}
        fallback={<div class="thought-stream-empty">No thoughts yet</div>}
      >
        <For each={thoughts()}>
          {(thought) => <ThoughtCard thought={thought} />}
        </For>
      </Show>
    </div>
  );
};

const ThoughtCard: Component<{ thought: Thought }> = (props) => {
  const info = () => typeColors[props.thought.type] ?? typeColors.observation;
  const time = () => {
    const d = new Date(props.thought.timestamp);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  return (
    <div class="thought-card" style={{ "border-left-color": info().fg }}>
      <div class="thought-card-header">
        <span
          class="thought-type-badge"
          style={{ background: info().bg, color: info().fg }}
        >
          {info().label}
        </span>
        <span class="thought-time">{time()}</span>
      </div>
      <div class="thought-content">{props.thought.content}</div>
    </div>
  );
};

export default ThoughtStream;
