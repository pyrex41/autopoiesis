---
date: 2026-06-25
reviewer: Yaron Minsky (persona)
status: review
topic: "OCaml-in-production review of the mvfs OCaml/Irmin direction brief"
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
lane: "OCaml as foundation, type-driven design, Irmin fit/maturity, runtime/concurrency, JS-grade engineering judgment"
---

# Minsky Review: Is OCaml + Irmin the right foundation for `mvfs`?

## Verdict (one paragraph)

**Conditional yes on OCaml, conditional no on Irmin-as-load-bearing-core, and a hard no on OCaml 5 + Eio + an Lwt bridge as a day-one production bet.** OCaml is a genuinely good language for the *brain* of this system — the land FSM, the trunk/commit/change-id model, the ACL evaluator, the merge-result types. That's exactly the correctness-and-maintainability-sensitive control logic where I have, repeatedly and at Jane Street's scale, chosen OCaml over a systems language and not regretted it. But the brief has the dependency stack upside down: it treats *Irmin* as the de-risking move (the thing that "eliminates 12-18 months") and treats *types* as an afterthought it doesn't even sketch. In reality Irmin is the single largest source of long-term risk in this design — it is a Tezos-shaped library with quarterly breaking changes and on-disk format migrations, internally Lwt, not used the way you intend to use it (concurrent multi-reader VFS), and you do not control it. Meanwhile the brief describes the parts OCaml is *actually best at* — making illegal states unrepresentable — in a language-agnostic way that throws away the reason to pick OCaml at all. My recommendation: **pick OCaml for the control plane and the type-driven domain model; abstract Irmin behind a narrow `Object_store`/`Merge` interface you own (do not let `Irmin.*` types leak into your domain); and ship on the boring runtime you can actually operate today — OCaml 5 in single-domain or domain-pinned mode with Lwt, or `lwt_eio` only behind a measured spike, not on the critical path of P0.** If you cannot commit to abstracting Irmin and to encoding the land/leadership invariants in the type system, then the OCaml choice is not buying you anything a focused Rust build (with the `litevfs` precedent, better FUSE/perf story, and a team that exists) wouldn't buy you more cheaply — and at that point Rust is the more honest call.

---

## Findings

Severity scale: **Blocker** (do not proceed without resolving) / **Major** (will hurt, design around it now) / **Minor** (note and revisit).

### Finding 1 — [Major] The brief sells OCaml for de-risking but never uses OCaml's actual strength: the type system

**Concern.** Read §5 (the land FSM), §6 (single-leader landing), §7 (ACLs). Every one of them is described as a *procedure* — "claim head of queue → OCC base-check → merge → append log → notify", "deny-wins longest-prefix", "leader lands, replicas are read-only." Not one of them is described as a *type*. There is no variant type for land states, no phantom-typed token for "I hold the lease," no total `merge` signature, no proof-carrying "this change has passed admission." This is a language-agnostic procedural spec that happens to mention OCaml. You could implement it identically in Go and lose nothing.

