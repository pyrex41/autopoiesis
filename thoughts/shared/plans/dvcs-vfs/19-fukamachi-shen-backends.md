---
date: 2026-06-25
reviewer: "Eitaro Fukamachi (persona)"
status: review
topic: "Shippability head-to-head of the two Shen variants — Shen→Go (15) vs Shen→Rust (16) — for the trunk-only DVCS-VFS"
targets:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/16-plan-shen-rust.md
inputs:
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/10-fukamachi-review-v2.md
tags: [review, shen, shen-go, shen-rust, go-git, gix, gitoxide, litefs, ltx-rs, bazil-fuse, fuser, interop, dependency-posture, shipping, head-to-head]
---

# Shen→Go vs Shen→Rust — a shippability head-to-head

My lane, same as before: will it ship, what breaks in production, dependency/FFI/concurrency/
packaging reality, and — since you asked the polyglot directly — **which one I'd actually pick.** I
stay out of the consistency model (Aphyr), the VCS shape (Torvalds), and the type ergonomics
(Minsky), except where they collide with shipping reality. The Shen *brain* is identical in both
plans and identical to `14`; I do not re-review it. **The whole delta is the body, and the body is my
beat.**

Both plans rest on a stipulated production-ready Shen backend (`shen-go` / `shen-rust`). I honor the
stipulation but I weigh how load-bearing-on-faith each one is, because that is a shipping question.

---

## Headline verdict

**Neither ships as written, and for the *same* reason in mirror-image: each plan asserts its chosen
git library is mature where the public record says otherwise, and each got the merge-maturity
comparison exactly backwards.** The Go plan's entire thesis — "go-git answers Torvalds' no-merge
Showstopper *with real code, not a hand-rolled diff3*" — is **factually wrong**: go-git v6 is in
**alpha** and supports **only fast-forward merge** (no 3-way, no recursive/ORT, no rename detection,
no conflict surfacing). The Rust plan is *more honest* about gix being "younger," but it
**undersells** gix: gix actually has a shipping `gix-merge` / merge-tree in 2025, which is more than
go-git has. So the dependency-posture axis, which the Go plan treats as its trump card, **inverts**.

That correction changes the call. After fixing both plans' factual errors:

