---
date: 2026-06-25
reviewer: "Kyle Kingsbury (persona)"
status: review
topic: "Adversarial distributed-systems review of the no-Raft, single-leased-leader mvfs direction brief (07-direction-brief.md)"
target: thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
  - thoughts/shared/plans/dvcs-vfs/01-aphyr-review.md
tags: [review, jepsen, litefs, lease, linearizability, single-leader, split-brain, async-replication, durability]
---

# Jepsen-style review v2 of `mvfs` (07-direction-brief.md) — the no-Raft pivot

## Verdict

This is a **much more honest document than the one I reviewed last time**, and dropping Raft was the
right call for the stated scale. Two of my four original Criticals genuinely **dissolve** — not
because you papered over them, but because the dual-authority structure that created them no longer
exists. Single leased writer + one append-only trunk is a legitimate, well-understood architecture,
and you correctly refuse to name-drop consensus you don't need.

**But the brief oversells one specific claim, and that oversell is load-bearing.** §6 asserts:

> "Trunk landing is linearizable *because there is one leader and one append-only trunk* — not
> because of consensus."

That sentence is **false as written**, and the gap between it and reality is exactly the gap LiteFS
itself does not close — LiteFS *detects* split-brain and *recovers by discarding a fork*, which is
data loss, not linearizability. A leased single-leader system is linearizable **only if a stale
leader's write is fenced from ever taking effect.** A Consul-TTL lease + a CRC checksum chain gives
you *detection after the fact*, not *fencing*. So the correct honest statement is: "Trunk landing is
linearizable **as long as the lease's single-writer guarantee holds; when it doesn't (GC pause /
clock skew / lease handoff), the trunk can fork, and the checksum chain converts that fork into
detected data loss for one side, not into a consistency violation you'll silently serve.**" That is
a *defensible* design. It is **not** the same claim as "linearizable," and a developer whose landed
commit is in the discarded fork will not care that you call the outcome "detected."

So: the pivot is sound, but the brief has **1 Critical** (the linearizability claim is unbacked and
the fencing mechanism is unspecified) and **3 Majors** (failover loss-window honesty, idempotency
across handoff, read-your-writes liveness). The fixes are mostly *spec-and-restate*, not
*redesign* — which is the whole point of having dropped Raft. Close the Critical and you have a
system whose guarantees match its prose.

**Counts: 1 Critical, 3 Major, 2 Minor.**

---

## Findings

### 1. [CRITICAL] "Linearizable because one leader, not because of consensus" is false: a lease gives you a *likely* single writer, not a *fenced* one. The checksum chain DETECTS the fork; it does not PREVENT it — and recovery is data loss.

**Claim attacked.** §6: *"Trunk landing is linearizable because there is one leader and one
append-only trunk — not because of consensus."* And §4 / §6: the landed-log is
*"append-only, checksum-chained ... each entry `(seq, commit-hash, prev-checksum, post-checksum)`;
entry N+1.prev == entry N.post"* reused as the LiteFS-style *"split-brain detection."*

Here is the distributed-systems fact the sentence elides. Linearizability of an append-only
register requires that **at most one process can successfully append at any real-time instant.**
"One leader" is an *intention*, enforced by a lease. A lease is a **time-bounded** grant whose
safety depends on every participant agreeing, within a bounded clock error, on when it expired. The
fault model you handed me explicitly admits *processes pause arbitrarily (GC, swap)* and *clocks
lie*. Under those faults, **two nodes can simultaneously believe they hold the lease.** Consul's
default is a 10s TTL (06-grounding-research §1); that is the width of the window.

**Concrete history (two leaders, one trunk, fork):**

1. Cluster: L1 (leader, holds Consul lease, TTL 10s, last renewed at local t0), R2, R3 (replicas).
   trunk tip = seq 100, landed-log head checksum = `C100`.
2. L1 accepts a submit for change H, runs admission + OCC (base == tip 100, fast path), and
   **enters a stop-the-world GC pause at t0+ε** (you are not on SBCL anymore, but OCaml 5 has a
   stop-the-world minor-GC and the `lwt_eio` bridge + irmin-pack add their own latency cliffs; a
   multi-second pause under memory pressure or a blocked io_uring submission is not exotic).
