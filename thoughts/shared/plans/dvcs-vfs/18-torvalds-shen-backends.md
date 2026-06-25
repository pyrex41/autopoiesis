---
date: 2026-06-25
reviewer: "Linus Torvalds (persona)"
status: review
topic: "Head-to-head VCS-design review of the two Shen-brain backends — Go body (go-git/litefs/bazil-fuse) vs Rust body (gix/fuser/ltx-rs)"
targets:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/16-plan-shen-rust.md
related:
  - thoughts/shared/plans/dvcs-vfs/09-torvalds-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/14-plan-shen.md
tags: [review, vcs, shen, go-git, gix, gitoxide, litefs, ltx, fuser, bazil-fuse, merge, dirstate, mount, head-to-head]
---

# Linus-style review — the two Shen backends, head-to-head

I've reviewed this thing twice (`03`, `09`). The OCaml/Irmin pivot was real progress and it
finally answered my #1 demand: stop hand-rolling diff3, **use a real merge library**. Now you
hand me two variants of the *same* product — the same Shen brain (`14`), the body swapped onto
**Go** (`15`: go-git + litefs/ltx + bazil/fuse) or **Rust** (`16`: gix + fuser + ltx-rs). Both
claim to discharge my three Showstoppers with a mature git-merge engine instead of a few hundred
lines of diff3 someone wrote on a Friday.

So I'm going to do exactly one thing: ask, per variant, *is this a good, fast, pleasant VCS, and
which one delivers the merge I asked for?* And then I'm going to pick one.

The short version: **both plans are honest and well-structured, both keep the coherent brain, and
both finally reach for a real merge library — which is the thing I wanted.** But one of them
reached for a library that **actually has the merge**, and the other reached for a library whose
*own documentation* says merges are a gap. That single fact decides the head-to-head, and it cuts
*against* the way the two plans frame themselves.

---

## Verdict (blunt, one paragraph)

Credit first, because it's earned in both: you stopped pretending you'd write merge yourself, you
reused `litefs`/`ltx` for replication instead of reinventing it (genuinely smart in Go, where you
get the *whole daemon*; honestly scoped in Rust, where you only get the format), you put the
fencing CAS on the durable append where it belongs, and you wrote restack-on-land down at last —
the one operation that makes stacks worth having, which `09` said was missing. **But the central
claim that splits the two plans is backwards.** Plan `15` (Go) leans its entire #1 answer on
go-git's "purpose-built, battle-tested ORT 3-way merge with rename detection" — and go-git's own
maintainers describe merges as a **porcelain operation it lacks**; what go-git v6 ships is a merge
*strategy-option struct* and merge-base plumbing, not the rename-aware tree merge the plan
narrates as "real code." Plan `16` (Rust) leans on `gix`'s merge — and `gix` *actually shipped*
`gix merge tree` / `gix merge commit` with recursive virtual-merge-base and rename tracking,
test-driven, through 2024–2025. So the plan that **talks less confidently about merge has the
better merge**, and the plan that **promises the most has the weakest evidence**. On the mount,
it's not close: `fuser` is the best FUSE story in any of these ecosystems and Rust has no GC on
the syscall path; bazil/fuse is fine and cgo-free (a real virtue) but Go's GC sits under every
`read()`. On the three-sources-of-truth trap, both are *better than the OCaml brief* because ACLs
finally live in trunk (`policy.shen`), not a secret SQLite — credit to both. And on the Shen brain
itself: over a git library that already does the hard part, the Prolog control plane and the typed
land FSM are **mostly justified** (the ACL-in-trunk + sequent-typed land FSM earn their keep), but
the merge `datatype` is now thinner value than advertised — it's marshaling a library result into
a sum type, which is good taste, not deep work. **Net: Rust is the better VCS, and it wins on the
exact axis (merge) the Go plan claims as its headline.**

---

## The decisive finding first, because it reorders everything

### [Showstopper — Plan 15 (Go)] The #1 claim rests on a go-git merge that go-git itself says it doesn't have.

**Attacked:** `15 §0`/`§3.3`/`§12.5` — "go-git's purpose-built, battle-tested **ORT/recursive
3-way textual merge with rename detection** … real, mature, in-tree … answering Torvalds with
code, not a hand-rolled diff3." `§3.3` `gobody.merge-ort` is narrated as if go-git hands you
`(clean | text-conflict | structural)` from a complete ORT engine.