- **Shen→Go ships faster** — *but only after a major rewrite of its merge story* (drop "go-git gives
  us ORT," wrap real `git` or accept FF-only for v1), because the trivial-static-binary / cgo-free /
  one-GC / one-heap / reuse-the-real-litefs-daemon advantages are genuine and large.
- **Shen→Rust is the one I'd pick to *live with* for years** — better mount (`fuser`), an actually-
  shipping merge crate (`gix-merge`), no-GC syscall path, one static binary — **but** the
  Shen-dynamic↔Rust-ownership interop tax (handle/registry seam + standing `catch_unwind` on every
  primitive) is a real, permanent ergonomic and correctness drag that the Go variant simply does not
  pay.

**The blunt call (full reasoning in the last section): _ships faster: Go. The one I'd pick: Rust —
narrowly, and conditional on the interop spike (b) passing._** If the team is not willing to own a
panic-safety discipline on every FFI primitive forever, flip to Go.

| Plan | Verdict | Blocker | Significant |
|---|---|---|---|
| **15 — Shen→Go** | Ships, after the merge-claim is rewritten | **2** | **3** |
| **16 — Shen→Rust** | Ships, after the merge-maturity claim is corrected and spike (b) passes | **1** | **4** |

---

## The crux: which interop is less painful to LIVE WITH, day to day

You put me here for this. I have written FFI layers; I will be concrete.

### Shen→Go: the tax is *ergonomics*, and the plan is honest about it

The Go plan's central structural claim is **correct and it is the biggest single thing in its favor**:
because `shen-go` compiles Shen→KL→IR→Go, calling go-git/litefs/bazil-fuse is an **in-runtime call in
one process, one heap, one GC.** There is no C ABI, no marshaling across heaps, no GC-across-FFI
callback hazard. That is categorically the cleanest interop of the three Shen variants (and cleaner
than the OCaml `ctypes`→libgit2 path I flagged in `10`).

The residual tax, named accurately in §1.3/§12.1, is:
1. **Writing the `gobody/` shim layer** — flat, value-oriented KL primitives (strings/bytes/opaque
   handles, no Go generics/interfaces across the seam). This is *real* but it is boilerplate of a kind
   every embedder writes once per call site.
2. **Goroutine-safety of the `shen-go` KL runtime for concurrent pure reads** (Spike B). This is the
   one that could bite: if the KL evaluator is not safe to call from N goroutines even for pure read
   functions, the read path funnels through a serialized evaluator — the same chokepoint shape I
   blockered on the CL substrate and on the OCaml lwt_eio bridge in `10`. The Go-side content-hash
   cache mostly hides it, which is the right mitigation.

**Day-to-day: this is the pleasant one.** A Go panic, a Shen type error, and a KL runtime error are
three failure modes (a tax the plan names in §12.1), but they're all *in one address space with one
debugger and one stack*. You add a primitive, you write a `func(...) (string, error)`, you register
it. That is a Tuesday.

### Shen→Rust: the tax is *ownership impedance + panic safety*, and it is permanent

The Rust plan is admirably candid (§1.2, §9.1) that `shen-rust` **cannot** turn Shen into
borrow-checked Rust. Shen values are dynamic and GC'd; Rust is ownership/aliasing. The reconciliation
is not clever unification — it's a **discipline of never letting the two memory models touch**: the
handle/registry seam (a `HashMap<u64, Resource>` Rust-side, Shen holds only opaque `u64` tokens). This
is exactly the PyO3 `Py<T>` / Neon `JsBox` / magnus `TypedData` pattern. It *works*. I have written
this seam. But living with it costs two things every single day:

1. **A copy at the boundary** for every blob's bytes on the control path. The plan is honest that this
   is mitigated (not eliminated) by keeping the hot VFS read path Rust-side. Acceptable.
2. **`catch_unwind` on *every* primitive, forever.** This is the one I want to underline as a
   *standing correctness obligation*, not boilerplate (§1.5 says exactly this, to the plan's credit). A
   `gix`/`fuser` panic unwinding across the KL FFI boundary is **UB**. So every `rs_*` primitive must
   wrap `catch_unwind` and convert to a Shen `(error ...)`. Miss one — in a codebase that will grow
   dozens of primitives over years, edited by people who didn't write the original — and you have a
   latent UB landmine that a fuzzer or a production input finds at 2am. There is no compiler that
   enforces "you remembered the `catch_unwind`." This is a *review-discipline tax that never ends.*

**Day-to-day: this is the one with the permanent drag.** Every new crate call is "write the marshal,
write the handle plumbing, *don't forget the panic guard*, marshal the result tuple back into the Shen
datatype." Spike (b) in the plan is correctly identified as the go/no-go, but even a *passing* spike
(b) doesn't remove the tax — it just proves the tax is payable.

### Concrete head-to-head on interop

| | Shen→Go | Shen→Rust |
|---|---|---|
| Marshaling cost | None (one heap) | Copy at registry seam (control path) |
| Memory-model impedance | None (both GC'd) | Real (dynamic GC'd ↔ ownership) |
| Per-primitive correctness obligation | Value-oriented signature | **+ `catch_unwind` or UB** (permanent) |
| Concurrency model | goroutines; Spike B for pure-read safety | KLambda single-thread + tokio tasks → 1 mpsc consumer (cleaner *by construction*) |
| Debugging | one address space, one debugger | one address space, but panic/Result/Shen-error all cross a marshal |
| Add-a-primitive friction | low | medium-high (marshal + handle + panic guard) |

**Winner on raw interop pain: Go, decisively.** Go has no borrow checker to offend and no panic-
safety obligation. The Rust plan's *own* §9.6 concedes this ("shen-on-Go pays a smaller interop
tax"). I agree with that sentence completely — it is the single most important true thing in the Rust
plan's self-assessment.

*Caveat that softens it:* the Rust plan's **concurrency** story (§1.4 — KLambda single-thread, all
tokio tasks feed one mpsc consumer drained on the Shen thread) is actually *cleaner and more forced-
correct* than the Go plan's "Spike B: prove the KL runtime is goroutine-safe for pure reads or pool
per-goroutine evaluators." The Go plan has an *open question* on the read path's concurrency; the Rust
plan has *closed* it by construction. So interop-pain favors Go, but concurrency-correctness-by-design
favors Rust. Net on "live with day to day": **Go is less painful per-call; Rust is safer-by-
construction on concurrency.** I weight the per-call pain heavier because it compounds over the life
of the codebase.

---

## Reuse vs build: the litefs daemon (Go) vs ltx-rs replication (Rust)

This is the cleaner of the two big trades and it is **not** as one-sided as the Go plan implies.

**Go reuses the *real* superfly/litefs daemon + ltx + go-git.** Proven, running code. But — the Go
plan buries this — reusing the litefs *daemon* means **a second process and a second failure domain**,
which contradicts the plan's own "one binary, one process" selling point. You can't simultaneously
claim "single static binary, one GC, one heap" *and* "we reuse the litefs daemon" — litefs is its own
FUSE-mounting process with its own lease lifecycle. Either you (a) vendor litefs's *packages* (ltx,
the lease/stream logic) and call them in-runtime — in which case you're not reusing "the daemon,"
you're reusing libraries and you own the integration, much closer to the Rust story than the plan
admits — or (b) you run the actual daemon and you have two processes, two failure domains, two ops
runbooks. **The plan equivocates between these two and counts the benefits of both.** That is the
single biggest piece of optimism in plan 15 after the merge error.

