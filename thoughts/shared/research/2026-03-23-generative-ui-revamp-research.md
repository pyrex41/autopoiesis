---
date: 2026-03-23T19:14:48Z
researcher: Claude
git_commit: b6eac4193625e3581c1c73f1d7efb84b3b3933c0
branch: main
repository: autopoiesis
topic: "Generative UI — Revamping the Command Center Web UI"
tags: [research, codebase, frontend, generative-ui, solidjs, command-center, dag-explorer, arrow-js]
status: complete
last_updated: 2026-03-23
last_updated_by: Claude
last_updated_note: "Added Arrow.js analysis as generative UI widget runtime"
---

# Research: Generative UI — Revamping the Command Center Web UI

**Date**: 2026-03-23T19:14:48Z
**Researcher**: Claude
**Git Commit**: b6eac4193625e3581c1c73f1d7efb84b3b3933c0
**Branch**: main
**Repository**: autopoiesis

## Research Question

Investigate how Claude's generative UI approach (as reverse-engineered in the blog post at michaellivs.com) could be applied to revamp the Autopoiesis Command Center web UI, and document the current frontend architecture as context for that revamp.

## Summary

The Autopoiesis Command Center is a 50+ component SolidJS application with 11 hardcoded views, 17 reactive stores, and a bespoke CSS design system. Every view is statically defined at build time. Claude's generative UI takes a fundamentally different approach: the LLM dynamically generates complete HTML/CSS/JS widgets at runtime via a `show_widget` tool, streaming them token-by-token into the DOM using morphdom for incremental patching. The blog post reveals the full architecture — a `read_me` tool for lazy design guidelines, a `show_widget` tool for rendering, CDN-loaded libraries, strict CSP sandboxing, and a comprehensive design system enforced via modular documentation.

The Autopoiesis platform is uniquely positioned for generative UI because: (1) it already has a rich bidirectional WebSocket protocol with 30+ message types, (2) agents already have cognitive loops that could drive widget generation, (3) the backend already serializes complex entity state (departments, budgets, agents, snapshots, evolution data) as structured JSON, and (4) the Jarvis NL-to-tool loop already provides the conversational interface pattern.

## Detailed Findings

### 1. Claude's Generative UI Architecture (from blog post)

#### Tool-Based Widget System

Claude uses two tools to generate UI:

- **`read_me` tool** — A lazy documentation loader. Accepts a `modules` parameter (`diagram`, `mockup`, `interactive`, `chart`, `art`). Returns module-specific design patterns. Forces documentation compliance before widget generation.

- **`show_widget` tool** — Renders visual content with parameters:
  - `i_have_seen_read_me`: Boolean flag ensuring `read_me` was called first
  - `title`: Snake_case identifier for the widget
  - `loading_messages`: 1-4 strings displayed during render ("Spinning up particles...")
  - `widget_code`: Raw HTML fragment (no DOCTYPE/html/head/body tags)

#### Streaming Rendering Pipeline

1. HTML streams token-by-token as JSON string chunks
2. Client performs incremental HTML parsing on partial content
3. DOM nodes insert into the page in real-time using **morphdom** for minimal DOM patches
4. CSS variables resolve immediately (same document context)
5. Scripts execute after streaming completes
6. Code is structured as: `<style>` (short) -> content HTML -> `<script>` (last) to prevent FOUC

#### Security Model

Content Security Policy restricts script sources to whitelisted CDNs:
- `cdnjs.cloudflare.com`
- `cdn.jsdelivr.net`
- `unpkg.com`
- `esm.sh`

Libraries (Chart.js, D3, Three.js) are downloaded live from CDNs, not pre-bundled.

#### Design System Enforcement

The `read_me` tool's guidelines encode strict rules:
- No gradients, shadows, or blur (cause flashing during DOM diffs)
- Two font weights max (400, 500)
- CSS variables for all colors (9 color ramps, 7 stops each)
- Dark mode mandatory
- No HTML comments (waste tokens, break streaming)
- Sentence case exclusively
- Maximum 2-3 color ramps per widget
- SVG viewBox verification, font width calibration tables
- Diagram complexity budgets (5 words/subtitle, 4 boxes/tier)

