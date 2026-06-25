---
date: 2026-06-25
researcher: Claude
topic: "metavfs implementation roadmap — reconciling the architecture with the Jepsen-style review"
inputs:
  - thoughts/shared/plans/dvcs-vfs/00-architecture.md
  - thoughts/shared/plans/dvcs-vfs/01-aphyr-review.md
tags: [roadmap, dvcs, vfs, raft, shen, cas, monorepo, acl, land-queue, jepsen, plan]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# metavfs — Implementation Roadmap (review-reconciled)

This document turns the **architecture** (`00-architecture.md`) and the **adversarial
review** (`01-aphyr-review.md`) into an ordered, testable build plan. It does three
things:

1. Records the review **verdict** and which findings gate which work.
2. Commits to a **resolution** for each of the 4 Criticals (opinionated — these become
   the revised-spec deltas that must land in `00-architecture.md` **before any
   `packages/raft/` code is written**).
3. Lays out the **phased build sequence** (P0–P7) with per-phase gates, new packages,
   test suites, and SCUD-grain task seeds.

> **Review verdict (verbatim summary):** *Salvageable, not broken.* The load-bearing
> idea — hashes in the Raft log, bytes out of band, verify by re-hash — is correct.
> Two structural errors must be fixed in the spec first: (a) **two sources of truth**
> for claim/idempotency (substrate `:land-job` row vs. Raft log), and (b) **durability
> acked on the wrong event** (metadata quorum + leader-local byte presence → a
> linearizable pointer to bytes that exist on exactly one node). 4 Critical, 7 Major,
> 2 Minor findings.

---

## 1. Gate model

Work is gated in three tiers, mirroring the review's prioritization:

| Gate tier | Meaning | Blocks |
|---|---|---|
| **G0 — Spec gate** | The 4 Criticals. Must be resolved in a revised `00-architecture.md` (`status: revised`) **before** the Raft phase (P3) is implemented. | P3, P4 |
| **G1 — Phase spec** | The 7 Majors. Must be specified *in the phase that introduces the surface*, before that phase is called done. Documented-caveat is acceptable for an earlier prototype phase. | the owning phase's "done" |
| **G2 — Caveat** | The 2 Minors + the in-memory-store/no-durability-claim posture. Acceptable for v1 with a written caveat; no land may be advertised as durable until G0-#2 ships. | nothing (documentation only) |

The spine **P0 → P1 → P3** cannot proceed into P3 until G0 is closed. P2 (ACL) and the
VFS phases (P5/P6) are off the Raft critical path and can run in parallel once their
predecessors land.

---

## 2. G0 — the four Critical resolutions (the revised-spec deltas)

These are committed decisions, not options. Each cites the review finding it closes and
the existing code it must touch. They are written so they can be lifted directly into a
`00-architecture.md` revision.

### G0-1 — One authority for idempotency and claim (closes Finding 1)

**Decision.** The durable land decision depends on the Raft log **only**. The substrate
`:land-job` row and `take!` (`linda.lisp:39`) are demoted to a **leader-local scheduling
hint with no correctness role.**

- **Submit becomes a Raft command.** A submission appends `(:submit :key K :parent-seq P
  :root-node R :paths (…) :author A :acl-version V)` to the log. Every replica's RSM
  records `K` in a `submitted-keys` map → so idempotency is replicated and node-agnostic.
  The presubmit substrate check is explicitly a **non-authoritative fast-reject hint**.
- **Dedup authority is the idempotency-key, not the change-hash.** Because auto-rebase
  re-derives `change-hash` (Finding 5), the client can never predict it; `landed-keys`
  and `submitted-keys` therefore key on `K`.
- **Apply is the only commit.** The leader *selects* a candidate via the substrate
  projection ordering, but nothing transitions a client-visible status or writes a
  durable side effect until the `:land` entry **commits and applies**. Re-`pending`-ing
  on leader transition keys off RSM `landed-keys`/`submitted-keys`, never the in-memory
  `:landing` flag.

**Touches:** `00-arch §4.2` step 4 (remove the substrate idempotency authority),
`§4.3` (demote `take!`), `§5.2` (add `submitted-keys` to RSM), `§5.5` (key on `K`).

### G0-2 — Byte-durability width before ack (closes Finding 2)

**Decision.** A land is **not acked** until its **new** blobs are present on a quorum
(`f+1`) of replicas. Lazy/gossip replication stays for *already-landed history*; the
*write path* gets a barrier.

- **Blob barrier.** Before proposing `:land`, the leader requires `R = f+1` followers to
  confirm `store-blob-exists-p` (`content-store.lisp:102`) for every new blob hash. The
  confirming node-set is carried in the `:land` entry so apply can verify the invariant
  held at commit.