**Rust builds leased-primary replication on ltx-rs.** The plan is honest (§6.1, §9.2): ltx-rs gives
you the log format + checksum chain + apply primitive, and you **build** the leased-primary + replica
streaming on top. More code you own, more bugs that are yours — but **one binary, one failure domain,
no equivocation.** What you write is bounded and it's the part that's *your* product anyway (the
fencing/lease/cookie logic the panel cares about in C4/P1/P2/P4).

**From the shipping seat:** if you want the genuinely-reuse-proven-code advantage, plan 15 has to
commit to running litefs as a separate process and *own that as a real architectural cost* (two
failure domains is a P6 ops tax, not free). If it instead vendors ltx-as-a-library, it has converged
on the Rust plan's "own the distribution logic" posture and lost most of the reuse advantage. The
**honest** Go position is "reuse ltx the library, own the lease/stream glue" — which is ~the same
amount of build work as the Rust plan, just in a language with no ownership tax. The Rust plan's
framing here is *more honest than the Go plan's.*

**Verdict:** reuse-the-whole-daemon is a mirage once you take "single binary" seriously. Realistically
both plans **build the lease/stream/fence glue on a reused log format** (ltx vs ltx-rs). Slight edge
to Go only because ltx (Go) is more battle-tested than ltx-rs (younger), and litefs's lease/stream
*reference implementation* exists to copy from.

---

## Dependency posture (my prior Blocker, restated): which set is more stable/maintained

This is the heart of my lane and where I did the homework. The plans assert maturity; here is the
public record as of mid-2026.

### The merge engine — the plans have it BACKWARDS (the decisive finding)

- **go-git (Go):** v6 is in **alpha**. Its README states it "lacks the main porcelain operations
  **such as merges**." The only implemented `MergeStrategy` is **`FastForwardMerge`** — no 3-way, no
  recursive/ORT, **no rename detection**, no conflict surfacing. **Plan 15's headline claim that
  go-git provides "a purpose-built ORT/recursive 3-way textual merge with rename detection" answering
  Torvalds "with real code" is false.** This is not a nuance; it is the load-bearing premise of the Go
  plan (§0, §3.3, §8 C5, §12.5) and it does not exist in the dependency. (Sources below.)
- **gix / gitoxide (Rust):** actively, well-resourced; ships frequent releases (gix-v0.70+ in 2025).
  `gix status` landed in 2025 *with* rename tracking (`status.rename`/`renameLimit`); `gix merge
  tree` exists and gained `--message` for commit creation/cherry-picks in 2025. It is **younger and
  less complete than libgit2**, and `gix blame` rename-tracking is still missing — but a real
  merge-tree exists. **Plan 16's framing ("gix's 3-way merge + rename detection is younger than
  libgit2's") is accurate and appropriately hedged, and it actually *undersells* gix relative to
  go-git.**

**So the dependency-posture comparison the Go plan leans on is inverted.** On the single hardest VCS
obligation (Torvalds' Showstopper, the panel's C5), **Rust's gix is materially ahead of Go's go-git**,
not behind. Plan 15 spent its credibility on the wrong claim.

