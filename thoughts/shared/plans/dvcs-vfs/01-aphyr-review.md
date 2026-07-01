---
date: 2026-06-25
reviewer: "Kyle Kingsbury (persona)"
status: review
topic: "Adversarial distributed-systems review of metavfs architecture (00-architecture.md)"
target: thoughts/shared/plans/dvcs-vfs/00-architecture.md
tags: [review, jepsen, raft, linearizability, cas, consistency, fault-model]
---

# Jepsen-style review of `metavfs` (00-architecture.md)

## Verdict

The skeleton is sound and, unusually for a document I'm handed, it has *already done a lot of my job for me* — §9.3 and §10 enumerate several of the real landmines instead of pretending they don't exist, and the central insight (replicate hashes through Raft, replicate bytes out of band, verify by re-hash) is correct and is the one load-bearing idea that makes the whole thing tractable. But the design is **not yet safe to implement**: it repeatedly *names* the hard problem and then *gestures* at a fix without specifying the protocol that makes the fix correct, and in several places the prose contradicts itself about what is authoritative. The two structural errors are (a) treating the substrate `:land-job` row as a place where ordering/claiming/idempotency live, when the Raft log is supposedly the only authority — you cannot have two sources of truth and call the result linearizable; and (b) acking durability on the wrong event (leader CAS-presence + Raft-majority-of-*metadata*, with zero quorum on the *bytes*), which produces a perfectly consistent pointer to data that does not exist anywhere. It is **salvageable**, not broken — but at least four Critical issues must be closed in the spec before anyone writes a line of `packages/raft/`.

---

## Findings

### 1. [CRITICAL] `take!` and the Raft log are two authorities for the same fact; the "reconcile on leader transition" hand-wave hides a real split

**Claim attacked.** §4.3: "*Intra-node atomic claim: `(take! :land-job/status :pending :new-value :landing)` ... Linda `in()` semantics guarantee exactly one worker thread claims a given job.*" §9.3 (mitigation): "*reconcile-against-log on startup as primary, with `transact!`-backed claims as belt-and-suspenders.*" §5.2: "*the RSM register is the source of truth, the substrate is the queryable projection.*"

I read `linda.lisp:39`. Confirmed: `take!` mutates `update-entity-cache` + `update-value-index` **under `store-lock` but never fires hooks** — and hooks are where `transact!` (`store.lisp:124`) does LMDB persistence. So a `take!`-claim is an in-memory, non-durable, **single-node** state transition. That is fine intra-node. The problem is that the design also uses the *substrate* `:land-job` row to carry `:pending/:landing/:landed/:rejected/:failed`, `attempts`, `idempotency-key`, and to *select* the next job (§4.3 "sort candidate jobs by `(parent-seq, created-at)`"). Selection and claiming therefore happen in a data structure that Raft does not order. The "fast path" claim, the conflict check, and the rebase all read trunk state and job state from this non-authoritative projection, then *propose* to Raft. There is a TOCTOU between "what the leader read from substrate to make the land decision" and "what the log actually commits."

**Concrete history (claim disagrees with commit across a partition):**
1. Cluster {L1, F2, F3}. L1 is leader, term 5. trunk.tip = seq 100.
2. Job J (idempotency-key K, parent-seq 100, paths {`a/x`}) is enqueued as a `:land-job` row on L1's substrate.
3. L1's land worker `take!`-claims J → in-memory `:landing`. **No log entry yet, nothing durable.**
4. L1 runs conflict check (tip==100==parent → fast path), calls Shen, **proposes** `:land seq=101 change=H`. The `AppendEntries` reaches L1's disk and is in flight to F2/F3.
5. Network partitions L1 away from {F2,F3} *after* L1 locally appended index-i but *before* a majority acked. L1 has NOT committed (no majority), so it has NOT acked the client.
6. Election timeout fires on the {F2,F3} side. F2 becomes leader term 6, appends `:noop`, learns tip is still 100 (i-th entry was never replicated). J's row does not exist on F2/F3 at all (it was only ever written to L1's substrate; submit hit L1).
7. Client times out waiting for ack, retries J with **same key K** — but its leader cache points at L1 (partitioned) → it eventually discovers F2 and resubmits to F2. F2 has never seen K. Presubmit idempotency check (§4.2 step 4: `find-entities :land-job/idempotency-key K`) **queries F2's local substrate, finds nothing**, enqueues a fresh job, lands it at seq 101.
8. Partition heals. L1 steps down, truncates its uncommitted index-i (Raft log reconciliation). Its in-memory `:landing` claim for J is reconciled "against the log" → no committed `:land` for J's change-hash → J is re-`pending`-ed. L1's land worker (now follower) does nothing. **But J's change already landed via F2 at seq 101 under a different job row.** If by bad luck the client had *also* resubmitted to a now-recovered L1 path, you'd re-land H a second time at seq 102 — unless `landed-keys` saves you, which it only does if the change-hash is identical *and* still inside the dedup window (see Finding 7).