**Reasoning.** The entire reason to pay the OCaml tax — smaller hiring pool than Go/Rust, an ecosystem one-tenth the size, FFI friction for FUSE/libgit2 — is that OCaml lets you make illegal states unrepresentable, so whole classes of bug become compile errors instead of 3am pages. If your design doesn't cash that in, you're paying the tax with no return. Worse: the most dangerous bug in this entire system — a **stale leader landing a commit** (Kingsbury's split-brain) — is described in §6 as a runtime lease check. In OCaml that should be a *type* you cannot construct without a live lease witness. The brief leaves the single highest-severity correctness property as a runtime `if`.

**Recommendation.** Before P0 freezes, produce a `domain.mli` that encodes the load-bearing invariants as types (sketches in the "How to actually use OCaml's type system" section below). The land FSM is a variant; "only the leader can land" is a phantom-typed capability; "this change passed admission" is a distinct type from "this change was submitted"; the merge function is total and returns `Merged | Conflict of hunks`. If you can write that `.mli` and the illegal transitions genuinely don't typecheck, OCaml is earning its keep. If you can't, reconsider the language.

### Finding 2 — [Blocker] Betting the storage/merge/history core on Irmin, unabstracted, is the largest risk in the design — and the brief inverts it into the safe choice

**Concern.** The thesis (§1) and the grounding research (§3) frame Irmin as the de-risking move that "eliminates ~12-18 months." The data model (§4) and land FSM (§5) wire `Irmin.merge_into`, `Irmin.Contents.S`, and irmin-pack commits directly into the domain. The brief never proposes an abstraction boundary. §9 risk 7 even asks the question — "is Irmin's API churn an acceptable dependency?" — and then doesn't answer it.

**Reasoning.** I want to be precise, because this is the crux of my lane. Irmin is good software. But consider what you are actually betting on, from your own grounding research (§3):

1. **It is a Tezos artifact, not a product library.** Tezos is its single flagship, it's a *deep ledger tree with sequential single-writer writes*, and even your own research flags that irmin-pack is "*not* proven at 10M-file/500k-commit monorepo scale" and has "no built-in sparse/partial-clone-by-path network primitive." Your headline use case — §9 risk 1, "thousands of concurrent client reads of different path subsets behind a FUSE mount" — is precisely the workload Irmin has not been validated for. You are betting your read path on an unproven axis of someone else's database.
2. **Quarterly breaking changes and on-disk format migrations.** §3 says it plainly: "minor-version API churn is real — budget for it." For a *product* you intend to operate for years storing developers' source history, an upstream that does on-disk format migrations on its own cadence is a recurring, unbounded liability. At Jane Street the reason we build so much in-house is exactly this: we will not put a load-bearing dependency on a critical path unless we can either control its cadence or cheaply route around it.
3. **The typed-merge model is less load-bearing than the brief assumes.** The brief's §2 maps "Torvalds: no merge" → "Irmin typed 3-way merge." But §3's own caveat is the real story: *for raw blobs the default merge is "conflict if both touched."* Real line-level text merge "still needs a custom content type calling diff3/libgit2 xdiff." So the part you actually need — line-level source merge — **Irmin does not give you**; you write it yourself either way. What Irmin's typed merge gives you is *structural* merge of the tree (renames, deletes, path-level composition), which is real but much narrower than the brief's framing. You are importing a large, churning dependency substantially for the part (CAS blobs/trees/commits/GC) that is the *most* commoditized and the *easiest* to reimplement or vendor, while still hand-writing the hard part (text merge).

**Recommendation.** **Abstract, don't build-on-directly.** Define a narrow interface you own — roughly:

```ocaml
module type Object_store = sig
  type t
  type hash
  val put_blob   : t -> bytes -> hash
  val get_blob   : t -> hash -> bytes option
  val put_tree   : t -> (string * [`Blob of hash | `Tree of hash]) list -> hash
  val get_tree   : t -> hash -> (string * entry) list
  val commit     : t -> parent:commit_id option -> tree:hash -> meta:commit_meta -> commit_id
  val tree_merge : base:hash -> hash -> hash -> (hash, structural_conflict) result
end
```

Implement it *on Irmin* for P0 (so you get the 12-18 months of saved time). Keep `Irmin.*` types out of `domain.mli` entirely. Then Irmin churn is contained to one adapter module, you can reimplement the slice you need if the dependency becomes a liability, and you can swap to irmin-git, a hand-rolled pack store, or even libgit2-via-ctypes without touching the land FSM. This costs you maybe a week up front and buys you optionality on your single biggest risk. Refusing this abstraction is the one thing in the brief I would block on.

### Finding 3 — [Blocker] OCaml 5 + Eio + an Lwt↔Eio bridge is not a day-one production runtime; the integration risk is underestimated

**Concern.** §3 and §9 risk 2 want Eio (effects, multicore, io_uring) for the server, acknowledge Irmin is "Lwt-internally," and propose the `lwt_eio` bridge as the seam — flagged only as a "Minor/operational hazard" question. The brief treats this as a known-solved plumbing detail.

**Reasoning.** I lived the OCaml 5 multicore migration. At Jane Street it took roughly two and a half years, and the painful part was not the language — it was **GC pacing regressions** in a runtime whose collector had been re-architected for parallelism, hitting latency-sensitive code in ways that took deep expertise to diagnose. That was *with* the people who wrote the compiler down the hall and a multi-year runway. You are proposing, for a brand-new product with a small team, to stack three sources of immaturity simultaneously: (a) OCaml 5's multicore GC, still settling; (b) Eio, a 1.0-but-young effects-based IO library; and (c) a **long-lived, multi-domain server running an Lwt event loop and an Eio event loop bridged together** — which is the single most operationally fragile configuration in the OCaml runtime space right now. Effects-based stack unwinding interacting with Lwt's promise scheduling across domain boundaries, under a GC that's still being tuned, in a process that must stay up for weeks holding developers' source: that is not a "week of plumbing" risk. That is the kind of thing that produces a non-reproducible deadlock or latency cliff six months in that nobody on a small team can debug.

**Recommendation.** Run the boring thing in production and treat Eio as an *upgrade*, not a foundation. Concretely:
- **P0-P3 run single-domain, Lwt-native.** Irmin is Lwt; running the whole control plane on Lwt removes the bridge entirely. Single-leader serialized landing (your own §5) does not need multicore — it's serialized *by design*. The land path wants *correctness*, not parallelism.
- **Parallelism where it actually helps** — text merge of large files, hashing, replica fan-out — goes in `Domain`-pinned worker pools with explicit message passing, not a shared-everything Eio rewrite of the core.
- **Eio/io_uring on the read path** (the concurrent-FUSE-read workload) is a legitimate future win, but gate it behind a *measured* spike with a real benchmark and a real rollback story, after P5 when you actually have the mount. Do not put the bridge on the critical path of the first usable system.
- If you truly need effects+multicore on day one, that is itself evidence the workload is systems-shaped enough that **Rust** deserves a second look (Finding 6).

This is the most experience-grounded thing I can tell you: a new product does not get to spend its risk budget on the bleeding edge of its own language's runtime. Spend it on the domain.

### Finding 4 — [Major] The "idempotency in trunk metadata" claim leans on Irmin consistency the brief hasn't characterized

**Concern.** §5 step 4 and §9 risk 5: the idempotency key and change-id live "in the landed-log / Irmin commit metadata (the single source of truth), not a side table," and dedup happens "by reading trunk history." §9 risk 5 then asks whether this is "actually race-free when a client retries during a lease handoff."

**Reasoning.** This is partly Kingsbury's lane, but it has a type-and-API dimension that's mine: "read trunk history to dedup" is only race-free if the *land* operation and the *idempotency check* are a single linearization point. With one leader and a serialized queue that's achievable — but only if the dedup read and the commit-append are inside the same serialized critical section, against the same Irmin store handle, with a defined ordering. The brief asserts the property; it doesn't show the seam. And because Irmin's commit and the landed-log append are *two* writes (§4 distinguishes them), "the single source of truth" is actually two artifacts that must agree, which is the exact dual-authority shape Aphyr flagged in the prior design, reintroduced.

**Recommendation.** Make the landed-log entry and the Irmin commit one atomic step from the domain's perspective — the `Object_store.commit` adapter (Finding 2) should return a commit-id and the log-append should be derived from it deterministically, with one of the two designated the source of truth and the other a rebuildable projection (the brief already says the SQLite index is "derived, rebuildable" — apply the same discipline to the landed-log vs. Irmin relationship). Encode "this change has been landed" as a type produced *only* by that atomic step, so no code path can observe a half-landed state. This also directly de-risks Kingsbury's handoff concern.

### Finding 5 — [Major] Maintenance surface: Irmin + Eio + ocamlfuse + ocaml-9p + ctypes-to-libgit2 + custom merge + lease layer is a bus-factor-1 research artifact unless deliberately bounded

**Concern.** Tally the bespoke/niche surface a small team would own: irmin-pack (churning upstream you don't control), the Lwt↔Eio bridge, ocamlfuse (libfuse FFI, "fiddly" per §3), optionally ocaml-9p, a custom `Irmin.Contents.S` text-merge type wrapping diff3 or ctypes-to-libgit2-xdiff (C FFI with GC-callback hazards), the lease/landed-log/replication layer, and a SQLite index with optional `litevfs` replication. That is a very wide, very deep, very *specialized* surface for "hundreds of developers" of scale.

**Reasoning.** At Jane Street the two questions I ask about any new system are "can we maintain this in five years" and "can we hire and onboard people to it." OCaml passes the second better than its reputation suggests *if the code is type-driven and the surface is bounded* — our internal OCaml is highly maintainable precisely because the types carry the design. But this brief's surface is the opposite: lots of FFI, lots of niche bindings, a churning core dependency, and a runtime configuration (Finding 3) that few people on earth can debug. That's not "maintainable OCaml," that's a research artifact that happens to compile.

**Recommendation.** Cut surface aggressively and in this order: (1) **One mount technology, not two** — pick 9p *or* FUSE for P5, don't carry both as live options; 9p is Lwt-native and avoids the libfuse FFI, which fits Finding 3's Lwt-native stance, so I'd default to 9p unless a concrete requirement forces FUSE. (2) **Pure-OCaml diff3 for text merge before ctypes-to-libgit2** — a diff3 in OCaml is a few hundred LOC, has no FFI/GC hazard, and is far more maintainable than a libgit2 binding; only reach for xdiff if measured performance demands it. (3) **Drop the second replication system** — §9 risk 8 already doubts whether `litevfs`-replicating-SQLite earns its keep; make the landed-log the one replication path and SQLite a pure local rebuildable cache. (4) **Abstract Irmin (Finding 2)** so the churning dependency is one swappable module. Done, the maintainable core is: domain types + land FSM + lease/log + one object-store adapter + one mount + one merge — that a small OCaml team can own. Undone, it's bus-factor-1.

### Finding 6 — [Major] The "OCaml vs. Rust" question (§9 risk 7) deserves a real answer, and the honest one is split-stack

**Concern.** §9 risk 7 explicitly addresses this to me: "Is OCaml+Irmin genuinely lower total risk than a focused Rust build (Rust has the litevfs precedent, better FUSE/perf story, but no Irmin)?" The brief poses it and leaves it open.

**Reasoning.** I'm an OCaml advocate, but my credibility is in honest tool selection, not boosterism, so here's my real read. This system has two halves with opposite tool-fit:
- **The control plane** — land FSM, change-id/commit model, merge *result* logic, ACL evaluation, lease state machine. Correctness-critical, invariant-heavy, low raw-throughput. **OCaml wins decisively here** *if and only if* you do Finding 1 (encode invariants in types). This is the Jane-Street sweet spot.
- **The data plane** — FUSE/9p syscall handling, page/blob byte-twiddling, lazy fetch, concurrent multi-reader IO, perf-critical paths. **Rust wins here**: better FUSE story, io_uring without an effects-runtime gamble, no Lwt/Eio bridge, and — crucially — **the `litevfs` precedent already exists in Rust** per §1 of the grounding research. This is exactly the heavy-FFI/syscall/perf domain where OCaml's advantages are weakest.

The brief's choice to do *everything* in OCaml maximizes the data-plane risk (Findings 3, 5) to keep the control plane in OCaml. The brief's choice to do everything in Rust would sacrifice the type-driven control-plane clarity OCaml gives nearly for free.

**Recommendation.** Two legitimate paths, and I'd want the team to choose deliberately rather than default:
- **(Preferred) All-OCaml, but only if Findings 1-3 are accepted** — types load-bearing, Irmin abstracted, boring Lwt runtime first. Then OCaml's control-plane win pays for the data-plane friction, and you keep one language/one toolchain (a real maintainability asset for a small team).
- **(Equally honest) Rust data plane + OCaml control plane, talking over a narrow protocol.** You reuse the Rust `litevfs`/FUSE precedent for the mount and replication transport, and keep the land FSM / merge-result / ACL / type-driven domain in OCaml. The cost is a two-language build and an IPC seam; the benefit is each half in its best tool. Given that the brief *already* names `litevfs` (Rust) as reusable, this is less of a leap than it sounds.

What I would *not* endorse is "all-OCaml, Eio-multicore, Irmin-unabstracted, two mount techs" — that's the worst cell: maximum runtime risk and maximum maintenance surface, justified by a type-driven story the brief never actually tells.

### Finding 7 — [Minor] irmin-pack concurrency behind a multi-reader VFS is an unvalidated assumption, not a footnote

**Concern.** §9 risk 1 raises it; nothing in the design accounts for it. irmin-pack's read/concurrency model (append-only pack + index, GC windows) under thousands of concurrent path-subset reads is unknown.

**Reasoning.** This compounds Finding 2: not only is Irmin churning, its *one* validated workload is the opposite of yours (sequential single-writer vs. concurrent multi-reader). irmin-pack's GC and its index are designed around the ledger pattern. A FUSE mount that fans out reads across many domains/connections may hit lock contention or index hotspots that simply weren't on the Tezos path.

**Recommendation.** This is a P0/P1 *spike*, not a P5 discovery. Before committing the read path to irmin-pack, benchmark concurrent random-path reads at your target fan-out against a held-out store, with GC running. If it doesn't hold, the `Object_store` abstraction (Finding 2) is what lets you put a read-optimized cache or alternative backend in front without redesigning. Make this a gating experiment, not an open risk you ship into.

---

## How to actually use OCaml's type system here

This is the section the brief is missing, and it's the whole argument for OCaml. If these `.mli` shapes don't end up in the codebase, the language choice isn't earning anything. Sketches, not final designs.

### 1. The land FSM as a variant — illegal transitions don't typecheck

The brief describes land as a procedure. Make it a type where every state carries exactly the data that state can have, so you cannot, e.g., append to the log before the merge succeeded:

```ocaml
(* A change moves through states; each state is a distinct type.
   You physically cannot call [append_log] on a [Submitted] change. *)

type submitted    (* phantom tags *)
type admitted
type merged
type landed

type _ change =
  | Submitted : { change_id : Change_id.t; base : Commit_id.t;
                  paths : Path.Set.t; idem_key : Idem_key.t } -> submitted change
  | Admitted  : { change_id : Change_id.t; base : Commit_id.t;
                  paths : Path.Set.t; acl_ok : Acl.proof } -> admitted change
  | Merged    : { change_id : Change_id.t; tree : Tree_hash.t;
                  onto : Commit_id.t } -> merged change
  | Landed    : { change_id : Change_id.t; commit : Commit_id.t;
                  seq : Landed_seq.t } -> landed change

(* Transitions are the ONLY way to advance a state, and each demands its precondition. *)
val admit  : submitted change -> Acl.proof -> (admitted change, Reject.t) result
val merge  : admitted change -> onto:Commit_id.t ->
             (merged change, Merge.conflict) result        (* total: see #3 *)
val land_  : leader:Lease.witness ->                       (* see #2 *)
             merged change -> landed change                (* atomic commit+log: see Finding 4 *)
```

Now: you cannot `land_` something that wasn't `merge`d; you cannot `merge` something that wasn't `admit`ted; the `Acl.proof` is *unforgeable* (it's only produced by the ACL evaluator), so "landed without ACL check" is not a representable program. The brief's procedural §5 becomes a sequence of total functions where the compiler enforces the order.

### 2. "Only the leader can land" — a stale-leader land is a compile error, not a runtime check

This is the single most important type in the system, and it directly serves Kingsbury's split-brain concern. The lease is a *capability*: you cannot call `land_` without a `Lease.witness`, and a witness cannot outlive the lease.

```ocaml
module Lease : sig
  type witness                          (* abstract: cannot be forged or stored *)

  (* The witness is only available INSIDE the callback, for the duration the lease
     is provably held. It cannot escape (use a region/rank-2 style guard). *)
  val with_leadership :
    t -> (witness -> 'a Lwt.t) -> ('a, [`Lost_lease | `Not_leader]) result Lwt.t
end

(* land_ demands the witness — see #1. There is no land_ that doesn't. *)
val land_ : leader:Lease.witness -> merged change -> landed change
```

Because `Lease.witness` is abstract and only handed to the callback under `with_leadership`, a code path that lands without currently holding the lease *does not compile*. A stale leader cannot construct a `witness`. This converts the brief's runtime "leader lands, replicas are read-only" convention into a type-level guarantee — exactly the "make the dangerous state unrepresentable" move that is the reason to use OCaml. (You still need fencing tokens at the storage layer for the *truly* concurrent case — that's Kingsbury's lane — but the application can no longer be the source of a split-brain land.)

### 3. Merge as a total function returning a sum, never an exception or a bool

The brief says "clean merge → commit; conflict → reject." Encode that the *only* two outcomes are merged-tree or structured-conflict — no exceptions, no nulls, no "merge sometimes throws":

```ocaml
type conflict =
  | Text_conflict of { path : Path.t; hunks : Hunk.t list }
  | Structural    of { path : Path.t; kind : [`Rename_rename | `Delete_modify] }

(* Total: every (base, ours, theirs) maps to exactly one constructor. *)
val merge_tree :
  base:Tree.t -> ours:Tree.t -> theirs:Tree.t ->
  (Tree.t, conflict list) result
```

The caller `match`es and the compiler forces both arms — you cannot forget to surface a conflict, and you cannot land a tree the merge didn't bless because `merge_tree` returns the `Tree.t` only on `Ok`. This is also where the brief's §9-risk-3 worry ("does text merge fight Irmin's per-path model?") gets answered *in your own types*: `merge_tree` is yours (Finding 2's abstraction), structural cases are explicit constructors, and the Irmin adapter implements it however it must underneath.

### 4. ACL evaluation produces an unforgeable proof, consumed by admission

The brief stores ACLs as SQLite rows and checks them at two points. Make the *result* of a successful check a value that admission requires:

```ocaml
module Acl : sig
  type proof                            (* abstract: only [check] makes one *)
  val check : Subject.t -> Path.Set.t -> Action.t -> (proof, Denied.t) result
end
(* admit (from #1) REQUIRES an Acl.proof — so "landed without ACL" is unrepresentable. *)
```

Now the TOCTOU surface shrinks to "is the proof still valid at land time," which you make explicit by carrying the proof *into* the serialized land section rather than re-deriving it — and by tagging the proof with the trunk tip it was evaluated against, so a stale proof is detectable by type-carried data, not convention.

### Net

Four small `.mli` files — the land FSM variant, the lease capability, the total merge, the ACL proof — convert the brief's four highest-risk *runtime* properties into *compile-time* ones. That is the OCaml dividend. If the team writes these and the illegal programs genuinely don't typecheck, I'm confident in the OCaml call. If the team finds itself unable or unwilling to express them this way, that's strong evidence the OCaml tax isn't buying anything and Rust (Finding 6) is the more honest choice.

---

## Irmin: build on / abstract / reimplement

**Call: abstract it — build on it underneath the abstraction for P0, keep the option to reimplement the thin slice you actually need.**

- **Don't build directly on it.** Letting `Irmin.merge_into` and `Irmin.Contents.S` and irmin-pack commit handles leak into the domain (as §4/§5 currently do) couples your product's lifetime to a Tezos-cadenced upstream that does on-disk format migrations on its own schedule. That's an unbounded liability for a years-long product storing developers' source. (Finding 2.)
- **Don't reimplement up front.** Reimplementing CAS + Merkle trees + commits + GC + sync to start is exactly the 12-18 months the brief is right to want to skip. Irmin's value is real *for the commoditized layer*.
- **Do abstract.** Put the narrow `Object_store`/`tree_merge` interface (Finding 2) between your domain and Irmin. Implement it on irmin-pack for P0. Three payoffs: (1) Irmin churn is contained to one adapter; (2) the unvalidated concurrency risk (Finding 7) can be addressed by caching or swapping the backend without touching the FSM; (3) if Irmin's cadence or concurrency story ever becomes intolerable, you reimplement *only the object store* (the well-understood part) — not the merge logic, not the FSM, not the ACLs, which are already yours.

The thing to internalize: **Irmin's typed merge is not as load-bearing as the brief assumes** (your own §3 caveat — raw-blob merge is "conflict if both touched," real text merge is yours regardless). So you are importing a large churning dependency primarily for the *easiest* layer to replace, while hand-writing the hard layer. That asymmetry is the whole argument for keeping Irmin at arm's length behind an interface you control.

---

## Summary for the panel

- **OCaml: conditional yes** — excellent for the control plane *if* Findings 1 and the type sketches are adopted; pointless tax if they aren't.
- **Irmin: abstract, don't bet-the-core-on directly** — Blocker (Finding 2) until there's an `Object_store` seam you own.
- **Runtime: Lwt-native, single/pinned-domain first; Eio behind a measured spike, not on P0's critical path** — Blocker (Finding 3) as written.
- **Honest alternative if the type discipline won't happen: split-stack (Rust data plane + OCaml control plane), or just Rust** — Finding 6.

**Finding counts:** 2 Blocker, 4 Major, 1 Minor (7 total).
