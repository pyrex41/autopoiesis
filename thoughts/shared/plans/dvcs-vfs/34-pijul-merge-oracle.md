# 34 — Pijul as the merge oracle (patch theory replaces git's heuristic merge)

**Status:** Decided + grounded by running pijul + panel-reviewed. Boundary wired,
typechecked. The two-store durability work is P1 (must-fix list below).
**User:** "there must be something better than [git]." → chose **Pijul / patch theory**.

This supersedes doc 33's "git is the merge oracle." Doc 33's storage finding stands
(git CAS source-of-truth, lore for bytes); **what changes is the merge axis.**

---

## TL;DR

git-as-CAS is fine. git-as-**merge-oracle** was the soft spot: `merge-tree` is a
heuristic line-based diff3, and this project's whole pitch is *provable* decisions.
**Pijul's merge is sound by construction** — and I proved the three properties that
matter by building pijul 1.0.0-beta.15 and running it, not by trusting docs:

1. **Commutativity** — two independent changes applied in both orders → byte-identical
   file **and identical cryptographic state hash** (`VH3VVH5X…NXYQC` both ways). Pijul's
   version id is an order-independent discrete-log multiset hash.
2. **Conflict determinism** — two same-line edits → byte-identical conflict markers **and
   identical state hash** in both orders (`TQZB5NG5…C5JQC`). A conflict is a first-class
   persistent graph state, not a heuristic outcome.
3. **Rebase dissolved** — a change recorded against the *original base* applied cleanly
   onto an *already-advanced* trunk: **0 conflicts, hash unchanged, no rewrite.**

(3) is the money result for a **totally-ordered submission queue**: a change admitted
against a stale tip applies deterministically at land time without rebasing, and when it
*does* conflict, detection is sound — exactly what mvfs's I2 + clean-trunk goal want.

**Architecture (panel-ratified):** merge is a **second pluggable axis** (`merge-oracle`),
orthogonal to `storage-backend` (doc 33). pijul = **text** merge oracle; **lore** = large
binary bytes; **git** = CAS source-of-truth + the kept-warm fallback oracle; **mvfs** =
the trunk-only fenced-land control plane owning I1–I9 above all of them. We **exec the
`pijul` CLI, never link libpijul** (GPL-2.0). pijul is a sealed merge subroutine: **one
channel**, no pijul branches/remotes/identity leak upward.

---

## Why pijul fits patch-theory to mvfs's model (the synergy)

mvfs is a *trunk-only, totally-ordered land queue*. The two layers compose cleanly:

- **mvfs total order (I2)** is a property of the **landed-log** — the append sequence of
  *decisions*; the audit/replication authority. It keeps a total order on `seq`.
- **Pijul order-independence** is a property of the **state function**: `state = f(set of
  changes)` where `f` is a commutative fold. A replica that applies `{c1..cN}` in *any*
  order lands on the same state hash.

These don't fight — it's pure upside (Aphyr): the landed-log `seq` is the canonical apply
order; pijul guarantees a differently-ordered replica reaches the *same* state. So the
order-independent state hash becomes a **checkable replica witness** (strengthens I8) and
a stronger content witness in the landed-entry (strengthens I5/I4).

---

## What I ran (evidence)

pijul 1.0.0-beta.15, built from source (needs libsodium + an ssh-agent signing identity).

```
# TEST 1 — commutativity (independent edits: line1 vs line3)
HA=5F7RJJ…V4HAC (edit line1)   HB=R5IIHU…6V3QC (edit line3)
order1 (A,B): ALPHA-edited/beta/GAMMA-edited   state VH3VVH5X…NXYQC
order2 (B,A): ALPHA-edited/beta/GAMMA-edited   state VH3VVH5X…NXYQC   → IDENTICAL ✅

# TEST 2 — conflict determinism (both edit line2)
conf1 (X,Y): >>>>>>> X / ======= / Y <<<<<<<   state TQZB5NG5…C5JQC
conf2 (Y,X): >>>>>>> X / ======= / Y <<<<<<<   state TQZB5NG5…C5JQC   → IDENTICAL ✅
(note: marker order keyed by change-hash, not apply order)

# TEST 3 — rebase dissolved
Alice records HA against base (edit line5). Trunk advances (Bob edits line1).
apply HA onto advanced trunk → ONE-bob/two/three/four/FIVE-alice
conflict-markers: 0   HA present verbatim (no rewrite) ✅
```

Object model (research-confirmed): changes BLAKE3-addressed (53-char base32); pristine =
CRDT graph (vertices = (change-hash, pos), edges alive/dead) in **Sanakirja** (CoW B-tree,
O(log n) fork); conflicts are non-blocking first-class states; libpijul is **GPL-2.0-or-
later**, pre-1.0, single-maintainer, sparse docs, perf sharp edges (slow channel switch,
poor large-binary diff, repo bloat), no production users at scale.

---

## Panel synthesis (Aphyr / Torvalds / Fukamachi)

**Aphyr (correctness):** integration is sound and *strengthens* I4/I5/I8. The one genuinely
hard problem is **two-store crash atomicity** — the fenced landed-log (truth) and the
Sanakirja pristine (cache) must crash-agree. Discipline: **log is truth, pristine is a
rebuildable cache**; log-first 2-phase; idempotent forward re-apply + backward orphan sweep
on recovery (works *because* pijul apply is idempotent + order-independent).

