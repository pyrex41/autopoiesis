---
date: 2026-06-25
reviewer: "Eitaro Fukamachi (persona)"
status: review
topic: "Implementation-reality review of the OCaml/Irmin direction (07-direction-brief.md), grounded in 06-grounding-research.md"
target: thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
tags: [review, ocaml, irmin, eio, lwt, fuse, packaging, opam, rust, litevfs, dependency-risk, shipping]
---

# Implementation-reality review of `mvfs` (OCaml/Irmin direction) — v2

My lane: will it ship, what breaks in production, dependency/FFI/concurrency/packaging reality.
The consistency model is Aphyr's, the VCS shape is Torvalds', the type/language ergonomics are
Minsky's. I stay out of those. My three earlier Blockers (NFS-in-SBCL, the substrate global lock,
the dynamic-var threading footgun) were all CL-substrate artifacts and are genuinely **gone** with
the pivot — I confirm that cleanly below and do not re-litigate them.

---

## Verdict

**Shippable, with one Blocker and four Significant items to resolve before P0 commits the team to
the stack.** This direction is real engineering, not a demo fantasy. Irmin buys you the single most
dangerous thing to build from scratch — a content-addressed, merging, GC'd, syncing object store —
and it is production-load-bearing under Tezos, which is not nothing. The "borrow ideas, not code"
call is **correct**: I am the CL guy and I am telling you there is nothing in the CL codebase worth
carrying across the language boundary except the four reviews and the data model on paper.

But the brief is honest about its own soft spots and they are the right ones. The single Blocker is
**not** a line of code — it is a governance/dependency posture: you are about to make your entire
storage layer a hostage to one upstream (Tarides) that ships **breaking minor versions and on-disk
format migrations** on a quarterly cadence, and the brief currently has **no abstraction seam, no
pin/vendor policy, and no migration drill** around it. That is the thing that kills shipping
products eighteen months in, long after the demo wowed everyone. Fix the seam and the pin policy in
P0, before you have written enough code to make Irmin's API shape load-bearing, and this ships.

The Lwt↔Eio bridge is a real-but-bounded hazard (Significant, not Blocker — it is plumbing with a
known failure mode, not an unknown). The two-and-a-half replication systems are over-scoped: the
SQLite-via-litevfs second replication path should be **cut to a local rebuildable cache** for v1.
And the FUSE binary + opam-vs-lockfile packaging story has the usual cross-platform sharp edges that
nobody budgets for until the CI matrix is red.

On Rust vs OCaml: I would not overturn the decision, but the honest answer is "it depends on whether
you trust Irmin," and I give the full argument in its own section rather than dodge.

---

## On the "borrow ideas, not code" call (you asked the CL guy specifically)

**Throw the CL code away. All of it. Confirmed, cleanly.** Here is why this is not a sunk-cost
tragedy:

- The CL substrate's value was its homoiconic agent story, not its VCS plumbing. The VCS-relevant
  parts I reviewed last time — CAS keyed by hex strings in an `equal` hash-table, whole-file
  `(unsigned-byte 8)` reads, recursive plist manifests, the single global `store-lock`, the
  dynamic-var threading model — were *exactly* the parts that were going to need rewriting anyway.
  You are not discarding good code; you are discarding the parts I already flagged as the problem.
- **Irmin makes the rewrite a net deletion of code, not a port.** irmin-pack is the CAS + Merkle +
  commit graph + GC + push/pull you were going to hand-roll on LMDB + ironclad. That is the 12–18
  months the research claims, and it is roughly right. Porting CL CAS to OCaml would be porting a
  thing you should not own.
- **The one thing genuinely worth keeping is not code — it's the four reviews and the on-paper data
  model.** The land FSM, the ACL-as-data model, the idempotency-key reasoning, the conflict model:
  those are design assets and they survive the pivot intact. The brief already keeps them. Good.