- **Read-failure semantics (stated, not implied).** A `read()` against a referenced blob
  not yet local **blocks with a bounded timeout while fetching from a confirmed-holder
  peer, then errors**; it never returns wrong bytes (content addressing, I5). The set of
  confirmed holders is known from the entry.
- **GC stated in terms of byte replicas, not reachability alone.** Maintain a per-blob
  live-replica count. Invariant: **never collect a blob reachable from the retention
  horizon; never collect the last replica of a reachable blob.** Over-replicated copies
  may be collected on a single node. GC horizon is leader-proposed (`§5.4`).

**v1 caveat (G2):** P0/P1 run single-node, in-memory content-store; **no land may be
advertised as durable** until this barrier and an LMDB-backed blob DB ship (P3/P4).

**Touches:** `00-arch §4.1`/`§4.2` (add barrier step), `§5.4` (durability width + GC
invariant), `§9.1 I4` (split into I4-metadata and I4-content with the width stated).

### G0-3 — Fence every land on its authorizing ACL version (closes Finding 3)

**Decision.** Admit a **pure, deterministic, cache-free Datalog ACL re-check into the
apply function**, reading only RSM ruleset state. This is allowed because Datalog over
RSM state is pure (no clock, no RNG, no Shen, no I/O).

- The `:land` entry carries `acl-version` (the Raft index of the ruleset it was
  authorized against). Apply evaluates `acl-can-land?(author, paths)` against the RSM's
  **current** `acl-rules` pmap at the entry's apply point.
- **Resolution rule:** if `entry.acl-version < rsm.acl-version-at-apply`, apply MUST
  re-evaluate (it does, by construction); a land that the now-current ruleset forbids is
  **rejected at apply** (status `:rejected(acl)`), deterministically on every replica.
  This closes the TOCTOU where a revoke commits between leader-check and land-apply.
- **Reads:** the read's linearization point fixes **both** tip and acl-version atomically
  (a read-index/quorum read returns `(tip, acl-version)` as a pair). Follower reads are
  stale on both and are labeled stale (see G0-4). This keeps the Datalog ACL evaluator on
  the *hot read path* (lock-free) while the *authoritative* land re-check is in apply.

**Note:** this is a deliberate, scoped exception to "apply is policy-free" — apply may run
**pure Datalog over RSM state**, but still never calls Shen (G1-9 keeps Shen out of apply).

**Touches:** `00-arch §5.2` (apply runs pure Datalog ACL check), `§6.1` boundary note,
`§8.3` (land-time check is *in apply*, not pre-propose), `§9.1 I6`.

### G0-4 — Honest read consistency: read-index over lease; bounded read-your-writes (closes Finding 4)

**Decision.** The "linearizable tip" is served by a **read-index / quorum-confirmed
read**, not a clock-based lease. Lease reads are an *optional* optimization with a stated
clock bound, off by default.

- **Read-index** (Raft §6.4 style): the leader confirms it is still leader via a
  heartbeat round-trip to a quorum before answering, returning `(tip, acl-version)`. No
  clock assumption.
- **Lease reads, if enabled, require in writing:** `lease_duration < election_timeout −
  max_clock_error − max_pause`, **and** a bounded `max_pause` — which on SBCL means a
  bounded stop-the-world GC. Until that bound is measured and documented, lease reads stay
  off and nothing follower-served is called "linearizable."
- **Read-your-writes** gets a **timeout → leader read-index fallback**: a client holding
  its land's `seq` waits on a follower for `applied-seq ≥ my-seq` up to `T`, then redirects
  to a leader read-index. No unbounded wait under partition.

**Touches:** `00-arch §5.6` table (replace lease-default with read-index; relabel follower
rows "bounded-stale, NOT linearizable"), `§9.2` split-brain note (lease expiry no longer
the safety argument — quorum is).

---

## 3. G1 — Major findings, assigned to phases

Each Major is a **must-specify before that phase is done** item (the review's "before GA"
tier). They do not block the first prototype if documented, but they must be closed in the
owning phase's spec.