### FUSE binding

- **bazil.org/fuse (Go):** pure-Go, **no cgo** — this is real and it is a genuine advantage (no
  libfuse on the matrix). But maintenance is **thin**: no published releases, ~40 open issues, low
  recent activity; it reads as maintenance-mode, not actively developed. Not archived, but not
  thriving. For a load-bearing mount you will likely be carrying patches.
- **fuser (Rust):** the strongest FUSE story in any of these ecosystems, actively maintained, the
  de-facto Rust FUSE crate. Plan 16's claim that the mount is "the most solid here" is **correct** —
  this is the clearest single win in either plan, and it lands in exactly the component that was the
  *riskiest* in the OCaml (`ocamlfuse`) and SBCL (`sb-alien` libfuse) variants.

### Replication substrate

- **litefs + ltx (Go):** litefs is **lightly maintained** by Fly now (LiteFS Cloud sunset Oct 2024;
  the OSS repo still gets commits but it is no longer a strategic priority). ltx the format is stable
  and proven. Reusing the *format/library* is fine; betting on the *daemon* as a growing dependency is
  not.
- **ltx-rs lineage (Rust):** younger, less proven than Go's ltx; you build more on top of it. Higher
  build cost, but you own a smaller, more stable surface.

### Net dependency-posture call

| Component | Go set | Rust set | Edge |
|---|---|---|---|
| **Merge engine** | go-git **alpha, FF-only, NO 3-way/rename** | gix: real merge-tree + rename, younger than libgit2 | **Rust (decisively)** |
| FUSE | bazil/fuse: pure-Go/no-cgo but thinly maintained | fuser: best-in-class, active | **Rust** |
| Replication | litefs/ltx: proven but lightly maintained | ltx-rs: younger, build-more | **Go (slight)** |
| Object store (blob/tree/commit CAS) | go-git: solid for plumbing reads | gix: solid, well-resourced | ~Tie |

**Which needs more vendoring/pinning?** Both must vendor+pin (my standing C1 rule). The *Go* set needs
it *more urgently* on two fronts: (1) go-git is alpha — you are pinning a moving target whose merge
you cannot yet use, and (2) bazil/fuse is thinly maintained — you will likely carry patches. The Rust
set's gix moves fast too (pin a tag, expect churn), but it's *forward* churn on a *growing* library,
which is a better kind of churn than pinning an alpha you've outgrown. **My prior Blocker (abstract +
pin + vendor + migration-drill) applies identically to both; both plans correctly include the C1 seam
and the format-round-trip CI drill — good, that survived.**

---

## Build & deploy

Both claim a single static binary. Reality check:

