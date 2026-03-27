import { type Component, createMemo } from "solid-js";
import "../styles/context-gauge.css";

interface ContextGaugeProps {
  used: number;
  total: number;
}

const ContextGauge: Component<ContextGaugeProps> = (props) => {
  const pct = createMemo(() => {
    if (!props.total || props.total === 0) return -1;
    return Math.min((props.used / props.total) * 100, 100);
  });

  const color = createMemo(() => {
    const p = pct();
    if (p < 0) return "var(--text-dim)";
    if (p < 60) return "var(--emerge)";
    if (p < 85) return "var(--warm)";
    return "var(--danger)";
  });

  // SVG arc math: radius 24, circumference ~150.8
  const R = 24;
  const C = 2 * Math.PI * R;

  const dashOffset = createMemo(() => {
    const p = pct();
    if (p < 0) return C;
    return C - (C * p) / 100;
  });

  return (
    <div class="context-gauge" title={pct() >= 0 ? `${Math.round(pct())}% context used` : "Context: N/A"}>
      <svg width="60" height="60" viewBox="0 0 60 60">
        <circle cx="30" cy="30" r={R} fill="none" stroke="var(--border)" stroke-width="4" />
        <circle
          class="context-gauge-circle"
          cx="30" cy="30" r={R}
          fill="none"
          stroke={color()}
          stroke-width="4"
          stroke-linecap="round"
          stroke-dasharray={String(C)}
          stroke-dashoffset={dashOffset()}
          transform="rotate(-90 30 30)"
        />
        <text class="context-gauge-text" x="30" y="28" text-anchor="middle" dominant-baseline="middle">
          {pct() >= 0 ? `${Math.round(pct())}%` : "N/A"}
        </text>
        <text class="context-gauge-label" x="30" y="40" text-anchor="middle" dominant-baseline="middle">
          ctx
        </text>
      </svg>
    </div>
  );
};

export default ContextGauge;
