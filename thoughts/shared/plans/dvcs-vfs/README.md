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