#### Terminal Integration via Glimpse

For terminal-based agents (like Pi), Claude uses **Glimpse** — a native macOS WKWebView spawned in <50ms:
- Opens native window via Glimpse on first widget detection
- `_setContent()` uses morphdom for DOM diffing
- `_runScripts()` activates scripts after complete HTML arrives
- Bidirectional JSON communication via `window.glimpse.send()`
- Streaming: `toolcall_start` -> `toolcall_delta` (debounced 150ms) -> `toolcall_end`

### 2. Current Command Center Frontend Architecture

#### Tech Stack

- **Framework**: SolidJS 1.9.3 with TypeScript
- **Build**: Vite 6 with `vite-plugin-solid`
- **Graph Layout**: dagre 0.8.5
- **Canvas/SVG**: d3-selection + d3-zoom (DAG pan/zoom)
- **3D**: Three.js 0.183.2 (holodeck)
- **CSS**: Plain CSS files (no Tailwind, no CSS-in-JS, no component library)
- **Location**: `dag-explorer/`

#### Application Structure

```
dag-explorer/
├── src/
│   ├── index.tsx              # Main entry point
│   ├── App.tsx                # Root component
│   ├── api/
│   │   ├── client.ts          # REST API client (fetch-based)
│   │   └── types.ts           # TypeScript type definitions
│   ├── components/            # 50+ SolidJS components
│   │   ├── AppShell.tsx       # Fixed shell layout + view routing
│   │   ├── Dashboard.tsx      # View 1
│   │   ├── DAGView.tsx        # View 2 (lazy)
│   │   ├── TimelineView.tsx   # View 3
│   │   ├── TasksView.tsx      # View 4
│   │   ├── HolodeckView.tsx   # View 5 (lazy, Three.js)
│   │   ├── ConstellationView.tsx  # View 6 (lazy, force sim)
│   │   ├── OrgChart.tsx       # View 7
│   │   ├── BudgetDashboard.tsx    # View 8
│   │   ├── ApprovalsView.tsx  # View 9
│   │   ├── EvolutionLab.tsx   # View 10
│   │   └── AuditLog.tsx       # View 11
│   ├── stores/                # 17 SolidJS signal-based stores
│   ├── graph/                 # Dagre layout computation
│   ├── lib/                   # Utilities (audio, commands, detach, markdown)
│   └── styles/                # 39 plain CSS files
├── vite.config.ts
├── package.json
└── index.html
```

#### Routing — Signal-Based, No URL Router

Active view is a module-level SolidJS signal:
```ts
export const [currentView, setCurrentView] = createSignal<ViewId>("dashboard");
```
`ViewId` is a union of 11 string literals. Navigation is via `navigateTo(view, label, agentId?)` which pushes to a history stack (max 50). `AppShell` renders the active view via `<Dynamic component={viewComponents[currentView()]} />`.

#### Shell Layout

```
┌─────────────────────────────────────────┐
│ StatusBar            (42px)             │
│ ViewSwitcher         (11 tabs, 2 groups)│
│ Breadcrumb           (nav trail)        │
├──────────────┬──────────────┬───────────┤
│ AgentList    │ <Dynamic />  │ AgentDetail│
│ + TeamPanel  │  (active     │ (right    │
│ (left panel) │   view)      │  panel)   │
└──────────────┴──────────────┴───────────┘
│ JarvisBar            (chat/CLI)         │
└─────────────────────────────────────────┘
```

Global overlays: CommandPalette (Cmd+K), CreateAgentDialog, CreateTeamDialog, ThoughtModal, Toast, CrystallizePulse.

#### Backend Communication

**WebSocket** (port 8080): Single persistent connection via `wsStore`. Client sends `{ type: "set_stream_format", format: "json" }` on connect. Supports channel-based subscriptions (`"agents"`, `"events"`, `"snapshots"`, `"agent:<id>"`, `"evolution"`, etc.). Exponential backoff reconnect (2s-30s). Handles 20+ inbound message types.