- **Go:** trivially static. `CGO_ENABLED=0` works because **bazil/fuse is cgo-free** (the plan
  correctly notes this — it is the one place go-git's ecosystem genuinely shines for packaging). Cross-
  compile is routine. **This is the best packaging story of any variant**, full stop. *Caveat:* if you
  run the litefs *daemon* separately (see reuse-vs-build above), your "deploy" is now two binaries, not
  one.
- **Rust:** static via musl is routine; `cargo`+`Cargo.lock` is the lockfile story OCaml had to
  assemble by hand (I praised this in `10`). The **no-GC win** is real and it matters *specifically on
  the syscall/mount path* — a VFS serving reads doesn't stall on a runtime GC for IO. Go *has* a GC
  with (small, sub-ms) pauses; for a latency-sensitive mount that is a real, if modest, edge to Rust.
  *Caveat:* the Shen *brain* still has a GC (`shen-rust`'s runtime) — so "no GC" applies to the body/
  IO path, not the control path. The plan states this correctly (§9.5).

**Cross-platform / macOS mount reality** — neither plan addresses this and both should (Significant
for both):
- bazil/fuse is **Linux/FreeBSD-focused**; macOS support via macFUSE is historically weak/abandoned in
  that lineage. macOS dev laptops will not get a working mount easily.
- fuser is also **Linux/FUSE-centric**; macOS needs macFUSE (kext-signing-gated, a perennial CI
  headache, same tax I flagged for `ocamlfuse` in `10`).
- **Both should ship the no-mount sparse checkout as the real default** (as `14`/the OCaml brief did)
  so the core CLI has zero FUSE dependency on macOS/locked-down CI. Neither plan says this loudly
  enough.

**Packaging edge: Go** (cgo-free, single trivial binary, best cross-compile) — *if* it keeps the mount
in-process and doesn't fork a litefs daemon. **No-GC-on-syscall-path edge: Rust.**

---

## The wildcard: which stipulation is less load-bearing-on-faith — shen-go or shen-rust?

This is the right question and the answer is clear.

**A Shen→Go backend is the more plausible mature compiler.** Reasons, from the compiler-shipping seat:

1. **Go's runtime is a GC'd, dynamic-friendly target.** Compiling a dynamic, GC'd Lisp kernel
   (KLambda, ~46 primitives) onto Go's GC and goroutine model is a *natural fit*. Shen values map onto
   Go values, Shen's GC delegates to Go's GC, done. `shen-go` (tiancaiamao) is a real, known project.
   The impedance is **near-zero**, so a "production-ready" claim is *believable* — there's little hard
   part to get wrong.
2. **A Shen→Rust backend must reconcile dynamic GC'd values with ownership/borrow-checking.** That is
   genuinely hard *for the runtime author*, and the plan's own §1.2/§9.1 spends its longest, most
   candid section on exactly this. A "production-ready `shen-rust`" is a *bigger* claim because the
   thing it claims to have solved (a dynamic GC'd `Value` arena living comfortably inside Rust's
   ownership world, with safe FFI to ownership-typed crates) is *the* known-hard problem in embedding
   dynamic languages in Rust. It's solvable (PyO3/magnus prove the *pattern*), but a *Shen-specific*
   mature KLambda-on-Rust runtime is a thinner, more heroic stipulation than a KLambda-on-Go one.

**So the Go plan rests less on faith.** Its load-bearing stipulation (`shen-go` mature) is the more
believable of the two. The Rust plan's stipulation (`shen-rust` mature *and* its extern-primitive
marshaling ergonomic *and* panic-safe — spike (b)) is **more** load-bearing-on-faith. The Rust plan
knows this (§9.1: "if spike (b) fails, this variant is strictly worse than `14`") and is honest about
it. Credit for the honesty; the risk is still real.

**This partially offsets the dependency-posture win Rust earned on merge/FUSE.** Rust has the better
*libraries*; Go has the more believable *compiler stipulation*. That tension is the whole call.

---

## Findings (Severity · which plan · concrete recommendation)

### F1. [Blocker · Plan 15 (Go)] go-git does NOT provide 3-way/ORT merge with rename detection — the plan's headline VCS claim is false
go-git v6 is **alpha**; it implements **only `FastForwardMerge`**; its README states it lacks porcelain
merges. Plan 15 builds its answer to Torvalds' Showstopper (C5) and its "real code, not hand-rolled
diff3" thesis (§0, §3.3, §8 C5, §12.5) on a capability that does not exist in the dependency.
**Recommendation:** rewrite the merge story honestly. Three options, in order of my preference:
(a) **wrap real `git`** as a subprocess for 3-way merge (boring, correct, what everyone actually
ships) and keep the Shen `merge-result` sum type as the totalizing wrapper — *this preserves the whole
brain-makes-it-total thesis while using a merge that exists*; (b) vendor git's `xdiff` (self-contained
C) via cgo for diff3 + write rename detection yourself — but this **reintroduces cgo**, killing the
cgo-free packaging win; (c) accept FF-only for v1 and defer real merge — unacceptable, it *is* the
Showstopper. **Pick (a).** Note this makes the Go plan's merge no more "real code" than anyone else's.

### F2. [Blocker · Plan 16 (Rust)] Panic-safety is a permanent unenforced correctness obligation; spike (b) must gate, and the discipline must be mechanized
Every `rs_*` primitive must `catch_unwind` or a `gix`/`fuser` panic is UB across KLambda (§1.5, §9.1
— the plan names this but treats it as a P0 spike, not an ongoing regime). Over a multi-year codebase
with dozens of primitives, a single forgotten guard is a latent UB landmine.
**Recommendation:** (1) make spike (b) hard-gating as the plan says — good; (2) **mechanize the
discipline so it can't be forgotten**: a single `prim!` macro that *wraps every primitive body in
`catch_unwind` by construction* (no raw `extern fn` allowed; lint/deny on direct registration), plus a
fuzz harness that throws panics through each registered primitive in CI. Make it impossible to add an
unguarded primitive. Without this, the Blocker is "UB ships eventually."

