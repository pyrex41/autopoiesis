---
date: 2026-06-25
researcher: Claude
topic: "metavfs review panel synthesis — reconciling four reviewers + the polyglot option into a revised direction"
inputs:
  - thoughts/shared/plans/dvcs-vfs/00-architecture.md
  - thoughts/shared/plans/dvcs-vfs/01-aphyr-review.md
  - thoughts/shared/plans/dvcs-vfs/02-roadmap.md
  - thoughts/shared/plans/dvcs-vfs/03-torvalds-review.md
  - thoughts/shared/plans/dvcs-vfs/04-fukamachi-review.md
tags: [synthesis, dvcs, vfs, raft, shen, polyglot, merge, dirstate, 9p, roadmap]
status: draft
last_updated: 2026-06-25
last_updated_by: Claude
---

# metavfs — Review-Panel Synthesis & Revised Direction

Four independent reviewers examined the `metavfs` architecture from non-overlapping
angles. This document consolidates them, resolves the conflicts, folds in the **polyglot
option** (the user's note: *we are not locked to Lisp; Shen has ports in Go, Rust, Lua*),
and revises the plan. It **amends** `02-roadmap.md` (whose Aphyr-derived G0/G1 gates still
stand) — it does not replace it.

## 1. The panel

| Reviewer | Lane | Verdict | Findings |
|---|---|---|---|
| **Kyle Kingsbury** (`01`) | Consensus / linearizability / fault model | Salvageable, not broken | 4 Critical, 7 Major, 2 Minor |
| **Linus Torvalds** (`03`) | VCS design / workflow / perf / taste | Good plumbing, wrong half built first | 3 Showstopper, 4 Serious |
| **Eitaro Fukamachi** (`04`) | CL / SBCL implementation reality | Implementable; risk is NFS, the global lock, GC | 3 Blocker, 6 Significant |
| *(architect, `00`)* | The design under review | — | — |

The reviewers were deliberately siloed (Aphyr did consensus, Torvalds did the VCS, Fukamachi
did CL) so their agreements are *independent* — which makes the convergences below
high-confidence, not groupthink.

---

## 2. Where reviewers independently CONVERGED (highest confidence)

These are the conclusions more than one reviewer reached from different directions. Treat
them as settled.

### C1 — Shen does not belong in the production runtime
- **Torvalds:** "Cut Shen entirely" — Datalog already evaluates the ACLs; Shen has no
  load-bearing role, only a global-lock liability.
- **Fukamachi:** shen-cl is a bootstrap-not-ASDF, runtime-`load`, `save-lisp-and-die`-adjacent
  deployment liability; keep it dev-only, compile rules to Datalog.
- **Aphyr (Finding 9):** the single `*shen-lock*` is transitively on the apply→read path; apply
  must never call Shen.
- **Decision (with the polyglot note):** see §3. The hot path is **substrate Datalog**,
  always. Shen survives *only* as an optional, out-of-process, dev/CI authoring-and-verification
  surface — and because Shen has Go/Rust/Lua ports, if it is kept it runs as a **pinned sidecar
  in any language**, never `load`ed into a production SBCL image. The user's note removes the
  *operational* objection to Shen; it does not by itself answer the *necessity* objection, so
  the default is "Datalog is the engine; Shen is optional ceremony you can add for richer
  offline policy verification."

### C2 — The roadmap order is backwards: build a nice VCS before distributing it
- **Torvalds (Serious):** Git won on a single laptop (instant branch, good merge, fast status)
  *before* distribution. Building from-scratch Raft (P3) before proving the VCS is pleasant is
  the biggest misallocation.
- **Fukamachi (effort gut-check):** P0/P1 (manifest + land FSM) are weeks/low-risk; Raft is
  2–4 months/bounded; the spine should come first and Raft is not where the product risk lives.
- **Decision:** reorder (§5). Single-node, developer-delightful VCS first — **with the parts
  that are missing entirely** (§C4) — then Raft as a deferred, off-critical-path workstream.

### C3 — The mount is the real rabbit hole; NFS-in-SBCL is the wrong bet
- **Torvalds (Showstopper):** virtualization (the monorepo value prop) is shipped last and
  flagged research-grade; everything before it is sparse-checkout you could get from Git today.
- **Fukamachi (Blocker):** a userspace NFSv3 server means hand-writing ONC-RPC + XDR + MOUNT +
  portmapper — *four* libraries that don't exist in CL. Use **9P** (tiny, native `v9fs` mount,
  no FFI) or a non-Lisp component; keep the no-mount checkout as the realistic default.