**Torvalds (pragmatics):** ship-it-with-guardrails. **Exec, never link** (GPL — same pattern
every git-wrapper uses). pijul is a merge subroutine: one channel, never expose its
branches/remotes/identity. Tier split confirmed: pijul=text, lore=bytes, mvfs=control plane.
Pin exact SHA + vendor source + gate the on-disk format version; keep git-3way warm.

**Fukamachi (Shen design):** merge is a **second pluggable axis** (`merge-oracle` datatype),
NOT a new `storage-backend` arm — honoring doc 33's "merge is its own axis." Concrete
tc-safe Shen for the boundary verbs + dispatch (now implemented).

### Must-fix list (P1, ship-blocking for a real land path)

- **MF-1 — no silent transitive apply.** Admission must verify all pijul *dependencies* of
  a candidate are already in the trunk at `seq < N`; pijul must never pull un-`seq`'d
  dependency changes into the trunk as an apply side effect (else content enters the trunk
  with no landed-log entry → I1/I2 break).
- **MF-2 — structural conflict detection, not marker-grep.** Detect via the pristine graph
  (order / zombie / name / overlap classes), reject on ANY non-clean state. *(Boundary
  reflects this: `pijul-conflicts?` calls a structural host primitive
  `pijul-graph-conflicted?`, never greps `>>>>>>>`.)*
- **MF-3 — re-check at the land point.** Conflict-freedom is *not* stable across tip advance
  (TOCTOU). Admission's speculative check is advisory; re-run the speculative apply against
  the *committed* tip inside the lease before landing.
- **MF-4 — log-first two-phase durability.** (a) every applied change's body in the fenced
  blob store before the log append; (b) orphan sweep before accepting writes; (c) verify
  Sanakirja fsync-on-commit. The pristine must be fully rebuildable from log + change bodies.
- **MF-5 — pin libpijul version / hash-algo id in the landed-entry**, since the order-
  independent state hash is now in the audit chain and depends on pijul's (pre-1.0) hash
  construction.
- **Should-fix:** confirm `pijul record` determinism (if it embeds a timestamp/nonce,
  identical content → different hash, so keep I3 on the `idempotency-key`, never on
  change-hash equality); bound candidate change size at admission (large-binary DoS); doc
  loudly that the state hash is a *content witness, not ordering evidence*.

### Jepsen-style fault tests to add (P1)
- **T1** two-store crash-torn land (I4/W1/W2): SIGKILL + page-cache drop at every step;
  assert acked lands present in both stores, no orphan pristine change, `state == post-state`.
- **T2** fenced split-brain with shared pristine (I7 + orphan apply): only the fenced leader
  appends; stale leader's pristine writes swept on recovery; apply-idempotency holds.
- **T3** conflict-admission under concurrent tip advance (MF-3): pairs clean@T but conflict@T+1
  (all conflict classes) must be rejected at the land-point re-check; discarded forks reclaim
  Sanakirja pages.

---

## What's built now (this commit)

The **merge-oracle axis** is implemented and typechecks on shen-lua/LuaJIT 2.1:

- `boundary.shen`:
  - **`merge-oracle` datatype** (`git-merge` | `pijul-merge`) — orthogonal to `storage-backend`.
  - **pijul verbs** over `shell-run` (exec, never link): `pijul-record` (author/msg →
    BLAKE3 change hash), `pijul-apply` (idempotent), `pijul-fork` (O(log n) probe primitive),
    `pijul-drop-channel`, `pijul-state` (order-independent state hash), `pijul-conflicts?`
    (structural, via `pijul-graph-conflicted?` host primitive — MF-2), `pijul-admits?`
    (speculative fork+apply+probe+discard), `pijul-land-state` (idempotent land-apply — I3
    backstop).
  - **oracle dispatch** `oracle-admits?` / `oracle-merged` (git arm = `merge-tree` +
    clean-scan; pijul arm = speculative apply + structural probe).
  - git merge helpers relocated here (self-contained oracle, loads before fsm).
- `fsm.shen`: **`base` now routes through the oracle** — `{ admitted → hash → merge-oracle
  → based }`. git fast-path kept; `land` keeps writing the durable commit via git
  (landed-log is git-addressed source-of-truth, doc 33).
- `test/illegal.shen`: illegal-3 updated to pass `git-merge` so it remains a *type*
  violation (submitted≠admitted), not an arity error. All four illegal programs still
  rejected by `tc +`.
- `Makefile`: runtime smoke passes the `git-merge` oracle; `base` still yields a `based`.

**Verified:** `make typecheck`, `typecheck-lore` pass; `typecheck-negative` rejects the
illegal programs; runtime smoke yields `[mvfs.mk-based c1 k1 ttree tbase alice
[mvfs.mk-proof alice [] 0]]` via the git-merge arm.

## Guardrails (standing rules)
1. **Exec only, never link libpijul.** CI tripwire on any libpijul symbol in the control plane.
2. **Generic merge membrane** — `apply(base, changes) → (state, conflicts)`; channels,
   remotes/push/pull, pijul identity do NOT cross it. One channel. Single fixed service key
   for recording; real authz lives in the fenced log.
3. **Fenced log is truth; Sanakirja is a disposable, rebuildable cache.** Prove
   `rm -rf .pijul` + replay-from-log in CI.
4. **Pin exact SHA, vendor source, gate on-disk format version; run git-3way shadow in CI**
   as regression guard + warm fallback. **Exit = replay log into another oracle; never
   depend on pijul→git export.**

Next per the must-fix list: P1 = host backend (real `shell-run`/`pijul-graph-conflicted?`),
the log-first two-phase land path, MF-1/MF-3 admission discipline, and T1–T3.