Here's the problem, and it's the one that matters most because it's the whole reason this variant
exists. go-git's own project status is explicit that it **"covers the majority of the plumbing
read operations and some of the main write operations, but lacks the main porcelain operations
such as merges."** What go-git v6 actually exposes is an `OrtMergeStrategyOption` — a *strategy
selector* — plus solid merge-*base* (LCA) computation. "ORT is a synonym of recursive since git
2.50" is a statement about *git*, not about how much of ORT go-git reimplemented. The hard 80% I
named in `09` — the diff3 text engine, **rename detection (similarity scoring across the changed
set)**, delete/modify and rename/edit structural resolution, conflict-marker generation — is
**not** demonstrably in go-git as shipping code. The plan describes `merge-ort` as if it returns
rename-aware structural conflicts; the evidence says you'd be **building or wiring most of that
yourself**, which is precisely the cost the plan claims to have deleted.

This is *the same sin from `09`, one layer down*: "the dependency has the feature" → "the hard
part is done." Last time it was "Irmin has merge." This time it's "go-git has ORT." Both overclaim
the rename/structural part — the part that *is* merge.

**Severity: Showstopper for this plan specifically**, because merge is the plan's stated #1
deliverable and its entire reason to prefer Go ("real code, not hand-rolled diff3") is the part
that isn't real. It's not a Showstopper for the *product* — you can fall back to wrapping libgit2
via cgo, or hand-rolling, or switching bodies — but every one of those fallbacks **deletes the
plan's headline advantage** (cgo reintroduces exactly the GC-callback hazard `§1.1` brags about
avoiding; hand-rolling is the diff3 I told you to stop writing).

**What I'd do:** (a) Stop saying go-git gives you rename-aware ORT. Say "go-git gives the object
model + merge-base; the rename-detecting tree merge is **work we scope**, with libgit2-via-cgo as
the costly fallback." (b) Put a P0 gating spike — *before* P1 hardens — that runs go-git merge on
the rename-vs-edit and delete-vs-modify corpus and **measures how much is missing.** That spike
is more important than Spike A or B, because if it fails the variant's reason-to-exist is gone.

### [Good — Plan 16 (Rust)] gix's merge is the one that's actually shipping, and the plan is appropriately modest about it.

**Credit:** `16 §2.2c`/`§9.3` — "`gix` does textual 3-way merge AND rename detection natively
(`rs_gix_merge3`) … `gix-merge`/`gix-diff` … **younger than libgit2's**." This is the correct
posture and it matches reality: gix shipped `gix merge tree` (takes all three trees, invokes
tree-merge directly), `gix merge commit` (computes merge-base, recurses on multiple bases to a
**virtual merge-base, like merge-ORT**), `gix merge file` for blob content, `--tree-favor` for
irreconcilable tree conflicts, and rename tracking wired through `status.rename`. It is test-driven
to the point its authors call the algorithm's complexity "motivated by a test." It is *younger*
than libgit2 — the plan says so plainly (`§9.3`) and flags the libgit2/cgo fallback honestly — but
"younger and real" beats "older and absent." **This is the variant that delivers my #1.** The plan
under-sells what it has; the Go plan over-sells what it doesn't.

---

## Comparative findings (Severity · Plan · why · fix)

### [Serious · Plan 15] go-git at monorepo scale + the merge gap compound each other.
`15 §12.3` is honest that go-git is unproven at 10M-file scale and has known pack-read/memory soft
spots. Fine, flagged, gated (Spike A). But layer it on the merge finding: the variant's two
biggest technical unknowns — *does the merge exist* and *does the store scale behind a mount* — are
**both** in the body you chose specifically to de-risk the body. That's not fatal, but it means the
Go variant's "mature body" framing (`§12.5`) is doing more work than the evidence supports. **Fix:**
demote the "mature, in-tree, real code" language to "mature object model; merge and scale are the
two gates," and gate both in P0.

### [Serious · Both, worse in Go] Mount: GC on the syscall path.
`15 §1.1`/`§12.5` correctly celebrates bazil/fuse being **pure Go, no cgo** — that genuinely kills
the libfuse-FFI/GC-callback hazard that sank the SBCL variant (`14`), and it's a real credit. But
it does not kill the *other* GC problem: every `read()`/`readdir()` through a bazil mount runs in a
goroutine on Go's GC'd heap, and the read path also touches Shen's runtime. Go's GC pauses are
small and getting smaller, but a latency-sensitive VFS serving a syscall storm is exactly where a
stop-the-world tail hurts. `16 §9.5` is right that **Rust has no GC on the IO path** — `gix`/`fuser`/
`tokio` are not garbage-collected, and only the Shen *brain* (off the hot read path by design,
`§5`) has a runtime GC. For a mount, this is a real Rust edge. **Fix (Go):** the content-hash read
cache (`§1.3`) is the mitigation — measure p99/p999 with GC on, under fan-out, in Spike A, and put
the tail-latency number in the plan, not a hand-wave.

