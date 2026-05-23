---
date: 2026-05-22
author: Claude (Opus 4.7) — session under reuben
git_commit: bb99c19
branch: main
status: ACTIVE — Week 1 experiment in flight
experiment: aether-week-1-layout-feasibility
related:
  - thoughts/shared/plans/star-dream-plan.md
  - thoughts/shared/research/2026-05-21-rethinking-usability-layer-star-map-inspiration.md
  - /Users/reuben/.claude/plans/write-a-plan-to-enumerated-comet.md
tags: [handoff, aether, star-map, snapshot-dag, persistent-agents, prototype, team-execution]
---

# Handoff — AETHER Week-1 Layout-Feasibility Experiment

**You are receiving this from a Claude Opus 4.7 session that just wrote and finalized the plan.** Reuben (the user) approved the plan and asked for the work to be picked up by a team of agents. This document is everything you need to proceed without the prior conversation.

---

## TL;DR

Autopoiesis has accumulated ~80k lines of scaffolding around ~1.6k lines of irreplaceable code (snapshot CAS + persistent-agent forking + `sexpr-diff`). The vision in `thoughts/shared/plans/star-dream-plan.md` is to throw out the 15-view dashboard and build a single full-screen spatial canvas — **AETHER** — in the aesthetic of the Hail Mary / Gaia DR3 star map.

Every downstream piece of that vision (birth events, deep zoom, light cones, etc.) is contingent on one unanswered question:

> **Does the real snapshot DAG, projected into 2D with force-directed layout (edges weighted by `sexpr-diff` magnitude, nodes spectrally colored by persistent-agent structure), look like Hail Mary — or does it look like a graph?**

**The deliverable for Week 1 is a single screenshot that answers that question.** Not a polished product. Not a tab in the dashboard. One image. Reuben wants to stare at it and either commit to the direction or pivot.

Read the full plan at `/Users/reuben/.claude/plans/write-a-plan-to-enumerated-comet.md` before doing anything.

---

## Why this matters (the soul)

The repo has been dormant since late March 2026 — confirmed by `git log` (all 11 of the dormant packages last touched in the same mass commit). Reuben loves the substrate (content-addressable snapshots + O(1) persistent-agent forking via fset structural sharing) but the product surface has eaten the soul. This experiment is the smallest possible move toward "the substrate IS the product, made spatial and visible."

If the layout works visually, this becomes the path forward. If it doesn't, we know in days instead of months.

The plan, the star-dream-plan, and the research doc are all coherent — read them. Don't second-guess the strategic direction. Your job is execution on a well-scoped experiment.

---

## Team structure & work split

Two parallel agents in isolated worktrees, converging back to main session for Phases 4–5:

### Agent A — Backend track (Phases 1 + 2)

**Worktree:** auto-created (`.claude/worktrees/aether-backend`)

**Deliverables:**

1. **Phase 1 — Verify the data pipe**
   - Bring up the existing REST API server: `(autopoiesis.api:start-rest-server :port 8081)` — entry point at `packages/api-server/src/rest-server.lisp:36-73`
   - Manually create 2–3 `persistent-agent`s, fork them, snapshot, save
   - Exercise the relevant endpoints (defined in `packages/api-server/src/routes.lisp:332-441`):
     - `GET /api/snapshots`
     - `GET /api/snapshots/{id}`
     - `GET /api/snapshots/{id}/diff/{other-id}`
     - `GET /api/snapshots/{id}/children`
   - **Capture exact actual JSON responses** (curl + jq output) to a fixture file at `e2e/fixtures/aether-api-shape.json` — the frontend agent will read this to know the real shape, not the documented shape.
   - If `agent--state` comes back as a `prin1`'d Lisp string rather than structured JSON, document it explicitly. Decide and document whether to (a) add a precomputed `diff-magnitude` endpoint server-side or (b) parse client-side. Prefer (a) if the prin1 string is painful.

2. **Phase 2 — Synthetic lineage generator**
   - Write `packages/core/scripts/aether-seed.lisp`
   - Idempotent (seeded random) — same invocation produces same store
   - ~30–80 persistent-agents across 3–5 root lineages
   - **Variance is the whole point**: variable branching factor (some lineages fork heavily, some stay linear), variable cognitive activity (agents accumulate thoughts/capabilities/heuristics at different rates), variable diff magnitudes (some forks diverge sharply, some stay close)
   - Reuse existing primitives only: `make-persistent-agent`, `persistent-fork`, `make-snapshot`, `save-snapshot`, `pvec-push`, `pset-add`, `pmap-put`
   - Provide a public function `(aether-seed:populate :path <path> :n <count> :seed <int>)`
   - Output store at `/tmp/aether-seed/` should be servable by the REST API server

