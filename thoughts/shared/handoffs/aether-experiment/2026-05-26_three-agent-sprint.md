---
date: 2026-05-26
author: Claude (Opus 4.7)
git_commit: cbe6531
branch: main
status: ACTIVE — three agents running in parallel worktrees
related:
  - thoughts/shared/plans/star-dream-plan.md
  - thoughts/shared/handoffs/aether-experiment/2026-05-22_aether-week-1-experiment.md
tags: [handoff, aether, multi-agent, parallel, compare, lmdb, blame]
---

# Handoff — AETHER three-agent sprint (compare / lmdb / blame)

`main` is at `cbe6531`. AETHER is now a live agent driver with FS-tree snapshotting and click-a-star-to-checkout. The substrate-as-product premise is demonstrable. Reuben asked for three parallel sub-agents to take it from "demonstrable" to "powers a real workflow."

## What's already real on `main`

- `POST /api/aether/spawn {prompt, parent?, cwd?, model?}` spawns rho-cli as a subprocess and streams its events into the snapshot store.
- WS channel `aether:snapshots` broadcasts each new snapshot to subscribed clients.
- Each `prompt` / `tool_result` / `complete` event captures the working-dir filesystem as a Merkle tree (snapshot-tree-entries + snapshot-tree-root).
- `GET /api/aether/snapshots/:id/files` returns the file listing at a snapshot.
- `POST /api/aether/snapshots/:id/checkout` materializes a snapshot's tree back to a target dir.
- Frontend: full-screen spatial canvas, hover HUD, detail panel with files section, `/` to prompt, `c` to checkout, focus mode on selected lineage.

## What three agents will build

Each in its own isolated worktree; final merges done by the main session. Each agent has a tightly-scoped mission so file-overlap is minimized.

1. **Sibling-fork comparison** — fire N variants of a prompt as parallel forks; diff any two stars (cognition + filesystem) side-by-side. Bucket-5 workflow ("try this 5 ways").
2. **LMDB-backed blob store** — make the content store durable so checkouts survive SBCL restart. Wire to substrate's existing `blob.lisp` (LMDB-backed).
3. **`aether-blame`** — per-line file ancestry. For any file at any star, walk ancestors and tag each line with the earliest star that introduced it.

## Strict file-ownership rules (to make merges clean)

All three agents are working on the same codebase. To avoid stomping each other:

- **`aether-runtime.lisp`** — each agent ADDS its own branch to the `rest-handle-aether` dispatcher cond chain. Do not refactor existing branches. Add helpers either inline below the existing helpers or in a new file.
- **`stores/aether.ts`** — only ADD to the `aetherStore` exports object. Don't refactor existing fields. New API wrappers go after the existing ones.
- **`AetherMap.tsx`** — only ADD new sections / handlers. Don't restructure the panel or status bar. New UI affordances should be new functions called from the existing render tree.
- **`aether.html`** — append CSS to the existing `<style>` block. Don't refactor existing rules.

If you need to modify a function another agent might also touch, do it as a small, well-named replacement (e.g. swap a `defvar` initialization) so a 3-way merge can resolve it trivially.

## The plan-of-record

`thoughts/shared/plans/star-dream-plan.md` is canon. The big bet is documented in `thoughts/shared/research/2026-05-21-rethinking-usability-layer-star-map-inspiration.md`. The strategic memo from earlier this week framed AETHER's killer use case as "bucket 5" — exploratory branching, where the substrate's O(1) fork is uniquely positioned.

## Boot script

`/tmp/aether-start-server.lisp` boots SBCL with both REST (`:8081`) and WS (`:8095`) servers. Frontend is in `frontends/command-center/` and runs via `AP_REST_PORT=8081 bun run dev` on `:3000` with `/api` and `/ws` proxied.
