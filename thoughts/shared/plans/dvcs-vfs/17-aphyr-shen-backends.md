---
date: 2026-06-25
reviewer: "Kyle Kingsbury (persona)"
status: review
topic: "Jepsen-style head-to-head consistency review of the two Shen backends: shengo-vfs (Shen brain + Go body, reusing superfly/litefs + ltx + go-git) vs shenrs-vfs (Shen brain + Rust body, building leased-primary replication on ltx-rs + gix)"
targets:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/16-plan-shen-rust.md
inputs:
  - thoughts/shared/plans/dvcs-vfs/12-synthesis-v2.md
  - thoughts/shared/plans/dvcs-vfs/08-aphyr-review-v2.md
tags: [review, jepsen, shen, litefs, ltx, gix, fencing, lease, split-brain, async-replication, durability, two-process, single-binary]
---

# Jepsen-style head-to-head: shengo-vfs vs shenrs-vfs (the consistency story)

I have reviewed this product twice already — once as a CL/Raft thing, once as the no-Raft
OCaml/Irmin direction (`08`). The brain is settled and I am not re-litigating it: the four
`datatype` rule sets (land FSM, `lease-witness`, total merge, `acl-proof`) are the same in both Shen
plans, byte-for-byte, and they are good. The *type-layer* fencing — `advance-landed` demanding a
`lease-witness` that only `with-leadership` can mint — is identical in `15` and `16` and it correctly
makes an **application-originated** split-brain land a compile error in both. That dissolves nothing
about the storage layer, which is where I live, but credit is shared and equal. **The type layer is a
tie.**

The interesting question is the *storage-and-replication layer*, and there the two plans diverge in a
way that matters more for consistency than either author admits. One **reuses an async-replicated
daemon whose consistency semantics are fixed by someone else** (litefs); the other **builds the
replication layer** and therefore *can* — but has not yet *committed to* — getting the fence right by
construction. This review is about that fork.

## Verdict

**Both plans inherit the exact v2 Critical I raised in `08`: a lease is not a fence.** Neither has
discharged it at the storage layer, and the way each *fails* to discharge it is different and
decisive.

- **`15` (Go/litefs)** writes the right words — "CAS the fence on the durable append," `LtxAppendFenced`
  with a `fenceHead` check — but **those words contradict the daemon it claims to reuse.** litefs owns
  the lease, owns the LTX log, owns the position cookie, and resolves split-brain by *detect-then-resync*
  (data loss), which is *precisely* the semantics I said in `08` was detection-not-fencing. You cannot
  reuse the real litefs *and* CAS your own fence on the durable append, because **litefs's append is
  inside litefs, not inside your `gobody.LtxAppendFenced`.** The plan is internally inconsistent about
  whether it is reusing litefs or replacing its write path. That ambiguity is a **Critical**, and it is
  worse than `16`'s, because a reader will believe the fence is there when it is not.

- **`16` (Rust/ltx-rs)** is honest that it **builds** leased-primary + streaming on top of the
  `ltx-rs` *format/checksum/apply* primitive. Because it owns the append, `rs_ltx_cas_append` *can*
  genuinely CAS the fence on the fsync'd durable head — the one place `08` said the fence must live.
  The code sketch even does it in the right order (CAS → write → fsync → re-check lease → ack). So
  `16` is the only one of the two that *can* close my v2 Critical by construction. It hasn't *finished*
  closing it (the lease source, the fence-vs-lease-epoch relationship, and the `ltx-rs` apply path's
  interaction with the CAS are under-specified), so it carries a **Major**, not a clean bill. But a
  Major you can fix by writing more spec beats a Critical that the architecture forbids you from fixing.

**Plus a second-failure-domain finding unique to `15`:** reusing the litefs *daemon* (a separate
process) splits trunk-tip authority across two processes — the Shen/go-git process and the litefs
process — that must agree about what the tip is. That is a new linearizability seam `08` never had to
consider and `16` does not have at all. **Major against `15`.**

**Counts:**

| Plan | Critical | Major | Minor |
|---|---|---|---|
| **`15` shengo (Go/litefs)** | **2** | **3** | 2 |
| **`16` shenrs (Rust/ltx-rs)** | **0** | **3** | 2 |

