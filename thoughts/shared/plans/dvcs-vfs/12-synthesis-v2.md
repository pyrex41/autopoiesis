---
date: 2026-06-25
researcher: Claude
topic: "Panel-v2 synthesis — the clean OCaml/Irmin direction after Aphyr/Torvalds/Fukamachi/Minsky review"
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/08-aphyr-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/09-torvalds-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/10-fukamachi-review-v2.md
  - thoughts/shared/plans/dvcs-vfs/11-minsky-review.md
tags: [synthesis, ocaml, irmin, rust, split-stack, fencing, dirstate, merge, decision]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# Panel-v2 Synthesis: the OCaml/Irmin direction, reviewed

Four reviewers examined the clean OCaml/Irmin direction brief (`07`) from non-overlapping lanes.
This consolidates them: the verdicts, the **independent convergences** (settled), the surviving
sharp problems (with owners), and the **one genuinely open product decision** — the language/stack
fork — which the panel says hinges on an input only the user has.

## 1. Verdicts

| Reviewer | Lane | Verdict | Findings |
|---|---|---|---|
| **Aphyr** (`08`) | consistency w/o Raft | Pivot sound; one overstated claim | 1 Critical, 3 Major, 2 Minor |
| **Torvalds** (`09`) | VCS design | Real, mostly right; still oversells 3 hardest parts | 1 Showstopper, 4 Serious, 1 Annoying |
| **Fukamachi** (`10`) | shippability / deps | Shippable, conditionally | 1 Blocker, 4 Significant |
| **Minsky** (`11`) | OCaml/types/Irmin fit | Cond. yes OCaml; cond. NO Irmin-unabstracted; hard NO Eio-day-1 | 2 Blocker, 4 Major, 1 Minor |

**Headline:** nobody says the direction is wrong. All four say it is *salvageable and mostly
right*, and all four locate the risk in the **same few places**. The pivot away from
CL/Raft/Shen/NFS was correct; the remaining work is disciplining the new foundation.

## 2. Independent convergences (2+ reviewers, different lanes → high confidence; treat as settled)

These are now **P0 obligations**, not open questions.

### C1 — Abstract Irmin behind a narrow interface you own *(Fukamachi Blocker + Minsky Blocker)*
Do **not** let `Irmin.*` types leak into the domain. Define `module type Object_store`
(`put/get_blob`, `read/write_tree`, `commit`, `tree_merge`, `gc`, `push/pull`); implement it on
irmin-pack for P0. **Plus the dependency posture** (Fukamachi): exact `opam` pin + committed
`opam.locked`, **vendor irmin-pack source**, and a **CI format-migration drill** (dump→neutral→
reimport). Rationale (both): Irmin is a Tezos-cadenced upstream with quarterly breaking changes +
on-disk format migrations, sitting under your most precious data, and — critically — its typed
merge is **narrower than the brief framed** (raw-blob merge = "conflict if both touched"; real text
merge is yours regardless), so you're importing a churning dep for the *commoditized* layer while
hand-writing the hard one. Abstraction contains the churn to one module and preserves a
reimplement-the-slice exit.

### C2 — Collapse to ONE replication system; SQLite is a local rebuildable cache *(Torvalds + Fukamachi Significant + Minsky Major)*
Irmin store + landed-log + a *litevfs-replicated* SQLite index = **three sources of truth**, with
ACLs **secretly authoritative** in the "derived" SQLite (Torvalds). Kill the second replication
path: the **landed-log is the one replication substrate**; SQLite is a pure local projection
rebuilt by replaying it (Fossil model). Reusing `litevfs` here is "you own it," not an engineering
reason (Fukamachi) — and LiteFS Cloud is sunset anyway.