### [Good · Both] `fuser` vs bazil/fuse — Rust has the better mount, Go has the simpler dependency.
`fuser` is, flatly, the best-maintained FUSE binding in any of these ecosystems (`16 §9.6`), and it
makes P5 — the riskiest, least-proven phase everywhere else — the *most* solid phase in the Rust
plan. That's a clean win. The one thing bazil/fuse wins is **dependency hygiene**: pure Go, no cgo,
no system libfuse at all. `fuser` still binds the system FUSE library. Neither is a problem;
`fuser` is the better *mount*, bazil is the simpler *build*. The mount itself (the product
experience) goes to Rust.

### [Serious · Both] The Shen↔body boundary — Go's is genuinely easier; Rust's is the existential risk, and `16` says so.
This is where the two plans honestly diverge and both are candid about it. `15 §1.1` is *correct*
that Shen-compiles-to-Go means **no FFI marshaling** — one heap, one GC, values shared in-runtime;
the tax is ergonomics (writing the `gobody/` shims, goroutine-safety of the KL runtime for pure
reads — Spike B), not copying. `16 §1.2`/`§9.1` is *correct* that Shen-dynamic-on-Rust-ownership is
a real impedance mismatch: you reconcile it only by the handle/registry discipline (never let the
two memory models touch), which costs **a copy at the boundary** and a **standing `catch_unwind`
panic-safety obligation on every primitive** — a correctness surface that simply doesn't exist on
the Go side. `16 §9.8`/`§9.1` correctly calls Spike (b) the **go/no-go on the whole thesis**: if
`shen-rust`'s extern-primitive marshaling is clumsy or panic-unsafe, the Rust variant is *worse*
than the SBCL `14`. **So on the boundary, Go is the lower-risk, less-impedance choice — full
stop.** This is the one axis where Go genuinely wins, and it's not small. (It's why my final call,
below, is "Rust, *conditional on Spike b*.")

### [Annoying · Both] Two-language cognitive surface, identical in both.
Both maintain Shen *and* a systems language plus the Shen→KL→IR→{Go,Rust} pipeline (`15 §12.6`,
`16` implied). Same tax both sides. The all-OCaml path (`12`) is still one language/one toolchain
and `12` preferred it for shipping risk for exactly this reason. Neither Shen variant beats OCaml
on maintenance surface; they're tied with each other. Not a differentiator.

### [Good · Both] Restack-on-land is finally written down.
`09 Finding 4` said stacks without restack-on-land are just "`git commit` x3." Both plans now spec
it: `15 §6` and `16 §6.5` both rebase the orphaned remainder per-commit via the real merge
(`merge-tree`/`rs_gix_merge3`), preserve Change-Id across the rewrite, drop already-landed commits
by Change-Id (reusing idempotency), and surface restack conflicts through the **same**
`merge-result` sum type rather than silent drops. This is the Sapling model done right, in both.
**One caveat that lands harder on Go:** restack quality == merge quality (I said this in `09`). If
go-git's rename-aware merge isn't real, **restack-on-rename silently corrupts** — a higher commit's
edits land on a path that moved and either vanish or spuriously conflict. So the merge Showstopper
*doubles* on the Go side via restack. On the Rust side, gix's rename tracking makes restack
rename-correct. Another point to Rust, derived from the same root cause.

---

## Three-sources-of-truth check (my recurring catch)

This is the trap I've hit in every prior round: object store + landed-log + an index that's
*secretly* authoritative (in `09` it was ACLs hiding in SQLite). **Both Shen plans avoid it better
than the OCaml brief did, and they avoid it the same way — credit to both:**

- **ACLs live in trunk**, as homoiconic `policy.shen` (`15 §7`, `16 §2.3`), loaded from the trunk
  tip at each land. That kills the `09 Finding 5` "ACLs secretly authoritative in SQLite" seam
  outright. This is the single best structural improvement over the OCaml brief, and it's *native*
  in Shen (homoiconic policy-as-data) rather than bolted on. Both earn this.
- **One replication substrate**: the LTX/ltx landed-log streams; any query index is a **local,
  rebuildable, never-replicated** projection (`15 §8 C2`, `16 §6.3`). Both state the rule crisply.
