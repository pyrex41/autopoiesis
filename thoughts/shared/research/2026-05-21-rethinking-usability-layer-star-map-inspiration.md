---
date: 2026-05-21T17:39:52-05:00
researcher: Grok 4.3 (xAI)
git_commit: bb99c19
branch: main
repository: autopoiesis
topic: "Rethinking Direction and Usability Layer: Content-Addressable State, Forking, and Immersive Spatial Interface (Star Map Inspiration)"
tags: [research, codebase, usability, interface, visualization, snapshot, persistent-agents, constellation, holodeck, rethinking, direction]
status: complete
last_updated: 2026-05-21
last_updated_by: Grok 4.3
---

# Research: Rethinking Direction and Usability Layer — Content-Addressable State + Forking + Star Map Interface Inspiration

**Date**: 2026-05-21T17:39:52-05:00
**Researcher**: Grok 4.3 (xAI)
**Git Commit**: bb99c19
**Branch**: main
**Repository**: autopoiesis

## Research Question

[User-provided context with image] This project has been dead for a little while and it's really jumped around quite a bit and got kind of bloated. I love the underlying idea of using the content addressable framework to state and forking and all of that. I love the idea of having an interface to run agents, but I want to rethink it. This app right here, it's not about agents, it's just a star map. But it has a great example of something like the interface that I actually want for this. Can you help me? /cl:research_codebase -- i want to rethink the direction / usability layer and shift gears to make this useful. Also, a lot of work has been done on agents since I built this, and I want to maybe move to the state of the art. Hermes came out etc.

The provided image is a screenshot of the "Hail Mary - Star Map" (valhovey.github.io/gaia-mary/), a clean, immersive 3D stellar navigation chart using real Gaia DR3 astronomical data. It features a full-screen starfield with subtle grid plane, elegant labeled stars (Arcturus, Vega, Sirius, Tau Ceti, etc.), red trajectory lines, minimal pill-shaped mode controls at bottom (SOL SYSTEM / TRAJECTORY / TAU CETI / GALACTIC), right-side info panel with range/near-field/backdrop/dest data, and a very high-quality, focused, data-rich but chrome-minimal aesthetic.

## Summary

Autopoiesis is a large, multi-phase Common Lisp platform (core ~25k LOC Lisp + multiple frontends and supporting Rust/Go components) centered on homoiconic agent cognition where all thoughts, state, configuration, and code are S-expressions. The unique technical foundation that the user explicitly loves is the **content-addressable snapshot DAG** (structural SHA-256 hashing of S-expressions, branch pointers, diff/patch, time-travel) combined with **persistent agents** built on fset structural sharing for O(1) forking of immutable cognition state.

The project has accumulated substantial scope across 12+ phases: substrate datom store (Datomic-inspired EAV + Linda `take!`), conductor orchestration, multi-provider integration, self-extension compiler, swarm evolution, team coordination strategies, Jarvis NL loop, crystallize-to-source, supervisor, sandbox, eval platform, and at least three distinct visualization/interaction efforts (SolidJS Command Center with 15 views, Rust/Bevy Holodeck, Go TUI, plus earlier dag-explorer and ANSI timeline).

Multiple UI experiments have explored "spatial" or "constellation" metaphors for agents, snapshots, and relationships. The existing `ConstellationView` already uses a twinkling starfield + force-directed agent nodes. The Holodeck uses 3D ECS (icospheres for agents, particle bursts for thoughts, 3D DAG). However, the overall experience remains a multi-view dashboard (AppShell + ViewSwitcher with tabs for Dashboard, DAG, Timeline, Tasks, Constellation, Holodeck, Org Chart, Budget, Approvals, Evolution Lab, Audit, etc.).

The user's provided image represents the aspirational quality and interaction model for the usability layer: a single, beautiful, immersive, direct-manipulation spatial "map" (not a dashboard of views) where the data domain (in this case, stellar positions + trajectories) is the entire experience. Applied here, the "stars" and "constellations" would be the content-addressable snapshots, agent lineages, thought streams, forks, and decision branches — with elegant labels, trajectories as timelines or explorations, modes for different scales (local agent cognition, team, global possibility space), and minimal UI.

The agent runtime itself is a custom 5-phase cognitive cycle (perceive → reason → decide → act → reflect) with capabilities, learning (heuristics from experience), and dual mutable/persistent facade. Since initial development, the broader agent ecosystem has advanced significantly (graph-based state machines like LangGraph, multi-agent handoff protocols such as OpenAI Swarm, structured tool use + computer-use APIs, durable execution, observability platforms, and various "Hermes" function-calling or agent frameworks). The user wants to consider aligning the execution model with current SOTA.

This document neutrally maps what currently exists to support the rethink.