### C3 — Lwt-native, single/pinned-domain first; Eio behind a measured spike *(Fukamachi Significant + Minsky Blocker)*
OCaml 5 multicore GC + Eio (young) + an `lwt_eio` bridge in a long-lived multi-domain server is the
most operationally fragile cell in the OCaml runtime space (Minsky, from JS's 2.5-yr migration). The
land path is serialized *by design* — it wants correctness, not parallelism. Run **one domain that
owns the Lwt loop and is the only thing touching Irmin**; serve reads from a **content-hash-keyed
cache in front of the bridge** (correct-by-construction since objects are immutable). Spike pure-Lwt
in P0; adopt Eio/io_uring only post-P5 with a benchmark and rollback.

### C4 — The "linearizable trunk" needs a fencing token (and the type system can enforce it) *(Aphyr Critical + Minsky Major)*
A Consul-TTL lease is *likely* a single writer, not a *fenced* one; under GC-pause+clock-skew
handoff the trunk forks and the checksum chain only *detects*-then-*discards* (data loss). Fix
(Aphyr, no Raft): a **fencing token monotonic in the landed-log, CAS'd on the durable append**, with
lease re-validation after fsync, before ack. Complement (Minsky): make `Lease.witness` an
**abstract capability** so a land without a held lease is a **compile error** — the application can
no longer be the *source* of a split-brain land (storage-layer fencing still handles the truly
concurrent case).

### C5 — Merge and dirstate are overclaimed; close the gap *(Torvalds Showstopper/Serious + Minsky Major)*
- **Merge:** Irmin passing the LCA is real credit, but **diff3 text merge is yours to write**, and
  **rename-vs-edit / delete-vs-modify** are unsolved (Irmin's per-path merge is blind to them).
  Model merge as a **total function** `merge_tree : base→ours→theirs → (Tree, conflict list) result`
  with **explicit structural-conflict constructors**. Prefer **pure-OCaml diff3** over linking
  libgit2 (Minsky/Fukamachi: smaller surface, no FFI/GC hazard).
- **Dirstate:** the brief says "O(changes), first-class P1" but the mechanism (FUSE write-tracking)
  is **P5** — so P1 `status` is an O(repo) stat-walk (Torvalds Showstopper *on the claim*). Fix:
  build a **real Git-index-style dirstate in P1** (stat + (size,mtime,ctime,inode) short-circuit,
  re-hash only suspects) that works **without** the mount; the mount later *upgrades* it via
  write-tracking. Don't claim O(changes) until the index exists.

## 3. Surviving sharp problems (owners)

| # | Problem | Owner | Fix direction |
|---|---|---|---|
| P1 | Fencing token for lease handoff | Aphyr | C4 |
| P2 | Failover ack carries no durability signal (client can't tell durable from lost) | Aphyr | ack returns the achieved durability width; client policy on it |
| P3 | Idempotency = commit + landed-log = two writes = dual-authority returns | Aphyr + Minsky | one atomic `commit`→derive log entry; one source of truth, other rebuildable |
| P4 | Read-your-writes cookie can deadlock under partition | Aphyr | timeout → leader fallback; state the staleness bound |
| P5 | Stacked changes have no restack-on-land spec | Torvalds | specify stack rebase when the bottom lands |
| P6 | irmin-pack concurrency behind a multi-reader VFS is unvalidated | Minsky + Torvalds | **P0/P1 gating spike**, not a P5 discovery; the C1 seam lets you cache/swap |
| P7 | Type-driven domain not yet expressed | Minsky | the four `.mli` (land FSM GADT, Lease.witness, total merge, ACL proof) — `11 §"How to actually use OCaml's type system"` |

## 4. The one open product decision: the language/stack fork

Two reviewers (Fukamachi, Minsky) independently concluded that the all-OCaml choice is *conditional*
and that the **deciding input is the team's existing language depth**, which the brief never states.
Three honest options:

1. **All-OCaml, with the discipline** (C1–C5 + the `.mli` type design). *Preferred by Fukamachi and
   by Minsky — but only if the type discipline actually happens.* The Irmin leverage (not building
   the object store) outweighs Rust's better FUSE/perf/packaging, *provided* the Blockers are
   executed. One language, one toolchain — a real maintainability asset for a small team.
2. **Split-stack: Rust data plane + OCaml control plane.** Minsky's "equally honest" option, and it
   fits the system's natural seam: **Rust** for the FUSE/9p mount + byte/blob IO + replication
   transport (the heavy-FFI/syscall/perf half — *and* where the user's `litevfs` precedent already
   lives), **OCaml** for the land FSM + merge-result + ACL + type-driven domain (the correctness
   half). Cost: two languages + an IPC seam. Benefit: each half in its best tool.
3. **All-Rust over `gix`.** The defensible fallback *if* the Irmin churn risk is unstomachable
   (Fukamachi): trade "Irmin churn" for "build-the-store cost + own-it-forever," and get the better
   FUSE/packaging/litevfs-lineage story. You hand-write the merge substrate either way.

What the panel explicitly **rejects**: "all-OCaml, Eio-multicore, Irmin-unabstracted, two mount
techs" — the worst cell (max runtime risk + max maintenance surface, with the type story untold).

**This is a genuine user decision** — it turns on team language depth (OCaml vs Rust experience) and
appetite for a two-language build. Raised to the user separately.

## 5. Amended P0 (folds the convergences in)

P0 is no longer just "Irmin spine." It is **"Irmin spine, behind a seam you own, with the type
skeleton and the gating spikes":**
- `module type Object_store` + irmin-pack adapter; **no `Irmin.*` in `domain.mli`** (C1).
- `opam.locked` pin + vendored irmin-pack + CI format-migration drill (C1).
- The four domain `.mli`s as the skeleton: land FSM GADT, `Lease.witness`, total `merge_tree`,
  `Acl.proof` (C4, C5, P7).
- **Gating spikes** (decide before code hardens): (a) **irmin-pack concurrent multi-reader** read
  benchmark with GC running (P6); (b) **pure-Lwt vs lwt_eio** for read+land (C3).
- Pure-OCaml diff3 chosen over libgit2 (C5).
- SQLite designated a **local rebuildable cache**, landed-log the sole replication path (C2).
- Single replication authority: atomic commit→derived log entry (P3).

Then P1 adds the **real dirstate** (C5) + local commits/stacks (P5), P2 the land-queue with the
**fencing token** (C4/P1), etc. — the VCS-first order survives; it's now disciplined.

## 6. Next action

The architecture is now well-understood and heavily de-risked on paper. The remaining blocker to
*starting* is the **§4 language/stack decision**, which depends on the team's language depth — an
input only the user can give. Once chosen, P0 above is concrete and buildable.

## Appendix — document set (v2 layer)
`07` direction brief → `08` Aphyr v2 → `09` Torvalds v2 → `10` Fukamachi v2 → `11` Minsky →
`12` this synthesis. The v1 layer (`00`–`05`) remains the CL-substrate design + its reviews; `06`
is the grounding research.
