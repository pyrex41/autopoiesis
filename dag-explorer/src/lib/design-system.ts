/**
 * Design system CSS variables for injection into widget sandboxes.
 * Mirrors the :root block from styles/reset.css so widgets can use
 * var(--signal), var(--font-mono), etc. inside their isolated iframes.
 */
export function getDesignSystemCSS(): string {
  return `
:root {
  --void: #04060e;
  --deep: #080c18;
  --mid: #0e1525;
  --surface: #141d30;
  --raised: #1a2640;
  --border: #1e2d4a;
  --border-hi: #2a3f66;
  --text: #d0daf0;
  --text-muted: #7a8ba8;
  --text-dim: #4a5a78;
  --signal: #4fc3f7;
  --signal-dim: #2196f3;
  --signal-glow: #29b6f6;
  --warm: #ffab40;
  --warm-dim: #ff9100;
  --emerge: #69f0ae;
  --danger: #ff5252;
  --purple: #b388ff;
  --magenta: #f06292;
  --ghost: #1a2744;

  --font-mono: 'JetBrains Mono', 'SF Mono', 'Fira Code', Consolas, monospace;
  --font-display: 'Space Grotesk', 'Inter', system-ui, sans-serif;
  --radius: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;
  --transition: 0.18s cubic-bezier(0.4, 0, 0.2, 1);
}

* { margin: 0; padding: 0; box-sizing: border-box; }

body {
  font-family: var(--font-mono);
  font-size: 13px;
  line-height: 1.5;
  color: var(--text);
  background: transparent;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

a { color: var(--signal); }
button { cursor: pointer; font-family: var(--font-mono); }
`;
}

/**
 * Design system documentation for LLM consumption.
 * Agents call read-design-system before generating widgets.
 */
export function getDesignSystemDocs(): string {
  return `# Autopoiesis Widget Design System

## Colors (CSS variables)
Background depth scale (darkest to lightest):
  --void: #04060e, --deep: #080c18, --mid: #0e1525, --surface: #141d30, --raised: #1a2640

Borders:
  --border: #1e2d4a, --border-hi: #2a3f66

Text:
  --text: #d0daf0 (primary), --text-muted: #7a8ba8 (secondary), --text-dim: #4a5a78 (disabled)

Accent colors:
  --signal: #4fc3f7 (cyan, primary accent)
  --signal-dim: #2196f3, --signal-glow: #29b6f6
  --warm: #ffab40 (amber, secondary)
  --warm-dim: #ff9100
  --emerge: #69f0ae (green, success)
  --danger: #ff5252 (red, error)
  --purple: #b388ff
  --magenta: #f06292

## Typography
  --font-mono: 'JetBrains Mono' (all UI text)
  --font-display: 'Space Grotesk' (headings only)

## Spacing & Borders
  --radius: 4px, --radius-md: 6px, --radius-lg: 8px
  --transition: 0.18s cubic-bezier(0.4, 0, 0.2, 1)

## Rules
- Dark mode only — all backgrounds use --void/--deep/--mid/--surface
- Max 2-3 accent colors per widget
- No gradients, box-shadows, or blur (causes flashing during streaming)
- Sentence case exclusively
- Cards: background var(--surface), 1px solid var(--border), border-radius var(--radius-md), padding 12px
- Buttons: background var(--signal-dim), color white, border none, border-radius var(--radius), padding 6px 12px
- Use semantic color: --signal for primary actions, --emerge for success, --danger for errors, --warm for warnings

## Arrow.js Widget Template
\`\`\`javascript
import { reactive, html } from 'https://esm.sh/@arrow-js/core';

const data = reactive({ /* state */ });

html\\\`
  <div style="padding: 12px;">
    <!-- widget content using \\\${() => data.value} for reactive slots -->
  </div>
\\\`(document.getElementById('app'));
\`\`\`

## Available APIs
- \`output(data)\` — send data back to the host application
- \`fetch('/api/...')\` — call any REST endpoint
- All CSS variables above are available via var()
`;
}