| # | Major (review finding) | Resolution direction | Owning phase |
|---|---|---|---|
| G1-5 | Rebase result-manifest conflict semantics; landed `change-hash` is system-assigned post-rebase | Define conflict on the **post-rebase result manifest**: a rebase that would overwrite a path the change did not observe at that value is a **conflict**, not a silent merge. Specify add-vs-add, delete-vs-modify, rename-target. Document that `change-hash` is system-assigned. | **P1** |
| G1-6 | Apply's substrate side effect is non-pure; crash window | Projection write is **idempotent by construction** (fixed entity-id derived from `seq`, replace-cardinality datoms, upsert-on-replay). Projection is **truncatable & fully rebuildable** from log+snapshot; on divergence **discard and rebuild**, never repair-in-place. Side effect identical on leader and followers. | **P3** |
| G1-7 | Idempotency window unbounded; "ancient parent saves us" is false for clean re-adds | Make `submitted-keys`/`landed-keys` **permanent in the RSM** (tiny; snapshot-bounded) **OR** define the window numerically **and** make a clean-rebasing re-add a **content-equality no-op** (target path already holds identical blob hash → idempotent land). Prefer permanent keys. | **P1** (no-op rule), **P3** (RSM keys) |
| G1-8 | Land path not term-fenced at propose | `:land` entry carries the worker's believed **term**; Raft rejects stale-term appends (standard) — state it. **No** client-visible status or substrate side effect before **commit**. | **P3** |
| G1-9 | Shen global lock transitively on apply→read path | **Apply never calls Shen.** ACL changes apply as **pure data** (update `acl-rules` pmap). Shen recompilation is **async/offline** materialization the hot path never waits on; the Datalog evaluator reads the pmap directly. Cache invalidation is a pure version bump. | **P2** |
| G1-10 | No fsync/durability contract for the Raft log | **Fsync-before-ack** for log append; name the storage (dedicated WAL, or LMDB in durable — never `MDB_NOSYNC` — mode). State the correlated-failure assumption: survive `f` independent failures; correlated loss of `f+1` is outside the model. | **P3** |
| G1-12 | Land-queue liveness / poison-job head-of-line | **Dead-letter** policy for poison jobs (bounded attempts → `:dead`, surfaced for operator). Disjoint-path lands **bypass a stuck head** — selection is by `(parent-seq, created-at)` but a job blocked on a genuinely-lost blob does not block disjoint lands. Reconcile with `§4.3` strict ordering. | **P1** (selection), **P4** (dead-letter) |

