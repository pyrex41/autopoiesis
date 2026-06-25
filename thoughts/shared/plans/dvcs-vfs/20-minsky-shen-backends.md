---
date: 2026-06-25
reviewer: Yaron Minsky (persona)
status: review
topic: "Comparative review of the two Shen-brained variants (Shen-on-Go, Shen-on-Rust) against the all-OCaml foundation"
inputs:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/16-plan-shen-rust.md
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
lane: "foundation soundness, type-driven design, whether the functional brain earns its keep, 5-year maintainability, bus-factor"
---

# Minsky Review: Do either of the Shen backends earn their keep over all-OCaml?

## Verdict (one paragraph)

Both plans are honest, well-argued, and — to their authors' credit — they front-load exactly the
right risk in exactly the right spike (the interop boundary). But they are answering a question I did
not ask. My entire prior argument (`11`) was: **use the type system or don't bother.** The deciding
test for a Shen brain is not "is the brain expressive" — it manifestly is — it is **whether the Shen
sequent-type guarantees still bind the values they govern once those values are opaque handles into a
foreign runtime.** And the answer, in both plans, is *partially, and weaker than the all-OCaml
variant.* In the OCaml/Irmin design the land FSM, the `Lease.witness`, the total `merge_tree`, and the
`Acl.proof` and the tree they govern all live in **one** type system; `merge_tree` returns a
`Tree.t` that the *same* checker tracks into `land_`. In both Shen plans the most load-bearing value —
the merged tree — is a **go-git/gix hash string handed back across the boundary**, which Shen's
checker sees only as an opaque `tree`/`hash`. The sequent rule `(merge)` still forces *the caller* to
have produced a `merged-tree` constructor, so the FSM ordering guarantee survives; but the *content*
of that constructor is an unchecked string whose correspondence to "go-git actually produced a clean
merge of these three inputs" is a **runtime hope inside the `gobody`/`prim_gix` shim**, not a
compile-time fact. That is a real demotion from the OCaml story, and it is the same demotion in both
Shen variants. Net: **the Shen brain earns its keep over Go (whose type system is too weak to express
any of this) but does NOT earn its keep over Rust (whose type system can express all of it natively,
in the same runtime as the body, with no boundary).** Shen-on-Rust is, from my lane, close to the
worst cell: it pays a boundary tax AND runs two type systems where one would do, and the redundant one
(Rust's) is the better one. Shen-on-Go is the defensible Shen variant *because* Go can't do the job.
But neither reaches the bar I'd accept at Jane Street over the all-OCaml variant, which remains the
sounder foundation: one language, one type system, one toolchain, types and store co-resident.

---

## The core question, answered directly: does the Shen type discipline survive the host boundary?

This is the crux and I want to be precise, because both plans wave at it but neither states the
consequence sharply.

**What survives the boundary (genuinely):** the *FSM ordering* and the *capability discipline*.
- `advance-merged` cannot be called on a non-`admitted` change; `advance-landed` cannot be called
  without a `lease-witness`. These are guarantees about *the shape of Shen call sequences*, and they
  hold regardless of what Go/Rust does underneath, because the checker runs entirely on Shen terms
  before any host code executes. The `lease-witness` capability (my `11 §2`) and the unforgeable
  `acl-proof` (my `11 §4`) survive **fully** — they govern Shen-internal tokens, not host handles.
  This is real and both plans preserve it correctly.

**What does NOT survive (the demotion):** the *correspondence between a typed Shen value and the host
fact it claims to represent.*
- In OCaml, `merge_tree : base → ours → theirs → (Tree.t, conflict) result` returns a `Tree.t` that
  is *the same `Tree.t`* the object store stores and `land_` consumes. The type tracks a value the
  store understands. There is one type system spanning brain and store.
- In both Shen plans, `merge-tree` calls `gobody.merge-ort` / `rs_gix_merge3`, which returns a
  **string hash** that Shen tags as `merged-tree`. Shen's checker has no idea whether that string is
  a real go-git tree, the *right* tree, or `"deadbeef"`. The tag is applied **inside the adapter**
  (`classify-merge`, `mk-text-conflict`), and the adapter is the trusted boundary. Everything the
  sequent checker "proves" about the merged tree downstream is conditional on the adapter having
  tagged honestly — which is exactly a **runtime hope wearing a compile-time costume.**

So the precise answer to "do the guarantees still MEAN anything": **the structural/ordering half means
exactly what it meant; the value-correspondence half is reduced to trust-the-shim.** This is strictly
worse than the OCaml/Irmin variant, where my Finding 2 abstraction (`Object_store` seam) kept
`Irmin.*` types out of the domain but the values crossing the seam were *still OCaml values the
checker understood* — `hash`, `Tree.t`, `commit_id` are OCaml types, not opaque foreign handles. The
OCaml seam is an *abstraction* boundary inside one type system; the Shen seam is a *runtime* boundary
between two type systems, and the typed side is the weaker, slower one.

**Both plans are equally guilty here.** Go and Rust both return opaque handles; the impedance is
different (Go: GC-friendly, smaller marshaling cost; Rust: ownership boundary, copy + `catch_unwind`
obligation) but the *type-theoretic* demotion is identical. The merged tree is an unchecked string on
both sides.

---

## Comparative findings

Severity: **Blocker** (foundation-disqualifying for this variant) / **Major** (design around it now) /
**Minor** (note).

### Finding A — [Major; both plans] The most load-bearing value (merged tree) crosses the boundary as an opaque, unchecked handle — the sequent checker's central dividend is demoted to shim-trust

**Concern.** `merge-tree` (15 §3.3 / 16 §2.2c) returns `(merged-ok T)` where `T` is a go-git/gix tree
hash *string*. The `(merge)` sequent rule then admits `(advance-merged C T)`. But `T : tree` is
satisfied by *any* string the adapter chooses to tag. The compile-time guarantee "you may only build a
`merged` change from a real merged tree" is, in fact, "you may only build a `merged` change from
whatever string `classify-merge` decided to call a tree."

**Reasoning.** In my `11 §"How to actually use OCaml's type system"` the whole point of making
`merge_tree` total and returning a `Tree.t` was that *the tree the merge blessed is the same tree
`land_` commits* — one value, one type, tracked end to end. Both Shen plans break that chain at the
boundary. This is not fatal (the FSM ordering still holds, idempotency still holds), but it means the
single highest-value type in the design — the one I said in `11` was where "§9-risk-3 gets answered in
your own types" — is now answered in someone else's untyped runtime. The brain proves the *grammar*
of landing; it no longer proves the *referential integrity* of what gets landed.

**Recommendation.** If a Shen variant proceeds, the adapters in `adapters/object-store.shen` /
`shen/object-store.shen` must be treated as **trusted-computing-base code reviewed to a higher
standard than the brain**, with property tests asserting the tag-honesty invariant ("a `merged-ok`
hash, when re-read, is a tree that is the 3-way merge of the three inputs") — `15 §9`/`16 §7` have
merge-totality property tests but **not** a tag-correspondence test; add it. This is the test that
stands in for the type guarantee the boundary took away. It does not restore the guarantee; it
mitigates its loss.

### Finding B — [Blocker for shen-rust as a *foundation choice*] Shen-on-Rust runs two type systems where the better one already spans the body — redundant invariant layer + boundary tax = worst cell

**Concern.** `16` is candid (§9.1, §9.8) that the dominant risk is the Shen-dynamic ↔ Rust-ownership
impedance. But it never confronts the question I care most about: **if Rust already has a type system
strong enough to express the land FSM, the lease capability, the total merge, and the ACL proof —
which it unquestionably does — what is Shen's sequent checker adding that Rust wouldn't, that justifies
running a second, weaker, slower type system across a copy-and-`catch_unwind` boundary?**

**Reasoning.** Every one of my four `.mli` sketches has a direct, idiomatic Rust encoding:
- Land FSM variant → Rust enum with typestate (phantom/`PhantomData` or sealed-trait typestate); the
  `merge`-before-`land` ordering is a standard Rust typestate pattern.
- `Lease.witness` → an unforgeable Rust token type whose constructor is private to a `with_leadership`
  closure; this is *the* canonical Rust capability/RAII pattern, and Rust's `Drop` makes "witness
  cannot outlive the lease" enforceable in a way Shen's GC'd token cannot.
- Total `merge_tree` returning a sum → Rust `Result<Tree, Conflict>` with an exhaustive `match`; and
  crucially, **the `Tree` here would be a real `gix` tree value in the same type system as the merge
  engine** — closing exactly the gap Finding A opens.
- `Acl.proof` → unforgeable Rust struct, private constructor.

So Shen-on-Rust gives you: (1) a boundary tax (copy, registry handles, mandatory `catch_unwind` on
every primitive — a *correctness surface that does not exist in single-language designs*, by the
plan's own §9.1), PLUS (2) a sequent type checker that re-proves, *more weakly* (it loses Finding A's
correspondence) and *more slowly* (Shen's checker is Turing-complete, terse, can loop — `16 §9.7`),
invariants Rust would prove natively, co-resident with the store, with no boundary. That is the
**worst-of-both** configuration in my taxonomy: it is the Shen analogue of the "all-OCaml,
Eio-multicore, Irmin-unabstracted, two-mount" cell I named as the worst in `11 §6` — maximum surface,
redundant machinery, justified by a type story that a single language already tells better.

The plan's defense is the *declarative control plane*: Shen-Prolog ACLs + homoiconic policy-as-data
(`16 §2.1`, §2.3). That is a real and genuine advantage — Prolog for path-scoped deny-wins ACLs is
more expressive than hand-written Rust predicate code, and homoiconic policy-versioned-in-the-repo is
native in Shen and bolt-on elsewhere. **But that advantage lives in the Prolog layer, not the
sequent-type layer.** You do not need Shen's *type* discipline to get Shen's *Prolog* and
*homoiconicity*; and you certainly don't need to run that type discipline over a Rust body whose own
types are better. If the team wants the Prolog control plane, the honest design is Prolog-as-policy-
data *interpreted* by Rust (or an embedded Datalog/Prolog crate), not the whole Shen toolchain
straddling a boundary.

**Recommendation.** Do not adopt Shen-on-Rust as a foundation on the strength of its type system —
that strength is redundant with Rust's and degraded by the boundary. The *only* coherent reason to
pick it is the Prolog + homoiconic policy plane, and that is achievable far more cheaply than a
two-language Shen-on-Rust toolchain. If you want Rust's body and types, write Rust. If you want the
declarative policy plane, embed a policy interpreter in Rust. Shen-on-Rust is the union of two
penalties.

### Finding C — [Major; tilts toward shen-go] For Go, Shen's type discipline is a genuine net upgrade, because Go has nothing to compete with it

**Concern.** The mirror image of Finding B. Go has no sum types, no exhaustiveness, no phantom/typestate
capabilities, no way to make `advance-landed`-without-a-lease a compile error. Go's "type system"
cannot express a single one of my four `.mli`s. So for the Go body, the Shen brain is not redundant —
it is supplying invariant machinery the host *fundamentally lacks*.

**Reasoning.** This genuinely changes the calculus. In `11` I said the procedural land spec "could be
implemented identically in Go and lose nothing" — meaning Go gives you *no* type help, so the
correctness properties stay runtime `if`s and 3am pages. The Shen-on-Go plan (`15`) is precisely the
move that *fixes* that: it puts the land FSM, the lease capability, and the total merge into a type
system that actually has them, and bodies the IO in Go where Go is strong (mature go-git, pure-Go
bazil/fuse, litefs/ltx as real code). The division of labor is honest: **Shen supplies the types Go
cannot; Go supplies the mature body Shen cannot.** Each language covers the other's hole. That is a
real, non-redundant pairing — unlike Shen-on-Rust where both cover the same ground.

The Finding A demotion still applies (merged tree is an opaque hash), so the dividend is *the
structural/capability half*, not the full OCaml dividend. But half a type dividend over a Go body that
otherwise has *zero* is a real gain; half a dividend over a Rust body that already has the *whole*
thing natively is a loss. **This asymmetry is the single most important comparative point in this
review.**

**Recommendation.** If a Shen variant must be chosen, this is the one — see the explicit call below.

### Finding D — [Major; both, worse for shen-go] The Shen sequent checker is a 5-year maintainability liability, and the worse it is the less the body's strength matters

**Concern.** Both plans flag it (`15 §12.4`, `16 §9.7`): Shen's checker is Turing-complete, slow to
compile, terse on errors, and **can loop on a bad `datatype`**. From the Jane-Street "can we maintain
this in five years / can we hire and onboard to it" lens, this is the axis I weight most heavily and
both plans under-weight it relative to the body-maturity wins they emphasize.

**Reasoning.** My positive view of OCaml's maintainability (`11 §5`) was explicitly *conditional on
the types carrying the design with good tooling* — "our internal OCaml is highly maintainable
precisely because the types carry the design." Shen carries the design in types too, but with tooling
that is strictly worse than OCaml's on every axis I named: error quality, compile speed, and
*termination of the checker itself*. A type system that can non-terminate is a type system that can
turn a routine invariant change into an un-debuggable hang for a small team with a thin maintainer
base. OCaml's checker has none of these failure modes. This is not a tie-breaker; it is a structural
reason the Shen *type* layer is a weaker foundation than the OCaml *type* layer regardless of body.

Note the interaction with Finding C: for Go the checker's pain is *worth paying* because there's no
alternative source of these guarantees; for Rust the checker's pain is *pure waste* because Rust's
checker is better and already there.

**Recommendation.** Whichever Shen variant (if any), budget the type-checker compile-time and
loop-risk as a *first-class operational hazard* (both plans defer it to "P6"; it should be a P0 spike
output, because if `datatype` editing is a hanging-checker nightmare the whole brain thesis is in
question). Add a CI guard: every `datatype` change must typecheck within a hard wall-clock budget or
fail the build.

### Finding E — [Major; both] Bus-factor: a two-language Shen-on-host stack is strictly worse than the all-OCaml single stack, and the Shen runtime port is itself the load-bearing thin dependency

**Concern.** Both plans rest on a *stipulated* production-ready `shen-go` / `shen-rust` (`15 §12.4`,
`16 §9.4`). Both correctly identify this as the single assumption the whole edifice sits on. From the
foundation-soundness lane this is the decisive bus-factor fact: you are betting the runtime on a
tiny-maintainer-base KLambda port, *and* you carry a second language and a second toolchain (Shen→KL→
IR→host), *and* the Shen ecosystem is smaller than OCaml's (which is itself small).

**Reasoning.** All-OCaml is one language, one toolchain, one mature self-hosted compiler with a
real (if small) commercial ecosystem behind it and a hiring story I have personally validated at
scale. Both Shen variants are: Shen (tiny) + host (large) + a Shen-on-host port (tiny, stipulated,
load-bearing). My `11 §5` Blocker-adjacent concern was "bus-factor-1 research artifact unless
deliberately bounded." Both Shen plans are *more* exposed on this axis than the all-OCaml design I was
already worried about — they add a whole second language and a thin runtime port on the critical path.
The body maturity (go-git, gix, fuser, litefs) is real and I credit it — but a mature body under a
thin-maintainer brain-runtime is a foundation whose weakest link got *thinner*, not stronger, versus
all-OCaml.

Between the two: shen-go's runtime port story is marginally less fragile *in kind* (Go's GC-friendly
runtime makes a KLambda port more conventional; no ownership impedance, no mandatory `catch_unwind`
correctness surface). shen-rust's port has to reconcile dynamic GC'd values with ownership — a harder
port to write and to trust, and `16 §9.1` admits a failed interop spike makes the variant "strictly
worse than `14`." So on pure runtime-port bus-factor, **shen-go ≥ shen-rust.**

**Recommendation.** Neither clears the all-OCaml bar on this axis. If a Shen variant is chosen anyway,
the `shen-{host}` runtime must be vendored, pinned, and the team must accept they may have to *fork and
own it* — i.e. treat the stipulated runtime as code you maintain, not a dependency you consume. That is
a sobering cost that should be priced in before, not after, P0.

### Finding F — [Minor; both] Body-maturity wins are real and I credit them — they just don't bear on the type question

**Concern.** Both plans lead with the body win: go-git/gix give a real ORT/rename-aware 3-way merge
(answering Torvalds' C5 with code, not hand-rolled diff3); bazil-fuse/fuser give a real mount
(no immature `ocamlfuse`); litefs/ltx(-rs) give real replication; single static binary; no Lwt/Eio
bridge (C3's worst OCaml hazard absent).

**Reasoning.** These are genuine and I will not pretend otherwise — they are real improvements over
the all-OCaml body, and `12 §C5`/`11 §5` did flag OCaml's hand-rolled-diff3 and `ocamlfuse` as soft
spots. But every one of these is a *body* advantage, available to a *pure-Go* or *pure-Rust* build
without any Shen at all. They argue for "use Go/Rust's body," not for "put a Shen brain on top." They
are reasons the OCaml *body* is not the strongest body; they are not reasons the Shen *brain* earns
its keep. Keep the two questions separate — the plans sometimes let the body win launder credit onto
the brain.

**Recommendation.** When deciding, score body-maturity and brain-type-dividend on separate ledgers.
The body ledger favors Go/Rust over OCaml. The brain ledger favors OCaml's *one-type-system* over both
Shen variants. The all-OCaml verdict turns on whether the body soft spots (diff3, ocamlfuse) outweigh
the foundation cost of a two-language Shen stack. My judgment: they do not — diff3-by-hand is a few
hundred reviewable LOC and `ocamlfuse` is a contained P5 risk, whereas a second language + thin runtime
port is a permanent foundation tax.

---

## Ranking of the three as foundations

From my lane — foundation soundness, type-driven design earning its keep, 5-year maintainability,
bus-factor — ranked best to worst:

**1. all-OCaml (with the `11` discipline: types load-bearing, Irmin abstracted, Lwt-first).**
Still the soundest foundation. One language, one type system, one toolchain, one mature compiler.
Types and store co-resident — the merged tree is a `Tree.t` the same checker tracks into `land_`
(Finding A's demotion does not occur). Its weaknesses are *body* weaknesses (diff3, ocamlfuse, Irmin
churn) that are contained by the C1 seam and a few hundred LOC — not *foundation* weaknesses. It
remains my `12` shipping preference and nothing in the Shen plans dislodges it.

**2. shen-go.** The defensible Shen variant. The Shen brain supplies type machinery Go genuinely
lacks (Finding C) — a non-redundant pairing where each language covers the other's hole. Mature Go
body, no FFI marshaling (in-runtime calls), pure-Go fuse, real replication. Demoted below all-OCaml by:
the Finding A boundary demotion, the two-language bus-factor (Finding E), and the worse type-checker
tooling (Finding D). But it is a *coherent* design with a *real* division of labor.

**3. shen-rust.** The worst foundation of the three, despite having the best *body*. It runs two type
systems where Rust's alone — the stronger one — already spans body and would natively express every
invariant (Finding B), so the Shen type layer is redundant *and* degraded by the boundary *and* it
carries a copy-tax + mandatory-`catch_unwind` correctness surface that no single-language design has.
Its real advantage (Prolog + homoiconic policy) does not require the Shen *type* system and is
obtainable far more cheaply. It is the worst cell: boundary tax + redundant-and-weaker type layer,
justified by a body win that argues for *pure Rust*, not for Shen-on-Rust.

> Note the inversion worth sitting with: shen-rust has the **best body** and the **worst foundation**;
> the body strength is exactly why the Shen brain is *least* justified there. A great body does not
> rescue a redundant brain; it indicts it.

---

## If you must pick a Shen backend: Go or Rust, and why

**Go. Decisively, and for a single principled reason: Shen's type discipline is only worth its cost
where the host cannot supply it, and that is true of Go and false of Rust.**

The whole thesis of putting a sequent-typed brain on a foreign body is "the brain supplies invariants
the body's own type system can't." That thesis is *true for Go* — Go has no sum types, no
exhaustiveness, no capability/typestate, so the land FSM, the lease witness, the total merge, and the
ACL proof are real additions Go could never express. It is *false for Rust* — Rust expresses all four
natively, in the same runtime as the body, with no boundary, and (via `Drop`) enforces the lease
lifetime *better* than Shen's GC'd token can. So Shen-on-Rust pays the boundary tax to re-prove,
weakly, what Rust already proves strongly; Shen-on-Go pays the boundary tax to prove what Go cannot
prove at all. Same tax, opposite payoff.

Two secondary reasons reinforce it: (a) the Shen↔Go runtime port is a more conventional, lower-risk
artifact than the Shen↔Rust port that must reconcile dynamic GC'd values with ownership and carry a
mandatory-`catch_unwind`-or-UB obligation on every primitive (Finding E); and (b) shen-go can *reuse*
the whole litefs daemon as real code, whereas shen-rust must *build* leased-primary replication on
`ltx-rs` — more of your own bugs (`16 §9.2`).

The one thing that would flip me to Rust: if the team's actual requirement is "we want Rust's body AND
strong types" — then the answer is **not Shen-on-Rust, it is pure Rust**, and the Shen brain should be
dropped entirely. There is no version of the requirements where Shen-*on*-Rust is the right answer:
either you want the Shen brain (then Go, where it's non-redundant) or you want Rust's types (then pure
Rust, no Shen). Shen-on-Rust falls between two stools.

**And the honest closing caveat, unchanged from `11`:** neither Shen variant clears the bar I'd accept
at Jane Street over the all-OCaml variant. The all-OCaml design keeps the types and the store in one
system, one language, one toolchain — and that single-stack coherence is worth more than the Shen
brain's expressiveness or even the Go/Rust body's maturity. If the team has no OCaml depth and is
choosing among these three on other grounds, pick **shen-go** and pay the boundary demotion knowingly.
If the all-OCaml option is genuinely on the table, take it.

---

## Finding counts

- **Blocker:** 1 (Finding B — disqualifies shen-rust *as a foundation choice*)
- **Major:** 4 (A, C, D, E)
- **Minor:** 1 (F)
- **Total:** 6

3-way foundation ranking: **all-OCaml > shen-go > shen-rust.**
If forced to a Shen backend: **Go** — because Shen's types are a real upgrade over Go's and pure waste
over Rust's.