## Detailed Findings

### 1. Core Value to Preserve: Content-Addressable Snapshot DAG + Persistent Forking

The snapshot layer provides content-addressed, immutable history with cheap branching.

**Key files:**

- `packages/core/src/snapshot/snapshot.lisp:11-44` — `snapshot` CLOS class with `id`, `timestamp`, `parent`, `agent-state` (serialized S-expr), `tree-root` (Merkle for filesystem), `tree-entries`, `hash` (content hash via `sexpr-hash`).
- `packages/core/src/snapshot/content-store.lisp` — Dual hash tables (`data` for S-exprs keyed by structural hash, `blobs` for bytes). Reference-counted GC. `store-put` only writes on miss.
- `packages/core/src/core/sexpr.lisp` (and utilities) — `sexpr-hash` (type-tagged SHA-256: "S" for symbols, "I" for ints, "(" for cons), `sexpr-diff` / `sexpr-patch` (path-based cons-tree edits), `sexpr-equal`.
- `packages/core/src/snapshot/branch.lisp` — Named mutable pointers into the immutable DAG. `(setf (branch-head b) snap-id)` creates lightweight branches. Forking is O(1) because the DAG nodes are shared until divergence.
- `packages/core/src/snapshot/diff-engine.lisp`, `time-travel.lisp`, `consistency.lisp` — Traversal, common-ancestor, compaction, six-check verification + repair.
- `packages/core/src/snapshot/filesystem-tree.lisp` — `tree-hash` (Merkle), `scan-directory-flat`, `materialize-tree`.

**Persistent Agents (the runtime objects that get snapshotted and forked):**

- `packages/core/src/agent/persistent-agent.lisp:13-28` — `persistent-agent` defstruct using only persistent collections:
  - `thoughts` (pvec)
  - `capabilities` (pset)
  - `membrane` / `metadata` (pmap)
  - `genome`, `heuristics`, `children`, `parent-root`
- `make-persistent-agent` + `copy-persistent-agent` (all updates return new root; old is unchanged).
- `persistent-fork` (mentioned in CLAUDE.md key signatures) — O(1) via structural sharing.
- Dual-agent bridge (`dual-agent.lisp`): Mutable CLOS facade over a persistent root with recursive lock; setters trigger sync back to persistent root. Used for ergonomic REPL/loop integration while preserving immutability for snapshots/forks.
- `persistent-cognition.lisp`, `persistent-lineage.lisp`, `persistent-membrane.lisp`, `persistent-substrate.lisp` — Supporting pieces.

These two systems together enable "fork reality, explore a branch, diff the cognition trees, merge or discard" with full history and no mutation hazards — the exact property the user loves.

### 2. Current Agent Runtime (What Would Need Alignment with SOTA)

- `packages/core/src/agent/agent.lisp` and `cognitive-cycle` — 5-phase generic function loop: `perceive`, `reason`, `decide`, `act`, `reflect`.
- `capability` + `defcapability` macro — Registered in `*capability-registry*`, with parameter specs and permissions.
- Learning: `experience` records → n-gram / heuristic extraction with confidence decay (`learning.lisp`).
- Conversation layer (`packages/core/src/conversation/`) — Turn-based with its own forking.
- Integration: `provider-*.lisp`, Claude CLI worker, direct Anthropic/OpenAI, MCP client.
- Extensions: `swarm/` (genome evolution, crossover, lparallel fitness), `team/` (5 strategies: leader-worker, parallel, pipeline, debate, consensus + workspace + CV await), `supervisor/` (checkpoint/revert), `jarvis/` (NL→tool loop with human-in-loop blocking requests).

Modern SOTA references the user wants considered (noted here without recommendation):
- Graph-based agent state (LangGraph-style nodes/edges with checkpointing).
- Simple but effective multi-agent handoff (OpenAI Swarm).
- Structured tool calling + "computer use" style high-level actions.
- Durable, observable, replayable executions.
- "Hermes" (Nous Research Hermes models specialized for function calling / agentic use; or other 2025-era agent runtimes) — better prompt adherence, tool use, and efficiency than generic loops.

### 3. Usability / Visualization Layers (The Accumulated Interface Surface)

The project has **multiple parallel interface efforts**, none of which is currently "the one".