So: no, there is no reusable CL *code*. There is reusable CL *thinking*, and it is already retained.
This is the rare case where "rewrite in another language" is the right call and not hubris, because
the rewrite is mostly "delete our store, call Irmin's." If the team had built a great network server
or a great FUSE layer in CL I would fight to keep it — they didn't, and CL gave them no FUSE/NFS to
keep. Clean cut. Ship it.

---

## Findings

### 1. [Blocker] Irmin is a single-upstream, quarterly-breaking, format-migrating dependency with no abstraction seam, pin policy, or migration drill in the plan

**Concern.** The research is admirably blunt: irmin-pack has *real minor-version API churn* and
**on-disk format migrations** (irmin-pack has gone through multiple pack-file format versions; the
v2→v3 and the layered-store/GC transitions were not free for downstreams). You are betting the
**entire storage layer** — the part that owns your users' source history, the part you cannot lose a
byte of — on one vendor (Tarides) whose release cadence is driven by Tezos's needs, not yours. As
someone who *maintains* libraries other people build companies on (Woo, Clack, Dexador): I know
exactly what it feels like to be on the *other* side of this, and I am telling you that a quarterly
breaking-change dependency with on-disk format implications, sitting under your most precious data,
with **zero insulation in the current plan**, is the thing that turns into a 3-week unplanned
migration sprint at the worst possible time. The brief lists "Irmin API churn" as an *open risk for
the panel* (§9.7) but the plan itself (§10, P0) has no de-risking line item. That gap is the
Blocker — not Irmin itself, which is good software.

**Recommendation (concrete, do all four in P0):**
1. **An abstraction seam — a narrow OCaml module signature `Object_store` (`module type`) that your
   land FSM and VFS depend on, with `Irmin_store : Object_store` as the only implementation.** Keep
   the surface tiny: `add_blob`, `get_blob`, `read_tree`, `write_tree`, `commit`, `merge_into`,
   `gc`, `push`/`pull`. Do NOT let Irmin's `Irmin.S` signature, its `Tree` API, or its Lwt types
   leak past this seam into your land FSM. This is one afternoon of discipline in P0 and it is the
   difference between "Irmin broke, fix one module" and "Irmin broke, grep the whole codebase."
2. **Pin Irmin exactly (`opam pin` to a tag or commit, recorded in an `opam.locked` lockfile
   committed to the repo).** Never float on `>= x.y`. Upgrade Irmin as a deliberate, tested,
   single-PR event — never transitively.
3. **Vendor irmin-pack's source into the tree (git submodule or `opam-monorepo`/`dune` vendoring)**
   so a Tarides repo move, an opam-repository yank, or an upstream you-must-upgrade-to-keep-CVE-fixes
   situation cannot brick your build. You do not have to *fork* it; you have to be able to *build it
   without the internet* and to *carry a one-line patch* if v1.0 day demands it.
4. **Write the format-migration drill before you have data you care about.** A scripted
   "dump every blob+commit out of Irmin into a neutral format (tar of `hash → bytes` + a commit
   manifest) and re-import" round-trip, run in CI. This is your insurance against a format migration
   you can't take *and* your exit hatch if you ever leave Irmin. The seam in (1) is what makes this
   tractable.

If you do these four, Irmin is a great bet. If you do none, you have built your house on someone
else's release schedule.

### 2. [Significant] The Lwt↔Eio bridge in a long-lived, multi-domain server is an operational hazard — bound it hard, don't let it be load-bearing

**Concern.** Irmin is Lwt-internally; the brief wants Eio (io_uring, multicore, OCaml 5.x) for the
server (§ research). So you run `lwt_eio` to bridge. I lived the monadic-async era (Woo/Clack on
the CL side, and I watch the OCaml async wars closely) and here is the real failure mode: `lwt_eio`
runs the Lwt event loop *inside* one Eio fiber on **one domain**, and it is explicitly **not
safe to drive the same Lwt engine from multiple domains**. So the moment you want Eio's multicore
story (multiple domains serving FUSE/RPC), every call that bottoms out in Irmin (i.e. *all of them*)
must funnel back to the single domain running the Lwt loop. That is fine until it isn't: you have
re-introduced a single-threaded chokepoint — ironically the *same shape* as the CL global
`store-lock` I blockered last time — except now it's hidden inside a bridge instead of a mutex, so
it's harder to see in a profile.

