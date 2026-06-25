---
date: 2026-06-25
researcher: Claude
topic: "Panel synthesis — Shen-on-Go vs Shen-on-Rust (and vs all-OCaml), with the panel's resolution"
inputs:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/16-plan-shen-rust.md
  - thoughts/shared/plans/dvcs-vfs/17-aphyr-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/18-torvalds-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/19-fukamachi-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/20-minsky-shen-backends.md
tags: [synthesis, shen, go, rust, ocaml, merge, consensus, decision]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# Synthesis: Shen-on-Go vs Shen-on-Rust (panel-reviewed)

Four reviewers assessed both Shen-backend plans head-to-head. This consolidates their
go-vs-rust calls, the one fact they unanimously corrected, the axes on which they split, and
the resolution — which is subtler and more decisive than "pick Go or Rust."

## 1. The panel's go-vs-rust calls

| Reviewer | Lane | Call | Go counts | Rust counts |
|---|---|---|---|---|
| **Aphyr** (`17`) | consistency | **Rust** (only it can fence correctly) | 2 Critical, 3 Major | 0 Critical, 3 Major |
| **Torvalds** (`18`) | VCS design | **Rust** (real merge), cond. on interop spike | 1 Showstopper, 3 Serious | 0 Showstopper, 2 Serious |
| **Fukamachi** (`19`) | shippability | **"Go to ship, Rust to keep"** | 2 Blocker, 3 Significant | 1 Blocker, 4 Significant |
| **Minsky** (`20`) | foundation/types | **shen-go** among Shen variants; ranks **all-OCaml > shen-go > shen-rust** | — | shen-rust = "worst cell" |

## 2. The fact the panel unanimously corrected (both plans had it backwards)

**go-git cannot do a real merge.** Independently verified by Torvalds and Fukamachi against the
public record: **go-git v6 is alpha and supports only fast-forward merge** — no 3-way/ORT, no
rename detection; its README explicitly says it lacks porcelain merges. **`gix` (Rust) actually
shipped `merge tree`/`merge commit`/`merge file` with rename tracking in 2025.**

This **guts plan 15's (Go) headline thesis** ("go-git answers Torvalds' no-merge Showstopper with
real code") and means the Go variant would have to *build or vendor* a real 3-way merge (libgit2
via cgo, shell to `git`, or port gix's merge) — eroding its "reuse mature Go code" advantage on the
single most important VCS operation. Plan 16 (Rust) was honest and, if anything, *undersold* gix.

> Correction logged against `15-plan-shen-go.md`: its merge claim is false as written and must be
> replaced before that plan is buildable.

## 3. The axes — and why they point different directions

- **Product quality (merge, mount, consistency-fence correctness) → Rust.** Real `gix` merge
  (Torvalds), `fuser` + no-GC syscall path (Torvalds/Fukamachi), and the ability to **own the
  append so the fencing token is CAS'd on the durable write** (Aphyr — Go can't, because litefs owns
  the append and its async lease *is* the "lease ≠ fence" Critical, plus a two-process authority
  split). On correctness and the developer-facing VCS, Rust is ahead.
- **Time-to-v1 / interop simplicity → Go.** One heap, one GC, one cgo-free static binary, no
  marshaling, no `catch_unwind` regime; and a Shen→Go KLambda backend is a far more believable
  stipulation than Shen→Rust reconciling dynamic GC'd values with ownership (Fukamachi). Shortest
  path to something running.
- **Foundation coherence → eliminates shen-rust.** Minsky's decisive point: Shen's sequent types
  are a **real upgrade over Go** (no sum types/exhaustiveness/typestate) but **pure redundancy over
  Rust** (which expresses all four invariants natively, and `Drop` enforces the lease lifetime
  *better* than Shen's GC'd token). And the one value that matters — the merged tree — crosses the
  Shen↔host boundary as an **opaque hash both ways**, so the sequent checker's central dividend
  (value-correspondence) degrades to shim-trust in *both* variants. Net: **Shen-on-Rust pays for two
  type systems where the stronger one already spans the body** — the worst cell.

## 4. The resolution (more decisive than "Go or Rust")

Put the four together and the asked question ("all-Shen: Go or Rust?") resolves into an elimination
plus a fork:

- **shen-rust is dominated and should be dropped *as posed*.** It has the best *body* but wastes it
  under a redundant Shen type layer + the hardest interop (the most faith-based stipulation + a
  forever panic-safety obligation). Minsky's logic: *if you want Rust's strengths, the coherent move
  is pure-Rust (drop Shen), not Shen-on-Rust.* Three reviewers' product praise for Rust is praise
  for **Rust**, not for **Shen-on-Rust**.
- **shen-go is the coherent Shen variant** (Shen earns its keep over Go; ships fastest; believable
  compiler) — **but its body is the weakest on the two hardest axes** and must be repaired:
  1. **Merge:** go-git can't 3-way merge → vendor a real merge (libgit2-via-cgo, shell-to-git, or
     port gix-merge). Mandatory; it's Torvalds' #1.
  2. **Consistency:** don't trust litefs's lease as the fence and don't split trunk authority across
     the litefs daemon + the go-git process → own the landed-log append and the fencing token in one
     process (Aphyr's 2 Criticals).
  With both repaired, shen-go is a legitimate, shippable, *coherent* Shen system.

So the honest menu is three coherent options (shen-rust is **not** among them):

| Option | What it is | Best when |
|---|---|---|
| **shen-go (repaired)** | Shen brain (Prolog control plane + sequent types + homoiconic policy) on Go; vendor a real merge; own the fence | The **Shen brain is the reason to build this**; want shortest path to a coherent v1 |
| **pure-Rust (drop Shen)** | gix merge + fuser + correct fence + native Rust types; embed a small Prolog/Datalog *only* for the ACL control plane | **Body quality/correctness dominates** and Shen's *type* layer isn't the point — you want the declarative policy idea, not the Shen type apparatus |
| **all-OCaml** | one type system spanning brain + Irmin store; body weaknesses (diff3, ocamlfuse) are contained | **Foundation soundness** weighted highest (Minsky's #1) |

## 5. Recommendation

- **If the question stays strictly "all-Shen, Go or Rust": choose Go** — because shen-rust is
  dominated by pure-Rust, so within the Shen constraint Go is the only coherent one. Ship it with the
  two mandatory repairs (real merge; owned fence). This is also the "Go to ship" half of Fukamachi
  and the "Shen earns its keep over Go" of Minsky.
- **But the panel's stronger signal is a fork**, and it's worth surfacing rather than burying: the
  three reviewers who praised Rust were praising *Rust's body*, and Minsky shows Shen adds nothing to
  Rust — so if Rust's body is what attracts you, the coherent destination is **pure-Rust with an
  embedded logic engine for policy**, not Shen-on-Rust. Conversely, if the **Shen brain** is the
  point (Prolog control plane, homoiconic policy, autopoiesis lineage), **Go** is its right host.
- **all-OCaml remains the soundest foundation** if you weight one-type-system coherence above all;
  its weaknesses are body-level and contained.

The decision now reduces to a values question, not a technical unknown: **do you want the Shen brain
(→ shen-go, repaired), the best body (→ pure-Rust + embedded Prolog), or the soundest single-type
foundation (→ all-OCaml)?**

## 6. Next actions (whichever you pick)

- **shen-go:** amend `15` — replace the go-git merge claim with a vendored-merge plan; redesign the
  fence to be owned in-process (don't delegate to litefs's lease); keep everything else.
- **pure-Rust:** I can write a `22-plan-rust.md` (gix + fuser + owned ltx-style fenced log + embedded
  Prolog/Datalog ACLs) — the "drop Shen, keep the idea" option Minsky pointed at.
- **all-OCaml:** `13-plan-ocaml.md` is already buildable; start P0 (Object_store seam, the four
  `.mli`, the two gating spikes).

## Appendix — document set (Shen-backend layer)
`15` shen-go plan, `16` shen-rust plan → `17` Aphyr, `18` Torvalds, `19` Fukamachi, `20` Minsky
(all comparative) → `21` this synthesis. Earlier layers: `00`–`05` CL design+reviews, `06` grounding,
`07`–`12` OCaml direction+panel+synthesis, `13` all-OCaml plan, `14` all-Shen-on-SBCL plan.