### F3. [Significant · Plan 15 (Go)] "Reuse the litefs daemon" contradicts "single binary, one process, one GC"
§0/§1.1 sell one process/one heap; §4.3/§10 reuse the litefs *daemon* — a second process and failure
domain. The plan counts the benefits of both and the costs of neither.
**Recommendation:** commit to **vendoring ltx + litefs's lease/stream *packages* and calling them
in-runtime** (preserves single-binary; costs you the integration work — be honest that this is build,
not free reuse). If you instead run the daemon, *book the two-failure-domain ops cost explicitly* in
P6. Stop claiming both.

### F4. [Significant · Plan 16 (Rust)] gix is younger than libgit2 for merge/rename; name the fallback cost precisely
gix-merge exists and is real (ahead of go-git) but younger than libgit2; §9.3's fallback to `git2`
(libgit2) **reintroduces a C dep + the GC-callback hazard** the pure-Rust path avoided.
**Recommendation:** pin gix to a known-good tag; build a **merge conformance test suite** (rename/
edit, delete/modify, criss-cross) run in CI against gix *now*, so you know the day gix-merge is
insufficient *before* you're in production. Keep the `git2` fallback **designed but not linked** —
behind the same C1 `object-store` seam — so adopting it is a one-module change, not a re-architecture.

### F5. [Significant · BOTH] Concurrent-reader-behind-the-mount is unvalidated; it's the gating spike, not a P5 discovery
Both plans correctly make this Spike A — good, that survived from my prior P6 obligation. But it is the
same risk that's gone wrong in every variant.
**Recommendation (both):** the C1 `object-store` seam + a content-hash read cache (both plans have it)
is the right insurance; *run Spike A in P0 with GC on and target fan-out* before the design hardens.
For **Go specifically**, fold in the open Spike-B question (is the KL runtime goroutine-safe for pure
reads?) — that's a *combined* gating risk on the read path. For **Rust**, the single-consumer-channel
design (§1.4) already closes the concurrency-correctness question; only raw gix read throughput is at
issue.

### F6. [Significant · BOTH] macOS / cross-platform mount reality is unaddressed; ship no-mount as the real default
Neither bazil/fuse nor fuser gives a painless macOS mount (macFUSE tax for fuser; bazil's macOS
lineage is weaker still).
**Recommendation (both):** ship the **no-mount sparse checkout** as the default core CLI with **zero
FUSE in its dependency closure** (the `14`/OCaml-brief discipline), and treat the mount as a separate
power-user binary/package. Say this loudly in P5. Static-link the no-mount core (musl for Rust,
`CGO_ENABLED=0` for Go).

### F7. [Significant · Plan 15 (Go)] The dependency posture as written is over-optimistic on three of its four pillars
go-git (alpha, no merge), bazil/fuse (thinly maintained), litefs (lightly maintained) are all softer
than §8 C1/§12.5 imply; only ltx-as-format is genuinely solid.
**Recommendation:** restate §12 risks to reflect this — the Go body is **less mature than the plan
claims** on merge and mount; its real, defensible wins are **packaging (cgo-free static binary)** and
**interop simplicity (one heap, no panic tax)**, not library maturity. Lead with the wins that are
actually true.