- **One atomic land authority**: git commit is truth, the log entry is *derived deterministically*
  in the same critical section (`15 §8 P3`, `16 §4`). No dual-write.

**Which avoids the trap better?** Marginally **Go**, for a non-obvious reason: it reuses the
*entire* `litefs`/`ltx` daemon as the replication system (`15 §0`, `§4`), so the landed-log's
streaming, position-cookie, and apply are all one proven component — fewer moving parts you own,
fewer seams to drift. Rust (`16 §6.1`, `§9.2`) only reuses the LTX *format + checksum chain* and
**builds** the leased-primary + replica streaming itself — more code, more of your own bugs in the
replication layer, more chance a hand-built streamer and the log projection drift. So on *this*
specific axis (avoiding divergence by reusing rather than rebuilding), **Go is cleaner.** It's a
real point for Go and I'm giving it fully. It's just outweighed by merge + mount.

---

## The Shen brain over a git body — taste check

You asked me directly: is the Shen brain adding real value over a git library that already does the
hard part, or is it ceremony? Honest, itemized:

- **ACL-in-trunk as Shen-Prolog + homoiconic policy-as-data: real value, native, keep it.** Self-
  describing-VCS policy with free blame/time-travel, enforced from trunk at land — this is genuinely
  nicer than the bolt-on SQLite-ACL design I hammered in `09`, and Shen's homoiconicity makes it
  fall out naturally. Both plans. This is the brain earning its keep.
- **The land-FSM `datatype` (submitted→admitted→merged→landed) + `lease-witness` capability: real
  value.** Making app-originated split-brain a *compile error* (`15 §3.2`, `16 §2.2b`) is a genuine
  invariant — the storage CAS fence handles the true race, the type handles the whole class of
  "we shipped a stale-leader land." That's the kind of thing types are *for*. Keep it.
- **The merge `datatype` (total `merge-result` sum): good taste, but thinner than advertised.** Over
  a library that already returns clean/conflict, the Shen contribution is **marshaling the library
  result into an unignorable sum type** so the caller must handle every conflict class. That's
  worthwhile — it's exactly the totality the library's API *doesn't* force on you — but it is
  *plumbing over the hard part*, not the hard part. Don't let `15 §3.3`'s prose ("the whole thesis
  in miniature") inflate a `cond` over three tags into deep VCS work. The deep work is in the
  library; on Go, per the Showstopper, some of it isn't there at all.
- **Would a developer's stacked-changes / Change-Id / restack-on-land workflow be nice here?** Yes —
  *if the merge is real.* The workflow spec (`§6`/`§6.5`) is the right one (Sapling/Gerrit), and the
  brain expresses it cleanly. But "nice" is entirely downstream of merge quality: on Rust, restack
  is rename-correct and the workflow is genuinely pleasant; on Go, restack inherits the merge gap
  and the workflow is *nice until someone renames a file mid-stack*, then it's a silent-corruption
  bug report. The brain's workflow taste is good; its pleasantness is hostage to the body's merge.

**Net taste read:** the brain is *not* ceremony — the ACL/policy and land-FSM/lease parts add real,
non-duplicative value over a git library. The merge part is good-taste glue, not deep work, and the
plans (Go especially) over-narrate it. The brain is justified; one plan's body can't back the
brain's merge promise.

---

## Showstopper scorecard — my original three, per variant

| My v1 Showstopper | Plan 15 (Go body) | Plan 16 (Rust body) |
|---|---|---|
| **#1 — No merge (need real 3-way + rename/delete)** | **NOT DELIVERED AS CLAIMED.** Leans on go-git ORT, which go-git's own status lists as a *missing porcelain op*; what ships is a strategy-option struct + merge-base. The rename/structural 80% is unproven-or-absent. The plan's headline reason-to-exist is its weakest evidence. → **Showstopper (this plan).** | **DELIVERED (younger, but real).** gix shipped `merge tree`/`merge commit` (recursive virtual merge-base, ORT-shape) + `merge file` + rename tracking, test-driven through 2025. Younger than libgit2, flagged honestly, libgit2 fallback named. This is the merge I asked for. → **Fixed.** |
| **#2 — No dirstate / O(repo) status** | **Fixed (as honest).** Git-index dirstate in P1, `os.Stat` short-circuit on (size,mtime,ctime,inode), re-hash only suspects → O(changes), works *without* the mount; mount later upgrades via write-tracking (`§8 C5`). Doesn't repeat the `09` overclaim. | **Fixed (as honest), identical mechanism.** `rs_stat` short-circuit, Git-index dirstate in P1, no-mount O(changes), mount upgrades later (`§7 P1`). Same design, same honesty. **Tie.** |
| **#3 — Virtualization last / infeasible** | **Fixed.** bazil/fuse is real, pure-Go, **no cgo** — kills the libfuse-FFI hazard that sank `14`; no-mount-first ordering honest. Residual: Go GC on the syscall path; go-git-behind-a-mount perf unproven (Spike A). | **Fixed, and best-in-class.** `fuser` is the strongest FUSE in any ecosystem; **no GC on the IO path**; P5 (riskiest phase elsewhere) is the *most* solid here. Residual: gix-behind-a-mount perf still gated (Spike a). **Rust wins this one.** |

### Showstopper / Serious counts

- **Plan 15 (Go):** **1 Showstopper** (merge claim vs go-git reality), **3 Serious** (go-git scale ×
  merge compounding; mount GC on syscall path; Shen↔Go boundary — *lower risk than Rust but still a
  real spike*). Plus 1 Annoying (two-language surface).
- **Plan 16 (Rust):** **0 Showstoppers**, **2 Serious** (Shen↔Rust ownership-impedance interop —
  the existential Spike b; mount/merge perf gates — bounded, gix is younger). Plus 1 Annoying
  (two-language surface).

Note the asymmetry honestly: Rust's *one* big risk (interop, Spike b) is **existential to its
thesis** — if it fails, Rust is worse than SBCL `14`. Go's interop risk is *smaller* (no ownership
impedance, no marshaling). So Rust has fewer Showstoppers but a sharper single knife. That's the
real trade, and it's why my call is conditional.