**This is Significant, not a Blocker, because it's plumbing with a known shape, not an unknown.** But
the brief treats "use Eio for multicore" and "use Irmin (Lwt)" as compatible without naming the
funnel. They are compatible; they are not *free*.

**Recommendation:**
- **Architect Irmin as a single-domain service actor, on purpose, named as such.** Run *one* domain
  that owns the Lwt loop and is the *only* thing that touches Irmin. The land FSM is serialized
  anyway (single leader, OCC) so the *write* path funneling to one domain costs you nothing — that
  is a feature, not a bug.
- **The read path is where the funnel hurts** — thousands of concurrent VFS reads. Solve it the way
  it's actually solved: a **read cache/snapshot layer in Eio-land** (an in-memory or mmap'd blob/tree
  cache, populated from Irmin) so the *common* read does not cross the bridge at all. Irmin's
  immutable, content-addressed objects make this cache trivially correct (a hash is a hash forever).
  Cross the bridge only on a cache miss. This is the single most important perf decision in the
  build and it dovetails with Aphyr's read-concurrency worry and the §9.1 risk.
- **Do not chase io_uring on day one.** Eio with the plain epoll/libuv backend is fine for moderate
  scale; io_uring is an optimization, not a requirement, and it adds its own kernel-version-matrix
  pain. Ship on the boring backend, measure, then decide.
- **Alternative worth a spike:** OCaml 5 + Lwt now supports `Lwt_domain.detach` and Lwt itself runs
  fine on OCaml 5. If the Eio multicore upside turns out marginal at moderate scale, **staying
  pure-Lwt and skipping the bridge entirely** removes a whole class of risk. Decide this with a
  one-week spike in P0, not by assumption.

### 3. [Significant] Two-and-a-half replication systems — the SQLite/litevfs second replication path is over-scope; make SQLite a local rebuildable cache for v1

**Concern.** Count the moving storage parts the brief proposes to operate: (a) Irmin object store,
(b) the append-only landed-log, (c) an *optional* SQLite metadata index **replicated via
litevfs/LiteFS**. That third one is a *second, independent replication system* with its own leader
lease semantics, its own catch-up/position-cookie story, its own failure modes — bolted next to the
landed-log which is *already* your replication substrate. Two replication systems means two split-brain
stories, two failover drills, two consistency-cookie reconciliations, and the genuinely nasty one:
**the Irmin store and the SQLite index can diverge** (replica applied landed-log up to seq N but
litevfs streamed SQLite up to seq M≠N), and now your blame/path-history view disagrees with reality.
And the research already notes **LiteFS Cloud was sunset Oct 2024** and litevfs's lazy-fetch backend
"no longer exists as a service" — so the litevfs lineage you'd lean on is itself in a degraded state.