**Constraints:**
- **Do not modify any of the 11 dormant packages** (`crystallize`, `eval`, `jarvis`, `paperclip`, `research`, `sandbox`, `supervisor`, `swarm`, `team`, `shen`, `holodeck` Lisp glue) — they're slated for deletion in a future pass.
- **Do not modify backend protocols** unless you hit a genuine blocker. If you add a precomputed `diff-magnitude` endpoint, that's the one exception — and document the addition clearly in the PR description.
- If something is broken in the API server boot path, fix the minimum to get it running and document it in the handoff back.

**Commit format:** small commits, conventional style. Branch will be reviewed by Reuben.

---

### Agent B — Frontend track (Phase 3)

**Worktree:** auto-created (`.claude/worktrees/aether-frontend`)

**Deliverables:**

A standalone `/aether.html` page that hits the REST API and renders the canvas. **No tab in `AppShell` / `ViewSwitcher`.** Mirror the existing `vite.holodeck.config.ts` precedent for the standalone build.

New files:
- `frontends/command-center/aether.html` — minimal host
- `frontends/command-center/src/pages/AetherMap.tsx` — full-screen Solid component, single Canvas 2D
- `frontends/command-center/src/stores/aether.ts` — fetches snapshots once, runs force simulation, exposes positioned nodes
- `frontends/command-center/vite.aether.config.ts` (or add a Rollup input to root `vite.config.ts` — your call, pick the cleaner one) — build entry

**Reuse without modification:**
- `api/client.ts` `listSnapshots()` for the data fetch (file: `frontends/command-center/src/api/client.ts:33-42`)
- Starfield code from `ConstellationView.tsx:19-95` — copy-paste, 200 stars, twinkle
- Color palette from `lib/design-system.ts` (`--void`, `--deep`, `--signal`)
- Pan/zoom math from `DAGCanvas.tsx:235-620` — wheel zoom, drag pan
- Force simulation pattern from `stores/constellation.ts:117-166` — repulsion + spring + centering + damping. **Modify** to use edge spring rest-length = f(diff-magnitude) instead of fixed.

**Spectral classification function** (small, in `stores/aether.ts`):

```
spectralClass(agent) → HSL
  hot blue-white:  high recent-diff + low version (young, exploring)
  cool red:        high version + many heuristics (old, stable, reflective)
  white-yellow:    high capability count
  size:            log(thoughts pvec length + 1)
```

Crude is fine. The question is whether even a crude function produces a visually meaningful spread.

**Hard constraints:**
- **No** animations, no birth-event particle systems, no label-on-hover, no selection panels, no right-side info panel, no JarvisBar, no chrome at all besides the canvas itself.
- **Pan and zoom only.** That's it for interactivity.
- **No new dependencies.** Use what's already in `package.json`. Hand-roll the force simulation.
- **Do not touch** `AppShell.tsx`, `ViewSwitcher.tsx`, or any of the 15 views.
- **Do not** read `agent--state` as parsed Lisp client-side if Agent A reports it's painful — instead wait for the precomputed endpoint or pass the magnitude through metadata.

**While Agent A is working on Phase 1**, you can scaffold the page against the *documented* JSON shape (in `packages/api-server/src/serialization.lisp:54-72`) and a small hand-written placeholder fixture you create at `frontends/command-center/src/pages/__fixtures__/aether-placeholder.json`. Once Agent A's fixture lands at `e2e/fixtures/aether-api-shape.json`, swap to that.

**Definition of done for Phase 3:**
- `bun run build:aether` (or whatever you call the new entry) succeeds
- Loading `/aether.html` against a running API at `localhost:8081` shows: starfield background + force-positioned spectrally-colored nodes + pan + zoom
- No console errors
- Code is small, readable, throwaway-ready

---

## Convergence point

**Phases 4 (iterate) and 5 (real-data confirmation) stay in Reuben's main session.** They are inherently coupled — tweak the generator, look at the image, tweak more. Doing them in two separate worktrees would multiply the dev-loop cost.

When both Agent A and Agent B finish, each should:
1. Push their branch
2. Open a PR (or leave the branch ready) and reply with the branch name + a 5-line summary of what they did and any surprises
3. Note any blockers or open decisions for Reuben

Reuben will merge both, then iterate locally on the synthetic generator + spectral function until the screenshot either passes or definitively fails.

---

## Critical files map