- **Decision (with the polyglot note):** **drop NFS.** The mount, *if built*, is either **9P**
  (Fukamachi's recommendation) or a **native Rust/Go component** (the polyglot option). It is
  gated behind a 2-week spike (§5, M-spike) and is **cut from the critical path** — fast
  sparse-checkout + a real dirstate (§C4) covers a large fraction of real users without it.

### C4 — The design is missing VCS essentials that no amount of consensus fixes
Torvalds found three things that simply aren't in the design or roadmap, and they are
non-negotiable for a *version control system*:
- **A real 3-way textual merge.** Path-overlap + whole-file-blob rebase cannot combine two
  concurrent edits to one file. This is the defining job of a VCS and it is absent.
- **A dirstate.** `scan-directory` re-hashes every file on every `status`/`diff` → O(repo).
  EdenFS exists to kill exactly this. Needs a Git-index-style (or VFS-fed) change journal.
- **Change identity + stacked changes.** No stable Change-Id across review revisions, no local
  commit stack (the Sapling model). Today every review round is an identity-less resubmission.

Plus the storage/wire gaps: **whole-file blobs with no delta/packfiles/chunking**, and a
**one-blob-per-RTT** fetch protocol with no batching. **Decision:** these become first-class
roadmap items (§5), most of them *ahead* of Raft.

---

## 3. The polyglot boundary (resolving the user's note)

The user's note — *not locked to Lisp; Shen ports exist in Go/Rust/Lua* — converts two
reviewer "blockers/cuts" into a **boundary-drawing exercise** instead of a dead end. The
principle: **keep the homoiconic core in Lisp where it earns its keep; push the
FFI/perf/protocol-heavy edges to a native component where CL fights its runtime.**

| Component | Language | Why |
|---|---|---|
| Substrate (EAV, Datalog), CAS, recursive manifest, `:change`/land model, land FSM, ACL **evaluation** (Datalog) | **Common Lisp** | This is the homoiconic core — code-as-data, time-travel, the existing bones. CL's strengths, Fukamachi rates it weeks/low-risk. |
| **The mount** (9P or FUSE server) | **Rust or Go** (or CL 9P) | Fukamachi: NFS = 4 missing CL libs; FUSE = foreign-thread/GC FFI risk. A native 9P/FUSE server sidesteps both. Polyglot note makes this clean. |
| Raft transport + durable log | **CL default, native optional** | Fukamachi: CL Raft is tractable (2–4 mo, bounded) — keep it in-process with the RSM. Only reach for a native Raft (e.g. a Rust lib) if the CL log-durability/throughput proves inadequate. |
| Native SHA-256 (SHA-NI) | **CL + libcrypto via CFFI** | Fukamachi Finding 5: ironclad is correct but slow; FFI to OpenSSL EVP for throughput, ironclad fallback. A thin FFI, not a separate process. |
| **Shen policy authoring/verification** (if kept at all) | **pinned sidecar — Go/Rust/Lua port**, dev/CI only | C1. Compiles rules → Datalog/CL; never in the production SBCL image. The polyglot note's most direct application. |

**The seam** is a small, well-typed RPC boundary (Fukamachi recommends `cl-messagepack` or
`cl-conspack` frames over raw sockets/`iolib` — *not* HTTP/dexador). Everything crossing the
Lisp↔native line is content-addressed bytes + manifest hashes + policy decisions, all of which
are already serialization-friendly.

> **Net effect on the two hardest reviewer items:** Torvalds' "this is a science project in CL"
> and Fukamachi's "NFS is a person-year hole" both dissolve — not by doing more in Lisp, but by
> drawing the line *at the mount* and letting a native component own it.

---

## 4. Resolved decision log

| # | Decision | Driven by | Status |
|---|---|---|---|
| D1 | Hot-path ACL = substrate **Datalog**; Shen is optional, out-of-process, dev/CI only (any-language port) | C1 (Aphyr+Torvalds+Fukamachi) | **Settled** |
| D2 | **Reorder**: single-node delightful VCS first; Raft deferred off critical path | C2 (Torvalds+Fukamachi) | **Settled** |
| D3 | **Drop NFS**; mount = 9P or native Rust/Go, behind a spike, off critical path | C3 (Torvalds+Fukamachi)+polyglot | **Settled** |
| D4 | Add **real 3-way merge**, **dirstate**, **change-id + stacks**, **batched wire**, **delta/CDC blobs** as first-class items | C4 (Torvalds) | **Settled** |
| D5 | Polyglot boundary per §3 table; Lisp↔native seam = conspack/messagepack frames | polyglot note | **Settled** |
| D6 | CL implementation guardrails (§6) adopted wholesale | Fukamachi | **Settled** |
| D7 | Aphyr G0/G1 gates from `02-roadmap.md` still apply to the (now deferred) Raft phase | Aphyr | **Unchanged** |
| **Q1** | **Target scale**: moderate (hundreds of eng) vs hyperscale (10k+). Determines whether parallel-disjoint landing, heavy virtualization, and delta storage are required-now or deferred. | Torvalds (throughput, "stop name-dropping 10k") | **Needs user** |
| **Q2** | **Is true virtualization a hard requirement**, or is fast sparse-checkout + dirstate enough? If enough, the mount is cuttable. | Torvalds Finding 7 | **Needs user** |
| **Q3** | **Polyglot appetite**: mount-only native, or also Raft/other edges in Rust/Go? | polyglot note (degree unspecified) | **Needs user** |

Q1–Q3 are genuine product forks, not implementation details — they are raised to the user
separately rather than guessed.

---

## 5. Revised phase plan (amends `02-roadmap.md §4`)

The spine becomes **VCS-first**. Raft moves from "P3, the spine" to a deferred workstream. New
items from C4 are inserted ahead of it. Aphyr's G0 gate now blocks the *deferred* Raft phase,
not the early VCS phases.

| Phase | Deliverable | New vs `02` | Gates |
|---|---|---|---|
| **P0 — Recursive manifest + CAS round-trip** | Content-addressed recursive manifest; LMDB-backed blobs (**raw-digest keys**, conspack codec); sparse subtree fetch. | unchanged | — |
| **P1 — Linear trunk + land FSM (single-node)** | `:change`/`:trunk` model; DAG→chain; durable land FSM via `transact!` (not `take!`); result-manifest conflict semantics (G1-5). | unchanged | G1-5, G1-7(no-op) |
| **P1.5 — Dirstate / fast status (NEW)** | Git-index-style `(path,size,mtime,ctime,inode,hash)` cache; `status`/`diff` = O(changes). Later fed by the mount's write-tracking. | **NEW (C4/Torvalds Showstopper)** | — |
| **P1.6 — Real 3-way merge (NEW)** | diff3 / `ort`-style line-level merge on blob bytes; conflict defined at line granularity + structural rename/delete; auto-rebase only on clean merge. | **NEW (C4/Torvalds Showstopper)** | — |
| **P1.7 — Change identity + stacks (NEW)** | Stable Change-Id across revisions; local commit stacks (Sapling model); review-iteration lifecycle. | **NEW (C4/Torvalds Serious)** | — |
| **P2 — Path-scoped ACL (Datalog)** | `:path` resource type; inherit-down rules; **Datalog evaluation, Shen dev-only/out-of-process**. | amended (Shen out) | G1-9, D1 |
| **P2.5 — Batched wire + delta/CDC blobs (NEW)** | `fetch-blobs([H...])` pack protocol (no per-blob RTT); delta or content-defined chunking for large/generated files; subtree prefetch. | **NEW (C4/Torvalds Serious)** | — |
| **M-spike — Mount spike (NEW, parallel, time-boxed)** | 2-week throwaway: **9P** (CL or native) **or** native Rust/Go mount. Measure `READDIR`/`READ` latency + GC-pause behavior. Go/no-go on a real mount. | **NEW (C3)** | decides P6 |
| **P3 — Raft RSM + land linearization (DEFERRED)** | The full Aphyr-gated Raft layer from `02-roadmap.md §4`. CL transport (messagepack/conspack frames, `iolib`/`usocket`), **verified fsync** (LMDB or `sb-posix` WAL), term-fenced propose, blob barrier, pure-Datalog ACL re-check in apply. Now **off the critical path**. | reordered later | **G0-1…G0-4**, G1-6/7/8/10 |
| **P4 — Read consistency + cluster GC + dead-letter** | As `02`. | unchanged | G0-2/4, G1-12 |
| **P5 — VFS sparse checkout (no mount)** | Sparse-profile materialize-on-demand; lazy cross-node fetch; **fset read-snapshot for lock-free reads**. | amended (lock fix) | — |
| **P6 — Mount (9P/native, ONLY if M-spike passes)** | The mount, in whatever the spike validated. Explicitly optional. | amended (9P/native, not NFS) | — |
| **P7 — Hardening + parallel landing (scale-gated)** | If Q1 = hyperscale: parallel disjoint-path landing, throughput targets. Else: ops/runbooks. | amended | — |

**New critical path:** `P0 → P1 → P1.5 → P1.6 → P1.7` (a genuinely usable single-node VCS) →
then P2/P2.5 in parallel → then *measure* → then decide whether/when to spend the Raft quarter
and the mount spike. Raft and the mount are no longer load-bearing for "is this a good VCS."

---

## 6. CL implementation guardrails (adopt wholesale — Fukamachi)

These apply to every phase and are cheap to honor from day one:

- **CAS keys = raw 32-byte digest** (`equalp`/integer keys), never 64-char hex in the in-memory index. Hex only at the wire/UI boundary.
- **Blob bytes in LMDB** (mmap, off the SBCL heap) — the `"blobs"` db is already opened; biggest GC-pressure win.
- **`static-vectors`** for large file buffers; SHA them in place. **libcrypto EVP via CFFI** for SHA-NI throughput, ironclad fallback.
- **`cl-conspack`** for manifest CAS bytes + Raft log entries (binary, canonical, **no `read-eval`**). **Never** `read-from-string` peer/client bytes. Close the `persistence.lisp:69` tree-field gap with conspack, not by extending `prin1`.
- **In-memory manifest nodes = `defstruct`**, decoded once from the sexpr CAS form and LRU-cached; `fast-io` instead of `format` in `canonical-entry-string`.
- **Lock-free VFS reads via an `fset` immutable projection snapshot**, atomically swapped by the land worker per commit — fixes the global `store-lock` contention *and* the unsynchronized-hash-table rehash race (Fukamachi Blocker 2).
- **Get the LMDB fsync off `store-lock`**: dedicated writer thread draining a batch (`with-batch-transaction`).
- **One enforced `with-substrate-thread` macro**; forbid raw `bt:make-thread` in `packages/raft` & `packages/metavfs`; prefer passing the store explicitly. Capture `*substrate*` into `lparallel` workers too (Blocker 3).
- **Raft log durability**: verify the `lmdb` binding's fsync (write a kill-9-mid-commit test) **or** a `fast-io` + `sb-posix:fsync` append-only WAL (~100 lines, exact fsync-before-ack control). Separate LMDB env for the log vs. the projection (single-writer-per-env).
- **`lparallel` `pmap`** for the initial monorepo scan/blob fan-out; bound the kernel to core count.
- **Qlot** (`qlfile.lock`) pinning every dep — including `lmdb`, `iolib`/`usocket`, `cl-conspack`/`cl-messagepack`, `cffi`, and Shen-if-any. A consensus system must build reproducibly.

---

## 7. What every reviewer agreed is GOOD — do not regress

- **CAS: hashes through the log, bytes out of band, verify by re-hash.** The one load-bearing idea; tiny RSM snapshots fall out of it. (Aphyr, Torvalds both credit it.)
- **Recursive content-addressed manifest** for server-side scale (O(depth) fetch, O(1) unchanged-subtree compare). (Torvalds, Fukamachi.) — Just trim `size`/`mtime` out of the *hashed* identity (Torvalds taste-nit) and use structs in memory (Fukamachi).
- **Ruthless DAG→linear-chain demotion**, deleting dead multi-parent code. (Torvalds.)
- **Datalog (terminating, lock-free) on the hot path**, Shen as authoring only. (All three — and the basis for C1/D1.)
- **No-mount checkout first; FUSE-avoidance honesty; §9.3/§10 self-honesty.** (Aphyr, Torvalds, Fukamachi all credit the candor.)

---

## 8. Immediate next actions

1. **Get the three product forks (Q1–Q3) answered by the user** — they determine whether this is a moderate-scale mostly-Lisp tool or a hyperscale polyglot system, which changes what P2.5/P6/P7 even contain.
2. **Revise `00-architecture.md` → `status: revised`** to: remove Shen from the runtime (D1), add merge/dirstate/change-id/batched-wire as first-class (D4), state the polyglot boundary (D5), and fold the Aphyr G0 deltas. 
3. **Start P0** — unchanged, on the critical path, and the CL guardrails (§6) make it concrete.
4. **Schedule the M-spike** (mount go/no-go) to run in parallel — the answer gates a lot of downstream framing, and per Torvalds you want to know in week 2, not P6.

---

## Appendix — document set

- `00-architecture.md` — the design (to be revised per D1/D4/D5 + G0).
- `01-aphyr-review.md` — consensus/fault-model review (4C/7M/2m).
- `02-roadmap.md` — Aphyr-reconciled gates + original phase plan (G0/G1 still valid).
- `03-torvalds-review.md` — VCS-design review (3 Showstopper/4 Serious).
- `04-fukamachi-review.md` — CL-implementation review (3 Blocker/6 Significant).
- `05-synthesis.md` — **this document**: panel synthesis, polyglot boundary, revised plan.