**Recommendation:**
- **For v1: SQLite is a pure local, rebuildable, derived cache. Do not replicate it. Do not use
  litevfs for it.** Each node rebuilds its SQLite index by replaying the landed-log it already
  receives. The landed-log is the *one* replication system; SQLite is a local projection of it,
  exactly the Fossil model the research endorses ("blob store is truth; SQLite is a recomputable
  derived index"). This deletes an entire replication subsystem, an entire class of divergence bugs,
  and a dependency on a sunset service — for the price of a few seconds of index-rebuild on node
  start, which you can checkpoint.
- **Keep the seam so the litevfs path can return later** if HA *reads of the index specifically*
  ever become a measured bottleneck — but that is a P-later optimization, not v1 architecture.
- **Honestly:** the only reason litevfs is in this brief is that the user owns it and it would be
  satisfying to reuse. That is not an engineering reason. Reusing your own thing where it doesn't
  fit is how products grow a second replication system nobody asked for. If the landed-log replicates
  everything (it can — it's *your* log, you control its schema), SQLite never needs to be replicated.
  Make it a cache.

### 4. [Significant] FUSE binary packaging + the libgit2/diff3 FFI are the two places the build goes hairy; budget the cross-platform matrix now

**Concern.** Two FFI surfaces, each with a classic shipping tax:
- **`ocamlfuse` links libfuse (2 or 3).** Good news: it's maintained and `google-drive-ocamlfuse`
  proves it in production. Bad news, the *shipping* news: you now have a binary that needs `libfuse`
  present at the right major version on every target, needs `/dev/fuse` + `user_allow_other` +
  appropriate mount perms, behaves differently on libfuse2 vs libfuse3, and is **macOS-painful**
  (macFUSE is out-of-tree, kext-signing-gated, and a perennial CI headache). The brief's §9 risks
  don't mention the packaging tail of the mount at all.
- **The diff3/libgit2-xdiff content type** means a C FFI (via `ctypes` or hand-stubbed) into
  libgit2 or a vendored xdiff. C-callback-into-OCaml and the OCaml-5 GC interaction with `ctypes`
  is exactly the "FFI pain" you put me here to flag. It's tractable (`ctypes` is good) but it's
  another native dep on the matrix.

**Recommendation:**
- **Pick libfuse3 and 9p, and ship the no-mount checkout as the real default.** The brief already
  ships no-mount first (correct). Lean into it: the no-mount sparse checkout has *zero* FUSE
  dependency and is the path that works on every box including locked-down CI and macOS dev laptops.
  Treat the FUSE mount as a power-user feature with a *separate* binary/package so the core CLI never
  drags libfuse into its dependency closure. **`ocaml-9p` (mirage, Lwt-native, no C FUSE dep) is
  genuinely the better server-side mount** if you control the client OS (Linux `mount -t 9p`), and
  it sidesteps the libfuse/macFUSE matrix entirely — prefer it.
- **For the merge content type: prefer a pure-OCaml or vendored-C diff3 over linking full libgit2.**
  Linking all of libgit2 to get xdiff is a heavy dependency for one algorithm. Either vendor the
  small xdiff sources directly (it's self-contained C) and `ctypes`-stub just that, or use a pure
  OCaml diff (`patience-diff`/`simple-diff` lineage) and only reach for xdiff if quality demands it.
  Smaller native surface = fewer red CI rows.
- **Build static-ish where you can.** A musl/static-linked CLI for the no-mount core makes
  deployment a copy-one-binary story. The FUSE/9p mount binary can be dynamically linked since it
  needs the kernel module anyway.

### 5. [Significant] Packaging: opam-the-loose-solver vs a committed lockfile — pick the lockfile, and reproduce the build in CI from a cold cache

**Concern.** opam by default resolves the *latest compatible* of everything at install time. For a
product with a quarterly-breaking core dependency (Finding 1), "latest compatible" is a loaded gun:
a fresh `opam install` six weeks apart can pull a different Irmin, a different Eio, a different
`ctypes`, and your reproducible build is suddenly not. The CL world taught me this the hard way —
it's why Qlot exists (a per-project lockfile for Quicklisp). OCaml has the equivalent and the team
must use it.

**Recommendation:**
- **Commit an `opam.locked` lockfile (via `opam lock`) and/or use `opam-monorepo` / `dune`'s
  vendoring + a pinned opam switch.** CI must build from the lockfile, not from a floating solve.
  This is the OCaml analogue of Qlot and it is non-optional for a shipping product.
- **Pin the OCaml compiler version** (a specific 5.x) in the lockfile — Eio and the effect handlers
  are compiler-version-sensitive, and "works on my 5.1, breaks on the CI 5.3" is a real morning.
- **One CI job that builds from a cold cache (empty opam root) on the lockfile alone**, so you find
  out the dependency closure broke *before* a customer does. Add a periodic (weekly) "try to bump
  the lockfile" job so upgrades are a deliberate green/red signal, never an emergency.

### 6. [Nice-to-have] Read-cache + landed-log durability ack is where moderate-scale perf is won or lost — instrument it from P2

**Concern.** Not a blocker, but a "ship well vs ship badly" note. The two numbers that decide
whether this feels good are (a) read latency through the Lwt-bridge funnel (Finding 2) and (b) land
throughput given the fsync-before-ack durability knob (Aphyr's lane, but I own the *measurement*).
The brief asserts single-leader serial landing is "fine" for hundreds of devs (true — LiteFS does
~100 TPS through *FUSE*, and native Irmin commit is faster), but "fine" should be *measured*, not
asserted.

**Recommendation:** From P2, expose two metrics — `land_commit_to_ack_ms` (including fsync) and
`vfs_read_cache_hit_ratio` — and put a load test in CI that lands N changes and reads M paths
concurrently. You want to know the funnel's ceiling on *your* hardware long before a customer finds
it. Cheap to add now, invaluable at P6 hardening.

---

## Rust vs OCaml: what I'd pick, and why (no dodging)

You asked me, the polyglot, to actually answer. Here it is.

**For *this* product, betting on Irmin being real, I'd ship OCaml — but it's a close call decided
almost entirely by one question: do you trust Irmin enough to make it load-bearing?**

The honest trade:

**OCaml's case (why the brief is right):** Irmin is a genuine, rare gift. A content-addressed,
typed-3-way-merging, GC'd, push/pull-syncing object store, production-hardened under Tezos, that you
get as a *library*. There is **no equivalent in Rust.** In Rust you would build the CAS + Merkle +
commit graph + merge + GC + sync yourself, or glue `gix`/`git2` (libgit2 bindings) into doing it —
and `gix` is excellent but it's Git's object model and Git's merge story, not a clean typed-merge
substrate, and you'd still be assembling the pieces the brief gets for free. That's the 12–18 months
the research cites, and it's real. OCaml also gives you a sound, expressive type system that makes
the land FSM and merge content type genuinely safer (Minsky's lane, but I'll grant it from the
shipping seat: fewer 2am bugs). The FUSE/9p story is *adequate* (`ocamlfuse` maintained, `ocaml-9p`
clean).

**Rust's case (why it's genuinely tempting):** Rust has the *better* systems-shipping story on
almost every axis I care about as the packaging/FFI guy. The FUSE story is better (`fuser` is
excellent, actively maintained, no Lwt/Eio bridge nonsense — async is `tokio`, mature and
single-story). The performance story is better and *predictable* (no GC pauses, no effect-handler
surprises). The FFI story is better (`bindgen`, `cxx`, and a culture of vendoring C). **The litevfs
precedent is Rust/Go lineage** — the user's own distributed-SQLite knowledge maps onto Rust more
directly than OCaml. Cross-platform binary distribution is a *solved problem* in Rust
(`cargo`+`Cargo.lock` is the lockfile story OCaml has to assemble from opam-lock+monorepo;
cross-compilation and static musl binaries are routine). Hiring and longevity: more systems
engineers know Rust than OCaml, and that matters for a product that has to be maintained for years.

**Where I land:** The *whole* bet is Irmin. If you believe Irmin is solid enough to de-risk per
Finding 1 (seam + pin + vendor + migration drill), then OCaml is the right call **because not building
the object store is worth more than every Rust advantage combined** — that's the long pole, and Rust
makes you carry it. If Finding 1 scares you — if a quarterly-breaking, format-migrating, single-vendor
core dependency under your most precious data is a risk you can't stomach — then **Rust over `gix`**
is the defensible alternative, and you trade "Irmin churn risk" for "build-the-store cost + own-it-
forever certainty," plus you get the better FUSE/packaging/litevfs-lineage story as a bonus.

My actual recommendation: **OCaml, conditional on executing Finding 1 in P0.** The Irmin leverage is
too large to walk away from, and every other OCaml weakness (FUSE matrix, Lwt/Eio bridge, opam
reproducibility) is *plumbing I've named a fix for above* — bounded, known, shippable. Rust's
advantages are real but they're advantages on the *parts you can survive*, while OCaml's Irmin is an
advantage on the *part that would otherwise sink the schedule*. Pick the leverage; pay the plumbing
tax with eyes open. **But do the one-week pure-Lwt spike (Finding 2) — if Eio's multicore upside is
marginal at moderate scale, dropping the bridge removes the single most OCaml-specific risk and makes
the OCaml choice nearly unassailable.**

(If the team had zero OCaml experience and three strong Rust engineers, I'd flip to Rust — language
familiarity at shipping time beats library leverage you can't drive. The brief should state the
team's existing language depth; it's the missing input that would settle this for real.)

---

## De-risk-Irmin cheat-sheet

A one-page checklist for the Blocker (Finding 1). Do all of it in P0, before code depends on Irmin's
shape.

| # | Action | Tool/how | Why |
|---|--------|----------|-----|
| 1 | **Abstraction seam** — `module type Object_store` that hides `Irmin.S`/`Tree`/Lwt from your FSM & VFS | a `.mli` signature; `Irmin_store` the sole impl | "Irmin broke" becomes a one-module fix, not a codebase grep |
| 2 | **Pin exactly** — no floating `>=` on Irmin | `opam pin` to a tag/commit + committed `opam.locked` | Upgrades are deliberate single-PR events, never transitive surprises |
| 3 | **Vendor irmin-pack source** into the tree | git submodule or `opam-monorepo`/dune vendoring | Survive a repo move, an opam yank, a forced-upgrade; carry a one-line patch if v1 day demands |
| 4 | **Format-migration drill in CI** — dump→neutral→reimport round-trip | script: Irmin → `tar of hash→bytes` + commit manifest → reimport; assert equality | Insurance against an un-takeable on-disk migration; doubles as your Irmin exit hatch |
| 5 | **Single-domain Irmin actor** — one domain owns the Lwt loop, only it touches Irmin | architecture rule + `lwt_eio` on that domain only | Contains the Lwt↔Eio bridge to a place where the write-path serialization is already free |
| 6 | **Read cache in Eio-land** keyed by content hash | mmap/in-mem cache, populated on miss across the bridge | Keeps the common read off the bridge; correct-by-construction (hash is immutable) |
| 7 | **Pure-Lwt spike (1 week)** before committing to Eio | build the read+land path both ways, benchmark | If Eio's multicore win is marginal at moderate scale, drop the bridge entirely |
| 8 | **Lockfile + cold-cache CI build** + weekly bump job | `opam lock` / `opam-monorepo`; pinned compiler | Reproducible builds despite a quarterly-breaking core dep; upgrades are a green/red signal |
| 9 | **Pin the OCaml compiler version** (specific 5.x) | in the switch/lockfile | Eio/effect handlers are compiler-version-sensitive |
| 10 | **Tiny native surface** — vendor xdiff or use pure-OCaml diff; prefer `ocaml-9p` over `ocamlfuse` | `ctypes` only for vendored xdiff; 9p has no C FUSE dep | Fewer red CI rows; smaller dependency closure; dodge the macFUSE matrix |

---

## Summary

- **Verdict:** Shippable. **1 Blocker, 4 Significant** (plus 1 nice-to-have).
- **The Blocker is not Irmin — it's the absence of a de-risk posture around Irmin.** Fix the seam,
  the pin, the vendoring, and the migration drill in P0 and the bet is sound.
- **"Borrow ideas, not code" is the right call.** I'm the CL guy; there's no CL code worth keeping,
  and the ideas/reviews you *are* keeping are the right ones. Clean cut.
- **Cut the second replication system** (SQLite-via-litevfs) to a local rebuildable cache for v1.
- **Contain the Lwt↔Eio bridge** to a single-domain Irmin actor + a content-hash read cache; spike
  pure-Lwt before committing to the bridge at all.
- **OCaml over Rust, conditionally** — the Irmin leverage outweighs Rust's (real) superior
  FUSE/perf/packaging/litevfs-lineage story, *provided* the Blocker is executed. State the team's
  language depth; it's the one missing input that could flip the answer.
