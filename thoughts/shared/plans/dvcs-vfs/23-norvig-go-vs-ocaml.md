---
date: 2026-06-25
reviewer: Peter Norvig (persona)
status: review
topic: "shen-go vs all-OCaml — does the Shen brain (Prolog ACLs, sequent types, homoiconic policy) earn its keep?"
inputs:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/13-plan-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/21-synthesis-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
lane: "simplicity, correctness, and whether the logic-programming / homoiconic cleverness pays for itself"
---

# Norvig Review: Does the Shen brain earn its keep?

## Verdict (one paragraph)

I wrote a Prolog interpreter, a logic engine, and a compiler in Common Lisp, in a book, on purpose,
because the homoiconic/declarative tradition is genuinely powerful and I love it. So believe me when I
say this is **over-cleverness, not genuine value** — for *this* problem, at *this* scale. The Shen
brain is three distinct bets stacked on top of each other (Prolog ACLs, a Turing-complete
sequent-calculus type system, and homoiconic policy-as-data), and only the third is even *interesting*
here, and even it is a feature you could add to the OCaml design in an afternoon without importing a
second language, a second type system, a research-grade compiler, and a bus-factor-of-three ecosystem.
The path-scoped ACL problem is **longest-prefix-match with deny-wins** — that is a `sort` and a fold,
not a resolution engine; dressing it as `defprolog` adds a backtracking search where a total function
would be clearer *and* easier to prove correct. The sequent types buy exactly what OCaml's GADTs
already buy (the four invariants Minsky sketched), but with terser errors, slower compiles, and a
checker that can *loop*. And the whole edifice sits on a single load-bearing stipulation — that
`shen-go` is production-ready — which, the moment you lean on it, I do not believe, and which the
synthesis already shows was wrong about the one thing that mattered most (go-git's merge). **Build the
all-OCaml plan.** It is the simplest thing that demonstrably works, one language end to end, with the
correctness properties already expressed as types and the merge weakness *named and contained* rather
than *claimed and false*.

---

## The fact that reorders everything (and why it sharpens my call)

The synthesis (`21 §2`) records that the panel **unanimously corrected both Shen plans on the single
most important VCS operation**: go-git v6 is alpha and does **only fast-forward merge** — no 3-way, no
ORT, no rename detection. Plan 15's entire headline thesis — "the body is real, mature Go code;
go-git answers Torvalds' no-merge Showstopper *with real code*" (`15 §0`, `§3.3`, `§12.5`) — is
**false as written**. Section 3.3 of plan 15 is built around `gobody.merge-ort` doing "go-git's
purpose-built, battle-tested ORT/recursive merge." That function does not exist.

This matters to *my* lane specifically, because plan 15's whole pitch is "keep the clever brain, get a
boring proven body." If the body's hardest, most load-bearing component has to be *built or vendored*
after all (libgit2-via-cgo, shell-to-git, or porting gix's merge — `21 §4`), then plan 15 is **clever
brain + clever-OR-unproven body**, and the all-OCaml plan's honesty looks much better by comparison:
plan 13 (`§5 P1`, residual risk #3) *already* says "pure-OCaml diff3 is the schedule risk, libgit2 is
the measured escape hatch." Plan 13 told the truth about the hard part; plan 15 told a comforting
falsehood. That is a tell about which document I'd rather build from.

---

## Findings

Severity: **Blocker** / **Major** / **Minor**.

### Finding 1 — [Blocker, shen-go] The headline "reuse a mature merge" claim is false; the chief reason to prefer Go evaporates

Covered above. Plan 15's reason-for-being over all-OCaml on the body axis is go-git's merge + litefs +
bazil/fuse. One of those three (the most important) doesn't deliver. With a real merge to be vendored
anyway, the body advantage shrinks to litefs/ltx and pure-Go FUSE — real, but not enough to justify a
second language *and* a second type system *and* a faith-based compiler. Must be repaired before plan
15 is even comparable; even repaired, it concedes the axis it was built to win.

### Finding 2 — [Major, shen-go] Path-scoped ACLs as `defprolog` is reaching for a logic engine where a fold would do — and is *less* clear, not more

This is the heart of my lane, so I'll be concrete. Look at what the policy actually is (`15 §3.5`):
grants are `(subject-or-group, action, path-prefix, effect)`; the decision rule is "**longest matching
prefix wins; among ties, deny wins**"; membership is a flat lookup. That is not a relational/recursive
problem. It has no transitive closure worth the name (group membership is one hop), no recursive rules,
no unification you couldn't do with equality, no search space. The "resolution" in `resolve-acl` is
literally: collect candidates, take max prefix length, if any tie is `deny` return false. **That is a
`filter` + `maximum` + `any`.** I can write it as a total function in five lines in any language, and
when I'm done I can *read it and see it's right*.

Now look at what `defprolog` does to it. It turns a deterministic decision into a **backtracking
search** (`collect-applies` = "findall over applies+prefixp"), where the *engine's* search order, the
cut semantics, and the interaction of `member`/`grant`/`applies` clauses are now things you must reason
about to convince yourself deny-wins actually holds. The plan even has to bolt a non-logical
`resolve-acl` function *on top of* the Prolog `findall` to re-impose the longest-prefix/deny-wins
total order — because Prolog gives you *a* set of derivations, not *the* decision. So you've paid for a
logic engine and then written the deciding logic in ordinary code anyway. That's the worst of both: the
indirection of resolution **plus** a hand-rolled resolver.

When does the declarative/logic approach pay off? When the rules are genuinely *relational and
recursive* — role hierarchies with inheritance and overrides, delegation chains, "X may approve for Y
if X is in a team that owns a path that transitively contains Z," constraint propagation, or
when you want non-programmers to author rules and you need an explanation/derivation trace for an audit
("why was this denied?"). **A logic engine earns its keep when the *closure* of the rules is the hard
part.** Here the closure is one hop and the hard part is a tie-break ordering — a comparator, not a
search. This problem does not qualify. Plan 13's `lib/acl/predicates.ml` ("longest-prefix, deny-wins,
plain-OCaml evaluator") is the right altitude: it says what it does and you can test it exhaustively.

One steelman, honestly: if path-ACL policy genuinely grows into hour-of-day windows, signed-approver
escalation, and team-of-team inheritance (the example plan 13 itself raises in `shen_oracle.ml`), a
small Datalog/Prolog evaluator *consulted only at land admission, off the hot path* becomes
defensible. Note that's **exactly** plan 13's optional design (`§0` row 9, `§2 acl.mli`): plain OCaml
by default, optional out-of-process Shen oracle behind a flag, never load-bearing, never on a VFS read.
That is the disciplined way to reach for logic programming — pay for it only where it pays you back,
and never on the read path. Plan 15 makes Prolog **load-bearing and on the enforcement path** (`§3 P3`:
"Shen-Prolog becomes load-bearing"), which inverts the right tradeoff.

### Finding 3 — [Major, shen-go] The sequent-calculus types are power you've already got cheaper in OCaml's GADTs

Compare directly. Minsky's `.mli` sketch (`11`, "How to actually use OCaml's type system") and plan
13's `domain.mli` (`§2`) express **all four** load-bearing invariants — land FSM as a GADT with
phantom states, `Lease.witness` as an unforgeable capability, total `merge_tree` returning a sum,
`Acl.proof` as an abstract token only the checker mints. Plan 15's `datatype` rules (`§3.1–§3.4`)
express the *same four* invariants. Same guarantees: illegal land orderings don't typecheck;
split-brain-by-application is unrepresentable; merge is total; ACL proof is unforgeable.

So the question is purely cost, and the synthesis already nailed it (`21 §3`, Minsky): Shen's sequent
types are a **real upgrade over Go** (which has no sum types, no exhaustiveness, no typestate) but
**pure redundancy over OCaml**, which has all of it natively. Plan 15 even lists the cost itself
(`§12.4`): the checker is **Turing-complete and can loop** on a bad `datatype`, errors are **terse**,
and compiles are **slow**. OCaml's GADT exhaustiveness gives you the same "you must handle every
conflict constructor" guarantee with mature tooling, fast incremental compiles, and error messages a
human can act on. The sequent calculus is more *powerful* (it's a full dependent-ish logic), but you
don't need that power here — none of the four invariants needs anything past phantom types + sums +
abstract types. **Choosing the more powerful, less ergonomic tool when the weaker one fully covers the
requirement is cleverness for its own sake.** The line is exactly there: use the strongest type system
your *problem* needs, not the strongest one your *language* offers.

And the synthesis adds the deflating kicker (`21 §3`): the one value the types most want to track — the
merged tree — **crosses the Shen↔Go boundary as an opaque hash** (`15 §1.3` handle discipline). So the
checker's central dividend, value-correspondence between the typed brain and the bytes on disk,
**degrades to shim-trust** at exactly the boundary that matters. You're paying for a research-grade
type system and then handing it an opaque token at the seam. All-OCaml has no such seam: the same type
system spans the domain *and* the Object_store adapter (`13 §2`), so the correspondence is real all the
way down.

### Finding 4 — [Minor→Major, shen-go] Homoiconic policy-as-data is the one genuinely nice idea here — and it is not Shen-specific

I have deep affection for code-as-data, so I want to give this its due. Storing the policy as S-exprs
at `.shengo/policy.shen` in trunk, versioned, content-addressed, going through the same land queue and
ACL gate as code, with blame/time-travel for free (`15 §7`) — that is a *legitimately attractive*
property for a VCS. Self-describing, inspectable, evolvable policy. In Shen it's "native" because the
language is homoiconic and `read-shen-forms` + `eval-defprolog-forms` is the whole implementation.

But here's the thing: **it's a 40-line feature in any language, and a VCS is the one kind of system
where it's trivial** because the substrate is *already* a content-addressed versioned store. Plan 13
already does the structurally identical thing — ACL grants stored **in Irmin under `/.mvfs/acl/`**,
versioned, replicated with the objects, rebuilt into the SQLite index, `Acl.proof` evaluated against
the same tip you land onto (`13 §0` row 2, `§5 P3`). That *is* policy-as-data. The only difference is
that Shen's policy is *also executable as Prolog* without a parse step, whereas OCaml reads a config
format (S-exprs, TOML, a tiny DSL) and interprets it. The "no parse step" saving is real but tiny, and
it comes bundled with "your policy file is now a Turing-complete program in a niche language that few
can read" — which for an *audit-sensitive ACL file* is a downgrade, not an upgrade. I'd rather my
security policy be inert data interpreted by a small reviewed evaluator than a live program. So:
genuinely nice idea, correctly attractive for a VCS, **not a reason to pick Shen** — OCaml gets 95% of
it with versioned grants and the last 5% (executable-without-parsing) is arguably a liability for this
particular file.

### Finding 5 — [Blocker, shen-go] The whole design rests on one stipulation I don't believe under load

Plan 15 is admirably honest in `§12.4` and `§12.6`: "**the whole thing rests on `shen-go` being
production-ready** — a single stipulated assumption that, if false, is fatal." The plan needs the
`shen-go` KL runtime to be (a) goroutine-safe for pure read functions or cheaply pool-able per
goroutine, (b) fast enough that the Shen interpreter on the read path isn't a tax, (c) ergonomic to
register Go shims as KL primitives, and (d) debuggable across the Shen→KL→IR→Go translation when a
panic, a type error, and a runtime error are three different failure modes through a translation layer.
That is four production properties asked of a single-maintainer research compiler. The synthesis
already shows the *body* stipulations were over-optimistic (go-git merge). My prior on the *runtime*
stipulation being equally optimistic is high. "Simplest thing that works" means *demonstrably* works;
this rests on an undemonstrated foundation, and it's the foundation, not a leaf. All-OCaml rests on a
mature compiler used in production for decades — its risks (Minsky's: irmin-pack concurrency, the
Lwt/Eio bridge) are real but they are *named, bounded, and about libraries you can swap behind a seam*,
not about whether the compiler itself is ready.

### Finding 6 — [Major, both, leans shen-go] Two languages and two type systems is more to get correct, not less

Plan 15 concedes this (`§12.6`): the team maintains Shen *and* Go, the `gobody/` shim layer, *and* the
Shen→KL→IR→Go build pipeline. All-OCaml is one language, one toolchain, one type system, one set of
stack traces (Minsky's maintainability point, `11 F5`). My "simplest thing that works" standard cares
about the *total* cognitive surface a small team holds in its head at 3am during an incident. Plan 15's
surface: Shen semantics + the sequent checker's quirks + Prolog resolution order + KL primitive
registration + Go concurrency + the boundary's three failure modes. Plan 13's surface: OCaml + Lwt +
the Irmin adapter. The Shen design isn't *removing* the systems-language concern (Go is still there for
every byte of IO); it's *adding* a declarative layer on top. Adding is the opposite of simplifying. The
one real consolation plan 15 has — "no FFI, one heap, one GC, in-runtime calls" (`§1.1`) — is a genuine
and elegant property, the best thing about the design, but it reduces the *interop* cost, not the
*two-language* cost.

---

## Does the Shen brain earn its keep? (the focused judgment)

Three components, three verdicts:

**Prolog/`defprolog` ACLs — NO, does not earn its keep.** The problem is longest-prefix + deny-wins +
one-hop group membership. That is a comparator and a fold, deterministic, exhaustively testable. Prolog
turns it into a backtracking search and then *still* needs a hand-written `resolve-acl` to recover the
deterministic decision — paying for resolution and re-implementing the decision on top. Logic
programming pays off when the *closure/derivation* is the hard part (recursive roles, delegation,
constraint propagation, audit-explanation). This policy has no such closure. I wrote Prolog-in-Lisp; I
know when to reach for it, and this is below the threshold. The disciplined exception — a small logic
evaluator *only at admission, off the hot path, behind a flag* — is precisely what the **OCaml** plan
already offers as an option (`13 shen_oracle.ml`). Plan 15's mistake is making Prolog load-bearing and
on the enforcement path.

**Sequent-calculus types — NO, redundant here.** They deliver exactly the four invariants OCaml's GADTs
already deliver, at the cost of terser errors, slower compiles, and a checker that can loop, and the
one value they most want to verify (the merged tree) crosses the seam as an opaque hash, degrading the
guarantee to shim-trust. More powerful than the problem needs; that's the definition of over-built. The
sequent calculus would earn its keep if the invariants were genuinely dependent/relational (proofs that
*compute*); the four here are phantom-state typestate + sums + abstract tokens, which is squarely GADT
territory. Use the weakest type system that fully expresses the requirement; OCaml's does.

**Homoiconic policy-as-data — PARTIAL, the one nice idea, but not Shen's to claim.** Versioned,
content-addressed, time-travelable policy is genuinely good for a VCS and I won't pretend otherwise. But
a content-addressed VCS gives you that *regardless of language* (plan 13 stores grants in Irmin under a
reserved path and gets the same property), and Shen's only true differentiator — policy that is *also a
live Prolog program with no parse step* — is, for a security-sensitive ACL file, closer to a liability
than a feature. Nice idea; not a reason to take on Shen.

**Net:** of the three pillars, two are redundant-or-worse against OCaml and the third is replicable
without Shen. The brain is intellectually beautiful — I mean that sincerely, it's the kind of design I'd
enjoy reading — but beauty that doesn't buy correctness or clarity over the boring alternative is
exactly the cleverness I warn people away from.

---

## The call: **all-OCaml**, and why

Build `13-plan-ocaml.md`. Reasons, in priority order:

1. **It is the simplest thing that demonstrably works.** One language, one type system, one toolchain,
   one runtime, one set of stack traces. The invariants Minsky asked for are already expressed as GADTs
   in `domain.mli` (`13 §2`). A small team can hold the whole thing in its head.

2. **Its correctness story is honest where Shen-go's is not.** Plan 13 names the merge weakness
   (pure-OCaml diff3, libgit2 as a measured escape hatch) and the concurrency unknown (irmin-pack
   multi-reader, gated by a P0 spike behind the Object_store seam). Plan 15 *claimed* a mature merge
   that doesn't exist. I trust the document that told me the truth about its hard part.

3. **The Shen brain's three pillars don't pay for themselves here** (the section above). The ACL problem
   is a fold, not a search; the sequent types are GADTs with worse ergonomics; policy-as-data comes free
   with content-addressing. None of the three justifies a second language, a research-grade type system,
   and a single-maintainer compiler on the critical path.

4. **The one thing Shen-go does better — no FFI, in-runtime Go calls — solves a problem all-OCaml
   mostly doesn't have.** OCaml's seam is to Irmin (same language) and to FUSE (plan 13 defaults to
   pure-OCaml 9p, `§1`, sidestepping libfuse). The boundary tax plan 15 elegantly avoids is largely a
   tax all-OCaml doesn't pay in the first place.

**Caveats, to be fair to the alternatives.** (a) If, after a *real* P0 spike, irmin-pack's concurrent
multi-reader story or the Lwt/Eio bridge proves untenable (Minsky's two real blockers), the honest
fallback is **not** shen-go — it's the split-stack or pure-Rust path the synthesis surfaces (`21 §4`):
keep OCaml's typed control plane, put the data plane in Rust with `gix`'s *actually-shipped* merge and
`fuser`. (b) If you are choosing among *Shen* variants only, the synthesis is right that shen-go beats
shen-rust — but that's choosing the best house on a street I wouldn't build on. (c) I'd genuinely steal
*one* idea from plan 15 for the OCaml build: lean into versioned, content-addressed policy-as-data
under a reserved trunk path (plan 13 already does), and keep the optional logic-evaluator escape hatch
for the day ACLs really do grow recursive — exactly where, and only where, the declarative approach
starts to pay.

---

## One-line judgment

The Shen brain is a beautiful piece of engineering that does not earn its keep on this problem: the
Prolog ACLs are a fold dressed as a search, the sequent types are GADTs with worse tooling, and the one
genuinely nice idea — homoiconic policy-as-data — comes free with any content-addressed VCS; build the
boring all-OCaml plan.
