---
date: 2026-06-25
researcher: Claude
topic: "Final verdict — shen-go vs all-OCaml, after the legend panel (Ptacek, Norvig, Hickey) + the standing panel"
inputs:
  - thoughts/shared/plans/dvcs-vfs/13-plan-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/21-synthesis-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/22-ptacek-go-vs-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/23-norvig-go-vs-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/24-hickey-go-vs-ocaml.md
tags: [final-verdict, ocaml, shen-go, decision, land-queue, datalog, policy-as-data]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# Final verdict: shen-go vs all-OCaml

The decision was narrowed to two finalists and put to three additional legends — **Thomas
Ptacek** (Fly.io / Matasano: ops + security + insider LiteFS knowledge), **Peter Norvig**
(Prolog-in-Lisp author: does the Shen brain earn its keep), and **Rich Hickey** (Datomic:
the closest prior art; simple-vs-easy). This consolidates them with the standing panel.

## 1. The vote

| Reviewer | Lane | Call |
|---|---|---|
| **Ptacek** (`22`) | ops / security / LiteFS reality | **all-OCaml** |
| **Norvig** (`23`) | Shen-brain value / simplicity | **all-OCaml** |
| **Hickey** (`24`) | architecture philosophy / Datomic | **all-OCaml** |
| Minsky (`20`, prior) | foundation / types | all-OCaml > shen-go |
| Aphyr (`17`, prior) | consistency | (go-vs-rust; findings damn shen-go: 2 Criticals from litefs reuse) |
| Torvalds (`18`, prior) | VCS design | (go-git can't merge → shen-go's #1 is false) |
| Fukamachi (`19`, prior) | shippability | (go-git merge false; litefs two-process) |

**Unanimous among the reviewers who compared shen-go to all-OCaml: all-OCaml.** The earlier
go-vs-rust panel independently produced the two facts that sink shen-go on its own merits.

## 2. Why shen-go lost — its two headline advantages are substantially false

shen-go's pitch rested on two claims; the panel verified both are wrong or hollow:

1. **"Reuse the real, battle-tested litefs daemon."** Ptacek (who works at the company that built
   it): you reuse a **~200-line format library (`ltx`), not the daemon**, and you must reimplement
   the fenced single-writer authority anyway — which **deletes the reuse premise**. Worse, reusing
   the daemon (if you did) **splits the transactor across two processes** (go-git object write +
   litefs append/lease), which Aphyr scored as **2 Criticals** and Hickey called "the tell that it
   reused a file format and inherited a process boundary, not the invariant."
2. **"go-git answers the merge problem with mature code."** Verified false by Torvalds and
   Fukamachi against the public record: **go-git v6 is alpha, fast-forward-merge only** — no 3-way,
   no rename detection. shen-go would have to vendor libgit2 or port gix's merge anyway. The single
   most important VCS operation is not actually reused.

With both reuse claims gone, what remains of shen-go is the one-heap/no-FFI elegance (a nicety, not
an operational win) and the Shen brain (a research goal) — and the brain doesn't survive scrutiny:

## 3. Why the Shen brain doesn't earn its keep (Norvig + Hickey converge)

- **Prolog ACLs are over-powered.** Norvig: *"a fold dressed as a search"* — longest-prefix +
  deny-wins wants a comparator, not a backtracking resolver. Hickey: the rules *are* Datalog; he
  deliberately chose **Datalog over full Prolog** for Datomic to avoid exactly the Turing-complete,
  can-loop checker Shen embraces. Both: **the good idea is policy-as-data, not Prolog.**
- **Sequent types ≈ GADTs with worse tooling** (Norvig) — and a checker that can loop. OCaml's
  GADTs already make the four invariants (land-FSM, lease-witness, merge-result, acl-proof)
  unrepresentable-when-illegal, with mature errors.
- **Homoiconic policy-as-data is the one genuinely nice idea — and it's free.** Norvig: it "comes
  free with any content-addressed VCS." Hickey: steal exactly this into OCaml — **policy as a
  Datalog data-value landed through the same queue** (Datomic's rules-as-data-in-the-log). No Shen,
  no Prolog runtime required.

Plus the operational/security case (Ptacek): a single-maintainer Shen→Go transpiler in the prod
failure path; repo-controlled Prolog evaluated on the **authorization hot path** (a DoS + audit
liability); and a 3am page that is a **silent data-loss fork** correlated across a Go panic, a Shen
error, and a daemon log nobody on the team can fully read.

## 4. The decision

**Build all-OCaml (`13-plan-ocaml.md`).** It is the simplest system that demonstrably works (one
language, one type system, one toolchain, one in-process transactor), its GADTs already express the
load-bearing invariants, and it told the truth about its hard part (merge) where shen-go's headline
was false.

**Steal exactly one idea from the Shen exploration into the OCaml plan** (Hickey/Norvig's convergent
point): make **policy (ACLs/admission/conflict-class) a data value — a small terminating Datalog
ruleset — landed through the same trunk queue and versioned in the repo.** This captures the only
durable win of the Shen detour (declarative, inspectable, evolvable, self-describing policy) without
a second language, a logic-engine runtime, or repo-controlled Prolog on the hot path. It supersedes
plan 13's "plain OCaml predicate ACLs (with an optional Shen oracle)" — keep the predicates as the
*evaluator*, but source the rules as landed data.

## 5. The honest caveat (Ptacek N1 — do not skip)

The defensible **kernel is language-agnostic**: a *single-leader, fenced, append-only land queue
with path-scoped admission ACLs and honest durability-width acks, in front of an ordinary CAS.*
Everything else (the VFS mount, the monorepo virtualization) is where Sapling+EdenFS and
git+sparse-checkout+partial-clone+Gerrit already deliver ~90%. So:
- Choosing OCaml is a bet on **execution quality and the Irmin leverage**, not on OCaml being
  required — the kernel would be correct in any of these languages.
- Before building the VFS half, be honest about whether it beats Sapling/EdenFS for the actual
  users, or whether the **land-queue kernel** (the genuinely novel, defensible part) is the product
  and the mount is optional.

## 6. Next action — start P0 of `13`, lead with the one risk everyone names

All reviewers point at the same single residual technical unknown for all-OCaml: **irmin-pack's
concurrency under a multi-reader VFS** (Ptacek's "loud 3am page," plan 13's own #1 risk, Minsky's
Finding 7). So P0 leads with it:

1. **Gating spike S1 — irmin-pack concurrent multi-reader benchmark with GC running.** Go/no-go for
   irmin-pack behind the mount; if it fails, the `Object_store` seam lets a cache/alternative
   backend slot in (or fall to split-stack), per plan 13.
2. **Gating spike S2 — pure-Lwt vs `lwt_eio`** for the read+land path; drop the bridge if Eio's win
   is marginal (kills Ptacek's other page).
3. **The `Object_store` seam + the four domain `.mli`** (land-FSM GADT, `Lease.witness`,
   total `merge_tree`, `Acl.proof`) — now with **`Acl` sourced from a landed Datalog ruleset**
   (the stolen idea).
4. Dependency posture: `opam.locked` pin, vendored irmin-pack, the format-migration CI drill.

If S1/S2 both pass, all-OCaml is de-risked and P1 (the nice single-machine VCS: dirstate, real
merge, local stacks) proceeds. If S1 fails, that is the signal to revisit the split-stack — **not**
shen-go.

## Appendix — full document set
`00`–`05` CL design + reviews · `06` grounding · `07`–`12` OCaml direction + panel + synthesis ·
`13` all-OCaml plan · `14` all-Shen-on-SBCL · `15` shen-go · `16` shen-rust · `17`–`20` shen-backend
panel · `21` shen-backend synthesis · `22` Ptacek · `23` Norvig · `24` Hickey · `25` this verdict.