3. L1's lease TTL elapses in real time. Consul does not renew (L1 is frozen). After the TTL +
   Consul's own failure-detection, the lease is released. R2 acquires it, becomes leader term-equivalent,
   tip still 100 (L1 never replicated H — it was mid-land). R2 lands a *different* change H' at
   seq 101, checksum `C100 → C101'`. R2 acks its client. From the cluster's view, trunk is linear:
   100 → 101'(H').
4. L1 **resumes**. From L1's frozen perspective only ε of wall-clock passed; its local lease-expiry
   check says "I still hold the lease until t0+10s, and it's only t0+ε." L1 completes its land:
   commits H to *its* Irmin trunk at seq 101, appends landed-log entry `C100 → C101(H)`, **acks its
   client "landed at seq 101."** Two clients have now received "landed at seq 101" for two different
   commits. **The trunk has forked.** Both forks are internally checksum-valid (`C100→C101` and
   `C100→C101'` are each well-formed chains; the chain invariant is *intra-fork*).
5. L1 tries to push to R2/R3. The checksum chain **detects** the divergence: R2's entry-101 has
   `prev == C100, post == C101'`; L1 presents an entry-101 with `post == C101`. Mismatch. This is
   precisely LiteFS's split-brain detection — and precisely its remedy: **the minority/stale node
   must do a full resync from the current primary, discarding its own divergent commits.** L1's H,
   already acked to L1's client as "landed," is **thrown away.**

The checksum chain did its job: it *noticed*. But "linearizable" means the second client's ack
should never have happened, or should have been a failure. Instead it was a success that gets
silently reversed. **A checksum chain prevents you from *serving* a forked history; it does not
prevent the fork, and it does not prevent the false ack.** That is detection + data loss, not
linearizability.

Compare to what consensus actually buys: in Raft, L1's append at index-i *cannot commit* without a
majority, and a majority is unreachable to a partitioned/paused old leader. The append is **fenced
by quorum** — it never acks. That is the property the brief's sentence claims to have for free and
does not.

**Why this still might be acceptable — but must be stated correctly.** At moderate scale, in a
single DC, with a leader that fsyncs-and-acks only *after* confirming it still holds the lease via a
**fencing token monotonic in the landed-log**, you can shrink this window to near-zero and make the
stale-leader append *fail to commit* rather than *commit-then-get-discarded*. LiteFS's own answer
(Consul lease + halt-on-checksum-mismatch) tolerates a *subsecond* loss window and is honest that
it's a loss window. The brief must adopt that honesty in the headline sentence, not bury it.

**Required fix / required-spec:**
- **Strike "linearizable ... not because of consensus."** Replace with the honest guarantee:
  *"Trunk landing is linearizable under the single-writer assumption the lease provides; the lease
  can fail to provide it during a handoff window (clock skew + pause + Consul TTL), in which case
  the trunk can fork. The checksum chain detects the fork and forces the stale fork to resync,
  discarding its un-replicated commits. The window is bounded by `lease_TTL + max_clock_error +
  max_pause`; commits acked-then-discarded in that window are lost. We accept this; we do not call
  it linearizable."*
- **Add a fencing token.** Every land must carry a monotonic **lease epoch / fencing token** (Consul
  session-modify-index is one source). The append to the durable landed-log must be **conditional on
  the token being the current maximum** — a stale-epoch append is *rejected at write time*, not
  detected at replication time. This converts the L1-resume case in step 4 from "commits and acks"
  to "fails to commit, returns error to client." That single change moves the failure from
  *silent-data-loss-on-resync* to *honest-error-to-client*, which is the difference between a
  footgun and a knob. **State where the token comes from, that the landed-log append is CAS'd on it,
  and that the leader re-checks lease validity *after* fsync and *before* ack.**
- **Bound `max_pause` and pick `lease_TTL`.** Write the inequality
  `lease_TTL > max_clock_error + max_pause + renewal_RTT`, give numbers for the target deploy, and
  state that violating it is the split-brain window. (This is the exact obligation that survives
  from my original Finding 4 — see the dissolution table below.)

---

### 2. [MAJOR] The failover data-loss window is real, and "fsync-on-leader + optional 1-replica-ack (durability width 2)" is an honest knob ONLY if the client is told which durability it got. As written, the client cannot tell a durable land from a lost one.

**Claim attacked.** §6: *"the leader fsyncs the Irmin commit + landed-log entry before acking the
client (durable-on-leader), and optionally waits for 1 replica ack (durability width 2) ... This is
a config knob, not a consensus protocol."* §9 risk 4 asks whether this is *"an honest substitute for
consensus ... or a footgun."*