---

## Better VCS: Go or Rust, and why

**Rust (`shenrs-vfs`, plan 16) is the better VCS — conditional on its interop spike (b) passing.**

Why, in my lane (is it a good, fast, pleasant VCS):

1. **Merge — my #1 — actually exists in Rust and doesn't in Go.** This is decisive. The whole point
   of the pivot, twice over, was "use a real merge library." `gix` *is* that library: shipped tree/
   commit/file merge, recursive virtual merge-base, rename tracking, test-driven. go-git, by its own
   maintainers' description, **lacks merge as a porcelain op** — the Go plan narrates a capability the
   library doesn't demonstrably have. A VCS whose merge is real beats one whose merge is a press
   release. And because restack-on-land *is* a merge loop, the merge gap doubles into stacked-change
   corruption on Go. The variant that talked *less* confidently about merge has the *better* merge.

2. **The mount is faster and more pleasant in Rust.** `fuser` is the best FUSE binding here, and
   Rust has **no GC on the syscall path** — for a VFS serving a read storm, that's a real latency
   edge over Go's GC'd goroutine read path. The riskiest phase everywhere else (the mount) is the
   *most* solid in Rust.

3. Both tie on dirstate (same Git-index design, both honest this time) and both beat the OCaml brief
   on the three-sources-of-truth trap (ACLs in trunk) — so those don't break the tie.

**Where Go genuinely wins, and why it doesn't flip the call:** Go has the **easier, lower-risk
Shen↔body boundary** (no ownership impedance, no per-primitive `catch_unwind`, no boundary copy —
one heap, one GC), and Go reuses the **whole litefs daemon** for replication (less code you own,
marginally better divergence-avoidance). Both are real advantages. But a VCS lives or dies on
*merge correctness* and *mount quality*, and Rust wins both — including the exact axis (merge) the
Go plan claims as its headline. Go's wins are in the *plumbing risk profile*; Rust's wins are in the
*product*. I'll take the better product and pay down the interop risk with a spike.

**The condition, stated plainly:** Rust is the call **iff Spike (b)** (`16 §7`/`§9.1`) shows
`shen-rust`'s extern-primitive marshaling is ergonomic and panic-safe across the ownership boundary.
If Spike (b) fails, the Rust interop tax becomes existential and the right fallback is **not** the Go
variant (whose merge is the deeper problem) — it's **all-OCaml** (`12`'s shipping preference, one
language, mature compiler) or **all-Rust without the Shen brain** (gix + fuser directly), keeping
the merge+mount wins and dropping the interop risk entirely. Go would only be preferable if go-git's
merge gap were closed *and* tail-latency under the mount measured acceptable — i.e., if its two
biggest unknowns both resolved favorably, which is a lot of "if."

Run gix's merge against the rename/delete corpus to confirm it holds at your scale, run Spike (b) on
the interop boundary, run go-git's merge against the *same* corpus to confirm the gap I'm flagging —
and if those land where the evidence says they will, build the Rust one.