**Sounder consistency story: `16` (Rust), and it is not close — on consistency alone.** See the
final section for the honest weighing against Go's reliability advantage.

---

## Findings

### F1. [CRITICAL — `15` Go] Reusing the *real* litefs daemon and "CAS'ing your own fence on the durable append" are mutually exclusive. The plan claims both. One of them is false, and the false one is the safety mechanism.

**Claim attacked.** `15 §4.2`: *"the LTX append carries a monotonic fencing token ... The Go durable
writer CAS's the fence on the fsync'd append and re-validates the lease after fsync, before ack. A
stale leader's append fails the CAS and is rejected."* with the `LtxAppendFenced` Go sketch doing
`if token <= s.fenceHead { return ErrStaleLeader }` then `writeLTX` then `Sync`.

And `15 §1` / the dep table / §4.3 / §12.5: *"reuse `litefs`/`ltx`," "the leased-primary + ... LTX
transaction log = the distribution/replication layer as **real code**, not a reimplemented pattern,"*
*"litefs's native model," "the actual replication code, not a reimplemented pattern."*

These two claims cannot both be true. Here is the distributed-systems fact that breaks them:

**litefs's lease, log append, and split-brain resolution are inside litefs.** litefs acquires the
Consul lease, decides who is primary, writes the LTX stream, ships it to replicas, and on a checksum-
chain divergence *halts the diverged node and resyncs it from the current primary, discarding its
divergent transactions* (this is litefs's documented behavior, and it is exactly the detect-then-discard
I described in `08 Finding 1`). If you are *reusing* litefs, then **your trunk write is a write that
litefs replicates**, and the fence — if there is to be one — must be enforced *by litefs's append path*,
which you do not own and cannot CAS into. `gobody.LtxAppendFenced` writing to `s.logFile` with your own
`s.fenceHead` is **not litefs's append**; it is a *parallel, second* append path that litefs does not
know about. Either:

- **(a)** you genuinely route trunk writes through litefs → you inherit litefs's async-lease,
  detect-then-resync semantics *unchanged*, your `fenceHead` CAS sits in front of a log litefs will
  itself overwrite on resync, and **the v2 Critical from `08` is re-imported wholesale** — lease is not
  a fence, the fork is detected and one side's acked commits are discarded; or
- **(b)** you write the LTX log yourself in `gobody/` (your own `writeLTX`, your own fence) and use
  litefs **only** for the Consul lease and the replica stream → then you are **not reusing the litefs
  replication layer**, you are reusing its lease client and reimplementing its log write path, and the
  "battle-tested real code" reliability argument (the entire thesis of choosing Go) **evaporates for the
  consistency-critical component**. You've kept litefs's *weakest* part (async lease) and rebuilt its
  *strongest* part (the tested log writer/replicator) yourself, badly, on the side.

The plan never says which. §4.1 says *"we are reusing LTX's format and chaining invariant as our
landed-log"* (sounds like (b) — reuse `ltx` the library, not `litefs` the daemon), but §4.3 and §12.5
repeatedly invoke *"litefs replication," "litefs's native model," "the actual replication code."* The
`gobody/litefs_lease.go` + `gobody/replica.go` files in §2 imply litefs *is* doing replication. **This
is an unresolved contradiction at the exact point where consistency is decided.** That is what makes it
Critical rather than a spec gap: a reader comes away believing the fence is enforced on the durable
append, when under reading (a) it is not enforced at all (litefs owns the append) and under reading (b)
the "reuse real code" safety argument is void.

**Concrete history (under reading (a), the realistic one for "reuse the real daemon"):**

1. Shen/go-git process P1 is on the litefs-primary node N1 (litefs holds the Consul lease). trunk tip
   = commit at seq 100, LTX head checksum `C100`. P1's land-worker goroutine owns the land-evaluator.
2. P1 runs `land-one` for change H: `with-leadership` asks litefs "am I primary?" → yes. `acl-check`
   passes. `merge-tree` (go-git ORT) clean. P1 calls `commit-tree` → go-git writes commit object for H.
