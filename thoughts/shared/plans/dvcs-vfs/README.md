# metavfs — Distributed Trunk-Based DVCS Virtual Filesystem

Design + review + roadmap for a content-addressable, **trunk-only** (no branches),
monorepo virtual filesystem in the EdenFS / Sapling / Piper mold, built on the existing
Autopoiesis substrate. Distribution is **Raft**; the declarative control plane (ACLs,
admission, conflict-class) is **Shen**, evaluated on the hot path by the lock-free
substrate Datalog engine.

## Documents (read in order)

| Doc | What it is | Status |
|---|---|---|
| [`00-architecture.md`](./00-architecture.md) | The design. CAS + Merkle manifest reuse, linear-trunk demotion of the snapshot DAG, the serialized land queue, the Raft RSM (hashes in the log, **bytes out of band**), the Shen/Datalog policy split, path-scoped ACLs, the NFS-loopback VFS, and the P0–P7 phase sequence. | draft → **to be revised** per the roadmap's G0 deltas |
| [`01-aphyr-review.md`](./01-aphyr-review.md) | Adversarial Jepsen-style review (Kyle Kingsbury persona). Verdict: *salvageable, not broken.* **4 Critical, 7 Major, 2 Minor**, each with a concrete failure history. | review |
| [`02-roadmap.md`](./02-roadmap.md) | Reconciliation. Commits a resolution for each Critical (the **G0 spec gate** that blocks Raft work), assigns the Majors to phases, and lays out the gate-annotated build plan + the `raft-jepsen-tests` strategy. | draft |
| [`03-torvalds-review.md`](./03-torvalds-review.md) | VCS-design review (Linus Torvalds persona). The parts Aphyr couldn't see: **no real merge**, **O(repo) `status` with no dirstate**, virtualization shipped last, missing stacked-changes, whole-file blobs, Raft-before-usable-VCS. 3 Showstopper, 4 Serious. | review |
| [`04-fukamachi-review.md`](./04-fukamachi-review.md) | CL-implementation review (Eitaro Fukamachi persona). **NFS-in-SBCL = invent 4 missing libs (use 9P)**, the **substrate global lock** throttles the VFS, GC/perf hot-path fixes, **shen-cl is a deploy liability**. 3 Blocker, 6 Significant. | review |
| [`05-synthesis.md`](./05-synthesis.md) | **Panel synthesis.** Where the four reviewers independently converged, the **polyglot boundary** (Lisp core vs native edges; Shen as any-language sidecar), the resolved decision log, and the **revised VCS-first phase plan** (merge/dirstate/change-id added; Raft + mount deferred off the critical path). | draft |
| [`06-grounding-research.md`](./06-grounding-research.md) | **Grounding research** (3 parallel passes). LiteFS/LTX/litevfs (distribution pattern, *not* a VCS — page granularity is wrong for source), the distributed-SQLite landscape (use SQLite as a Fossil-style derived index), and **Irmin** (OCaml git-like CAS with real typed 3-way merge, Tezos-proven). | complete |
| [`07-direction-brief.md`](./07-direction-brief.md) | **Clean-build direction** — `mvfs`: a clean OCaml/Irmin trunk-only DVCS-VFS at **moderate scale**. Irmin = CAS+merge+history; LiteFS pattern = leased land-leader + landed-log (no Raft); OCaml FUSE/9P mount; Shen cut. Borrows ideas + the review corpus from autopoiesis, not the code. Written to be attacked by the panel. | draft-for-review |
| [`08-aphyr-review-v2.md`](./08-aphyr-review-v2.md) | Consistency review of the no-Raft direction. Pivot sound; the "linearizable" claim needs a **fencing token** (lease ≠ fence). Orig. Criticals #1/#3 dissolve. 1 Critical, 3 Major. | review |
| [`09-torvalds-review-v2.md`](./09-torvalds-review-v2.md) | VCS-design review. Scorecard: merge **half-fixed/overclaimed** (diff3 + rename/delete still yours), dirstate **relocated** (P1 still O(repo)), virtualization **fixed**. Three-sources-of-truth returns. 1 Showstopper, 4 Serious. | review |
| [`10-fukamachi-review-v2.md`](./10-fukamachi-review-v2.md) | Shippability. Blocker = Irmin **dependency posture** (seam+pin+vendor+migration drill), not Irmin. Cut the 2nd replication system. Rust-vs-OCaml: OCaml conditionally. 1 Blocker, 4 Significant. | review |
| [`11-minsky-review.md`](./11-minsky-review.md) | OCaml/types/Irmin fit. Inverts the risk: **abstract Irmin** (Blocker), **no Eio day-one** (Blocker), **use the type system or don't use OCaml** (with `.mli` sketches), honest alt = **split-stack** (Rust data plane + OCaml control plane). 2 Blocker, 4 Major. | review |
| [`12-synthesis-v2.md`](./12-synthesis-v2.md) | **Panel-v2 synthesis.** Convergences (abstract Irmin; one replication system; Lwt-first; fencing token; close merge/dirstate gaps), surviving problems w/ owners, amended P0, and the **one open decision**: the language/stack fork (all-OCaml / split-stack / all-Rust), which hinges on team language depth. | draft |
| [`13-plan-ocaml.md`](./13-plan-ocaml.md) | **All-OCaml build plan** (`mvfs`). Monday-ready: `Object_store` seam over irmin-pack + pin/vendor/migration-drill, the four domain `.mli` (land-FSM GADT, `Lease.witness`, total `merge_tree`, `Acl.proof`), Lwt-single-domain + 2 gating spikes, 9p mount, landed-log replication + fencing, restack-on-land, P0–P6. | draft |
| [`14-plan-shen.md`](./14-plan-shen.md) | **All-Shen build plan** (`shenvfs`). Same product on shen-cl/SBCL: Shen-Prolog `defprolog` ACL control plane, sequent-calculus `datatype` invariants (stale-leader land = type error), homoiconic policy-as-data; same obligations discharged. Honest verdict: wins the control plane, loses the IO/mount half (assumed ports don't exist; CL FUSE is weak). | draft |
| [`15-plan-shen-go.md`](./15-plan-shen-go.md) | **All-Shen-on-Go** (`shengo-vfs`). Shen brain (plan 14) on a Go body via shen-go: calls **real go-git** (CAS + ORT 3-way merge w/ rename) + **real `superfly/litefs`+`ltx`** (replication) + `bazil/fuse`, one GC/one binary. Eliminates Irmin-churn, hand-rolled diff3, libfuse-FFI, and the Lwt/Eio bridge at once. | draft |
| [`16-plan-shen-rust.md`](./16-plan-shen-rust.md) | **All-Shen-on-Rust** (`shenrs-vfs`). Shen brain on a Rust body via shen-rust: `gix` (rename-aware merge) + **`fuser` (best mount)** + `ltx-rs` lineage (build the leased-primary) + tokio, no GC pauses. Risk: Shen-dynamic↔Rust-ownership interop (handle/registry seam, boundary-copy + `catch_unwind` tax). | draft |
| [`17`](./17-aphyr-shen-backends.md)/[`18`](./18-torvalds-shen-backends.md)/[`19`](./19-fukamachi-shen-backends.md)/[`20`](./20-minsky-shen-backends.md) | **Panel on both Shen backends** (Aphyr/Torvalds/Fukamachi/Minsky), each comparative w/ a go-vs-rust call. Unanimous correction: **go-git can't 3-way merge (v6 alpha, fast-forward only); gix can.** | review |
| [`21-synthesis-shen-backends.md`](./21-synthesis-shen-backends.md) | **Shen-backend synthesis.** Resolves to: **shen-rust is dominated** (Shen redundant over Rust → if you want Rust's body, go pure-Rust; if you want the Shen brain, use Go). Within "all-Shen", **pick Go** + 2 mandatory repairs (vendor a real merge; own the fence). Stronger signal = a values fork: Shen brain (shen-go) / best body (pure-Rust+embedded Prolog) / soundest foundation (all-OCaml). | draft |
| [`22`](./22-ptacek-go-vs-ocaml.md)/[`23`](./23-norvig-go-vs-ocaml.md)/[`24`](./24-hickey-go-vs-ocaml.md) | **Legend panel: shen-go vs all-OCaml** — Ptacek (Fly.io ops/security/LiteFS-insider), Norvig (Prolog-in-Lisp: does the Shen brain earn its keep), Hickey (Datomic prior art: simple-vs-easy). **All three → all-OCaml.** | review |
| [`25-final-verdict-go-vs-ocaml.md`](./25-final-verdict-go-vs-ocaml.md) | **VERDICT (ship-optimized): build all-OCaml** (`13`). shen-go's two headline advantages are false (you reuse ltx's ~200 LOC not the litefs daemon; go-git can't 3-way merge). Steal one idea: **policy-as-data (landed Datalog ruleset)**, not Shen/Prolog. Caveat (Ptacek): the defensible kernel is language-agnostic. | draft |
| [`26-hotpath-perf-architecture.md`](./26-hotpath-perf-architecture.md) | **Hot-path perf for the Shen path.** Crux claim: proving is build-time, running is LuaJIT; one provable Shen source → best host per path; brain decides, nginx serves zero-copy; content-addressing = zero-invalidation caching. | draft-for-review |
| [`27`](./27-agentzh-perf-review.md)/[`28`](./28-fukamachi-perf-review.md)/[`29`](./29-aphyr-perf-review.md)/[`30`](./30-ptacek-perf-review.md) | **Perf panel** (agentzh/Fukamachi/Aphyr/Ptacek). Pattern validated; **"Shen runs near-native on LuaJIT" is false** (interpreted, not JIT'd); the win **isn't Shen-specific** (transfers to OCaml-behind-nginx); + serious security (hash-keyed cache of private content) & consistency (as-of unenforced) gaps — all language-agnostic. | review |
| [`31-synthesis-perf.md`](./31-synthesis-perf.md) | **Perf synthesis.** The read-tier *pattern* is a keeper (adopt into `13`); the **Shen-on-LuaJIT perf bet is not** (JIT premise false → fix removes Shen from the hot path; no delta over OCaml-behind-nginx). **Reinforces all-OCaml.** Carries a panel-hardened serving-tier design (serve tokens, mlcache, kTLS, enforced as-of, trie policy matcher) into plan `13`. | draft |

## The one-paragraph version

Reuse the content-addressed blob store (`content-store.lisp`) and the deterministic Merkle
tree/diff/materialize layer (`filesystem-tree.lisp`) almost verbatim. Forbid branching by
demoting the snapshot DAG to a strictly linear trunk with a single mutable tip; the only
durable write path is a **serialized land queue** (submit → presubmit → claim → rebase/
conflict-check → commit → notify). A **new Raft layer** replicates a tiny state machine
(trunk-tip + ACL ruleset + idempotency keys); immutable CAS blobs replicate **out of band**
of the log and self-verify by re-hash. Shen authors policy; Datalog evaluates it lock-free.

## What the review changed (the four must-fix-first deltas)

1. **One authority for idempotency/claim** — move dedup into the Raft RSM; `take!`/the
   substrate `:land-job` row become non-authoritative scheduling hints.
2. **Byte-durability width** — a land is not acked until its new blobs are on `f+1`
   replicas (blob barrier); GC tracks byte-replica count, not just reachability.
3. **ACL fence in apply** — carry the authorizing acl-version; re-check with pure Datalog
   inside apply so a revoke between check and commit can't be escalated past.
4. **Honest reads** — read-index/quorum reads for the linearizable tip (not a clock lease);
   bounded read-your-writes; stop calling follower reads "linearizable."

These are committed as resolutions in `02-roadmap.md §2` and must land in a revised
`00-architecture.md` before any `packages/raft/` code is written.