It is an honest *substitute* — at moderate scale, "fsync on leader, wait for 1 replica, then ack" is
a perfectly reasonable durability story, and it is **not** consensus and shouldn't pretend to be.
The footgun is not the knob; it is **the ack carrying no information about which durability width was
actually achieved.**

**Concrete history (width-1, the default, loses an acked commit):**

1. Durability width = 1 (fsync-on-leader only — the brief's default phrasing "durable-on-leader,"
   with replica-ack "optional"). L1 lands H, fsyncs Irmin + landed-log, acks client "landed seq
   101." No replica has pulled yet (async).
2. L1's disk dies permanently (not a clean crash — controller failure, the node never comes back).
   This is a single-node loss.
3. R2 takes the lease, tip = 100 (it never saw 101). A new land H'' arrives, lands at seq 101.
4. The original client believes H is at seq 101. The cluster believes seq 101 is H''. **H is gone,
   acked-as-landed.** The client has *no signal*: its ack looked identical to a durable one.

**Concrete history (width-2 narrows but does not close it):**

5. Width = 2: L1 waits for R2's ack before acking client. Survives single-node loss of L1 (R2 has
   it). But correlated loss of L1+R2 (same rack/PDU — a failure mode you must name) loses an acked
   commit, *and* width-2 does nothing for the split-brain fork of Finding 1 (R2 acking the *bytes*
   doesn't mean R2 agreed L1 was still leader).

This is the standard async-replication truth: **width-`w` survives `w-1` simultaneous losses of the
ack set, and nothing more.** That is fine to *offer*. The footgun is silence.

**Required fix / required-spec:**
- **The ack must report the achieved durability width**, e.g. `{landed: seq 101, durable_on: [L1,
  R2], width: 2}`. A client (or CI gate) that requires width ≥ 2 can then *refuse to proceed* on a
  width-1 ack. An ack that cannot distinguish "durable on 2 nodes" from "durable only on the node
  that's about to die" is the actual footgun, not the async-ness.
- **State the default explicitly and pick it.** "Optional" is not a default. For "survive single-node
  loss without consensus," the default must be **width 2**, and the brief should say so, with the
  latency cost named (one extra replica RTT per land — fine at hundreds of devs / single-leader
  throughput).
- **Name the correlated-failure boundary.** "Width 2 survives 1 *independent* node loss; correlated
  loss of the ack set (shared rack/PDU/AZ) is outside the model." Say it.
- **Distinguish durability from agreement.** A replica ack of the *bytes* is not a vote that L1 was
  leader. Width-2 durability and the Finding-1 fencing token are orthogonal; the brief currently
  conflates "1 replica ack" with safety. Keep them separate in the spec.

---

### 3. [MAJOR] Idempotency-key in trunk/Irmin commit metadata is NOT race-free across a leader handoff: the new leader may not yet hold the old leader's last (unreplicated) landed commit, so its dedup query returns "not seen" for a key that WAS landed.

**Claim attacked.** §5 step 4: *"the idempotency-key and change-id live in the landed-log / Irmin
commit metadata (the single source of truth), not a side table — so a retry is deduped by reading
trunk history, consistently."* §2 / §5: *"made trivial by having exactly one authority — Irmin
trunk — at moderate scale with one leader."*

Putting the key in the commit metadata genuinely **dissolves my original Finding 1's dual-authority
problem** — there is now one authority, the trunk, and you read dedup state from it. Good. But "one
authority" is only "one *consistent* authority" when there is exactly one leader **and** the new
leader has the old leader's full history. Across a handoff with async replication, the second
condition fails for exactly the commits in the Finding-2 loss window.

**Concrete history (retry across handoff lands a duplicate):**

1. L1 lands change H with idempotency-key K at seq 101, fsyncs, acks client (width 1, or the replica
   ack is in flight). **R2 has not yet pulled seq 101.**
2. L1 dies / loses lease before R2 pulls 101. R2 becomes leader. R2's trunk tip = 100; R2's history
   contains **no commit carrying key K.**
3. The client's ack was lost (it died with L1, or the client timed out). The client **retries** the
   same logical submission with the **same key K** (correct client behavior — that's what idempotency
   keys are for).
4. R2 receives the retry, performs the §5-step-4 dedup: *"read trunk history for key K."* K is not in
   R2's trunk. **Dedup misses.** R2 lands the change at seq 101 (its tip+1). Now the change exists
   once on the dead L1 (lost) and once on R2 — **or**, if L1 comes back and its 101 survives in a
   fork, twice. At-most-once is violated; you got at-least-once, which for a *non-idempotent
   side-effecting land* (e.g. one that triggers CI, a deploy, a release tag) is a real duplicate.

The deeper point, same as the consensus version: **dedup is only as consistent as the replication of
the thing you dedup against.** With consensus, K commits to a majority before the ack, so any new
leader has it. With async single-leader, K is durable only to whatever width the *land* achieved —
so dedup inherits the *exact same loss window* as durability (Finding 2). The brief's "trivial
because one authority" is true *within a leader's tenure* and false *across a handoff inside the loss
window.*

**Required fix / required-spec:**
- **Couple dedup durability to land durability and say so.** Dedup across handoff is race-free **iff**
  the key is durable to the new leader before the client could observe an ack. That requires the key
  to be part of the *width-`w` durable* land (Finding 2), and the client retry protocol must not
  treat a *timeout* (no ack) as "definitely not landed" — a timed-out submit may have landed at
  width-1 on a now-dead node. State: *"a retry with key K after a timeout may produce a duplicate iff
  the original landed at a width that did not survive the failover; raise durability width to make
  duplicates impossible up to `width-1` correlated losses."*
- **Make the land side-effect-idempotent on K at apply.** Even with the above, define that re-landing
  the same K with content-equal result is a **no-op that re-returns the original seq** when the key
  *is* present, and that downstream side effects (CI/deploy/tag) are keyed on the *landed-seq*, not on
  the submit, so a duplicate land does not double-fire them. (This is the content-equality no-op I
  asked for in my original Finding 7, and it's *more* important here because you have no quorum to
  lean on.)
- **Specify the client's "unknown" state.** A submit that times out is in state *unknown*, not
  *failed*. The CLI must query-by-key on the new leader before retrying, and must understand that a
  "not found" on the new leader could be a real not-landed OR a lost-in-handoff land. Write that
  truth into the client protocol.

---

### 4. [MAJOR] Read-your-writes via a `landed-seq` cookie against an async replica: liveness under partition is unspecified (wait forever?), and "bounded-stale" is asserted but not bounded.

**Claim attacked.** §6: *"Read-your-writes via a landed-seq position cookie: a read waits until the
replica's applied seq ≥ the client's last landed seq, else redirects to leader."* and *"Reads off
replicas are bounded-stale."*

The cookie mechanism is correct and is exactly LiteFS's `(TXID, checksum)` position cookie — good,
reuse it. Two unstated properties make it unsafe-as-written:

**(a) Liveness under partition.** "waits until applied seq ≥ my-seq, else redirects to leader" — but
*when* does "else" fire? If a replica is partitioned from the leader, its applied-seq is frozen below
my-seq **forever** while partitioned. A read that "waits until applied seq ≥ my-seq" on that replica
**blocks forever** unless there's a timeout. And the "redirect to leader" fallback assumes the leader
is reachable — if the *client* is on the partitioned side with the replica, it can reach neither a
caught-up replica nor the leader. This is the same liveness hole I flagged in my original Finding 4,
and it survives the Raft removal unchanged because read-your-writes is a *client-side* property
independent of how the trunk is replicated.

**Concrete history (read-your-writes deadlock):**

1. Client lands H at seq 101 via leader L1 (reachable at land time). Cookie = 101.
2. Client is then served by replica R2, which partitions from L1 at applied-seq 100.
3. Client reads with cookie 101. R2's applied-seq is stuck at 100 < 101. The read **waits.** R2
   never catches up (partitioned). If "redirect to leader" requires reaching L1 and the client's
   partition also cuts L1, the read **never completes.**

**(b) "Bounded-stale" is unbounded as specified.** Nothing in the brief bounds replica lag. Async
replication lag is bounded only by the *slowest* of: replica pull interval, leader land rate,
network, and disk apply speed — none of which the brief caps. "Bounded-stale" is a promise; a
promise needs a number or a mechanism (lease-based max-lag eviction, lag-budget that takes a replica
out of rotation). Without one, a backed-up replica can be **arbitrarily** stale and still serve
"bounded-stale" reads. (LiteFS does not actually bound staleness either; it bounds read-*your*-writes
via the cookie, and lets non-cookie reads be arbitrarily stale. The brief should not claim more than
LiteFS delivers.)

**Required fix / required-spec:**
- **Specify the cookie wait as: wait up to `T_ryw`, then fall back to a leader read-index (a
  leader-served read confirms it still holds the lease, reads tip, serves).** Give `T_ryw`. If both
  replica and leader are unreachable, the read **fails with an explicit "cannot satisfy
  read-your-writes under partition"** — availability sacrificed for the consistency the client asked
  for, which is the correct trade and must be *stated* not *deadlocked into*.
- **Replace "bounded-stale" with the truth.** Either (a) "non-cookie replica reads are
  *unbounded*-stale; use the cookie for any read that needs recency," or (b) implement an actual lag
  bound: replicas self-evict from the read pool when `tip_leader − applied_seq` exceeds a configured
  lag budget (requires replicas to know the leader's tip — a heartbeat). Pick one and write the
  number. Do not ship the word "bounded" without a bound.

---

### 5. [MINOR] The split-brain "detection" is correct but the brief never states the recovery semantics — which fork wins, and that the losing fork's commits are discarded (data loss), and how an operator/author is notified.

**Claim attacked.** §4: the checksum chain is the *"replication + read-your-writes substrate, and the
audit trail."* §2: split-brain concerns *"mostly dissolved."*

Detection without a *specified, deterministic, notified* recovery is an operational landmine. LiteFS's
recovery is "the node that diverged from the current primary halts and resyncs, discarding its
divergent transactions." If `mvfs` reuses the chain, it must answer: when L1 and R2 have forked at
seq 101 (Finding 1), **which 101 survives** — the one the current lease-holder has, presumably — and
**what happens to the discarded fork's acked commits**? They are lost. An author whose commit was on
the losing fork must be *told* ("your landed commit H at seq 101 was rolled back due to a leadership
split; please re-submit") — because to that author, a commit that was acked-as-landed has silently
vanished from trunk. This is the human-facing face of Finding 1 and deserves its own spec line.

**Required fix:** State (1) the deterministic winner rule (current lease-holder's chain wins); (2)
that the losing fork's commits are **discarded, not merged** (the checksum chain cannot merge — it's
linear); (3) the notification path to affected authors; (4) that this is logged to the audit trail
as a split-brain event, not a normal resync.

---

### 6. [MINOR] "Linearizable reads off the leader trivially" reintroduces the lease/clock assumption you otherwise avoided — say so.

**Claim attacked.** §6: *"the leader serves linearizable reads trivially."*

It is not trivial. A leader serving a linearizable tip-read without a round-trip is doing a
**lease read**, and a lease read is linearizable only under the same `lease_TTL > clock_error +
pause + RTT` assumption as Finding 1. A leader that GC-paused past its lease while R2 took over and
landed seq 101 will, on resume, serve tip=100 as "linearizable" — stale. "Trivially" hides the clock
dependency.

**Required fix:** Either serve the linearizable read as a **lease-validated read** (re-confirm the
lease/fencing token is current *at read time*, after any pause) — and state the clock assumption — or
do a lightweight leader-confirms-it-still-leads check (a Consul session check / token compare) before
answering. Drop "trivially."

---

## What dropping Raft correctly bought you (credit where due)

These are real wins, and the brief should keep them and stop apologizing for them:

1. **One authority for dedup and ordering (my original Finding 1: DISSOLVED).** The whole
   `take!`-vs-Raft-log dual-authority split-brain — the substrate row being a second, non-replicated
   source of truth for claim/idempotency/selection — is **gone**, because there is no substrate-row /
   RSM duality anymore. The idempotency key lives in the *one* place that is authoritative (trunk
   commit metadata), read from the *one* writer. That was my single largest original Critical and it
   genuinely evaporates with the architecture. The only residue is the *cross-handoff* race (Finding 3),
   which is a smaller, well-bounded problem, not a structural contradiction.

2. **No apply-purity contradiction (my original Finding 6: DISSOLVED).** There is no replicated state
   machine whose `apply` must be a pure function of the log while also doing a `transact!` side
   effect. Irmin *is* the store; landing *is* the commit. The "apply is pure but also writes LMDB"
   self-contradiction has nothing to attach to. Replicas pull Irmin objects + landed-log and verify
   the chain — a clean, idempotent, replay-safe model by construction. Good.

3. **No term-fenced-propose subtlety on the hot path (my original Finding 8: mostly DISSOLVED, see
   below).** You don't have a deposed-leader-proposing-into-a-log problem because there's no log
   consensus to propose into. The fencing problem *relocates* to lease validity (Finding 1) — a
   single, well-understood check — rather than living inside a Raft propose/commit boundary.

4. **No Shen, no global lock on the control plane (my original Finding 9: DISSOLVED — and confirmed
   by the brief's own scope cuts).** ACLs are OCaml predicates evaluated inline; there is no
   `*shen-lock*` that apply could deadlock on. The entire control-plane-liveness-via-global-lock
   hazard is cut, correctly.

5. **Simpler failure model that's easier to *test*.** A single-leader + async-replica + lease system
   has a *small, enumerable* set of dangerous interleavings (lease handoff, async loss window, replica
   lag) versus Raft's combinatorial election/log-matching/commit-index space. You can actually Jepsen
   this in a week: partition the leader mid-pause, kill it post-ack-pre-replication, and assert the
   ack honestly reflects durability and the chain detects forks. That testability is itself a safety
   property. **This is the right-sized system for hundreds of developers.** I am not asking you to put
   Raft back.

The honest one-liner you've earned: *"At moderate scale, a single leased writer over an append-only
trunk gives you linearizable landing **whenever the lease holds a single writer**, plus a detect-and-
discard split-brain backstop and a tunable async durability window — and that is enough, provided we
state the window and fence the stale writer."*

---

## Original Criticals: dissolved vs. surviving

| # | Original Critical (v1, 01-aphyr-review) | Status under the no-Raft pivot |
|---|---|---|
| **1** | `take!` + Raft log = two authorities for idempotency/claim; per-node substrate dedup diverges across partition | **DISSOLVED.** One authority (trunk commit metadata), one writer. Residue → Finding 3 (cross-handoff retry), a Major, not a structural split. |
| **2** | Durability acked on metadata quorum + leader-local byte presence; committed land points to bytes that exist nowhere | **RELOCATED & NARROWED.** No metadata/byte split anymore (Irmin commit *is* the bytes). But async replication reintroduces a *failover loss window* for the whole landed commit → Finding 2, downgraded to Major because the fix is a durability-width knob + honest ack, not a quorum-on-bytes protocol. |
| **3** | ACL TOCTOU / stale-allow across an `:acl` commit interleaving the Raft log between check and apply | **MOSTLY DISSOLVED.** No log-interleave-between-propose-and-apply, because there's no propose/apply gap — the single leader checks ACL and lands in one serialized step. *Residual obligation:* the leader must evaluate ACLs against the **same tip it lands onto** (read ACL rows and land in one OCC-serialized critical section). If ACL rows live in the async-replicated SQLite index and the leader reads a *stale* replica's ACLs, a revoked principal could land — so: **leader must read ACLs from its own authoritative trunk/index state, never from an async replica.** State that one line and it's closed. Not a standalone Critical anymore. |
| **4** | "Linearizable" trunk reads depend on an unstated leader-lease clock-skew bound; read-your-writes can deadlock under partition | **SURVIVING — this is the v2 Critical (Finding 1) plus Finding 4/6.** Dropping Raft did **not** remove the lease/clock dependency; it made the lease the *primary* safety mechanism instead of a read optimization, so the clock-skew/pause/handoff window is now load-bearing for *write* safety (fork), not just read freshness. This is the one original Critical that not only survives but gets *more* central. It must be specified: fencing token CAS on the landed-log append, `lease_TTL > clock_error + pause + RTT`, bounded pause, lease-validated reads, and read-your-writes timeout→leader-fallback→explicit-fail. |

**Summary:** 2 of 4 original Criticals dissolve cleanly (1, 3), 1 narrows to a Major with a knob-and-
honesty fix (2), and 1 survives and intensifies as the v2 Critical (4 → Finding 1). That is a *good*
trade: you traded a combinatorial consensus surface for a single, sharp, well-understood lease-fencing
obligation. Close that one obligation honestly and the design's guarantees match its prose.

---

## The single gate before implementation

**Fix Finding 1.** Specifically: (a) delete the word "linearizable" from §6's causal claim and
replace it with the lease-conditioned guarantee + named loss window; (b) add a fencing token,
monotonic in the landed-log, that the durable landed-log append is CAS'd on, so a stale leader's
land **fails to commit** rather than commits-then-resyncs-away; (c) require the leader to re-validate
its lease *after* fsync and *before* ack; (d) write the inequality and the numbers. Everything else
(Findings 2–6) is "specify it and state the honest bound," which is exactly the kind of work dropping
Raft was supposed to make small — and here it genuinely is.