3. **The Go process P1 stop-the-world GCs** (Go's GC is concurrent but has stop-the-world phases; under
   heavy heap pressure from go-git pack reads + a high-fan-out FUSE read load, a multi-hundred-ms to
   multi-second pause is not exotic — and the *whole runtime*, including the litefs lease-renewal
   goroutine living in the same binary if litefs is in-process, *or* the separate litefs process's view
   of N1, freezes for the in-process case).
4. litefs's Consul lease TTL elapses. litefs on N2 acquires the lease, N2 becomes primary, tip still
   100. A client lands H' through N2: litefs writes LTX entry seq 101, `C100 → C101'`, replicates,
   acks. Cluster trunk: 100 → 101'(H').
5. P1 resumes. Its `with-leadership` *type-layer* witness `W` is still in scope (it was minted before
   the pause and the brain has no way to know wall-clock moved). P1 proceeds: `next-log-entry` builds
   entry seq 101 `C100 → C101(H)`; `durable-append!` → `gobody.LtxAppendFenced`. **Now the two readings
   diverge:**
   - **(a) litefs owns the append:** P1's commit goes to litefs's primary write path, but litefs on N1
     is no longer primary (N2 is). litefs *rejects or, on the next sync, detects* the divergence and
     *resyncs N1 from N2, discarding H*. P1 already returned `(ok width)` up through the Shen `land-one`
     and **acked its client "landed at seq 101."** Two clients told "landed at 101," H silently
     discarded on resync. **Detection + data loss. Identical to `08 Finding 1`.** The `fenceHead` CAS
     in `LtxAppendFenced` did nothing because the authoritative append is litefs's, not yours.
   - **(b) you own the append:** P1's `LtxAppendFenced` checks `token <= s.fenceHead`. But `s.fenceHead`
     is **local to P1's process** — N2 advanced *its own* `fenceHead` to 101, P1's is still 100, P1's
     `token` is 101 > 100 → **CAS passes**, P1 writes its fork. Your CAS is only monotone *within one
     process's memory*; it is not a distributed fence unless the fence read-modify-write is itself
     serialized through the same durable, single-writer medium across both nodes — which is the thing
     litefs's async log is *not*. So even under (b), the naive `s.fenceHead` is a per-process counter,
     not a fence. (This is fixable in (b) — make the fence a CAS against the *durable shared* head with
     compare-and-swap semantics enforced by the single-writer lease + the log's own linearization point
     — but the sketch does not do that; it does an in-memory compare.)

Either way, `15` does **not** have a working storage-layer fence. Under (a) because litefs owns the
append; under (b) because the CAS is process-local.

**Why `16` is structurally better here (the comparison):** `16 §6.2` does the CAS *inside the durable
append it owns* (`rs_ltx_cas_append`: *"verify `Token > durable_head_token` (CAS); write entry, fsync;
re-check lease still held post-fsync; return width"*). Because `16` builds the replication, the
`durable_head_token` *is* the durable log's head, and the append *is* the linearization point — the CAS
and the durable write are the *same* operation on the *same* single-writer medium. That is exactly the
fix I prescribed in `08`. `16` can therefore make the stale-leader land **fail to commit** rather than
commit-then-discard, *if* it follows through (see F4 for the gap that keeps it a Major).

**Required fix for `15`:** Pick (a) or (b) *in writing*, and live with the consequence.
- If **(a)** (reuse real litefs end-to-end): **delete every "CAS the fence on the durable append"
  claim** (§4.2, §8 C4, §11 C4/P1). State plainly: *"trunk landing inherits litefs's async-lease
  semantics; split-brain is detected by the LTX checksum chain and resolved by discarding the diverged
  fork (data loss in a bounded window); we do not fence the stale appender at write time."* That is the
  honest `08`-conditioned guarantee — and it means `15` does **not** discharge C4, full stop.
- If **(b)** (own the append, litefs for lease+stream only): say so, drop the "reuse the battle-tested
  replication code" reliability claim for the write path, and **make the fence a CAS against the durable
  shared head, not a per-process `s.fenceHead`** — which requires specifying how two nodes' appends
  serialize (they can't both be writing their own `s.logFile`). At that point you are building roughly
  what `16` builds, in Go, having thrown away the reuse argument that justified Go.

---

### F2. [CRITICAL — `15` Go] Two failure domains: the litefs *daemon* and the Shen/go-git *process* are two things that must agree about the trunk tip. Splitting trunk authority across a process boundary is a new linearizability seam, and the plan does not specify the cross-process commit ordering.

**Claim attacked.** `15 §2` project layout lists `gobody/litefs_lease.go` + `gobody/replica.go` and the
dep table lists `superfly/litefs` as *"leased single-primary, replica LTX streaming."* `15 §1` insists
the win is *"one process, one GC, one address space, one static binary."* But litefs **is a daemon** —
the real superfly/litefs is a separate process that runs a FUSE mount over SQLite and a Consul lease
loop. The plan wants both "reuse the real litefs" *and* "one process." **Those conflict.** Either:

- litefs runs **in-process** as a library (litefs is *not* designed for this; it is a daemon with a FUSE
  mount and an HTTP control API — embedding it in your binary means forking/owning it, which contradicts
  "reuse battle-tested code"), or
- litefs runs **as a separate process** (its real deployment shape) — and then there are **two
  processes that both hold beliefs about the trunk tip**: the Shen/go-git process (which writes go-git
  commit objects and believes a commit "landed") and the litefs process (which holds the lease and
  replicates the LTX log).

Take the realistic second case. The go-git commit (the source of truth for *content*, per `15 §8 P3`:
*"the go-git commit is the source of truth; the LTX entry is the rebuildable projection of ordering"*)
is written by **process A**. The lease that authorizes the land and the log that orders it are held by
**process B**. For trunk landing to be linearizable, A and B must agree, atomically, that "commit X is
at seq N and X is durable." But A and B are separate processes with separate fates:

**Concrete history (process-split torn land):**

1. Process A (Shen/go-git) wants to land H. It asks process B (litefs) "am I primary?" via the lease →
   yes. A writes the go-git commit object for H (durable in the go-git object store on disk).
2. A asks B to append the LTX ordering entry for H at seq 101.
3. **Process A crashes after the go-git commit write but before B records seq 101** (or B crashes after
   A's commit, or the IPC between them drops the append request). Now: the go-git object store contains
   H's commit object, but the litefs LTX log has **no seq-101 entry**. The "one atomic land step" of
   `15 §8 P3` / §5 is **not atomic** — it spans two processes and two durability domains.
4. On recovery: which is authoritative? §8 P3 says go-git is truth and the LTX entry is *"derived
   deterministically."* But the *ordering* (seq, fence) lives in litefs, and litefs doesn't know H
   exists. If recovery "rebuilds the log from go-git" it must scan go-git for un-logged commits and
   assign them seqs — but assigning a seq is exactly the fenced, leader-only operation that just failed.
   If a *new* leader (process B' on another node) is now primary, it will assign seq 101 to a *different*
   commit, and A's orphaned H-object is a dangling commit that some client may have been acked for.

This is the **dual-authority structure I spent `08 Finding 1` (v1) celebrating the *dissolution* of.**
The OCaml/Irmin plan and `16` both keep content+ordering in **one** address space with **one** fate:
in `16`, `rs_gix_commit` and `rs_ltx_cas_append` are two Rust calls in the *same process*, and the
fsync-crash test (`16 §7`) explicitly asserts *"recovery rebuilds the log projection from `gix` ... with
no half-landed observable state"* — recoverable precisely *because* one process owns both. `15`
re-introduces the split, across a *process* boundary, which is strictly harder to make atomic than the
in-address-space case (you cannot hold both writes under one lock; you need a cross-process commit
protocol the plan does not have).

**Which is easier to make linearizable?** Unambiguously `16`. One binary, one address space, one fate:
content (gix) and ordering (ltx) commit under one process's control, and the recovery story ("rebuild
ordering from content") is a single-process invariant. `15`'s "one process" claim is contradicted by its
own reuse-the-litefs-daemon choice; if litefs is truly reused as a daemon, trunk authority is split
across two processes and the land is not atomic.

**Required fix for `15`:** Either (a) prove litefs can be embedded in-process as a library and own that
fork (losing the "reuse the real daemon" argument), or (b) specify a cross-process commit protocol
between the go-git process and the litefs daemon that makes "commit-object-written ∧ seq-assigned" atomic
across a crash of either — a two-phase commit or a write-ahead intent in one of the two stores that the
other replays. Without one of these, the land is a torn write across two failure domains. Given the
brain already insists the land is one serialized critical section, the cleanest fix is to **not split it
across a process boundary at all** — i.e., do what `16` does and own the log in-process — which again
dissolves the reuse argument.

---

### F3. [MAJOR — both, worse in `15`] The async data-loss window is inherited identically by the lease model, but only `16` is positioned to *fence* it; `15` re-imports `08`'s exact "detect-then-discard = data loss" remedy.

**Claim attacked.** `15 §4.3` / §12.2: *"litefs replication is ASYNC — there is a real data-loss
window ... litefs's documented subsecond window,"* mitigated by fsync-before-ack + a 1-replica-ack
durability-width knob + returning achieved width. `16 §6.4`: *"failover has a data-loss window mitigated
by fsync-before-ack + the optional 1-replica-ack durability-width knob (proven LiteFS shape)."*

Both plans correctly carry forward the **P2 fix** from `08 Finding 2` (synthesis `12` P2): the ack
returns the achieved durability width, so a client can distinguish durable-on-leader from durable-on-N.
Both honestly state the window. **On the async window itself, this is a genuine tie** — it is a property
of the chosen distribution model (single leased leader + async replicas), not of Go vs Rust, exactly as
I said in `08`.

The difference is what happens at the *boundary* of that window, i.e. the split-brain fork:
- `15` (under reading (a) of F1) resolves the fork by litefs's **detect-then-resync = discard the
  diverged fork's acked commits**. That is `08 Finding 1`'s data-loss outcome, re-imported. A developer
  whose commit is on the losing fork is told "landed," then it silently vanishes. `15` does not fence
  the stale appender; it discards after the fact.
- `16`, because it owns the append, *can* convert the stale-leader land from "commit-then-discard" into
  "**fail to commit, return `(error stale-leader)` to the client**" — the difference between a footgun
  and a knob, in the exact words of `08`. `16 §6.2`/§7 fault test asserts *"two would-be leaders append
  concurrently; exactly one CAS wins, the stale one gets `(error stale-leader)`, the chain is intact."*
  That is the right behavior. (Whether the CAS is *actually* a distributed fence and not a per-process
  counter is F4's open question — but `16` is at least *trying* to fence, and is architecturally able
  to; `15` is not.)

**Required fix:** `15` must state the detect-then-discard recovery semantics explicitly (which fork
wins, that the loser's acked commits are discarded, how the author is notified) — this is `08 Finding 5`,
still undischarged in `15`. `16` must finish F4. Both must keep the width-returning ack (they do).

---

### F4. [MAJOR — `16` Rust] The fence is sketched correctly but under-specified: where the lease epoch comes from, how the fence relates to it, and how `rs_ltx_cas_append`'s CAS is a *distributed* fence and not a per-process counter, are all unstated. Get this wrong and `16` has the same per-process-counter bug as `15`-reading-(b).

**Claim attacked.** `16 §6.1`: *"Lease lives in a host KV (etcd/Consul via a tokio client, or a static
primary)."* §6.2: `rs_ltx_cas_append` *"verify Token > durable_head_token (CAS); write entry, fsync;
re-check lease still held post-fsync."* §4: landed-log entry carries a `fencing-token`.

The shape is right — CAS on the durable head, fsync, re-validate lease, ack — and it is the only one of
the two plans that puts the CAS *in the append it owns*. But three things are missing, and they are the
same three I demanded in `08`:

1. **Where does the fencing token come from, and is it monotone across leadership changes?** `08`
   required *"a fencing token monotonic in the landed-log ... Consul session-modify-index is one
   source."* `16` says the token is in the entry and is CAS'd, but does not say it is derived from the
   lease epoch (the etcd/Consul lease's monotonic fencing counter). If the token is just `landed-seq`
   (as `15 §4.2` conflates: *"the MaxTXID/landed-seq itself serves as the monotone fence"*), then two
   nodes that both think they're leader will both compute `tip+1` as their token and **collide on the
   same token value**, and the CAS cannot distinguish them. The token must be `(lease-epoch, seq)` or a
   single counter that *only the current lease-holder can advance*, sourced from the lease KV's fencing
   counter, not from the local tip. `16` must state this.

2. **Is `durable_head_token` the *durable shared* head, or a per-process variable?** This is the bug
   that sinks `15`-reading-(b). `rs_ltx_cas_append` must compare against the *log's own durable head as
   read from the single-writer medium at append time*, and the CAS must be atomic with the write to that
   medium. Since `16` owns the log and the land is serialized through one leader holding the lease, this
   is *achievable* — but only if the append is the linearization point and the head is read from durable
   state, not cached in process memory across a pause. `16` must state that the CAS reads the durable
   head fresh (post-pause) and that a non-leader cannot have advanced it (because non-leaders can't
   acquire the lease). Combined with the post-fsync lease re-validation, that closes it.

3. **The `ltx-rs` apply path on replicas must reject a lower-or-equal fence too.** When a replica applies
   the streamed log, it must enforce the same monotone-fence invariant, so a stale leader's stream that
   somehow reaches a replica is rejected at apply, not applied-then-detected. `16` says replicas *"apply
   by verifying the checksum chain"* — the chain detects a *fork* but, like litefs, detection is not
   rejection-of-the-stale-fence. Add: replicas reject any entry whose fence ≤ their applied fence.

**Why this is a Major and not a Critical:** unlike `15`, nothing in `16`'s architecture *prevents* the
fix — `16` owns the append, the lease client, and the apply path, so all three gaps are closable by
writing spec and code `16` is already committed to writing. It is the difference between "you have not
yet specified the fence correctly" (`16`) and "your chosen dependency forbids you from enforcing the
fence on the durable append" (`15`). A Major you can close beats a Critical the architecture imposes.

**Required fix for `16`:** Specify (1) the fencing token = the lease KV's monotonic fencing epoch (not
the local tip), threaded into the entry; (2) that `rs_ltx_cas_append`'s CAS reads the durable head fresh
and is atomic with the durable write, and that the post-fsync lease re-validation gates the ack; (3) that
the `ltx-rs` replica apply path rejects entries with a fence ≤ applied. With these three, `16` *discharges*
C4 — the first plan in this whole document set to do so at the storage layer.

---

### F5. [MAJOR — `15` Go, MINOR — `16` Rust] Idempotency-across-handoff (P3 / `08 Finding 3`): both dedup against trunk history read in the serialized section, but `15`'s two-process split means "trunk history" is itself split between go-git and litefs, widening the dedup miss window.

**Claim attacked.** Both: dedup by idem-key against trunk history in the same critical section. `15 §5`:
*"dedup by idem-key against trunk history (same critical section)."* `16 §5` step 3: same.

`08 Finding 3` established: dedup is only as consistent as the replication of the thing you dedup
against; across a handoff inside the loss window, the new leader may not have the old leader's last
landed commit, so the dedup query misses and a retry duplicates. **Both plans inherit this** — it is a
property of async single-leader, and neither has added the two fixes I asked for (couple dedup durability
to land durability; make re-land of a present key a content-equal no-op that re-returns the original seq;
key downstream side-effects on landed-seq not on submit). So both carry the base P3 residue.

But `15` makes it **worse**: the idem-key lives in the **go-git commit trailer** (`15 §4.1`, §8 P3),
while the *ordering and replication* of whether that commit "counts as landed" lives in the **litefs LTX
log** in a *different process*. So "read trunk history for key K" must read go-git's commit graph — but a
commit object can exist in go-git (F2: written by process A) **without** a corresponding litefs seq
(process B never recorded it). So the dedup query can find K in go-git and conclude "already landed" for
a commit that was *never actually ordered/replicated* (the F2 torn land), or miss K because it queries
litefs's log instead of go-git's objects. The two-process split (F2) **widens the dedup-miss / dedup-
false-hit window** beyond the base handoff race. `16`, single-process, has only the base handoff race.

**Required fix:** Both — implement the `08 Finding 3` fixes (content-equal no-op on present key; couple
dedup durability to land durability width; side-effects keyed on landed-seq). `15` additionally — define
*which* store is authoritative for the dedup read (it must be the ordered log, not the go-git object
presence, because object presence ≠ landed), and confront that this read now crosses the process boundary
of F2.

---

### F6. [MINOR — both] Read-your-writes deadlock under partition (P4 / `08 Finding 4`): both specify the cookie + timeout→leader-fallback, both fail to state the double-partition explicit-fail. Tie.

**Claim attacked.** `15 §4.3`: *"on timeout it falls back to the leader with a stated staleness bound
(P4 — no deadlock under partition)."* `16 §6.4`: *"timeout → leader fallback with a stated staleness
bound (avoids the partition deadlock)."*

Both correctly carry the `08 Finding 4` fix (timeout → leader fallback, don't wait forever). Both **fail
to state the residual case I required**: if the client is partitioned from *both* the caught-up replica
*and* the leader, the read must **fail explicitly** with "cannot satisfy read-your-writes under
partition," not deadlock and not silently serve stale. Neither plan writes that line. And neither gives
the actual staleness *number* — both say "stated staleness bound" without stating it. This is a genuine
tie: same fix carried, same gap left. **Minor against both.**

**Required fix for both:** Add the explicit-fail-on-double-partition case and write the `T_ryw` number
and the staleness bound, per `08 Finding 4`.

---

### F7. [MINOR — both] "Linearizable trunk landing because one leader + one append-only trunk" reappears in both, and it is the same overclaim I struck in `08`.

**Claim attacked.** `15 §4.3`: *"trunk landing is linearizable because one leader + one append-only
trunk, not because of consensus."* `16 §6.4`: *"Linearizable trunk landing holds because one leader +
one append-only trunk, not consensus."*

This is **verbatim the sentence I struck in `08 Finding 1`** as false-as-written. It is linearizable
*only while the lease provides a single writer*; during a handoff window it is not. `15` at least follows
it with the honest async-window paragraph; `16` likewise qualifies it. But both still lead with the
false causal claim. Since `16` is the one that can *actually fence* (F4), `16` is closer to *earning*
the word — but neither has earned it yet, and both should restate it as in `08`: *"linearizable under the
single-writer assumption the lease provides; the lease can fail to provide it during a handoff window,
in which case [`15`: the fork is detected and the stale fork discarded] / [`16`: the stale appender's
CAS fails and its land returns an error]."* Note the two correct continuations are *different*, and that
difference is the whole review: `15`'s honest continuation is "data loss," `16`'s is "honest error."

**Required fix:** Strike the bare "linearizable because one leader" from both; substitute the
lease-conditioned guarantee with each plan's *correct* (and different) failure continuation.

---

## Your prior Criticals/Majors — which variant handles each better

| `08` finding | `15` Go/litefs | `16` Rust/ltx-rs | Better |
|---|---|---|---|
| **C4/P1 — fencing token CAS'd on durable append** | **Cannot, by construction (F1).** litefs owns the append; the `LtxAppendFenced` CAS is either bypassed (litefs owns the write) or a per-process counter (you own a second write path). Re-imports the v2 Critical. | **Can, and sketches it correctly (F4).** Owns the append; CAS is in the durable write. Under-specified (token source, distributed-vs-process CAS, replica apply) but *closable*. | **`16`** — decisively |
| **P2 — ack carries durability width** | Carried (`§4.2`/§4.3, returns achieved width). | Carried (`§6.2`, returns width). | Tie |
| **Async failover loss window** | Inherited; resolved by litefs **detect-then-discard = data loss**. | Inherited; *can* convert stale land to **honest error** (if F4 closed). | **`16`** |
| **P3 — idempotency across handoff** | Base race **+ widened by two-process split (F2/F5)**: object presence ≠ landed; dedup read crosses process boundary. | Base race only; single-process recovery rebuilds ordering from content (`§7` fsync-crash test). | **`16`** |
| **P4 — RYW deadlock under partition** | Cookie + timeout→leader; missing double-partition explicit-fail + number. | Same: cookie + timeout→leader; missing double-partition explicit-fail + number. | Tie |
| **`08 F5` — split-brain recovery semantics stated** | Undischarged; inherits litefs discard, doesn't spec winner/notification. | N/A under correct fence (stale land fails, no fork to recover) — *if* F4 closed; else same gap. | **`16`** (if F4) |
| **Type-layer fence (`lease-witness`)** | Identical, correct. | Identical, correct. | Tie |
| **Atomic land authority (one process, one fate)** | **Split across two processes (F2).** | Single address space, single fate. | **`16`** |

`16` is better or tied on every line, and strictly better on the four that matter most (C4, the loss
window, P3, atomicity). The only axis where `15` could claim an edge — "battle-tested code" — is
*neutralized for the consistency-critical component* by F1: the part of litefs you'd be trusting (its
async lease + detect-then-discard) is exactly the part `08` flagged as not-a-fence, and the part you'd
have to rebuild yourself (the fenced append) is the part Go's reuse argument was supposed to give you for
free.

---

## Sounder consistency: **Rust (`16`)** — and the honest weighing

**On consistency alone, `16` wins, and it wins for one structural reason: it owns the append, so it can
put the fence where `08` says the fence must go — CAS'd on the durable, single-writer append, atomic
with the durable write. `15` cannot, because litefs owns the append, and litefs's append is async-leased
with detect-then-discard recovery, which *is* the "lease is not a fence" Critical I raised in v2.**
Reusing the real litefs does not give `15` a sounder consistency story; it **re-imports the exact
consistency weakness** of the v2 Critical and dresses it in a `LtxAppendFenced` function that, on close
reading, either does nothing (litefs owns the write) or is a per-process counter (you own a second
write). Add the second-failure-domain problem (F2 — trunk-tip authority split across two processes that
can't commit atomically), which `16` simply does not have, and the consistency gap is not close.

**Now the fair part, because the prompt rightly demands it.** Reusing proven code has real, non-consistency
value, and I will not pretend otherwise:

- **litefs is operationally battle-tested.** Its failure-detection, replica streaming, recovery
  plumbing, and ops surface have been run in production at Fly.io. `16`'s hand-built leased-primary on
  `ltx-rs` is **unproven** — and replication layers are exactly where hand-rolled code grows subtle bugs
  (the very kind I'm paid to find). `16 §9.2` is honest that "more control, more code, more bugs that are
  yours."
- **A weaker but *known* consistency model can be safer in practice than a stronger but *unproven* one.**
  litefs's sub-second async loss window is *characterized, documented, and survived in production*. `16`'s
  fence is *correct on paper* and *unproven in the field*; a fence with a subtle bug (e.g. F4's
  per-process-counter trap, or a fence-epoch that isn't actually monotone across a lease handoff) can be
  *worse* than litefs's honest, known window — because at least litefs *detects* the fork. An incorrectly-
  built fence that *thinks* it fenced but didn't gives you false confidence, which is the worst state.
- **So the verdict is conditional, and the condition is `16`'s F4.** `16` has the *sounder consistency
  architecture* and is the *only* plan that can discharge C4 at the storage layer. But it earns the win
  on consistency **only if it actually closes F4** — sources the fence from the lease epoch (not the
  tip), makes the CAS a distributed fence against the durable head (not a process counter), and enforces
  the fence on the replica apply path. Until F4 is closed, `16` has a *better-shaped* but *not-yet-correct*
  fence, and `15` has a *proven* but *consistency-weaker* (and self-contradictory) one.

**My call, stated as plainly as I can:** for a team that will *invest in getting the fence right and
Jepsen-test it*, **`16` (Rust) is the sounder consistency story** — it is the only one of the two whose
architecture permits the `08` fix, it avoids the two-process authority split entirely, and it can turn a
stale-leader land into an honest error instead of silent data loss. For a team that will *not* do that
verification work and wants the lowest operational surprise *today*, `15` (Go/litefs) gives you a known,
documented, weaker consistency window — but **only if `15` first resolves F1 honestly by admitting it
inherits litefs's async-lease/detect-then-discard semantics and drops the false "CAS the fence on the
durable append" claim.** A `15` that keeps that claim is the most dangerous of all the variants, because
it tells the reader the fence is there when the dependency it reuses forbids it.

**One-line answer:** *Rust (`16`) has the sounder consistency story, because it owns the append and can
therefore fence the stale leader at the durable write — the exact fix `08` demanded — whereas Go (`15`)
reuses litefs's async lease and detect-then-discard recovery, which re-imports the v2 "lease is not a
fence" Critical and additionally splits trunk authority across two processes; `16`'s advantage is
*architectural and real*, but it is *conditional on actually building the fence correctly (F4)*, which
litefs's maturity would have given `15` for free if litefs fenced — and it doesn't.*