### F8. [Significant · Plan 16 (Rust)] The `shen-rust` stipulation is the most load-bearing-on-faith of any variant; size it as such
A mature KLambda-on-Rust runtime reconciling dynamic GC'd values with ownership is a *bigger* claim
than KLambda-on-Go. §9.1 is honest; the *plan* should rank this as risk #1, above gix maturity.
**Recommendation:** spike (b) is correctly the go/no-go — keep it, but add a **fallback decision rule
in writing**: "if spike (b) shows marshaling/panic-safety is not ergonomic, fall back to Shen→Go
(smaller interop tax) or all-OCaml (`12`'s shipping preference)." Don't let a failed spike (b) strand
the team.

---

## Which ships faster, and which I'd pick: Go or Rust (no dodging)

**Ships faster: Go.** Once F1 is fixed (wrap real `git` for merge, per my recommendation), the Go
variant has the shortest path to a running v1: trivial cgo-free static binary, the *least* interop
friction of any Shen variant (one heap, no marshaling, no panic-safety regime), the more believable
compiler stipulation (`shen-go` is a natural KLambda target), and a reference replication
implementation (litefs) to copy from. The interop is a Tuesday; the packaging is a copy-one-binary.
The thing slowing it down is *its own merge claim being false* — and the fix (subprocess `git`) is
well-trodden. **Time-to-first-working-trunk-VCS: Go wins.**

**The one I'd pick to live with: Rust — narrowly, conditional on spike (b).** Here's the honest
weighing:

- Rust has the **better libraries on the two hardest components**: `gix` actually has a merge-tree
  with rename detection (go-git has *fast-forward only*), and `fuser` is the best FUSE in any of these
  ecosystems — and the mount was the single riskiest component in every prior variant. The plans got
  this backwards; corrected, it favors Rust.
- Rust gives **one binary, one failure domain, no equivocation** on replication (the Go plan's "reuse
  the daemon" advantage is a mirage once you take "single binary" seriously — F3).
- Rust gives the **no-GC syscall path**, which is exactly where a VFS wants it.

Against that, the **interop tax is real and permanent** (handle/registry + `catch_unwind`-or-UB on
every primitive). That is the thing that would make me hesitate, and it's why my pick is *narrow* and
*conditional*. If F2's mechanization (the `prim!` macro + panic fuzz harness) is done so the panic-
safety discipline is *enforced by construction*, the tax becomes a fixed up-front cost rather than an
unbounded liability, and Rust is the better long-lived product. If the team won't commit to that
discipline — or if spike (b) shows `shen-rust`'s marshaling is clumsy — **flip to Go**, because then
you're paying the interop tax forever for libraries that, while better, aren't worth a permanent UB
risk.

**So:** *Go to ship, Rust to keep* — with the explicit caveat that the Rust pick is only correct if
spike (b) passes and the panic-safety regime is mechanized. And note the meta-point that should worry
you more than either: **both plans asserted library maturity that the public record contradicts** (Go
worse, Rust better than claimed) — which tells me the dependency posture in *both* needs the
vendor/pin/conformance-test discipline from my original Blocker applied with more skepticism than
either plan currently shows.

---

## Relationship to prior reviews
This extends `10` (my OCaml/Irmin v2 review) and the settled obligations in `12` (C1–C5, P1–P7) to the
two Shen variants. C1 (abstract+pin+vendor+migration-drill) survives and both plans honor it — but my
finding is that the *dependency maturity* underneath the C1 seam is mis-stated in both, which is
exactly the class of risk C1 exists to contain. The `12` panel's all-OCaml shipping preference still
stands as the conservative baseline; of the two Shen variants here, **Go ships fastest, Rust is the
better long-term body — and neither is correct as written until the merge-maturity facts are fixed.**

---

## Sources (dependency-posture facts, mid-2026)
- go-git v6 alpha, FF-only merge, "lacks porcelain operations such as merges":
  [go-git releases](https://github.com/go-git/go-git/releases),
  [go-git/v6 pkg.go.dev (MergeStrategy = FastForwardMerge only)](https://pkg.go.dev/github.com/go-git/go-git/v6)
- gix/gitoxide merge-tree + rename-aware status (2025), younger than libgit2:
  [gitoxide crate-status](https://github.com/GitoxideLabs/gitoxide/blob/main/crate-status.md),
  [gitoxide Jan 2025 discussion](https://github.com/GitoxideLabs/gitoxide/discussions/1791),
  [gix-v0.70.0](https://newreleases.io/project/github/GitoxideLabs/gitoxide/release/gix-v0.70.0)
- bazil/fuse pure-Go/cgo-free but thinly maintained (no releases, ~40 open issues):
  [bazil/fuse](https://github.com/bazil/fuse)
- litefs lightly maintained, LiteFS Cloud sunset Oct 2024:
  [litefs](https://github.com/superfly/litefs),
  [Sunsetting LiteFS Cloud](https://community.fly.io/t/sunsetting-litefs-cloud/20829)
- fuser as de-facto Rust FUSE crate: corroborated across gitoxide/Rust FUSE ecosystem listings.
