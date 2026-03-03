## Summary

- Add a standalone interactive DAG explorer web app (`dag-explorer/`) for visualizing and navigating the autopoiesis snapshot history graph
- Built with SolidJS + TypeScript + Canvas 2D rendering + dagre layout engine — chosen for fine-grained reactivity mapping perfectly to interactive graph state, and dagre's Sugiyama algorithm being the gold standard for hierarchical DAG layout
- Features a "Mission Control Observatory" visual design direction with animated starfield, edge particle flow, radar pulse selection feedback, atmospheric gradients, and JetBrains Mono + Space Grotesk typography

## What changed

### New app: `dag-explorer/`

A complete SolidJS web application for power-user exploration of the snapshot DAG produced by agent activity. The app renders the full snapshot history as an interactive directed acyclic graph with:

**Rendering & Visualization (Canvas 2D)**
- 60fps animated Canvas 2D renderer with pan, zoom, and node selection
- Animated starfield background (120 pre-computed stars with individual twinkle rates)
- Edge particles: 40 luminous dots flowing along active lineage edges
- Radar pulse: concentric rings emanating from selected nodes
- Screen-space vignette and scan-line overlay for atmospheric depth
- Node rendering with rounded rects, left accent strips, glow halos, branch badges
- Color schemes: branch, agent, depth, time, monochrome
- Layout directions: top-to-bottom or left-to-right (dagre Sugiyama algorithm)

**Interaction & Navigation**
- Click to select, Shift+click for secondary selection (diff comparison)
- Double-click to collapse/expand subtrees
- Vim-style keyboard navigation: `h`/`l` parent/child, `j`/`k` sibling, `f` fit-to-view, `i` inspector toggle, `d` diff mode, `/` search, `Space` collapse, `Ctrl+K` command palette, `Escape` clear
- Command palette with fuzzy search across all actions
- Full-text search across snapshot IDs, hashes, and metadata

**Inspector Panel**
- Snapshot details: ID, timestamp, parent, hash, depth, descendant count
- Branch head badges
- Metadata viewer (JSON pretty-print)
- Lineage stats (ancestor/descendant counts)
- Two-node comparison with diff computation
- Agent state viewer

**Data Sources**
- Mock data generator: 30-node trunk with 6+ branches, sub-branches, realistic metadata (agent names, labels, tags, thought counts) — works standalone without the Lisp backend
- Live mode: connects to the autopoiesis REST API (port 8081) with full CRUD endpoints for snapshots, branches, agents, and SSE event streaming
- Automatic fallback from live to mock on connection failure

**Supporting Components**
- Corner minimap with gradient background matching observatory theme
- Branch list overlay with click-to-navigate
- Toolbar: data source toggle, layout direction, color scheme, diff mode, search
- Orchestrated page load with staggered reveal animations

### Files added (22 files, ~5,200 lines)

| File | Purpose |
|------|---------|
| `package.json` | Dependencies: solid-js, dagre, d3-zoom, d3-selection, vite, typescript |
| `index.html` | Entry HTML with font preconnect and void background |
| `vite.config.ts` | Vite + SolidJS plugin, API proxy to localhost:8081 |
| `tsconfig.json` | Strict TypeScript with JSX preserve for SolidJS |
| `src/index.tsx` | App bootstrap |
| `src/App.tsx` | Root component with orchestrated reveal |
| `src/api/types.ts` | TypeScript types: Snapshot, Branch, Agent, Layout*, Selection, etc. |
| `src/api/client.ts` | REST API client (snapshots, branches, agents, diffs, SSE events) |
| `src/api/mock.ts` | Deterministic mock DAG generator |
| `src/graph/layout.ts` | dagre wrapper + graph algorithms (ancestors, descendants, path finding) |
| `src/graph/globals.ts` | Typed window interface for cross-component communication |
| `src/stores/dag.ts` | Central SolidJS reactive store with all signals, memos, and actions |
| `src/components/DAGCanvas.tsx` | Canvas 2D renderer (starfield, particles, nodes, edges, interactions) |
| `src/components/NodeDetail.tsx` | Inspector panel with snapshot details, lineage, diff, agent state |
| `src/components/Toolbar.tsx` | Header toolbar with controls |
| `src/components/CommandPalette.tsx` | Fuzzy command search overlay |
| `src/components/KeyboardHandler.tsx` | Vim-style keyboard shortcut handler |
| `src/components/Minimap.tsx` | Corner minimap canvas |
| `src/components/BranchList.tsx` | Branch list overlay |
| `src/styles/global.css` | Complete design system (~750 lines) |
| `.gitignore` | Node artifacts |

## Design direction

**"Mission Control Observatory"** — the UI evokes a deep-space monitoring station. The aesthetic was developed through three iterations:

1. Functional baseline → 2. Space-age terminal (inspired by pyrex41/hl_project GitHub Dark palette, 100% monospace) → 3. Observatory redesign applying Anthropic frontend-design principles (bold aesthetic direction, distinctive typography, orchestrated motion, atmospheric backgrounds)

**Palette:** Deep navy void (#04060e → #1a2640), vivid cyan-blue signal (#4fc3f7), amber warm accent (#ffab40), emerald branch (#69f0ae), soft purple (#b39ddb)

**Typography:** JetBrains Mono (code/data) + Space Grotesk (headings/UI) via Google Fonts

## How it connects to the platform

The explorer maps directly to the autopoiesis snapshot system:
- `Snapshot` type mirrors `snapshot-to-json-alist` from `platform/src/api/serialization.lisp`
- `Branch` type mirrors `branch-to-json-alist`
- API client hits the REST endpoints defined in `platform/src/api/routes.lisp` (GET `/api/snapshots`, `/api/branches`, `/api/agents`, POST `/api/snapshots/:id/diff`)
- SSE event streaming from `/api/events` for live updates
- DAG traversal algorithms (findAncestors, findDescendants, findPath) mirror the Lisp equivalents in `platform/src/snapshot/time-travel.lisp`

## How to verify

- [ ] `cd dag-explorer && npm install && npm run dev` — app starts on localhost:5173
- [ ] Mock data renders a multi-branch DAG with ~30+ nodes
- [ ] Click nodes to select, Shift+click for comparison, double-click to collapse
- [ ] Keyboard shortcuts work: h/l/j/k navigation, f fit, i inspector, / search
- [ ] Command palette opens with Ctrl+K
- [ ] Minimap and branch list render correctly
- [ ] Layout toggles between TB/LR directions
- [ ] Color scheme switching works (branch/agent/depth/time/mono)
- [ ] Starfield animation, edge particles, and radar pulse render smoothly at 60fps

## Test plan

- [ ] Run `npm run build` to verify TypeScript compilation succeeds
- [ ] Manual verification of all interactive features listed above
- [ ] Visual inspection of observatory design elements (starfield, particles, gradients)

https://claude.ai/code/session_014r7R5nuPKjAti7ZrNdRcU7
