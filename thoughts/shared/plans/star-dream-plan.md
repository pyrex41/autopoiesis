---
title: "AETHER — The Star Dream Plan"
date: 2026-05-21
status: VISION / DIRECTIONAL PLAN
author: Grok 4.3 (with 1000x Engineer + Top-Tier Game Designer lens)
git_commit: bb99c19
tags: [vision, direction, aether, star-map, constellation, usability, snapshot, persistent-agents, forking, interface, game-design, ruthlessness]
related:
  - thoughts/shared/research/2026-05-21-rethinking-usability-layer-star-map-inspiration.md
  - thoughts/shared/research/2026-02-17-interaction-surfaces-rho-holodeck-opencode.md
  - thoughts/shared/plans/2026-02-17-holodeck-v2-game-quality.md
---

# AETHER — The Star Dream Plan

> **"One beautiful map. The data sky *is* the product. Forking is not a feature — it is stellar birth."**

This document captures the synthesized vision for a radical, focused, delightful re-direction of Autopoiesis around its single greatest strength: **content-addressable snapshots + O(1) persistent-agent forking via structural sharing**.

The north star is the Hail Mary / Gaia DR3 stellar navigation chart the user provided — clean, immersive, data-dense, chrome-minimal, spatially magnificent.

---

## The Core Insight

Autopoiesis has a genuinely unique technical foundation that no mainstream agent framework possesses:

- Every cognitive state is a first-class, content-addressed, immutable S-expression.
- Forks are O(1) because of fset structural sharing on `persistent-agent` (pmap / pvec / pset).
- The entire history of minds, decisions, heuristics, and self-modifications lives in one unified, queryable, diffable DAG.

Everything else that has accumulated (15-view dashboard, 13+ packages, custom ReAct loops, team strategies, budgets, approvals, multiple viz stacks) is scaffolding that obscures this magic.

**The new product does not document or manage the magic. It *is* the magic, made visible, spatial, physical, and emotionally resonant.**

---

## Product Name & Metaphor

**Primary Name: AETHER**

- The classical element of the immutable, perfect heavens.
- Perfect semantic fit for content-addressed snapshots that "carry light" (cognition).
- Feels ancient, scientific, and transcendent at the same time.

**Strong Alternatives:**
- SIDEREAL
- THE ORRERY (Living Orrery)
- ASTRA
- FORKLIGHT
- CELEST

**The Metaphor (non-negotiable):**
The entire experience is a living stellar cartography view. 

- Stars = snapshots / persistent agent versions / meaningful branch points
- Proper motion vectors + trajectory tails = divergence (computed from `sexpr-diff`)
- Spectral class, brightness, flare patterns, twinkle = derived from S-expression structure, recent thought density, heuristic volatility, capability growth
- Constellations = auto- or user-curated clusters of related lineages
- Birth events = `persistent-fork` with visible plasma bridges celebrating structural sharing
- Light cones + causal flight = time travel and "what-if" exploration
- Deep zoom = homoiconic inspection and live editing of the actual mind structure

The map does not *illustrate* the CAS DAG and forking. It *embodies* them.

---

## Minimal Viable Kernel (What Survives the Cut)

Ruthlessly small. Everything else is optional later or deleted.

**Must Keep (the physics engine):**
- `packages/core/src/snapshot/` — snapshot class, content-store (dedup + refcount), branch, diff-engine, time-travel, consistency
- `packages/core/src/core/s-expr.lisp` — `sexpr-hash`, `sexpr-diff`/`patch`, structural operations
- `packages/core/src/agent/persistent-agent.lisp` + `persistent-lineage.lisp` + `dual-agent.lisp` — the forkable mind
- Capability registry (`defcapability`)
- Thought primitives + recording hooks
- Thin reality pump: cognitive activity → new hashed snapshot + branch movement + event emission
- One renderer (single full-screen spatial canvas)

**Everything else is negotiable or loadable phenomena only:**
- The 15-view Command Center architecture (`AppShell`, `ViewSwitcher`, most per-view stores and components)
- Conductor, team, swarm, jarvis, crystallize, supervisor, sandbox, eval, paperclip, etc. (recast as special map layers or deleted)
- Custom 5-phase cognitive driver + hand-rolled ReAct loop

---

## High-Leverage Mechanics (The Magic)

These are not features. They are ways the unique substrate becomes obvious and joyful through spatial game design.

### 1. Proper Motion & Divergence Vectors
Every child snapshot receives a velocity vector computed from real `sexpr-diff` between parent and child. High structural or semantic change = high proper motion. You watch new realities acquire escape velocity and drift away. The red trajectory lines from the Hail Mary reference become literal, meaningful divergence tails.

