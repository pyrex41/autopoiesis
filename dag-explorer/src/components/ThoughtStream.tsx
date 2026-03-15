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

const hasStructured = (t: Thought) =>
  t.confidence != null || t.alternatives != null || t.chosen != null ||
  t.rationale != null || t.source != null || t.capability != null || t.result != null;

const ThoughtCard: Component<{ thought: Thought }> = (props) => {
  const [expanded, setExpanded] = createSignal(false);
  const info = () => typeConfig[props.thought.type] ?? typeConfig.observation;
  const time = () => {
    const d = new Date(props.thought.timestamp);
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  };

  const isExpandable = () => props.thought.content.length > 120 || hasStructured(props.thought);
  const displayContent = () => {
    if (expanded() || props.thought.content.length <= 120) return props.thought.content;
    return props.thought.content.slice(0, 120) + "...";
  };

  return (
    <div
      class="thought-card"
      classList={{ "thought-card-expandable": isExpandable(), "thought-card-expanded": expanded() }}
      style={{ "border-left-color": info().fg }}
      onClick={() => isExpandable() && setExpanded(!expanded())}
    >
      <div class="thought-card-header">
        <span
          class="thought-type-badge"
          style={{ background: info().bg, color: info().fg }}
        >
          {info().label}
        </span>
        <Show when={props.thought.confidence != null}>
          <span class="thought-confidence" title={`Confidence: ${Math.round((props.thought.confidence ?? 0) * 100)}%`}>
            <span class="thought-confidence-bar" style={{ width: `${(props.thought.confidence ?? 0) * 100}%` }} />
          </span>
        </Show>
        <span class="thought-time">{time()}</span>
      </div>
      <div class="thought-content">{displayContent()}</div>
      <Show when={expanded() && hasStructured(props.thought)}>
        <div class="thought-meta-grid">
          <Show when={props.thought.type === "decision" && props.thought.alternatives}>
            <div class="thought-meta-section">
              <span class="thought-meta-label">Alternatives</span>
              <ul class="thought-meta-list">
                <For each={props.thought.alternatives}>
                  {(alt) => (
                    <li classList={{ "thought-meta-chosen": alt === props.thought.chosen }}>
                      {alt}
                      {alt === props.thought.chosen ? " \u2713" : ""}
                    </li>
                  )}
                </For>
              </ul>
            </div>
          </Show>
          <Show when={props.thought.rationale}>
            <div class="thought-meta-section">
              <span class="thought-meta-label">Rationale</span>
              <span class="thought-meta-value">{props.thought.rationale}</span>
            </div>
          </Show>
          <Show when={props.thought.capability}>
            <div class="thought-meta-section">
              <span class="thought-meta-label">Capability</span>
              <span class="thought-meta-value thought-meta-cap">{props.thought.capability}</span>
            </div>
          </Show>
          <Show when={props.thought.result != null}>
            <div class="thought-meta-section">
              <span class="thought-meta-label">Result</span>
              <pre class="thought-meta-pre">{typeof props.thought.result === "string" ? props.thought.result : JSON.stringify(props.thought.result, null, 2)}</pre>
            </div>
          </Show>
          <Show when={props.thought.source}>
            <div class="thought-meta-section">
              <span class="thought-meta-label">Source</span>
              <span class="thought-meta-value">{props.thought.source}</span>
            </div>
          </Show>
        </div>
      </Show>
      <Show when={isExpandable()}>
        <span class="thought-expand-hint">
          {expanded() ? "click to collapse" : "click to expand"}
        </span>
      </Show>
    </div>
  );
};

export default ThoughtStream;