**REST** (port 8081): Fetch-based client hitting `/api/*` via Vite dev-proxy. 60+ endpoints covering agents, snapshots, branches, events, tasks, departments, goals, budgets, audit, approvals, teams, extensions.

**SSE**: Alternative to WebSocket via `EventSource` at `/api/events`.

#### State Management

17 module-level SolidJS stores, each exporting signals and actions:
`agentStore`, `dagStore`, `wsStore`, `navigationStore`, `constellationStore`, `holodeckStore`, `evolutionStore`, `orgStore`, `budgetStore`, `approvalsStore`, `auditStore`, `activityStore`, `teamStore`, `taskStore`, `toastStore`, `conductorStore`, `timetravelStore`.

Heavy use of `createMemo` for derived data and `batch()` for atomic multi-signal updates.

#### CSS Design System

Defined in `reset.css` via CSS custom properties:
- **Colors**: `--void` (#04060e) to `--raised` (#1a2640) depth scale; `--signal` (cyan), `--warm` (amber), `--emerge` (green), `--danger` (red), `--purple`, `--magenta` accents
- **Typography**: `--font-mono: JetBrains Mono` (dominant), `--font-display: Space Grotesk` (headings)
- **Spacing**: `--radius: 4px`, `--transition: 0.18s cubic-bezier(0.4, 0, 0.2, 1)`
- Canvas components (`DAGCanvas`, `ConstellationView`) duplicate color constants as TS string literals

### 3. Natural Integration Points for Generative UI

#### JarvisBar — Already a Conversational Interface

`JarvisBar.tsx` provides a bottom chat/CLI bar with dual modes:
- **Chat mode**: sends `chat_prompt` via WebSocket, receives streamed responses via `chat_stream_start/delta/end`
- **CLI mode**: `/` prefix triggers command palette matching

This is the natural anchor for a `show_widget`-style tool — agent responses that currently arrive as streaming text could include widget tool calls that render inline.

#### Agent Cognitive Loop — Tool-Based Architecture

The agent system already uses a tool-based architecture. The `invoke-tool` capability dispatches to registered tools. Adding a `show-widget` tool to the agent's capability set would follow existing patterns.

#### WebSocket Streaming Protocol — Already Supports Deltas

The WS protocol already handles streaming chat:
- `chat_stream_start` — initializes placeholder
- `chat_stream_delta` — appends content incrementally
- `chat_stream_end` — finalizes message

This maps directly to Claude's `toolcall_start/delta/end` pattern.

#### Backend Data — Rich Structured JSON

All Command Center entity types are already serialized to JSON with full schemas:
- Agents (state, capabilities, thought count, lineage)
- Departments (hierarchy, budget limits)
- Goals (status, ownership, parent chains)
- Budgets (entity allocation, spend tracking)
- Audit entries
- Approval workflows
- Evolution runs (fitness history, genome data)
- Holodeck frames (3D entity state)
- Activity tracking (cost, tokens, tool usage)

This structured data is available for widget generation without additional backend work.

#### ThoughtModal — Already Does Dynamic Content Rendering

`ThoughtModal.tsx` already handles dynamic content formatting: detecting JSON vs S-expressions vs tool invocations, pretty-printing each format differently. This is a primitive form of content-aware rendering.

#### Markdown Rendering — Inline HTML Generation

`lib/markdown.ts` implements dependency-free markdown-to-HTML rendering inserted via `innerHTML`. This is the same injection pattern generative UI widgets would use, at a smaller scale.

### 4. Key Differences Between Current Architecture and Generative UI

| Aspect | Current Command Center | Generative UI Approach |
|--------|----------------------|----------------------|
| View definition | 11 static SolidJS components, build-time | Dynamic HTML generated per-request, runtime |
| Component count | 50+ hand-written components | On-demand, context-specific widgets |
| Styling | 39 CSS files, bespoke design system | CSS variables + inline styles, enforced by LLM guidelines |
| Data binding | SolidJS reactive stores, WebSocket subscriptions | Widget code fetches/receives data directly |
| Libraries | Bundled (dagre, d3, Three.js) | CDN-loaded per widget (Chart.js, D3, etc.) |
| Layout | Fixed shell with panel regions | Inline in conversation flow |
| Interactivity | Full SPA with keyboard shortcuts, canvas rendering | Self-contained widget JS |
| Updates | Reactive signal propagation | Re-render widget or morphdom patch |

### 5. Backend API Surface Available for Widgets

A generative UI widget could call any of the 60+ REST endpoints. Key data sources:

| Endpoint | Returns | Widget Potential |
|----------|---------|-----------------|
| `GET /api/agents` | Agent list with states | Agent status dashboard, health grid |
| `GET /api/agents/:id/thoughts` | Thought stream | Thought timeline, cognitive analysis |
| `GET /api/agents/:id/capabilities` | Capability list | Capability map, comparison matrix |
| `GET /api/snapshots` | Snapshot DAG | Interactive DAG viewer, diff explorer |
| `GET /api/departments` | Org hierarchy | Dynamic org chart |
| `GET /api/goals` | Goal tree | Progress tracker, Gantt-style view |
| `GET /api/budgets` | Budget allocations | Spend visualization, burn-down |
| `GET /api/audit` | Audit trail | Filterable audit explorer |
| `GET /api/approvals` | Pending approvals | Approval workflow UI |
| `GET /api/events` | Integration events | Event timeline, activity heatmap |

### 6. Potential Architectural Approaches

#### Approach A: Hybrid — Keep Shell, Add Widget Zone

Keep the AppShell, ViewSwitcher, and side panels. Add a widget rendering zone (similar to JarvisBar's chat area) where agents can inject generative widgets. Static views remain for power users; generative widgets provide contextual, on-demand visualizations.

- **Pros**: Incremental migration, preserves existing functionality, low risk
- **Cons**: Two rendering paradigms to maintain

#### Approach B: Conversation-First — Replace Views with Agent Dialog

Replace the 11-view tab bar with a single conversational interface (JarvisBar expanded to full screen). All data visualization happens via generative widgets inline in the conversation. The agent decides what to show based on context.

- **Pros**: Matches Claude's native UX, maximally flexible, reduces frontend code
- **Cons**: Loses the structured dashboard experience, harder to monitor at a glance

#### Approach C: Widget Grid — Agent-Generated Dashboard

Replace static views with a configurable grid of widget slots. Agents generate and update widgets that persist in grid positions. Users can request new widgets conversationally via Jarvis. Widgets self-update via WebSocket subscriptions.

- **Pros**: Best of both worlds — structured layout with dynamic content
- **Cons**: Most complex to implement, needs widget lifecycle management

#### Approach D: Claude Tool Integration — Use Agents as Widget Generators

Register a `show-widget` tool in the agent capability system. When agents observe interesting state changes or receive user queries, they generate HTML widgets using the design system guidelines (loaded via a `read-me` equivalent). Widgets stream into the UI via the existing `chat_stream_delta` protocol.

- **Pros**: Leverages existing agent architecture, agents become UI authors
- **Cons**: Depends on agent quality, may be slow for interactive use

### 7. Technical Requirements for Implementation

Regardless of approach, these components would be needed:

1. **Widget Renderer** — SolidJS component that accepts raw HTML, injects it safely (CSP + sanitization), uses morphdom for streaming updates
2. **Design System Guidelines Document** — Machine-readable design rules (CSS variables, color ramps, typography, layout constraints) that agents/LLMs can read before generating widgets
3. **Widget Streaming Protocol** — Extension to existing WS message types: `widget_start`, `widget_delta`, `widget_end` with `widget_id`, `title`, `loading_messages`, `html_chunk`
4. **CDN Allowlist** — CSP configuration for approved CDNs (same as Claude's: cdnjs, jsdelivr, unpkg, esm.sh)
5. **Widget Sandbox** — iframe or Shadow DOM isolation to prevent widget code from breaking the host app
6. **Widget Registry** — Storage and retrieval of generated widgets for persistence across sessions

## Follow-up Research: Arrow.js as Widget Runtime

### Arrow.js Overview

[Arrow.js](https://arrow-js.com) is a sub-5kb reactive UI framework built on JavaScript primitives (tagged template literals, ES modules, plain functions). It was explicitly designed for the "agentic era" — AI-generated code that runs without a build step.

### Why Arrow.js Is a Strong Fit for Generative UI Widgets

Arrow.js solves several of the open questions from the initial research:

| Problem | Arrow.js Solution |
|---------|------------------|
| Build step requirement | None — works from CDN import |
| Widget isolation | Built-in WASM sandbox via `sandbox()` |
| Reactivity in generated widgets | Fine-grained reactive primitives (`reactive()`, `watch()`) |
| DOM update strategy | Surgical updates (only changed expression slots re-evaluate) |
| LLM code generation quality | API fits in <5% of 200k context window — LLMs can learn the full API |
| Bundle overhead per widget | <5kb total framework size |

### Core API (Complete)

```javascript
// CDN import — no build step
import { reactive, html, watch, component, sandbox } from 'https://esm.sh/@arrow-js/core'

// 1. Reactive state
const data = reactive({ count: 0, label: "clicks" })

// 2. Computed values
const derived = reactive({ doubled: reactive(() => data.count * 2) })

// 3. Templates with reactive slots (functions = reactive, bare values = static)
const view = html`
  <div>
    <span>${() => data.count} ${() => data.label}</span>
    <button @click="${() => data.count++}">+</button>
  </div>
`

// 4. Mount to DOM
view(document.getElementById('root'))

// 5. Components with lifecycle
const Widget = component((props) => {
  const local = reactive({ expanded: false })
  onCleanup(() => { /* teardown */ })
  return html`<div>${() => local.expanded ? 'open' : 'closed'}</div>`
})

// 6. Watchers for side effects
watch(() => {
  console.log(`Count changed to: ${data.count}`)
})

// 7. WASM sandbox for untrusted code
sandbox({
  source: { 'main.ts': widgetCode, 'main.css': widgetCSS },
  shadowDOM: true,
  debug: false
}, {
  output: (payload) => handleWidgetOutput(payload)
})
```

### How This Changes the Architecture

Arrow.js eliminates the tension between "pure HTML widgets" (Claude's approach) and "reactive components" (SolidJS approach). Widgets generated by agents can be **reactive Arrow.js code** that:

1. Loads from CDN with zero build step
2. Creates its own reactive state from backend data
3. Performs surgical DOM updates without morphdom
4. Runs in a WASM sandbox for security isolation
5. Communicates back to the host via `output()` callbacks

### Revised Approach: Arrow.js Widget Runtime

Instead of the four approaches outlined above, Arrow.js enables a cleaner architecture:

```
┌─────────────────────────────────────────────────┐
│ SolidJS Host App (AppShell, ViewSwitcher, etc.) │
│                                                 │
│  ┌─────────────────────────────────────────┐    │
│  │ WidgetContainer (SolidJS component)     │    │
│  │                                         │    │
│  │  ┌─────────────────────────────────┐    │    │
│  │  │ Arrow.js Widget (WASM sandbox)  │    │    │
│  │  │ - reactive() for local state    │    │    │
│  │  │ - html`` for templating         │    │    │
│  │  │ - fetch() to REST API           │    │    │
│  │  │ - output() to host app          │    │    │
│  │  └─────────────────────────────────┘    │    │
│  │                                         │    │
│  │  ┌─────────────────────────────────┐    │    │
│  │  │ Arrow.js Widget (WASM sandbox)  │    │    │
│  │  │ ...                             │    │    │
│  │  └─────────────────────────────────┘    │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  JarvisBar (chat input → triggers widget gen)   │
└─────────────────────────────────────────────────┘
```

**Flow:**
1. User asks Jarvis a question or requests a visualization
2. Agent generates Arrow.js code (reactive, templated, <5kb API to learn)
3. Code streams via `widget_delta` WS messages
4. Host app wraps code in `sandbox()` call with Shadow DOM isolation
5. Widget loads Arrow.js from CDN, creates reactive state, fetches data from `/api/*`
6. Widget communicates back via `output()` for cross-widget coordination
7. Host app can persist widget definitions as substrate datoms

### Key Advantages Over Raw HTML Approach

1. **Reactivity without morphdom** — Arrow's dependency tracking means widgets self-update surgically when data changes, no need for external DOM diffing
2. **WASM sandboxing built-in** — no need to design custom CSP or iframe isolation; Arrow's `sandbox()` handles it
3. **Tiny API surface for LLMs** — the entire Arrow.js API fits in a small prompt; agents can generate correct code reliably
4. **Component model** — widgets can have internal state, lifecycle hooks, and cleanup; they're not just static HTML
5. **CDN-native** — `import from 'https://esm.sh/@arrow-js/core'` works in any context, matches Claude's CDN allowlist pattern

### Integration with Existing WebSocket Protocol

The existing chat streaming protocol maps cleanly:

| Current Protocol | Widget Extension |
|-----------------|-----------------|
| `chat_stream_start` | `widget_stream_start` — includes `widget_id`, `title`, `loading_messages[]` |
| `chat_stream_delta` | `widget_stream_delta` — Arrow.js code chunks |
| `chat_stream_end` | `widget_stream_end` — trigger `sandbox()` execution |
| `chat_response` | `widget_complete` — final widget metadata for persistence |

### Design System as Agent Prompt

The existing CSS variables in `reset.css` can be formatted as an agent-readable design guide:

```javascript
// Design system excerpt that agents receive before generating widgets
const DESIGN_SYSTEM = `
Colors (CSS variables available in widget scope):
  --void: #04060e      (deepest background)
  --abyss: #0a0f1a     (panel background)
  --deep: #0f1628      (card background)
  --signal: #4fc3f7    (primary accent, cyan)
  --warm: #ffab40      (secondary accent, amber)
  --emerge: #69f0ae    (success, green)
  --danger: #ff5252    (error, red)

Typography:
  --font-mono: 'JetBrains Mono'  (all UI text)
  --font-display: 'Space Grotesk' (headings only)

Rules:
  - No gradients, shadows, or blur
  - Max 2 accent colors per widget
  - Dark mode only (all backgrounds use --void/--abyss/--deep)
  - Sentence case exclusively
  - Border radius: 4px (--radius), 6px (--radius-md), 8px (--radius-lg)
`
```

## Code References

- `dag-explorer/src/components/AppShell.tsx` — Shell layout and view routing via `<Dynamic>`
- `dag-explorer/src/components/JarvisBar.tsx` — Chat/CLI interface, natural anchor for generative widgets
- `dag-explorer/src/components/ThoughtModal.tsx` — Dynamic content rendering (JSON/S-expr detection)
- `dag-explorer/src/stores/ws.ts` — WebSocket connection, subscription model, reconnect logic
- `dag-explorer/src/stores/agents.ts:365-518` — Chat streaming protocol (`chat_stream_start/delta/end`)
- `dag-explorer/src/lib/markdown.ts` — innerHTML-based markdown rendering
- `dag-explorer/src/lib/commands.ts:18-29` — ViewId type and navigation signal
- `dag-explorer/src/styles/reset.css` — CSS design system custom properties
- `dag-explorer/src/api/client.ts` — REST API client (60+ endpoints)
- `dag-explorer/src/api/types.ts` — TypeScript type definitions
- `platform/src/api/handlers.lisp:30-60` — WebSocket message handler dispatch
- `platform/src/api/routes.lisp:1397-1478` — REST route table
- `platform/src/api/wire-format.lisp:37-40` — Stream message type classification
- `platform/src/api/serialization.lisp` — REST JSON serializers
- `platform/src/api/serializers.lisp` — WebSocket JSON serializers
- `platform/src/api/activity-tracker.lisp` — Agent activity/cost push broadcasts

## Architecture Documentation

### Current Data Flow

```
Agent Cognitive Loop
    → transact! datoms to substrate
    → event-bridge picks up events
    → broadcast-stream-data to WS subscribers
    → wsStore.onMessage in frontend
    → SolidJS signals update
    → Components re-render
```

### Proposed Generative UI Data Flow

```
User query via JarvisBar
    → chat_prompt WS message to backend
    → Agent cognitive loop processes query
    → Agent calls show-widget tool
    → Widget HTML streams via widget_delta WS messages
    → Frontend WidgetRenderer component:
        1. Shows loading_messages
        2. Incrementally parses HTML via morphdom
        3. Resolves CSS variables from design system
        4. Executes <script> tags after stream completes
    → Widget fetches additional data via REST API
    → Widget subscribes to WS channels for live updates
```

## Historical Context (from thoughts/)

- `thoughts/shared/prs/9_description.md` — Original dag-explorer PR, establishing the "Observatory" aesthetic and SolidJS + Canvas2D + dagre tech stack
- `thoughts/shared/research/2026-02-17-interaction-surfaces-rho-holodeck-opencode.md` — Foundational UI/UX vision document comparing TUI, 3D, and web interaction surfaces; defines what "feels different" for the sci-fi aesthetic
- `thoughts/shared/plans/2026-02-17-holodeck-v2-game-quality.md` — Most detailed design system spec ("Holographic Operations Center") with color palettes, typography, and visual quality standards
- `thoughts/shared/plans/2026-02-17-nexus-option-d-jarvis-cockpit.md` — "Nexus: The Autopoiesis Cockpit" plan for unified Jarvis interface
- `thoughts/shared/research/2026-03-02-platform-architecture-deep-dive.md` — Complete documentation of dag-explorer features, API connections, and ECS binding model
- `thoughts/shared/plans/2026-02-14-jarvis-implementation-plan.md` — Jarvis NL-to-tool loop plan, directly relevant to how agents could invoke a `show-widget` tool
- `thoughts/shared/research/2026-03-23-agent-eval-platform-feasibility.md` — Research on eval trajectory visualization through the Command Center

## Related Research

- `thoughts/shared/research/2026-02-17-interaction-surfaces-rho-holodeck-opencode.md`
- `thoughts/shared/research/2026-03-02-platform-architecture-deep-dive.md`

## Open Questions

1. **SolidJS or framework-agnostic?** — Should widgets be pure HTML/CSS/JS (like Claude's approach), or should they be SolidJS components generated at runtime? Pure HTML is simpler and matches the blog post's architecture, but loses SolidJS reactivity.

2. **Widget isolation** — Should widgets run in iframes (full isolation, like artifacts) or in the same DOM with CSP (like Claude's visualizer)? Iframes are safer but limit communication; same-DOM allows reactive data binding.

3. **Who generates widgets?** — Should the Autopoiesis agents themselves generate widgets (using their cognitive loops), or should a separate LLM service handle widget generation? Autopoiesis agents have domain knowledge but may not have the HTML/CSS generation capability.

4. **Widget persistence** — Should generated widgets be ephemeral (conversation-scoped) or persistable (saved as dashboard configurations)? The substrate could store widget definitions as datoms.

5. **Coexistence strategy** — How long do static views and generative widgets coexist? Is the goal to eventually replace all 11 views, or to supplement them?

6. **Streaming transport** — The existing chat streaming protocol (`chat_stream_delta`) sends text. Widget streaming needs structured metadata (widget_id, title, loading state) alongside HTML chunks. Should this be a new message type or an extension of the existing chat protocol?

7. **Design system synchronization** — The current CSS design system is in `reset.css` as CSS variables. How should these be exposed to the LLM for widget generation? A `read_me`-style tool that returns the variable definitions?