### 2. Spectral Classification from S-Expression Structure
The top-level shape and recent content of the serialized `persistent-agent` (thoughts pvec, genome, heuristics, membrane) determine stellar type:
- Hot blue-white = rapid capability growth / exploration
- Cool red = stable, reflective, high heuristic confidence
- Variable / flaring = high churn or recent self-modification

Color, size, twinkle rate, and flare patterns are driven by real data. Two identical forks look identical until they diverge — then their spectra visibly shift. This makes the content-addressable nature *visually true*.

### 3. Birth Events That Celebrate Structural Sharing
`persistent-fork` triggers a beautiful, multi-second "protostar ignition":
- Parent star flares brilliantly.
- A bright, physically accurate stream of shared-structure particles (representing the reused fset nodes) bridges to the newborn.
- The tether thins and fades as the child begins to diverge.
- The new star is born with *identical* initial spectrum and "mass."

This single animation will do more to communicate why Lisp + persistent data structures + CAS is different than any amount of documentation.

### 4. Deep Zoom into the Sexpr Universe (Homoiconicity Made Physical)
Zooming far into a star does not open a text editor. The camera transitions into the agent's internal cosmos:
- Cons cells become crystalline filaments or orbiting node networks.
- The genome is a central constellation.
- Heuristics and recent thoughts are luminous particles with relationships.

Because everything is S-expression, the user (or another agent) can grab a node, edit it, apply `sexpr-patch`, create a new snapshot, and watch the outer star update its color, satellites, and motion in real time. The map *is* the live structure editor.

### 5. Light Cones, Causal Flight, and "Enter the Snapshot"
A minimal peripheral chronoscope (pill modes like the reference: LOCAL / LINEAGE / GALACTIC / ALL TIME) lets you scrub time. The entire sky animates backward/forward along real DAG paths (`find-path`, ancestor traversal).

- Forward and backward light cones softly illuminate.
- "Fly the cone" warps the camera along the lineage with beautiful relativistic color shifts (blueshift toward future, redshift toward past).
- Selecting a star (or using a probe tool) can **warp the viewpoint inside** a rendered embodiment of that exact historical state (Obra Dinn influence). Thoughts become positioned objects. Decisions become spatial paths you can orbit.

Forking from inside the vision materializes the new branch on the outer map. Time travel stops being a database operation and becomes piloting the history of possibility.

### 6. Constellations + The Nursery as Physical Regions
Related branches form elegant, faint connect-the-dots constellations (user-named or auto-clustered by structural/semantic distance).

Swarm / evolution / parallel experimentation becomes a dedicated "molecular cloud" or nursery volume in one corner of the sky:
- Genomes are dropped in as raw material.
- Crossover looks like particle fusion.
- Successful variants ignite and fly out as new stars with inherited traits.

No separate Evolution Lab tab. It is a place in the universe.

### 7. The Map as the Only Orchestration Surface
Missions, tasks, and human intent are not kanban boards. They are trajectories, cargo, or gravitational influences attached to stars.

Approvals become "telescope locks" on high-risk divergence events.

The conductor and any remaining orchestration become invisible "dark matter" whose effects are visible as pulse rates, drift, or flare frequency on the map.

---

## Agent Runtime Strategy (Keep the God Layer, Delegate the Engine)

**Current state (as documented):** The 5-phase cognitive cycle + hand-rolled ReAct in `agentic-loop` + n-gram learning is elegant conceptually but duplicates what 2026 SOTA (LangGraph, Hermes-class function-calling models, Anthropic computer-use patterns, durable structured loops) already does better and more reliably.

**Preserve (the irreplaceable 5–10%):**
- Persistent agent roots + `persistent-fork` + structural sharing
- Full S-expression provenance and `sexpr-diff`
- Unified CAS DAG across minds, thoughts, and snapshots
- Capability surface (`defcapability`)
- Experience recording + heuristic injection (now reinterpreted as heritable "genome" traits)
- Dual-agent bridge for live interaction

**Delegate (the driving intelligence):**
Make a thin `provider-backed-agent` (or Hermes / LangGraph adapter) the primary execution path. The external executor owns reliability, parallel tools, GUI actions, structured routing, tracing, etc.

The Lisp side owns the durable, forkable, self-modifiable substrate and the beautiful recording of every step into the shared DAG.

In the map this appears as:
- Live stars whose position, spectrum, and trails update in real time from delegated activity.
- Forking a live agent = `persistent-fork` (O(1)) + handing the new root (or delta) to the executor as initialization state.
- Self-modification proposals from reflections appear as visible "mutation events" the user can accept/reject, forking the light accordingly.