The deeper bug: **idempotency state is per-node substrate, not in the RSM**, so `find-entities :land-job/idempotency-key` is a per-node query that gives different answers on L1 vs F2. The design *says* `landed-keys` lives in the RSM (§5.2) — good — but the **presubmit** idempotency check (§4.2 step 4) explicitly uses the substrate projection, not the RSM. Two dedup mechanisms, two scopes, and the one on the submit path is the non-replicated one.

**Required fix (must-specify before implementation):**
- The submit/idempotency record must be a **Raft command**, not a substrate row. Either (a) submit appends a `:submit key=K job=...` entry to the log so every replica's RSM has the key before any land decision, or (b) the idempotency check is performed *only* at apply time against `landed-keys` in the RSM and the presubmit substrate check is explicitly labeled a non-authoritative fast-reject hint that may produce duplicates (which then MUST be caught at apply — meaning apply must dedup on `(idempotency-key)` not just `change-hash`, because a retry that produced different bytes/rebase has a different change-hash but the same key).
- `take!` must be demoted from "claim primitive" to "leader-local scheduling hint with no correctness role." State explicitly: **nothing about the durable land decision may depend on the substrate `:land-job` status.** The leader selects a candidate, but commitment is *only* the Raft `:land` apply. Re-`pending`-ing on reconcile must key off RSM `landed-keys`, never the in-memory `:landing` flag.

---

### 2. [CRITICAL] Durability is acked on metadata quorum + leader-local byte presence — the bytes have **zero** replication guarantee at ack time

**Claim attacked.** §5.4: "*a land does not require every replica to already hold the blobs. It requires the leader to have verified the blobs exist ... The committed log is valid even if a follower is temporarily missing a referenced blob.*" §9.1 I4: "*No lost committed land. Once a land is acknowledged to a client (committed on majority), it survives any minority failure.*" §9.2: "*a blob can be absent but never wrong.*"

"Absent but never wrong" quietly redefines durability to be about the *pointer*, not the *data*. I4 is true for the metadata and **false for the content**. Walk it:

**Concrete history (committed land points to data that exists nowhere):**
1. {L1, F2, F3}. Client uploads new blob B (only to L1 — §5.4 "the client pushes new blobs to the node it contacts"). B exists on L1's in-memory content-store only (`content-store.lisp`: it's a hash table; `store-put-blob` doesn't touch LMDB or peers).
2. Client submits land referencing B. L1 presubmit: `store-blob-exists-p` on L1 → true. L1 proposes `:land`, F2 and F3 ack the *metadata*. Majority commit. L1 advances tip, acks client: "landed at seq 101." **I4 says this is durable.**
3. Out-of-band blob replication has not yet copied B to F2 or F3 (it's lazy/gossip, §5.4).
4. L1's disk dies / host is destroyed (not a clean crash — permanent loss). This is one node = a minority failure. I4 promises survival of minority failure.
5. F2 elected. tip = 101 (metadata committed). Trunk says: seq 101's root-node references blob B. **B existed only on L1 and is gone.** Every `read()` of that file across the cluster faults-in B from peers, finds it nowhere, and fails forever. The "linearizable trunk tip" now authoritatively points at unrecoverable content.

The metadata land survived a minority failure exactly as I4 promises. The *file content* did not. The system has lost committed user data while reporting the land as durable. "Absent but never wrong" is cold comfort: a file that reads as a permanent I/O error is, operationally, wrong.

**Same class, GC variant** (§5.4 GC): a leader-proposed GC horizon makes a blob collectable based on *trunk reachability*, but a follower that already fetched B may GC it while another follower never had it, and a recovering node rebuilds reachability from the log — reachability says B is live, but no extant replica holds the bytes. GC correctness is about *bytes existing on ≥1 live node*, which the reachability calculation does not track at all.

**Required fix (must-specify before implementation):**
- The land must not commit (or must not *ack*) until the referenced **new** blobs are present on a quorum (or at least f+1 nodes) of replicas. Options: (a) a pre-land "blob barrier": leader requires `R` followers to confirm `store-blob-exists-p` for all new blobs before proposing `:land`; carry the confirmation set in the entry. (b) Decouple: blobs may replicate lazily, but a land's *ack* to the client is delayed until durability-width is met, and the trunk tip is allowed to advance past not-yet-durable blobs only if you accept reads can hard-fail. Pick one and **state the durability width and the failure semantics of a read against a not-yet-replicated blob** (error? block-until-fetched-or-timeout?). Right now §5.4 implies the tip can advance with byte-durability = 1, which is not a quorum and violates I4 for content.
- State a **GC safety invariant in terms of byte replicas**, not reachability: "a blob is collectable only if unreachable from the retention horizon AND ≥ R replicas would still ... " — actually the correct statement is the inverse: *never collect a reachable blob*, and *track a per-blob replica count*; GC of an over-replicated copy on one node is fine, GC of the last copy of a reachable blob is the data-loss bug above.

---

### 3. [CRITICAL] Stale-allow / privilege escalation across an `:acl` commit — the version-keyed cache does not order ACL changes against in-flight lands and reads

**Claim attacked.** §6.3: "*Cache is invalidated by version bump whenever an `:acl` entry commits through Raft ... the `acl-ruleset-version` is the Raft index of the last `:acl` entry, so it is globally consistent.*" §9.1 I6: "*A read never returns content the principal is not authorized to read at the ruleset version current at the read's linearization point.*"

Keying the cache by Raft index is the right *idea*. But the design has two distinct evaluation points for a land (presubmit `acl-can-submit?` §4.2 step 3, and land-time `acl-can-land?` §8.3) and never pins which ruleset version is authoritative at *apply*. The apply function (§5.2) is declared Shen-free and clock-free — good — which means **ACL is NOT re-checked inside apply.** So the binding land-eligibility decision is made by the *leader, before propose*, against whatever `acl-ruleset-version` the leader had cached. Between that check and the commit, an `:acl` entry can interleave in the log.

**Concrete history (privilege escalation / stale-allow on land):**
1. trunk tip seq 100, acl-version = index 500. Rule R500 grants principal P `:write` on `a/`.
2. Admin submits an `:acl :del R500` (revoke P's write on `a/`). It's accepted and will commit at index 540.
3. P submits a land touching `a/x`. Leader presubmit and land-eligibility both consult the cache at acl-version 500 → **allow**. Leader proposes `:land` at log index 541 (i.e. *after* the revoke at 540).
4. Log order: 540 = revoke, 541 = P's land. Apply replays in order: at 540 P loses write; at 541 the `:land` applies **with no ACL re-check** (apply is policy-free) and lands P's change to `a/x`. P wrote to a path P is no longer authorized to write, and the write is *after* the revoke in the linearized order. I6 violated for `:write`; by symmetry the same hole exists for `:read` if any read decision is cached and consumed after a revoke commits.
5. The cache invalidation at index 540 *does* bump the version — but it bumps it on whichever node applies 540; the **leader already made its allow decision before proposing 541**, and nothing re-validates at apply. The version bump closes the cache for *future* questions, not for the in-flight land whose decision was already cached and is now being committed *behind* the revoke.

This is a classic TOCTOU: time-of-check is "leader cache at propose," time-of-use is "apply at index 541," and an authorization-changing event (540) slipped between them. The cache being globally-consistent-by-index does not help, because the consuming decision was taken at an earlier index and never re-taken.

**Required fix (must-specify before implementation):** the land entry must **carry the acl-version it was authorized against**, and apply must reject (or the leader at commit must re-verify) any `:land` whose authorizing acl-version is older than the acl-version current in the RSM at the entry's apply point — i.e. fence the land on `entry.acl_version >= rsm.acl_version_at_apply`, or make apply re-run the (now deterministic, Datalog-only, cache-free) ACL check against the RSM ruleset. The latter contradicts "apply is policy-free," so you must either (a) admit a *deterministic, side-effect-free* Datalog ACL evaluation **into** apply (allowed — it's pure if it reads only RSM state), or (b) fence on version monotonicity. Pick one and write it. For reads, state the read's linearization point explicitly and require the read decision's acl-version == the version at that linearization point (a leader-lease read fixes both tip and acl-version atomically; a follower read is stale on *both* and must be labeled as such — see Finding 6).

---

### 4. [CRITICAL] "Linearizable" is asserted for the trunk but the read path that delivers it depends on an unstated clock-skew bound (leader lease), and follower-read-your-writes can deadlock

**Claim attacked.** §5.6 table: "*Trunk tip (authoritative): Leader read with a read lease ... Linearizable.*" §9.1 I... and §5.6 "*a stale leader that lost quorum ... its lease expires.*"

A leader read-lease is a **clock-based** optimization: the leader serves linearizable reads without a round trip *because* it believes its lease has not expired, and lease expiry is measured against a local clock. This is only safe under a **bounded clock-skew / bounded-pause assumption**, and the document never states it. The fault model in the persona (and in §9) explicitly admits "*processes pause arbitrarily (GC, swap)*." A leader that GC-pauses for longer than its lease, while a new leader is elected, can answer a "linearizable" tip-read from stale state believing its lease is still valid.

**Concrete history (lease read returns stale tip):**
1. L1 leader, lease granted at local time t0 for duration Δ. tip = 100.
2. L1 enters a stop-the-world GC pause at t0+ε (the design runs on SBCL — this is not hypothetical).
3. {F2,F3} time out, elect F2 (term+1), F2 lands seq 101, 102. New tip = 102.
4. L1 resumes at t0+Δ+δ. **From L1's frozen perspective, only ε of wall time passed**; its lease check uses elapsed monotonic time, but if it reads the clock once at resume and compares to t0, and the pause is accounted as "still within Δ" due to a coarse or wall-clock-based check, L1 answers a tip read = 100. Linearizability violated: a read returned a value (100) that was overwritten (→102) before the read began in real time.

Even with a *correct* monotonic-clock lease, you must state: **lease safety requires `lease_duration < election_timeout − max_clock_error − max_pause`**, and you must bound `max_pause`, which on SBCL means bounding GC. The document claims linearizable reads without stating this. As written, the linearizability claim is unsubstantiated.

Separately, the **read-your-writes** row (§5.6: "*reads require `applied-seq >= my-seq` (wait or redirect)*") has a liveness hole: a client that did its land via the leader, then reads from a follower that is partitioned from the leader, will wait for `applied-seq >= my-seq` **forever** (the follower never catches up while partitioned). "Wait or redirect" is underspecified — redirect to whom, with what timeout, and does the client fall back to a leader-lease read? State the bound or it's an availability bug.

**Required fix (must-specify):** State the leader-lease clock assumption explicitly (`lease < election_timeout − clock_error − max_pause`), bound `max_pause` (SBCL GC), and prefer a **read-index / quorum-confirmed read** over a lease read for the "linearizable tip" row unless you accept the clock dependency in writing. For read-your-writes, specify a timeout → fall back to leader read-index. Until then, do not call follower-served reads "linearizable" anywhere.

---

### 5. [MAJOR] Two simultaneous lands: the "linear seq" invariant is fine, but the auto-rebase mutates content the client never saw and re-hashes a change the author didn't author

**Claim attacked.** §3 "*demote the DAG to a strictly linear append-only chain*"; §4.4: "*No overlap → auto-rebase: re-parent the job onto tip, recompute the root-node by replaying the job's `tree-diff` onto the tip's manifest.*" §9.1 I1: "*no gaps and no forks.*"

I1 (linear seq, single leader assigns seq=tip+1) holds — Raft genuinely gives you that, and demoting the DAG is sound for *ordering*. Where linear-seq assumptions break is not ordering, it's **identity and authorship under auto-rebase**:

- The `:change/hash` is `sexpr-hash` over the change record including `root-node` and `parent` (§3.3). Auto-rebase **recomputes root-node and re-parents**, so the landed change-hash is **not** the change-hash the client submitted or signed off on. If `idempotency-key`/`landed-keys` dedup on `change-hash` (§5.2), the post-rebase hash differs from any the client could precompute, so a client retry across a rebase cannot be deduped by change-hash — only by idempotency-key (reinforcing Finding 1's requirement that the key, not the hash, be the dedup authority).
- "No overlap" is computed by **path-overlap**, but two lands can be path-disjoint and still semantically conflict (rename `a/foo`→`b/foo` while another land adds `b/foo`; or a delete-of-directory racing an add-under-directory). The manifest-node fast path (§4.4) compares child-node hashes for untouched subtrees — but a directory-level rename touches *both* `a/` and `b/` subtrees, so it's "touched" and falls to `tree-diff`, which diffs *flattened entry lists for a given subtree*. Whether `tree-diff` detects an add-vs-add at the same post-rebase path, or silently produces a manifest where one land's add is clobbered, is **not specified**. Concrete: Land J1 adds `b/foo`=Hx; concurrently J2 renames `a/foo`→`b/foo`=Hy. Both based on tip 100, disjoint *source* paths until you compute the *result*. Lander picks J1, lands `b/foo`=Hx at 101. J2 rebases onto 101: replaying J2's diff (delete `a/foo`, add `b/foo`=Hy) onto tip-101 manifest — does it detect that `b/foo` already exists (overwrite-on-rebase, silent data loss) or conflict? Undefined.

**Required fix (must-specify):** Define conflict in terms of the **post-rebase result manifest**, not just source-path overlap: a rebase that would overwrite a path the rebasing change did not itself previously observe at that value is a conflict, not a silent merge. Specify `tree-diff`/rebase behavior for add-vs-add, delete-vs-modify, rename targets. And state that the landed `:change/hash` is necessarily a *system-assigned* identity post-rebase, distinct from the client's submitted content identity, so no downstream logic may assume the client can predict it.

---

### 6. [MAJOR] RSM apply has a substrate side effect, which makes apply non-pure and opens a crash window the doc acknowledges but does not close

**Claim attacked.** §5.2: "*as a substrate side effect on the leader and followers, `transact!` the `:change` entity and update the `:trunk` entity ... The substrate write is downstream of and slaved to the RSM.*" Then §5.2: "*Determinism requirement: apply must be a pure function of the log.*" §9.3: "*If a node's substrate write fails after the log commits, the projection lags ... a startup consistency pass repairs it.*"

You cannot in the same breath say "apply has a `transact!` side effect" and "apply is pure." It's not pure — it writes to LMDB, which can fail, partially apply, or fsync-lie. The design's own §9.3 catches this and says "rebuild by replaying the log." Fine — but then the apply function's *substrate write must be idempotent and replay-safe*, and that is not specified. `transact!` is not idempotent in general (it appends datoms; replaying a `:change` assertion twice yields two assertions of the same EAV which the EA-current cache may or may not collapse). Concretely:

1. Apply index 541 (`:land seq=101`): RSM advances tip in-memory. Begins `transact!` of `:change` seq=101 entity.
2. Crash between RSM-tip-advance and LMDB fsync of the `:change` row (or LMDB fsync-lies and the page is lost on power-cut).
3. Restart: RSM snapshot + log replay rebuilds tip=101 in-memory. Apply re-runs index 541's substrate side effect → `transact!` the `:change` seq=101 entity **again**. If the prior partial write left a half-row, you now have divergence between this node's projection and a peer that applied cleanly once.

The "startup consistency pass" (§9.3, modeled on `consistency.lisp:504`) is named but its repair semantics are not defined, and a consistency *check* is not a consistency *repair* protocol.

**Required fix (must-specify):** Make the apply→substrate projection **idempotent by construction**: the projection write must be a deterministic function of `(seq, change-hash)` that, replayed, produces the identical EAV (e.g. write with a fixed entity-id derived from seq, use `:replace`-cardinality datoms, and make replay an upsert). State explicitly that the substrate projection is *truncatable and fully rebuildable* from the log+snapshot, and that on any divergence the projection is discarded and rebuilt rather than repaired in place. Also: the side effect must be the *same on leader and followers* and must not depend on any leader-local state (e.g. the `:land-job` row, which followers don't have — see Finding 1).

---

### 7. [MAJOR] Idempotency window is unbounded in spec and the "ancient parent-seq saves us" argument is false for re-adds

**Claim attacked.** §5.5: "*`landed-keys` is bounded ... a duplicate beyond the window would re-land, but by then the client's parent-seq is ancient and the conflict/rebase machinery catches it — we accept this as the documented bound.*" §4.5: "*At-most-once landing.*"

The window size is never given (it's "large enough to cover the maximum client retry horizon" — an undefined quantity). Worse, the safety argument is wrong: "ancient parent-seq forces a rebase" only catches the duplicate if the duplicate's content **conflicts** on path-overlap with something landed since. A duplicate that re-adds a *new* file at a path nobody else touched has no overlap → **auto-rebases cleanly → lands a second time.** Example: client submits "add `docs/new.md`", it lands at seq 101, ack lost, `landed-keys` evicts K after the window, client retries K hours later. No one touched `docs/new.md` since. Conflict check: no overlap → auto-rebase → lands again at seq 5000 as a duplicate add (or a no-op-but-recorded change). At-most-once is violated; you got at-least-once. The "documented bound" is documented but its safety justification doesn't hold.

This compounds with Finding 1: because the *submit-side* idempotency check is the per-node substrate row, and the *apply-side* check is `landed-keys`, and `landed-keys` is evicted, there is no durable, replicated, permanent dedup of a logical submission.

**Required fix (must-specify):** Either (a) make idempotency keys permanent in the RSM (they're tiny — a set of opaque keys; with snapshotting the cost is bounded by retained-submission count, which for a monorepo land queue is not enormous), or (b) define the window in concrete time/seq terms AND change the client protocol so a retry beyond the window is *required* to use a fresh key, AND make the rebase machinery treat a clean-rebasing re-add as a no-op when the target path already holds the identical blob hash (content-equality → idempotent landing), which closes the at-least-once hole for the common case. State the chosen window numerically.

---

### 8. [MAJOR] Split-brain is correctly prevented for *commit* but the document never gates the land path on a current-term check **at apply/propose time** rather than submit time

**Claim attacked.** §9.2: "*the minority side cannot elect a leader → cannot land → no split-brain.*" §5.3: "*Only the leader runs the land worker.*"

True at the commit boundary — Raft majority prevents a minority leader from committing. But the design's land worker reads trunk state, runs Shen, computes rebase, and *then* proposes. The dangerous interval is a leader that **was** leader when it began draining a job and **is no longer** leader (or is in a new term) by the time it proposes. The doc relies on `am-i-leader?` (§5.3) but never says the leadership check is re-evaluated atomically with the propose, nor that the propose is fenced by the term the worker started in. A deposed leader whose `am-i-leader?` flag hasn't flipped yet (it's a local belief, updated on receiving higher-term RPCs which may be delayed by the same partition) can propose into a log that will reject it — harmless if Raft rejects, but the design also does substrate side effects and client-facing `:landing→:rejected` transitions based on the *worker's* belief, which can diverge from cluster reality and confuse retry logic.

**Required fix (must-specify):** The propose must be fenced: the `:land` entry includes the term the worker believed it held; Raft rejects an append from a stale term (standard) — *state this explicitly* and state that NO client-visible status transition or substrate side effect happens until the entry **commits**, never on propose. "Only the leader runs the worker" is necessary but not sufficient; you need "only a committed entry changes any state."

---

### 9. [MAJOR] The Shen single global lock is a control-plane liveness hazard even off the hot path — and the cache invalidation runs through it

**Claim attacked.** §6.3: "*the Shen lock never sits on the synchronous land path.*" §10.3: "*an `:acl` change forces a Shen recompile under `*shen-lock*`.*"

Confirmed in `bridge.lisp:14`: `*shen-lock*` is a single non-recursive `bt:make-lock`, and *every* `shen-eval`/`shen-query` serializes on it. The hot path is plausibly protected by the Datalog fallback + cache. But consider the **control-plane liveness** under the design's own apply semantics: §5.2 says an `:acl` apply must "*invalidate the Shen decision cache*" and §6.3 says Shen recompiles ACL rules under the lock. If apply is required to recompile/invalidate via Shen, and apply runs on **every replica in log order**, then a slow Shen recompile under the global lock **stalls log apply** on that replica — which stalls its tip advance, which stalls follower reads and read-your-writes (Finding 4). A single pathological rule recompile becomes cluster-wide apply latency. Worse: a thread holding `*shen-lock*` that GC-pauses or errors without unwinding (non-recursive lock, no `with-lock` shown around the recompile path in apply) can deadlock the control plane permanently — there is no lock timeout in `bridge.lisp`.

**Required fix (must-specify):** Apply must **never** call Shen. ACL changes apply as *data* (update the `acl-rules` pmap in the RSM — pure), and any Shen recompilation is an **asynchronous, off-apply** materialization that the hot path does not wait on (the Datalog evaluator reads the pmap directly). State that the decision cache is invalidated by a pure version bump in apply (no Shen call), and that Shen compilation is best-effort/offline. Otherwise the global lock is on the apply path, transitively on every read.

---

### 10. [MAJOR] No stated fsync/durability semantics for the Raft log itself; "committed on majority" is asserted but the disk is assumed honest

**Claim attacked.** §9.1 I4: "*committed on majority ... survives any minority failure.*" The persona's fault model: "*disks fsync-lie.*"

Raft's durability guarantee requires that a node which acks an `AppendEntries` has **fsync'd the entry to stable storage** before acking. The document never states that the Raft log writes are fsync'd before ack, nor what storage backs the Raft log (LMDB? a separate WAL?). If the log is buffered and a power-cut loses a "committed" entry on f nodes simultaneously (correlated failure: same rack, same PDU), a committed land is lost — I4 violated. The CAS content-store is in-memory (`content-store.lisp`), and §3.1/§10.5 note the LMDB blob DB is unbuilt — so *today* nothing is durable at all, but even in the target design the log durability contract is unstated.

**Required fix (must-specify):** State that Raft log append is fsync-before-ack, name the storage (and whether you trust LMDB's `MDB_NOSYNC`/sync semantics — by default LMDB is durable but the design must not run it in a nosync mode for the log). State the correlated-failure assumption (you survive f independent failures; correlated loss of f+1 is outside the model — say so).

---

### 11. [MINOR] "Linearizable trivially" for historical reads is fine but assumes no log truncation race

**Claim attacked.** §5.6: "*Historical change `seq=k`: Any node, immutable. Linearizable trivially.*"

Immutable history is linearizable *once a node has it*. But a follower that has snapshotted+truncated its log prefix, or a freshly-added node that hasn't caught up, may not have `seq=k` yet, or may serve a `seq=k` from a manifest whose blobs it lacks (Finding 2). "Any node" is too strong: a node that hasn't applied through k returns not-found, not the value. That's not a linearizability violation, but the table overstates availability. Tighten to "any node that has applied through seq≥k AND holds the referenced blobs."

---

### 12. [MINOR] The land-queue stall (liveness) conditions are not enumerated; backpressure is deferred to P7

**Observation.** §11 puts backpressure in P7 "Hardening," but the safety/liveness boundary deserves a statement now. The land queue STALLS forever (no land progresses) under: no quorum (correct — safety over liveness, good); leader elected but its substrate projection is corrupt/rebuilding; a job at the head of the `(parent-seq, created-at)` ordering that perpetually `:fails` and re-`:pending`s (head-of-line blocking — does a poison job block all subsequent disjoint-path lands? The single-leader, seq-ordered drain suggests **yes**). A poison land that always fails blob-presence (referenced blob genuinely lost) with bounded backoff re-pending forever is a head-of-line stall for the whole trunk. **Must-specify:** dead-letter policy for poison jobs and whether disjoint-path lands can proceed past a stuck head (they can — they're disjoint — but only if selection isn't strictly serialized; reconcile with §4.3's "select the head before claiming").

---

## What the design got RIGHT (load-bearing — do not regress)

- **Hashes in the log, bytes out of band, verify by re-hash (§5.4).** This is the correct and necessary architecture for a CAS monorepo on consensus; it is what makes RSM snapshots tiny (§5.5) and the whole thing tractable. Keep it — just fix the *durability width* of the bytes (Finding 2).
- **Single leader assigns `seq = tip+1`; client never assigns seq (§4.3, §5.2).** Correct. The linear-trunk invariant I1 genuinely follows from Raft single-leader-per-term + majority commit, *for ordering*. This is the soundest part of the document.
- **Apply must be deterministic, clock-free, RNG-free, Shen-free (§5.2, §5.8 reasoning).** Exactly right as a *goal*; the document then violates its own rule with a substrate side effect and an implied Shen call — but the stated principle is the correct one to hold the line on (Findings 6, 9).
- **Optimistic concurrency with structural-sharing-aware conflict detection at manifest-node granularity (§4.4).** The O(touched-subtrees) child-hash comparison is the right Sapling-class mechanism. It needs result-manifest conflict semantics (Finding 5), but the skeleton is correct.
- **Honest §9.3 / §10.** Naming the `take!` durability gap, the substrate-is-non-authoritative inversion, the Shen lock, the SBCL-NFS realism, and the GC-during-mutation problem *before* I had to — this is the behavior I want to see. The fixes are under-specified, but the hazards are correctly located.
- **NFS-loopback over in-kernel FUSE, with a no-mount checkout as P1 (§7.3, §10.4).** Realistic. Shipping the materialize-on-demand checkout first and treating the mount as a research subproject is the right risk ordering.
- **Substrate Datalog (terminating) for hot-path ACL, Shen as authoring surface (§6.3).** Correct instinct: keep the unbounded/global-lock engine off the evaluation path. Just ensure apply also never calls it (Finding 9).

---

## Prioritized gate list

### Must-fix before ANY implementation (Critical — the design is unsafe as written)
1. **Single authority for idempotency + claim (Finding 1).** Move the dedup key into the RSM; demote `take!`/substrate `:land-job` status to non-authoritative scheduling. No land state may depend on the non-replicated substrate row.
2. **Byte durability width (Finding 2).** Define how many replicas must hold a new blob before a land is *acked*, and the read-failure semantics for a not-yet-replicated blob. Restate GC safety in terms of *byte replicas*, not reachability alone.
3. **ACL TOCTOU / stale-allow (Finding 3).** Fence every land on the acl-version it was authorized against (`entry.acl_version >= rsm.acl_version_at_apply`), or admit a pure Datalog ACL re-check into apply. Define the read linearization point and its acl-version.
4. **Linearizability vs clock/lease + read-your-writes liveness (Finding 4).** State the lease clock assumption and SBCL-pause bound, or use read-index/quorum reads. Bound read-your-writes with a timeout→leader fallback. Stop calling follower reads "linearizable."

### Must-specify before GA (Major — needed for correctness under load, not blocking the first prototype if documented)
5. Result-manifest conflict semantics for rebase (add-vs-add, rename targets, delete-vs-modify) and the fact that landed change-hash is system-assigned post-rebase (Finding 5).
6. Idempotent, rebuildable substrate projection from apply; discard-and-rebuild on divergence (Finding 6).
7. Numerically-bounded idempotency window + content-equality no-op landing to kill the at-least-once re-add hole (Finding 7).
8. Term-fenced propose; no client-visible/substrate state change before commit (Finding 8).
9. Apply never calls Shen; ACL applies as pure data; Shen compile is async/offline (Finding 9).
10. Raft-log fsync-before-ack and storage backing; correlated-failure assumption stated (Finding 10).
12. Land-queue liveness: poison-job dead-letter + whether disjoint lands bypass a stuck head (Finding 12).

### Acceptable for v1 with a documented caveat
11. Historical/blob read availability wording — tighten "any node" to "any node applied-through-k with the blobs" (Finding 11). Document, don't block.
- The in-memory-only content-store and unbuilt LMDB blob DB (§10.5) are acceptable for P0/P1 *prototyping* provided no durability claim is made until the blob durability work lands — but the moment you ack a land as durable (Finding 2), this stops being acceptable.
