import { type Component, For, Show, createEffect, createSignal } from "solid-js";
import { agentStore, type Thought } from "../stores/agents";

const typeConfig: Record<string, { bg: string; fg: string; label: string; icon: string }> = {
  observation: { bg: "rgba(79, 195, 247, 0.12)", fg: "var(--signal)", label: "OBS", icon: "eye" },
  decision: { bg: "rgba(255, 171, 64, 0.12)", fg: "var(--warm)", label: "DEC", icon: "crosshair" },
  action: { bg: "rgba(105, 240, 174, 0.12)", fg: "var(--emerge)", label: "ACT", icon: "zap" },
  reflection: { bg: "rgba(179, 136, 255, 0.12)", fg: "var(--purple)", label: "REF", icon: "mirror" },
};

const ThoughtStream: Component = () => {
  let scrollRef!: HTMLDivElement;
  const [autoScroll, setAutoScroll] = createSignal(true);

  const thoughts = () => agentStore.agentThoughts();

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
        fallback={
          <div class="thought-stream-empty">
            <div class="thought-empty-icon">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="9" stroke="var(--border-hi)" stroke-width="1.2" stroke-dasharray="3 3"/>
                <path d="M12 8v4M12 16h.01" stroke="var(--border-hi)" stroke-width="1.5" stroke-linecap="round"/>
              </svg>
            </div>
            <span class="thought-empty-text">Awaiting cognitive output</span>
            <span class="thought-empty-hint">Thoughts appear as the agent runs cognitive cycles</span>
          </div>
        }
      >
        <div class="thought-stream-count">{thoughts().length} thought{thoughts().length !== 1 ? "s" : ""}</div>
        <For each={thoughts()}>
          {(thought) => <ThoughtCard thought={thought} />}
        </For>
      </Show>
    </div>
  );
};

const ThoughtCard: Component<{ thought: Thought }> = (props) => {
  const [expanded, setExpanded] = createSignal(false);
  const info = () => typeConfig[props.thought.type] ?? typeConfig.observation;
  const time = () => {
    const d = new Date(props.thought.timestamp);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  const isLong = () => props.thought.content.length > 120;
  const displayContent = () => {
    if (expanded() || !isLong()) return props.thought.content;
    return props.thought.content.slice(0, 120) + "...";
  };

  return (
    <div
      class="thought-card"
      classList={{ "thought-card-expandable": isLong(), "thought-card-expanded": expanded() }}
      style={{ "border-left-color": info().fg }}
      onClick={() => isLong() && setExpanded(!expanded())}
    >
      <div class="thought-card-header">
        <span
          class="thought-type-badge"
          style={{ background: info().bg, color: info().fg }}
        >
          {info().label}
        </span>
        <span class="thought-time">{time()}</span>
      </div>
      <div class="thought-content">{displayContent()}</div>
      <Show when={isLong()}>
        <span class="thought-expand-hint">
          {expanded() ? "click to collapse" : "click to expand"}
        </span>
      </Show>
    </div>
  );
};

export default ThoughtStream;