**A. SolidJS Command Center (primary web UI)**
- `frontends/command-center/src/` (~140+ TSX/TS files)
- `AppShell.tsx` + `ViewSwitcher.tsx` + routing store — 15+ views:
  - `Dashboard.tsx`, `DAGView.tsx` + `DAGCanvas.tsx` (dagre + canvas pan/zoom, minimap)
  - `TimelineView.tsx`, `SnapshotTimeline.tsx`
  - `ConstellationView.tsx` (see below)
  - `HolodeckView.tsx` + `HolodeckEmbed.tsx` + `ThreeScene.tsx` (Three.js)
  - `TasksView.tsx`, `TaskBoard.tsx`, `TaskScheduler.tsx`
  - `OrgChart.tsx`, `BudgetDashboard.tsx`, `ApprovalsView.tsx`, `AuditLog.tsx`
  - `EvolutionLab.tsx`, `EvalLab.tsx`, `CommandView.tsx`, `WidgetsView.tsx`
  - `JarvisBar.tsx` (NL input floating/docked)
- Stores: 14+ Zustand-like signals (agents, constellation, holodeck, timetravel, etc.)
- `CommandPalette.tsx` (h/j/k/l keyboard nav, global search)
- WebSocket + REST client to backend.

**B. ConstellationView (the closest existing "star map" attempt)**
- `frontends/command-center/src/components/ConstellationView.tsx:39-...`
- Canvas 2D: radial gradient void background, 200 procedural twinkling stars (`generateStars`), agent/team nodes placed in circle or force layout, parent/leader edges.
- Pan/zoom/drag with viewX/Y/Scale signals.
- `constellationStore` (nodes with x/y/radius/color/state/capCount, edges).
- CSS: `.constellation-view { background: var(--void) }`
- Currently one of many views, not the root experience.
- Blog screenshots (blog/images/constellation-view.png) show the force-directed agent graph.

**C. Holodeck (3D spatial embodiment)**
- Two implementations:
  1. Rust/Bevy: `holodeck/` (Cargo, ~50 Rust files) — ECS, WGSL shaders, icospheres for agents (state-colored emissive), particle bursts per thought type (6 colors for observe/reason/decide/act/reflect), 3D DAG tree, spinning cubes for blocking requests, egui HUD/panels, WS sync, camera controls. See `holodeck/src/` and `packages/holodeck/`.
  2. Three.js web embed: `HolodeckView.tsx`, `ThreeScene.tsx`, `holodeck-standalone.tsx`, `frontends/command-center/holodeck.html`.
- Historical plans: `thoughts/shared/plans/2026-02-17-holodeck-v2-game-quality.md` ("Holographic Operations Center" design system spec with palettes, typography, quality bars).
- Research: `2026-02-17-interaction-surfaces-rho-holodeck-opencode.md` — compares Holodeck to rho-gui and OpenCode TUI as pieces of a "Jarvis cockpit".

**D. Other interfaces**
- `packages/core/src/interface/` — CLI session with blocking `request-human-input` via condition variables, `navigator`, ANSI 2D timeline viewport (hjkl navigation).
- `tui/` — Go TUI (cmd + internal/).
- `dag-explorer/` — Earlier Three.js + SolidJS DAG explorer (now largely superseded by command-center).
- Blog/ has 15+ screenshots of the current multi-view dashboard.

**E. Design system attempts**
- `frontends/command-center/src/lib/design-system.ts`
- Various CSS files with --void, sci-fi scanlines, glows, particles.
- `thoughts/shared/research/2026-03-23-generative-ui-revamp-research.md` and `2026-02-17-holodeck-v2-game-quality.md` record ongoing dissatisfaction with visual quality and desire for a more cohesive "game-like" or "holographic" aesthetic.

### 4. Historical Context & Accumulated Scope (Why It Feels Bloated)

The `thoughts/shared/` directory (73+ files) + `ralph/IMPLEMENTATION_PLAN.md` record many pivots:
- Early LFE (Lisp Flavored Erlang) layer was removed (handoff 2026-02-16).
- Multiple "unified platform" plans, "super agent", "Jarvis phase", "provider generalization", "holodeck v2", "nexus option", "squashd sandbox", "team of agents", "three-layer autopoietic agents".
- Research docs: "what-is-autopoiesis-how-to-use-it.md", "platform-architecture-deep-dive.md", "generative-ui-revamp-research.md", "interaction-surfaces...", "full-codebase-architecture.md" (2026-03-26).
- Many extension packages were added as "optional" but the mental model and onboarding surface grew: swarm, supervisor, crystallize, team/workspace, jarvis, paperclip, eval, sandbox, shen, research, nexus (Rust), etc.
- CLAUDE.md explicitly notes "The LFE layer has been removed. ... Command Center frontend is a SolidJS dashboard with 15 views."

The substrate + snapshot + persistent agents remained the stable technical core while the "product" surface (orchestration, teams, budgets/approvals/org, evolution lab, self-crystallization, multiple viz stacks) expanded.

### 5. Package / System Map (High-Level)

