import { type Component, type JSX, Show } from "solid-js";

const icons: Record<string, () => JSX.Element> = {
  constellation: () => (
    <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
      <circle cx="12" cy="12" r="3" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <circle cx="36" cy="10" r="3" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <circle cx="24" cy="24" r="3.5" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <circle cx="10" cy="38" r="3" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <circle cx="38" cy="36" r="3" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <line x1="12" y1="12" x2="24" y2="24" stroke="var(--text-dim)" stroke-width="0.75" />
      <line x1="36" y1="10" x2="24" y2="24" stroke="var(--text-dim)" stroke-width="0.75" />
      <line x1="10" y1="38" x2="24" y2="24" stroke="var(--text-dim)" stroke-width="0.75" />
      <line x1="38" y1="36" x2="24" y2="24" stroke="var(--text-dim)" stroke-width="0.75" />
    </svg>
  ),
  radar: () => (
    <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
      <circle cx="24" cy="24" r="20" stroke="var(--text-dim)" stroke-width="0.75" />
      <circle cx="24" cy="24" r="14" stroke="var(--text-dim)" stroke-width="0.75" />
      <circle cx="24" cy="24" r="8" stroke="var(--text-dim)" stroke-width="0.75" />
      <circle cx="24" cy="24" r="2" fill="var(--border-hi)" />
      <line x1="24" y1="24" x2="38" y2="10" stroke="var(--border-hi)" stroke-width="1.5" stroke-linecap="round" />
    </svg>
  ),
  orbit: () => (
    <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
      <circle cx="24" cy="24" r="6" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <ellipse cx="24" cy="24" rx="20" ry="10" stroke="var(--text-dim)" stroke-width="0.75" transform="rotate(-20 24 24)" />
      <circle cx="40" cy="18" r="2.5" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="0.75" />
    </svg>
  ),
  signal: () => (
    <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
      <circle cx="24" cy="36" r="3" fill="var(--border-hi)" stroke="var(--text-dim)" stroke-width="1" />
      <path d="M18 30 C18 24, 30 24, 30 30" stroke="var(--text-dim)" stroke-width="0.75" fill="none" />
      <path d="M13 26 C13 18, 35 18, 35 26" stroke="var(--text-dim)" stroke-width="0.75" fill="none" />
      <path d="M8 22 C8 12, 40 12, 40 22" stroke="var(--text-dim)" stroke-width="0.75" fill="none" />
    </svg>
  ),
  mesh: () => (
    <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
      {/* Front face */}
      <polygon points="14,18 34,18 34,38 14,38" stroke="var(--text-dim)" stroke-width="0.75" fill="none" />
      {/* Back face connections */}
      <line x1="14" y1="18" x2="22" y2="10" stroke="var(--text-dim)" stroke-width="0.75" />
      <line x1="34" y1="18" x2="42" y2="10" stroke="var(--text-dim)" stroke-width="0.75" />
      <line x1="34" y1="38" x2="42" y2="30" stroke="var(--text-dim)" stroke-width="0.75" />
      {/* Back face */}
      <line x1="22" y1="10" x2="42" y2="10" stroke="var(--text-dim)" stroke-width="0.75" />
      <line x1="42" y1="10" x2="42" y2="30" stroke="var(--text-dim)" stroke-width="0.75" />
      {/* Corner dots */}
      <circle cx="14" cy="18" r="2" fill="var(--border-hi)" />
      <circle cx="34" cy="18" r="2" fill="var(--border-hi)" />
      <circle cx="34" cy="38" r="2" fill="var(--border-hi)" />
      <circle cx="14" cy="38" r="2" fill="var(--border-hi)" />
      <circle cx="22" cy="10" r="2" fill="var(--border-hi)" />
      <circle cx="42" cy="10" r="2" fill="var(--border-hi)" />
      <circle cx="42" cy="30" r="2" fill="var(--border-hi)" />
    </svg>
  ),
};

const EmptyState: Component<{
  icon: string;
  title: string;
  description: string;
  action?: JSX.Element;
}> = (props) => {
  const renderIcon = () => icons[props.icon]?.() ?? null;

  return (
    <div class="empty-state">
      <div class="empty-state-icon">{renderIcon()}</div>
      <div class="empty-state-title">{props.title}</div>
      <div class="empty-state-desc">{props.description}</div>
      <Show when={props.action}>
        <div class="empty-state-action">{props.action}</div>
      </Show>
    </div>
  );
};

export default EmptyState;