**G2 (caveat only):** Finding 11 (tighten "any node" → "any node applied-through-k that
holds the blobs" in `§5.6`) and the in-memory-store/no-durability-claim posture.

---

## 4. Phased build sequence (gate-annotated)

Phases from `00-arch §11`, now annotated with the gates each must satisfy and the new
packages/tests. **Bold gate IDs must be closed before the phase is "done."**

| Phase | Deliverable (testable) | New / reused | Gates closed | Test suite |
|---|---|---|---|---|
| **P0 — Recursive manifest + CAS round-trip** | Content-addressed recursive `:manifest-node`; O(depth) sparse subtree fetch; LMDB round-trip of manifests + blobs (closes the `persistence.lisp:69` tree-field gap). | reuse `content-store.lisp`, `filesystem-tree.lisp`, `blob.lisp`; NEW manifest indexer | — (foundation) | `snapshot-tests`, `core-tests` |
| **P1 — Linear trunk + land FSM (single-node)** | `:change`/`:trunk`/`:land-job` model; DAG→chain demotion; submit→land single-node; **content-equality no-op re-add**; **result-manifest conflict semantics**; `(parent-seq,created-at)` selection with disjoint bypass. No Raft. | reuse `snapshot.lisp`, repurpose `branch.lisp` `head`, `conductor.lisp` queue pattern | **G1-5**, **G1-7**(no-op), **G1-12**(selection) | `snapshot-tests`, `orchestration-tests`, NEW `land-queue-tests` |
| **P2 — Path-scoped ACL (Datalog hot path, Shen authoring)** | `:path` resource type; inherit-down longest-prefix-deny-wins rules; enforce on submit/land; decision cache + pure version invalidation; **apply/eval never call Shen**. | reuse `permissions.lisp`, `audit.lisp`, `shen/rules.lisp`, substrate `q-rules` | **G1-9** | `security-tests`, NEW `acl-path-tests` |
| **P3 — Raft RSM + land linearization** | `packages/raft`: election, log replication w/ **fsync-before-ack**, command set `:submit/:land/:acl/:noop/:config`, snapshot/compaction; **blob barrier (f+1)**; **pure-Datalog ACL re-check in apply**; **term-fenced propose**; **idempotent rebuildable projection**; **permanent RSM dedup keys**; read-index reads. | NEW `packages/raft`, builds on P1 FSM | **G0-1, G0-2, G0-3, G0-4**, G1-6, G1-7(keys), G1-8, G1-10 | NEW `raft-tests`, **`raft-jepsen-tests`** |
| **P4 — Read consistency + cluster GC + dead-letter** | Read-index linearizable reads; bounded-stale follower reads; read-your-writes w/ timeout→leader; per-blob replica-count GC; poison-job dead-letter. | builds on P3, `consistency.lisp` patterns | G0-2(GC), G0-4(reads), G1-12(dead-letter) | extend `raft-jepsen-tests`, `snapshot-tests` |
| **P5 — VFS checkout (no mount)** | Sparse-profile `materialize-on-demand` checkout; lazy cross-node blob fetch; LRU manifest cache. | reuse `filesystem-tree.lisp` materialize, `lru-cache.lisp` | G2-11 (read availability wording) | NEW `vfs-checkout-tests` |
| **P6 — NFS loopback mount** | Userspace NFSv3: `LOOKUP`/`READDIR`/`GETATTR`/lazy `READ`; ACL-gated visibility (deny → invisible). | builds on P5, P2 | — | NEW `vfs-mount-tests` |
| **P7 — Hardening** | Membership changes, backpressure, prefetch heuristics, audit completeness, operational runbooks. | all | residual | extend all |

**Critical path:** `P0 → P1 → [G0 spec revision] → P3 → P4`. P2 parallels after P1. VFS
(P5/P6) is independent of Raft correctness and can lag.

---

## 5. Test strategy — the Jepsen gate is non-negotiable

The review's whole point is that the hard correctness lives in the interleavings. The
`raft-jepsen-tests` suite (introduced P3) is the gate that the design's invariants
actually hold under fault injection. It must include, at minimum, a checker for each
stated invariant against an adversarial schedule:

- **I1/I2 (linear, totally-ordered trunk):** partition + re-elect + concurrent submits;
  assert no seq gap, no fork, single value per seq. Reproduce **Finding 1's** history
  (partition → re-elect → same-key retry) and assert **no double-land**.
- **I3 (at-most-once):** ack-loss + retry beyond a snapshot/compaction boundary;
  reproduce **Finding 7's** clean re-add; assert idempotent.
- **I4-content (byte durability):** **Finding 2's** history — land referencing a blob held
  by one node, then destroy that node; assert either the land was never acked OR the bytes
  survive on `f+1`. This is the headline checker.
- **I6 (ACL):** **Finding 3's** revoke-between-check-and-apply; assert the land is rejected
  at apply.
- **Lease/read-index:** **Finding 4's** GC-pause-and-stale-leader; assert no read returns a
  superseded tip; assert read-your-writes terminates under partition.
- **Liveness:** **Finding 12's** poison job; assert disjoint lands progress and the poison
  job dead-letters.

Model the harness on the existing fault-injection-friendly patterns (`consistency.lisp`
checks, the `orchestration-tests` event-queue tests) but with a real partition/crash nemesis
driving the Raft cluster.

---

## 6. Risk register (carried forward)

| Risk | Severity | Phase | Status |
|---|---|---|---|
| Dual authority for claim/idempotency | Critical | P3 | **Resolved in spec (G0-1)**; verified by `raft-jepsen-tests` |
| Byte durability = 1 at ack | Critical | P3 | **Resolved in spec (G0-2)**; headline checker |
| ACL stale-allow / privilege escalation | Critical | P3 | **Resolved in spec (G0-3)** |
| Unsubstantiated linearizability (clock/lease) | Critical | P3/P4 | **Resolved in spec (G0-4)** |
| Rebase silent clobber (result-manifest semantics) | Major | P1 | Resolution direction set (G1-5) |
| Non-pure apply / projection crash window | Major | P3 | Resolution direction set (G1-6) |
| Shen global lock on apply→read path | Major | P2 | Resolution direction set (G1-9) |
| Raft-log fsync contract unstated | Major | P3 | Resolution direction set (G1-10) |
| SBCL NFS/FUSE realism | Major (effort) | P6 | Mitigated: no-mount checkout ships first (P5) |
| Recursive-manifest migration at scale | Major (effort) | P0 | Foundation phase; isolated |
| Cross-node blob availability SLO / prefetch | Open | P4/P7 | Performance, not correctness |

---

## 7. Immediate next actions

1. **Revise `00-architecture.md` → `status: revised`** folding in G0-1…G0-4 (the spec gate
   for P3). This is a documentation task and the literal blocker on Raft work.
2. **Start P0** (recursive manifest + CAS round-trip) — it is on the critical path, has no
   open Criticals, and unblocks both P1 and the durability/GC work.
3. **Stand up the `land-queue-tests` skeleton** alongside P1 so the FSM is test-first.
4. Defer `packages/raft/` until G0 is in the revised spec.

---

## Appendix — document set

- `00-architecture.md` — the design (status: draft → to be revised per G0).
- `01-aphyr-review.md` — the adversarial review (4 Critical, 7 Major, 2 Minor).
- `02-roadmap.md` — this document: gates + phased plan.