- **Core systems** (ASDF): `autopoiesis.asd`, `substrate.asd`, `holodeck.asd`, etc.
- `packages/substrate/` — datoms, LMDB, `transact!`, `take!`, `defsystem` reactive, interning.
- `packages/core/src/{core,agent,snapshot,conversation,orchestration,integration,interface,viz,security,monitoring}`
- Extensions under `packages/`: swarm, supervisor, crystallize, team, jarvis, paperclip, sandbox, eval, shen, research, holodeck (Lisp glue).
- `frontends/command-center/` (Solid + Vite + Three + d3/dagre)
- `holodeck/` (Rust/Bevy)
- `tui/`, `nexus/` (Rust), `dag-explorer/`
- `blog/` with demo scripts and screenshots of the current UI.

## Code References (Selected Anchors)

- Snapshot CAS: `packages/core/src/snapshot/snapshot.lisp:46` (make-snapshot + sexpr-hash), `content-store.lisp`
- Persistent forking: `packages/core/src/agent/persistent-agent.lisp:13` (defstruct), `34` (make-), dual-agent bridge in `dual-agent.lisp`
- Constellation (current starfield attempt): `frontends/command-center/src/components/ConstellationView.tsx:17` (Star interface), `43` (200 stars), `80-95` (background + starfield draw), `98+` (graph layer + pan/zoom)
- Command Center views: `frontends/command-center/src/components/ViewSwitcher.tsx`, `AppShell.tsx`
- Holodeck Rust entry: `holodeck/src/main.rs` and ECS systems
- Cognitive loop: `packages/core/src/agent/agent.lisp` (cognitive-cycle methods)
- Layers overview: `packages/core/docs/layers.md:11-29` (Mermaid of 7 core layers + optional extensions)
- Recent full architecture: `thoughts/shared/research/2026-03-26-full-codebase-architecture.md`

## Architecture Documentation (Current Patterns, as Found)

- Homoiconicity everywhere possible: thoughts, capabilities, prompts, even some configuration as S-exprs.
- Substrate as single source of truth for mutable coordination state; snapshots as immutable history.
- Persistent data structures (fset) for agent cognition to enable safe forking + diffing.
- Multiple "ports" for the same concepts (web constellation vs 3D holodeck vs TUI timeline).
- "Optional" extensions that are actually deeply wired (e.g. swarm fitness using persistent agents).
- Conductor + `take!` for lock-free-ish worker claiming and timed actions.
- Dual mutable/persistent facade pattern to reconcile REPL ergonomics with immutability.

## Historical Context from thoughts/

- `thoughts/shared/research/2026-02-17-interaction-surfaces-rho-holodeck-opencode.md` — Foundational comparison of interaction surfaces and the search for a "purpose-built sci-fi TUI" or "Jarvis cockpit".
- `thoughts/shared/plans/2026-02-17-holodeck-v2-game-quality.md` — Detailed "Holographic Operations Center" visual spec.
- `thoughts/shared/research/2026-03-23-generative-ui-revamp-research.md` — Generative UI dissatisfaction and duplication across canvases.
- `thoughts/shared/research/2026-03-26-full-codebase-architecture.md` — Comprehensive snapshot of the bloated state just before this rethink request.
- Multiple handoffs and plans in `thoughts/shared/handoffs/` and `plans/` recording direction changes (removal of LFE, consolidation to pure CL, addition of sandbox/eval, etc.).
- Blog/ part-*.md series documenting the evolution of the Command Center dashboard.

## Open Questions (Areas for Further User-Driven Investigation)

- Exact semantics of "the map": are stars = snapshots? agent instances? decision branches? goals? thoughts? Or a higher-level "constellation of possible realities"?
- How should the content-addressable DAG be projected into 3D spatial coordinates (force-directed? embedding of cognition vectors? explicit trajectory metadata? astronomical analogy with "proper motion" for forks)?
- What is the minimal viable "agent" primitive if moving toward SOTA (graph node? durable step function? handoff participant?)?
- Scope boundaries: which of the 13+ extension packages survive the cut when the interface becomes the star map?
- Input model for the new interface: pure direct manipulation (drag to fork, click to inspect/expand, scrub trajectory), or hybrid with NL (Jarvis as "voice in the cockpit")?
- Relationship to existing Holodeck Bevy work and Three.js work — evolve one, or start fresh with the Hail Mary aesthetic as the north star?

---

**End of research document.** This is a neutral map of the current system as of commit bb99c19 on main. All descriptions are "what exists" with file-level precision. No recommendations or critiques are included.

Next steps for the user: review this document, the referenced thoughts/ files (especially the interaction-surfaces and holodeck-v2 ones), the ConstellationView implementation, and the snapshot/persistent-agent primitives. Then decide the new minimal core + the precise "star map" metaphor and interaction model. The Hail Mary UI screenshot provides an extremely clear visual and experiential target for the usability layer.