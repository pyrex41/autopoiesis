---
title: "AETHER as the Shen-Backpressure cockpit"
date: 2026-05-28
status: ACTIVE — slice 1 shipped, slices 2-3 pending
author: Claude (Opus 4.7) with reuben
git_commit: 4e07901
branch: main
related:
  - thoughts/shared/research/2026-05-28-aether-agent-observation-gap.md
  - thoughts/shared/plans/star-dream-plan.md
  - ~/projects/Shen-Backpressure/README.md
tags: [plan, aether, shen-backpressure, cockpit, gates, discharge-report, pivot]
---

# AETHER as the Shen-Backpressure cockpit

## The pivot

AETHER began as a spatial visualization of an agent's content-addressed
history (the "star map"). Research (`2026-05-28-aether-agent-observation-gap.md`)
showed it had built rare superpowers — fork, checkout, blame, compare on a
snapshot DAG — on top of an **absent foundation**: it captured the *shape*
of agent runs (prompt → think → tool → done) but discarded the *substance*
(tool output never captured, inputs/reasoning truncated, failed runs shown
as success). You could not see what an agent actually did.

The reframe: **AETHER becomes the cockpit for the Shen-Backpressure (SB)
paradigm.** Instead of observing arbitrary agents doing opaque work, it
observes *gated, spec-driven* loops where every iteration produces a
structured, audit-grade verification artifact. The substance problem
dissolves because the substance is now the discharge report.

## What Shen-Backpressure is (the engine)

`~/projects/Shen-Backpressure`. Formal verification gates for AI coding
loops. You write a Shen sequent-calculus spec (`specs/core.shen`) as the
source of truth for domain invariants + pure functions. `sb loop` runs the
Ralph loop; every iteration must pass 5-6 gates (shengen, test, build,
shen tc, tcb audit, shen-derive). A failing gate feeds back into the next
prompt as **backpressure**. Each gate run writes `.sb/discharge_report.json`
(time-stamped copies accumulate in `.sb/history/`): per-rule, per-premise
evidence of how each invariant was discharged — statically by guard types,
by runtime sampling, or unproven — with concrete counter-examples and
`go test -run …` reproduction commands for failures.

## Architecture: engine vs cockpit

**`sb` is the engine. AETHER is the cockpit. They stay separate.**

- `sb loop` orchestrates: spawns the agent (rho), runs the gates, applies
  backpressure, writes artifacts. AETHER does **not** reimplement this.
- AETHER **observes**: reads `.sb/discharge_report.json` + `.sb/history/` +
  the git commit per iteration + the spec, and renders them.
- `sq-sandbox` / the autopoiesis `sandbox` package (squashd) is where
  `sb gates` executes — inspectable, and it fixes the "rho writes
  ephemerally / where did the files go" problem because work runs in a
  real, addressable sandbox.
- rho is just the implementer inside the loop. The **rho patch is deferred**
  — the discharge report, not rho's raw tool I/O, is the substance for this
  use case.

Same relationship LangSmith has to a LangGraph run.

## How the substrate superpowers finally attach

The unit becomes **the iteration**; the content becomes **the gate result**.

- **Tracks** = the Ralph loop over time; each iteration a block, colored by
  gate pass/fail, gates as sub-pips.
- **Compare** two iterations → diff their discharge reports: which premises
  flipped discharged ↔ unproven.
- **Blame** → extend from "which step wrote this line" to "which iteration
  broke this gate / premise."
- **Fork** from the last all-green iteration to try a different approach
  against the same spec.
- **Checkout** any iteration's code to inspect it.

## Slices

### Slice 1 — discharge-report view  ✅ SHIPPED (commit 4e07901)

Prove the substance layer on real `sb` output before any loop wiring.

- Backend `GET /api/aether/discharge?report=<abs .json path>` reads/returns
  a discharge report (validates `.json` + existence).
  `packages/api-server/src/aether-runtime.lisp`.
- `frontends/command-center/src/stores/discharge.ts` — schema_version 1
  types + fetch + sort (violated/unproven first).
- `frontends/command-center/src/pages/DischargeView.tsx` — header, summary
  strip, per-rule cards (kind badge, status, human description, Shen
  spec_excerpt, premise table with discharge badge + basis + clickable code
  refs + sample counts, counter-example block with copyable repro).
- Standalone `discharge.html` + `discharge-entry.tsx`, wired as a Vite
  input; `?report=<path>` overrides the default (multi-tenant-api example).

Verified via rodney on the all-green multi-tenant-api report and a
synthesized failing report (violated rule at top, counter-example + repro).

### Slice 2 — `.sb/history/` as the iteration lineage  (NEXT)

Turn the history of discharge reports into the tracks lineage. Each gate
run = a track block colored by pass/fail (and per-gate sub-pips). Clicking
an iteration opens the slice-1 discharge view as the drill-down. This is
where the tracks UI and the substance layer fuse. Needs: read/sort
`.sb/history/*.json`, map each to a git commit, render as a lineage,
wire selection → discharge view.

### Slice 3 — drive `sb loop` live

Kick `sb loop` on a project in the sandbox, stream gate results as
iterations land, render them live, show backpressure steering the next
prompt. Most moving parts; needs sandbox + sb orchestration wired.

### Later

- Compare two iterations' discharge reports (premise-flip diff) — reuse the
  existing compare gesture on gate results.
- Per-gate (not just per-rule) status from `sb gates` output.
- rho patch (tool I/O) if we want the agent's raw moves alongside gates.

## Open questions

- `.sb/history/` cadence — one report per gate run, or per loop iteration?
  Does each map cleanly to a git commit AETHER can checkout?
- How does the autopoiesis `sandbox`/`shen` package already relate to `sb`?
  (There is a `feat/shen-prolog` branch and prior shen integration research.)
- Does `sb` expose a machine-readable per-gate pass/fail (for the gate
  strip), separate from the per-rule discharge report?
- Live drive: does AETHER shell out to `sb loop`, or does `sb` gain a mode
  that streams events AETHER subscribes to?

## The tradeoff (named explicitly)

This narrows AETHER from "observe any agent" to "the cockpit for
Shen-Backpressure loops." That focus is the point — generic agent
observation is exactly where it floundered. The cost is integration work,
and demoting the spatial map from "the product" to "one lens on gated
iterations."
