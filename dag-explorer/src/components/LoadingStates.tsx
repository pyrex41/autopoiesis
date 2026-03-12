import { type Component } from "solid-js";
import "../styles/loading.css";

export const RadarLoader: Component<{ label?: string }> = (props) => (
  <div class="loading-container">
    <svg class="radar-loader" width="80" height="80" viewBox="0 0 80 80">
      <circle cx="40" cy="40" r="35" fill="none" stroke="var(--border)" stroke-width="1" />
      <circle cx="40" cy="40" r="24" fill="none" stroke="var(--border)" stroke-width="0.5" />
      <circle cx="40" cy="40" r="13" fill="none" stroke="var(--border)" stroke-width="0.5" />
      <line class="radar-sweep" x1="40" y1="40" x2="40" y2="5" stroke="var(--signal)" stroke-width="1.5" stroke-linecap="round" />
      <circle cx="40" cy="40" r="2" fill="var(--signal)" />
    </svg>
    {props.label && <span class="loading-label">{props.label}</span>}
  </div>
);

export const MeshLoader: Component<{ label?: string }> = (props) => (
  <div class="loading-container">
    <svg class="mesh-loader" width="80" height="80" viewBox="0 0 80 80">
      {/* Wireframe cube */}
      <g fill="none" stroke="var(--purple)" stroke-width="1">
        {/* Front face */}
        <polygon points="25,25 55,25 55,55 25,55" />
        {/* Back face */}
        <polygon points="35,15 65,15 65,45 35,45" opacity="0.4" />
        {/* Connecting edges */}
        <line x1="25" y1="25" x2="35" y2="15" />
        <line x1="55" y1="25" x2="65" y2="15" />
        <line x1="55" y1="55" x2="65" y2="45" />
        <line x1="25" y1="55" x2="35" y2="45" />
      </g>
      {/* Corner dots */}
      <circle cx="25" cy="25" r="1.5" fill="var(--purple)" />
      <circle cx="55" cy="55" r="1.5" fill="var(--purple)" />
    </svg>
    {props.label && <span class="loading-label">{props.label}</span>}
  </div>
);