This keeps the soul while shedding the parts that were never going to compete with dedicated 2026 agent runtimes.

---

## Ruthless Deletions (The Engineer Is Brutal)

- The multi-view dashboard as the primary experience (`AppShell.tsx`, `ViewSwitcher.tsx`, routing hell).
- Most of the 140+ TSX files and 14+ stores become dead weight or tiny contextual holographic overlays.
- `DAGView`, `TimelineView`, `TasksView`, `OrgChart`, `Budget`, `Approvals`, `EvolutionLab`, `AuditLog`, etc. — absorbed into the single spatial layer or deleted.
- The assumption that "we need a tab for every capability."
- The proliferation of per-provider shims and the custom driver loops.
- Loading all the heavy extension packages by default.

The result must feel dramatically lighter and more focused than anything that has existed in the repo so far.

---

## External Inspiration (Stealable Techniques)

Drawn from the deep reference work:

- **Hail Mary / Gaia DR3 chart** — visual north star (full-screen, elegant labels, trajectories, minimal bottom modes + right panel, subtle grid for orientation).
- **Return of the Obra Dinn** — "enter the frozen snapshot" as primary transport; chaining via anchors inside the vision.
- **Outer Wilds** — living, independently evolving possibility space; knowledge/log as the only thing that persists across loops/forks; remote sensing tools.
- **Obsidian Graph + Canvas** + **LangGraph Studio** — direct forkable objects, local focus, freeform curation layers, checkpoint-as-star.
- **No Man's Sky / Elite Dangerous galactic maps** + successful Git DAG visualizers — claiming/naming, plotted routes with cost, visible organic branching as rivers/lanes, activity = brightness.
- Astronomical tools (Stellarium, Gaia explorers) — proper motion, LOD labeling, magnitude encoding, time-scrub epochs, toggleable overlays.

The winning combination: Hail Mary aesthetics + Obra Dinn "enter the moment" + Outer Wilds living dynamics + direct fork gestures on the objects themselves.

---

## Success Criteria (How We Will Know It Worked)

- A new user (or the original creator) can open AETHER and, within 60 seconds, understand that forking is the primary creative act and that the map makes the topology of possibility space visible and navigable.
- Watching a `persistent-fork` birth event produces an emotional reaction ("oh... that's why this matters").
- Deep zoom into a mind's S-expression geometry feels like a revelation rather than a debugging tool.
- People ask "can I live in this?" instead of "what does this button do?"
- The unique Lisp substrate (homoiconicity + structural sharing + CAS) is no longer a footnote — it is the obvious, delightful reason the thing exists.

---

## Immediate Next Steps (Proposed)

1. **Name lock + metaphor lock** — Agree on AETHER (or alternative) and write the one-paragraph positioning.
2. **Minimal data shape for a celestial object** — Define exactly which fields from `persistent-agent` + `snapshot` + diff drive position, spectrum, velocity, trail segments, flare type, etc.
3. **Renderer prototype** — Single full-screen canvas (evolve `ConstellationView.tsx` + Holodeck particle/shader knowledge) that can load real snapshots and persistent agents from the existing store and render them with at least two of the high-leverage mechanics (e.g., proper motion trails + spectral coloring).
4. **Birth event spec** — Detailed animation + particle system design for the structural-sharing celebration.
5. **Delegation boundary** — Write the narrow protocol between the persistent root and an external SOTA executor (Hermes-class or LangGraph).
6. **First "wow" video** — 60–90 seconds of flying through real (or seeded) agent lineage data with birth events and time travel.

---

## Open Questions

- Exact positioning model: pure force-directed on the DAG? Embedding of thought/genome vectors? Hybrid with user pinning and "gravitational" attraction for related lineages?
- What does "human-in-the-loop" look like when the primary gesture is spatial (drag to fork, probe to inspect, fly to explore)?
- How much of the existing Holodeck Bevy work and Three.js work becomes the rendering backend vs. starting fresh for the Hail Mary quality bar?
- Scope of the first public artifact: pure visualization of existing data, or live agents generating new stars in real time?
- Relationship to the old Command Center: does it become a secondary "scientific instrument" mode, or does it die completely?

---

**This is the dream.**

The project has been jumping around for years because it was trying to be a general platform. The star map direction says: "No. We are the place where you can *see* and *feel* what it means for minds to be forkable, versioned, and content-addressed. Everything else is secondary."

The substrate was always the treasure. The star map is how we finally let people hold it in their hands.

---

*Document created from deep codebase research + subagent synthesis on 2026-05-21. Ready for review, iteration, and the first prototype wave.*