**Read these to understand the substrate** (do not modify):
- `packages/core/src/snapshot/snapshot.lisp:11-43` — snapshot struct
- `packages/core/src/snapshot/persistence.lisp:42-78` — save/load
- `packages/core/src/agent/persistent-agent.lisp:13-28` — agent fields (`id`, `name`, `version`, `timestamp`, `membrane`, `genome`, `thoughts`, `capabilities`, `heuristics`, `children`, `metadata`)
- `packages/core/src/core/s-expr.lisp:156-176` — `sexpr-edit` struct returned by `sexpr-diff` (fields: `type :replace|:insert|:delete`, `path`, `old`, `new`)

**API server** (Agent A reads, modifies minimally if needed):
- `packages/api-server/src/rest-server.lisp:36-73` — `start-rest-server`
- `packages/api-server/src/routes.lisp:332-441` — snapshot endpoints
- `packages/api-server/src/serialization.lisp:54-72` — `snapshot-to-json-alist`, `snapshot-summary-alist`

**Frontend reuse anchors** (Agent B copies from):
- `frontends/command-center/src/components/ConstellationView.tsx:19-95` — starfield
- `frontends/command-center/src/components/DAGCanvas.tsx:235-620` — pan/zoom
- `frontends/command-center/src/stores/constellation.ts:117-166` — force simulation pattern
- `frontends/command-center/src/api/client.ts:33-42` — `listSnapshots()`
- `frontends/command-center/src/lib/design-system.ts` — color tokens
- `frontends/command-center/vite.holodeck.config.ts` — standalone Vite precedent

---

## Verification (end-to-end, post-merge)

```bash
# Terminal 1 — populate store + start API
sbcl --noinform \
  --eval "(ql:quickload :autopoiesis :silent t)" \
  --eval "(ql:quickload :autopoiesis-api-server :silent t)" \
  --load packages/core/scripts/aether-seed.lisp \
  --eval "(aether-seed:populate :path #P\"/tmp/aether-seed/\" :n 60 :seed 42)" \
  --eval "(autopoiesis.api:start-rest-server :port 8081 :store-path #P\"/tmp/aether-seed/\")"

# Terminal 2 — frontend
cd frontends/command-center
bun install
bun run dev

# Browser
open http://localhost:5173/aether.html

# Confirm:
#   curl http://localhost:8081/api/snapshots | jq length    →  ~60
#   Page loads without errors
#   Stars at varied (non-grid, non-circular) positions
#   Pan + zoom work
#   Colors vary visibly across nodes
```

---

## Hard guardrails (both agents)

1. **Do not touch the dashboard.** No new tab, no AppShell change, no ViewSwitcher edit. The whole point is to escape the 15-view disease.
2. **Do not add dependencies.** Both Lisp and JS sides should ride on what already exists.
3. **Do not animate.** This is a static-screenshot experiment. Animations come in Week 2 if the screenshot passes.
4. **Do not modify dormant packages.** Listed above. They're scheduled for deletion.
5. **Stay small.** Each agent's PR should be reviewable in 15 minutes. If you're at 600+ lines of new code, you've over-built.
6. **Iterate variance, not the renderer.** If the image looks wrong in Phase 4 (which is Reuben's job, not yours), the fix is almost always in the synthetic generator's distributions or the spectral function — not the renderer.
7. **Report honestly.** If something doesn't work, say so. The plan tolerates a "pivot" outcome; what it can't tolerate is silent over-promising.

---

## Open questions to resolve during build (not to wait on)

- **Spring rest-length scaling** — linear or log in diff-count? Likely log once real data is involved. Agent B's call, document it.
- **`agent--state` JSON shape** — depends on Agent A's Phase 1 findings. If structured JSON is reasonable, parse it. If it's a `prin1`'d string, add a small precomputed endpoint.
- **How many roots in the seed?** 3–5 with deep branching usually beats 20 shallow. Agent A's call.
- **Vite entry style** — separate `vite.aether.config.ts` vs. multi-input root config. Agent B's call. Cleaner one wins.

---

## Status as of handoff

- Plan written and approved: `/Users/reuben/.claude/plans/write-a-plan-to-enumerated-comet.md`
- TaskCreate tasks set up for all 5 phases
- No code written yet — this is the actual starting line
- Reuben is observing, not actively coding

When each agent finishes, post a one-paragraph summary back including:
1. Branch name
2. Files added/changed
3. Anything surprising
4. Anything blocked

That's it. Make the smallest thing that lets Reuben look at one image and decide.

— end of handoff —
