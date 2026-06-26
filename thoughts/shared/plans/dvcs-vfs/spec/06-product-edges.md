---
date: 2026-06-26
researcher: Claude
topic: "mvfs — product edges: user-facing workflows & semantics, fully squared"
status: design
layer: spec
builds_on: thoughts/shared/plans/dvcs-vfs/spec/00-overview.md
closes_findings:
  - thoughts/shared/plans/dvcs-vfs/03-torvalds-review.md (Finding 1: change lifecycle; Finding 2: real merge; Finding 3: dirstate)
  - thoughts/shared/plans/dvcs-vfs/09-torvalds-review-v2.md (Finding 1: rename/delete merge; Finding 2: dirstate honesty; Finding 4: restack-on-land)
  - thoughts/shared/plans/dvcs-vfs/18-torvalds-shen-backends.md (restack==merge quality; conflict as real op)
tags: [design, spec, product, workflow, stacked-changes, restack, conflict, monorepo, acl, cli, non-goals]
last_updated: 2026-06-26
---

# mvfs — Product Edges (workflows & semantics)

> This doc is **user-centric**: what a developer *does* and *sees*, and the exact semantics
> the VCS must guarantee. It builds on the keystone (`00-overview.md`) and refers to internals
> docs by number: data model `01`, land kernel `02`, policy/ACL `03`, read boundary `04`,
> serving/VFS `05`. Where this doc names a wire shape, it is the **user-visible projection** of a
> contract frozen in `00 §5`; it refines, never redefines.

This doc exists to close the product gaps the VCS-design reviews kept hitting: a change under
review has no identity (`03` Finding 1); there is no real merge (`03` Finding 2); `status`
re-hashes the world (`03` Finding 3); stacks have no restack-on-land (`09` Finding 4); conflict
must be a *resolved* operation, not "resubmit from scratch" (`03`/`09`/`18`). Each is squared below
with concrete CLI.

---

## 0. The mental model (say it once, plainly)

- **Trunk is linear and append-only.** It only grows by landing through the serialized fenced
  land-queue (`02`). There are **no branches in published history**, ever (I1).
- **A change is a first-class object with a stable identity** that lives *outside* trunk while it
  is authored and reviewed, and *enters* trunk exactly once, by landing. The published history is
  linear; the **developer's working set is not** — it is a stack of local commits. These are
  different requirements and mvfs keeps them separate (this is the core fix for `03` Finding 1).
- **Your local commits are real commits** (git commit objects in your local CAS, `01`), cheap to
  make, fork, amend, and reorder. They become trunk *only* by landing.
- **"Conflict" means the 3-way merge could not auto-resolve** — not "two changes touched the same
  path." Disjoint-line edits to one file merge cleanly (`02`, real git merge). A conflict is a
  thing you *resolve locally and resubmit*, not a thing you redo.

Everything below is the elaboration of these four sentences.

---

## 1. The change lifecycle under review

A **change** is the unit of review and the unit of landing. It is a named, evolving, reviewable
object that exists before — and independently of — trunk.

### 1.1 Stable Change-Id (the identity that survives everything)

At change *creation* (first local commit of a new logical change), mvfs assigns a **Change-Id**:
a stable opaque id (e.g. `I9a1f…`, Gerrit-style) written into the commit's metadata trailer.

| Property | Guarantee |
|---|---|
| **Stable across revisions** | Amending the change (new content, new commit hash) keeps the same Change-Id. |
| **Stable across rebase/restack** | Re-parenting the change onto a new trunk tip keeps the same Change-Id (the commit hash changes; the Change-Id does not). |
| **Distinct from the idempotency-key** | The Change-Id names the *review object across its life*; the idempotency-key (`00 §5.1`, `01`) dedups *one land attempt* (I3). Two different tools for two different jobs — see `03` Finding 1, fixed. |
| **Carried into the landed-log** | When the change lands, its Change-Id is recorded on the `landed-entry` (`00 §5.1`). This is how clients later recognize "trunk's commit with Change-Id X *is* my change, landed" — the load-bearing fact for restack (§2). |

The Change-Id is the join key between three worlds: your local stack, the review state, and the
landed-log. It is the only identifier that is meaningful in all three.

### 1.2 How a change accretes revisions

Review iteration is `mvfs amend`, not "new submission":

```
$ mvfs amend                 # fold working-copy edits into the current change, same Change-Id
$ mvfs amend -m "address review: handle nil case"
```

Each amend produces a **new commit hash** (new content identity, I5) under the **same Change-Id**.
The history of revisions is just the sequence of commit hashes that carried that Change-Id; the
review tool (not mvfs) renders them as "patchset 1, 2, 3…". mvfs's only obligation is: the
Change-Id is stable, and `mvfs submit` (§3) attaches the new revision to the existing change.

### 1.3 How review state attaches (and where mvfs stops)

mvfs is **not** a code-review tool and does not store approvals, comments, or scores. The contract
is narrow and deliberate:

- mvfs owns: the Change-Id, the chain of revisions (commit hashes) under it, and the land
  admission decision (`02`/`03`).
- The review system owns: discussion, approval, CI gating — keyed by Change-Id.
- **Admission (`02 submit→admit`) MAY require a review-approval predicate**, supplied as an ACL/
  policy fact (`03`): e.g. "land of change with Change-Id X requires an `approved` fact for X."
  mvfs evaluates the predicate at admission; it does not produce the approval. This keeps review
  policy *versioned and landed* (see §7) without mvfs becoming a review tool.

> **Decision recorded:** review identity = Change-Id; review *content* lives outside mvfs; review
> *gating* enters mvfs only as a landed policy predicate. This is the minimal identity+lifecycle
> the VCS must support, no more.

---

## 2. Stacked changes (the daily workflow)

A **stack** is an ordered chain of local commits, each its own change (own Change-Id), each
submittable for review independently while you keep building on top.

### 2.1 The shape

```
trunk-tip (seq=4187)
  └─ A   Change-Id I-aaa   "add config loader"     (local commit, in review)
       └─ B   Change-Id I-bbb   "use loader in server"  (local commit, in review)
            └─ C   Change-Id I-ccc   "tests for loader"  (local, still drafting)
```

A, B, C are local git commits (`01`) with a parent chain. Each has a stable Change-Id (§1.1). You
submit A and B for review and keep editing C — you are **not blocked on your own review queue**
(the exact `03` Finding 1 pain). `mvfs stack` shows the chain and per-change review/land status:

```
$ mvfs stack
  ○ C  I-ccc  draft        tests for loader
  ◑ B  I-bbb  in-review    use loader in server
  ◑ A  I-aaa  in-review    add config loader
  ● trunk @4187
```

### 2.2 restack-on-land (the operation that makes stacks worth having)

This is the load-bearing workflow `09` Finding 4 said was missing. When the **bottom** of the
stack lands, the children must move onto the new trunk tip — automatically, correctly, preserving
Change-Ids.

**Scenario:** A is submitted, reviewed, and lands as trunk `seq=4188`. Two cases:

1. **A landed unchanged** (trunk's A == your local A): trunk's commit for `I-aaa` is byte-identical
   to your local A. mvfs **drops local A** (recognized by Change-Id on the `landed-entry`,
   `00 §5.1`) and fast-forwards B,C onto `trunk@4188`. No merge needed — a pure re-parent.

2. **A was amended during review** (trunk's A ≠ your local A — e.g. a reviewer-requested fix landed
   in the version that actually merged): mvfs sees a landed-entry with Change-Id `I-aaa` whose
   commit hash ≠ your local A. It **drops local A** and **restacks B onto trunk-A via real 3-way
   merge** (`02`; base = old local A, ours = B's tree, theirs = trunk-A), then restacks C onto the
   new B. Each restacked commit **keeps its Change-Id**.

```
$ mvfs sync                 # pull new trunk; auto-detects I-aaa landed
landed:  I-aaa  -> trunk@4188  (your local A dropped; landed version differed)
restack: I-bbb  onto trunk@4188 ... clean
restack: I-ccc  onto I-bbb'    ... clean
stack now based on trunk@4188

$ mvfs stack
  ○ C  I-ccc  draft        tests for loader        (restacked)
  ◑ B  I-bbb  in-review    use loader in server    (restacked, revision +1)
  ● trunk @4188  (I-aaa landed)
```

**Restack is a loop of the §4 merge** (this is why `18` insists restack quality == merge quality).
If restacking B hits a real textual conflict, it stops and hands you a conflict to resolve exactly
as in §4 — but only for the conflicting commit. The rest of the stack waits.

```
$ mvfs sync
landed:  I-aaa  -> trunk@4188
restack: I-bbb  onto trunk@4188 ... CONFLICT in src/server.lua (2 hunks)
  stack paused at I-bbb. resolve, then: mvfs restack --continue
```

### 2.3 What happens to in-review revisions and Change-Ids

- The Change-Id is **never** reassigned by restack or land (§1.1). B keeps `I-bbb` through every
  re-parent. The review thread for `I-bbb` continues uninterrupted; the restacked B is just a new
  revision under the same change.
- A's review object is **closed by landing** — its Change-Id now resolves to a `landed-entry`
  (`seq=4188`), not a local commit.
- If you `mvfs amend` B after restack, that's another revision under `I-bbb`, normal §1.2 flow.

### 2.4 Landing a whole stack

`mvfs land` on a stack lands **bottom-up through the queue** (`02`), one change at a time, each
with its own idempotency-key (I3):

```
$ mvfs land --stack
land I-aaa ... landed seq=4188
land I-bbb ... landed seq=4189   (auto-restacked onto 4188 first)
land I-ccc ... needs-rebase      (trunk moved under it; run mvfs sync)
```

If a middle change bounces (conflict/needs-rebase), landing **stops there** — changes above it are
not landed, because they are now based on an un-landed parent. You resolve/sync and re-run. The
land FSM is single-change (`02`); the stack-land protocol is "bottom-up, stop on first bounce,"
which keeps the queue's totality (I2) intact.

---

## 3. submit → land, end to end (the user's POV)

`mvfs submit` sends one change (or a stack, §2.4) into the land-queue and returns one of a small,
closed set of outcomes. This is the user-visible projection of the land FSM (`02`) and the
admission/ACL decision (`03`).

### 3.1 The states a user sees

```
$ mvfs submit I-bbb
submitted   I-bbb  rev 3  base=trunk@4188  idem=k7f3…
admitted    (acl ok @acl-version=512; review approval ok)
queued      position ~2
landed      seq=4189   ✓     # durable at the stated durability width (see §8)
```

| Outcome | What it means | What the user does |
|---|---|---|
| **admitted** | ACL allows it at the current `acl-version` (I6); review predicate satisfied (`03`). | Wait for queue. |
| **rejected(acl)** | Path-scoped ACL denies a touched path at the linearization point (I6, `03`). | Get access (§7) or drop the path. |
| **rejected(conflict)** | Real 3-way merge could not auto-resolve onto current tip. Response carries **conflicting paths + hunks** (§4). | `mvfs resolve` (§4), then resubmit. |
| **needs-rebase** | Auto-rebase-clean is *possible* but trunk moved; client must rebase onto the new tip and resubmit (common, disjoint case). | `mvfs sync` (auto-restacks, §2.2), resubmit. |
| **landed(seq)** | Committed to trunk at `seq`, durable at the durability width (I4). Client receives `as-of=(seq, acl-version)` for read-your-writes (`00 §5.2`, I8). | Done. |

### 3.2 needs-rebase vs rejected(conflict) — the crucial distinction

- **needs-rebase** = your change is clean against tip *once re-parented*; the merge would succeed,
  but the queue won't silently rebase-and-land on your behalf past a moved tip (it tells you, you
  rebase, you resubmit). This is the common, disjoint case — `mvfs sync` handles it with **no human
  merge** (§2.2 case "clean").
- **rejected(conflict)** = re-parenting requires a 3-way merge that produced **textual conflicts**
  (overlapping hunks) or a **structural conflict** (rename-vs-edit / delete-vs-modify, §4.4). A
  human must resolve. This is the real-conflict case.

Both are *cheap to detect* and *never* "redo from scratch." The first is one command; the second
is §4.

### 3.3 Idempotent resubmit

Resubmitting is safe and explicit (I3):

- **Same content, same change, retried** (network hiccup, you re-run `mvfs submit`): the
  idempotency-key (`00 §5.1`) is unchanged, so the queue dedups — if it already landed, you get
  `landed(seq)` again, not a second land. **At-most-once landing** (I3) means a double-submit can
  never produce two trunk entries.
- **New content after a resolve/amend**: a *new* idempotency-key is minted for the new content
  (the Change-Id stays, §1.1). This is a fresh land attempt of the same change. The review object
  accretes a revision (§1.2); the land is deduped on the *new* key.

> User-visible promise: **clicking submit twice can never double-land, and resolving a conflict and
> resubmitting can never lose your resolution.**

---

## 4. Conflict resolution as a real operation

When the queue returns `rejected(conflict)` (§3), the user gets a **real conflict to resolve
locally** — with hunks — and resubmits. Not "resubmit from scratch." This closes the central
`03` Finding 2 / `09` Finding 1 / `18` complaint.

### 4.1 What the user receives

The rejection carries enough to reconstruct the conflict locally: the **base** (the merge-base
trunk tree the merge used), **theirs** (current trunk tip), **yours** (your change's tree), and the
**conflicting paths with hunk ranges**. The client materializes conflict markers into the working
copy (standard `<<<<<<< / ======= / >>>>>>>`), so any editor/mergetool works.

```
$ mvfs submit I-bbb
submitted   I-bbb  rev 3
rejected(conflict)
  src/server.lua    2 hunks   (textual)
  src/loader.lua    rename-vs-edit  (structural; see below)
  run: mvfs resolve
```

### 4.2 The resolve flow

```
$ mvfs resolve
conflicts materialized into working copy:
  src/server.lua    <<<<<<< markers at L40-58, L210-219
  src/loader.lua    STRUCTURAL: you renamed -> loader/core.lua; trunk edited loader.lua
    options: --take-rename  --take-trunk  --manual

# edit src/server.lua by hand or with $MERGETOOL, then:
$ mvfs resolve --mark src/server.lua          # mark one path resolved
$ mvfs resolve --take-rename src/loader.lua   # apply trunk's edits onto the renamed path
$ mvfs resolve --status
  resolved: src/server.lua, src/loader.lua
$ mvfs amend                                   # fold the resolution into the change (same Change-Id)
$ mvfs submit I-bbb                            # resubmit; new idempotency-key, same change
```

Key properties:
- Resolution is folded into the change with `mvfs amend` → **same Change-Id**, new revision (§1.2).
  Your reviewers see "patchset N+1: merge conflict resolved," not a brand-new change.
- Resubmit is idempotent on the new content (§3.3) — your resolution cannot be lost or
  double-applied.
- The merge mechanism is git's real 3-way merge (`02`); mvfs never invents its own diff3.

### 4.3 Auto-rebase-clean vs real textual conflict (what the user actually hits)

| Situation | Detection | User experience |
|---|---|---|
| **Disjoint files / disjoint lines** (the common case) | merge applies cleanly onto tip | `needs-rebase` at most → `mvfs sync` re-parents with no human step (§3.2) |
| **Same file, overlapping hunks** | git 3-way merge reports hunks | `rejected(conflict)` → `mvfs resolve` textual flow (§4.2) |
| **Structural** (rename-vs-edit, delete-vs-modify, add-vs-add) | tree-level, not a text hunk | `rejected(conflict)` with a **structural** marker + explicit `--take-*` choices (§4.4) |

### 4.4 Structural conflicts get a real slot (not just hunks)

`09` Finding 1 is explicit that per-path merge is blind to cross-path cases, and that a conflict UX
of "hunks only" has no slot for them. mvfs surfaces them as **named structural conflicts** with
explicit resolutions, so the user is never silently corrupted:

- **rename-vs-edit:** "you renamed `foo` → `bar`; trunk edited `foo`." Resolutions: `--take-rename`
  (replay trunk's edits onto `bar`), `--take-trunk` (keep `foo` with edits, drop rename), or
  `--manual`. mvfs relies on the merge engine's rename detection over the changed set (`02`); when
  detection is confident the restack/merge follows the rename automatically and this never surfaces.
- **delete-vs-modify:** "you deleted `foo`; trunk modified it." Resolutions: `--keep` (take trunk's
  modified file) or `--delete` (honor your delete).
- **add-vs-add / mode / symlink-vs-file:** surfaced as a structural conflict with the two
  candidates; user picks.

> User-visible promise: **a rename mid-stack never silently drops the other side's edits.** Either
> the merge follows the rename, or you get an explicit structural conflict to decide — never a quiet
> loss (the `18` "silent corruption on restack-over-rename" hazard, closed at the UX level).

---

## 5. `status` and `diff` are fast (the performance promise)

**User-visible promise:** `mvfs status` and `mvfs diff` cost **O(changes since last sync)**, not
O(repo). On a multi-million-file monorepo, `status` returns in the low hundreds of ms even when the
"whole repo" appears present.

What it depends on (the honest mechanism, per `05`):

- A **dirstate** index: `(path, size, mtime, ctime, inode, blob-hash)` per tracked path. `status`
  `stat()`s candidates and only re-hashes entries whose `(size,mtime,ctime,inode)` moved → it never
  re-hashes unchanged files (kills `03` Finding 3's "re-hash the world").
- In a **mounted/virtualized** working copy (`05`), the dirstate is fed by the **filesystem change
  journal** (the VFS knows which paths were written), so `status` is O(*files you touched*) — it
  consults a maintained dirty-set, not the disk.
- In a **no-mount checkout**, fast `status` comes from the dirstate plus a filesystem watcher
  (inotify/FSEvents) maintaining the dirty-set; without a watcher, `status` degrades to a stat-walk
  (O(files present in your sparse profile to `stat`), still re-hashing only suspects). `05` is
  normative on exactly which tier is available in which mode — this doc states the *promise*; `05`
  states the *mechanism and its phase*.

`mvfs diff` is the dirty-set turned into hunks: O(changed files), against trunk tip or any `as-of`
basis (`00 §5.2`).

---

## 6. Monorepo / sparse workflows

A developer works in a *slice* of a huge repo. The repo *appears* whole; only your profile is
materialized or eagerly present (`05`).

### 6.1 Declaring a sparse profile

```
$ mvfs clone mvfs://repo ~/work            # sets up the working root; nothing bulk-materialized
$ mvfs sparse set //services/payments/... //libs/common/...   # declare your slice
$ mvfs sparse show
  included: //services/payments/  //libs/common/
  (everything else is lazily-present, not on disk)
```

- **Visible vs lazily-present:** paths in your profile are present (materialized, or faulted-in on
  access under the mount). Paths outside it are *lazily-present* — they resolve and fault-in on
  first access (mount, `05`) or require `mvfs sparse add` (no-mount checkout). `ls` / `readdir` of
  an un-faulted directory still shows it exists (the tree is virtual); reading a file faults its
  bytes via an authorized serve step (`00 §5.3`, I9 — never reachable by hash alone).

### 6.2 What "checkout" means in a virtualized world

- **Mounted:** there is no bulk checkout. The mount presents the trunk tip (or an `as-of` basis);
  files fault in on `read()` (`05`). "Checkout" ≈ "point the mount at a basis."
- **No-mount:** `mvfs sync` materializes your sparse profile at the current trunk tip to a real
  directory. "Checkout" ≈ "materialize my slice." `mvfs sparse add //path` extends the slice.

### 6.3 Pulling new trunk

```
$ mvfs sync
trunk advanced 4188 -> 4205   (17 lands)
your sparse slice updated; 3 files changed in profile
2 local changes restacked onto trunk@4205   (see §2.2)
```

`mvfs sync` advances your working basis to the new trunk tip, updates your profile's materialized/
faulted files, and **restacks your local stack** (§2.2). It is the single "catch up to trunk"
verb. Reads of trunk are served at an `as-of=(seq, acl-version)` basis (`00 §5.2`); after your own
land, `sync`/reads honor read-your-writes (I8) using the `as-of` your land returned.

---

## 7. ACL administration as a landed policy change

Granting/denying path-scoped access is **itself a change that goes through submit → land** (`03`).
Policy is data, landed through the queue, versioned by log index, reviewable, and time-travelable.
This is the user/admin workflow.

### 7.1 The flow (an ACL grant is a normal change)

```
$ mvfs acl grant --path //services/payments/... --principal alice --role write
prepared policy delta as change I-pol-9  (touches policy ruleset)
$ mvfs submit I-pol-9
submitted   I-pol-9
admitted    (you have admin on //services/payments/, acl-version=512)
landed      seq=4206   ✓
acl-version now = 4206
```

- A policy change is a **distinguished landed-entry whose payload is a Datalog ruleset delta**
  (`00 §5.1`, `03`). It lands through the same fenced queue (I1/I2) — so it is ordered,
  reviewable (same review predicate, §1.3), and auditable like any change.
- **Who can admin:** authority to land a policy delta is itself an ACL predicate (`03`) — e.g.
  "admin on a path subtree may grant roles under it." Admin is path-scoped, not global, and is
  granted the same way (a landed policy change).

### 7.2 When a grant takes effect (acl-version, revocation latency)

- The grant is in force from the **acl-version it landed at** (here `4206`). Every subsequent land
  and read is authorized against the acl-version current at *its* linearization point (I6, `00 §5.2`)
  — **no stale-allow**: a land cannot be authorized against a policy that was superseded before it
  linearized.
- **Revocation latency** is bounded by how fast the read tier observes the new acl-version and how
  fast outstanding serve-tokens expire (`04`). Serve-tokens are minted at a specific acl-version and
  are short-lived/single-use (`00 §5.3`); a revoked principal stops getting *new* tokens
  immediately at land, and any in-flight token drains within its expiry. `04` is normative on the
  exact revocation-latency bound; the user-visible promise is **"a revoke lands like any change and
  is effective within token-expiry, with no stale-allow on the land path."**

### 7.3 Time-travel and audit

Because policy is landed data:
```
$ mvfs acl as-of 4100 --path //services/payments/   # who could write here at seq 4100?
$ mvfs log --policy //services/payments/             # every grant/revoke that touched this subtree
```
ACL history is just trunk history. This is the payoff of policy-as-data (`03`).

---

## 8. Failover / degraded modes (the user's POV)

The user does not run consensus; they experience a small set of degraded behaviors. The contract
is in `02`/`04`; here is what a developer *sees*.

| Event | Reads | Lands | What the user sees / does |
|---|---|---|---|
| **Leader failover** (lease handoff, `02`) | continue (served from replicas at their `as-of`, `04`) | briefly unavailable | `mvfs submit` may return `land-unavailable, retrying…` for a few seconds; it auto-retries idempotently (I3). No data loss. |
| **Partition — you're in the minority** | continue read-only at last-known `as-of` (`04`) | refused | `mvfs submit` returns `read-only (partitioned)`. You keep working locally (local commits, §2); land when reconnected. |
| **Not-yet-durable land** | n/a | ack semantics | A `landed(seq)` ack means **durable at the stated durability width** (I4, `00 §5.1`). The client trusts an ack only at that width; `mvfs land-status I-xxx` shows the durability the ack carried. |

**What the client should trust:** an ack that says `landed(seq)` is durable at the configured
durability width (I4) — fsync-on-leader, optionally plus N replica-acks (`02`/`04`). The client
treats anything short of that ack as *not landed* and safe to idempotently retry (I3). Reads always
carry an `as-of` (`00 §5.2`); a read can never observe a land the user's own session hasn't reached
(monotonic reads, I8).

> User-visible promise: **failover costs you seconds of land availability, never a read outage and
> never a lost acked land.** A minority partition is read-only, not wrong.

---

## 9. The CLI surface

Concrete command list. Each maps to a contract in the named internals doc.

| Command | Does | Refs |
|---|---|---|
| `mvfs clone <url> <dir>` | set up working root; no bulk materialize | `05` |
| `mvfs status` | O(changes) dirty set | `05`, §5 |
| `mvfs diff [--as-of S]` | hunks for changed files vs a basis | `05`, `04` |
| `mvfs log [--policy <path>] [--as-of S]` | trunk history; policy history | `01`, `07` |
| `mvfs commit -m …` | new local commit; assigns Change-Id if new change | §1.1 |
| `mvfs amend [-m …]` | fold edits into current change, same Change-Id | §1.2 |
| `mvfs stack` | show the local stack + per-change status | §2.1 |
| `mvfs restack [--continue/--abort]` | re-parent orphaned children via 3-way merge | §2.2 |
| `mvfs submit [<change-id>\|--stack]` | enter land-queue; returns the §3 outcome | `02`, `03` |
| `mvfs land [--stack]` | submit + wait for landed(seq), bottom-up for stacks | `02`, §2.4 |
| `mvfs land-status <change-id>` | queue position / outcome / durability width of ack | `02`, §8 |
| `mvfs resolve [--mark/--take-rename/--take-trunk/--delete/--keep/--status]` | resolve a real conflict locally | §4 |
| `mvfs sparse {set,add,remove,show}` | declare/adjust the visible slice | `05`, §6 |
| `mvfs acl {grant,deny,show,as-of}` | prepare/inspect policy changes | `03`, §7 |
| `mvfs as-of <seq>` / `mvfs sync` | pin a read basis / advance to trunk tip + restack | `04`, §6.3 |

> Naming note: `submit` enters the queue and returns the outcome; `land` is "submit and block until
> landed/bounced." A reviewer-driven flow uses `submit` (fire, keep working); a script uses `land`.

---

## 10. Non-goals / explicit product boundaries

| Not a goal | Why | Use instead |
|---|---|---|
| **Branches in published history** | Trunk is linear (I1); branches are the merge-hell mvfs exists to avoid. | Stacks (§2) for in-flight work; the linear trunk is the only published line. |
| **Rewriting published history** (rebase/amend/force-push of landed commits) | The landed-log is append-only and checksum-chained (I2, I5). | Land a *new* change that reverts/supersedes. `mvfs log` shows the correction in order. |
| **Multi-master / concurrent writers to trunk** | Single serialized fenced leader (I7); moderate scale (`00 §6`). | The land-queue serializes; disjoint work proceeds via independent submits, not parallel masters. |
| **A built-in code-review tool** | mvfs owns identity+lifecycle, not discussion/approval (§1.3). | Any review system keyed by Change-Id; gating enters mvfs as a landed policy predicate (§7). |
| **Long-lived divergent forks of trunk** | No branches; trunk is the one line. | Stacks for short-lived in-flight work; feature flags / incremental landing for big refactors. |
| **Offline landing** | Land needs the leader + durability ack (I4). | Work offline as local commits (§2); land on reconnect. Reads of a pinned `as-of` work offline (`04`). |
| **Hash-only content access** | No content reachable by hash alone (I9). | Authorized resolve → serve-token (`00 §5.3`); all reads are ACL-checked. |

---

## 11. Cross-reference map (so nothing drifts)

| This doc § | Refines / depends on |
|---|---|
| §1 Change-Id, lifecycle | `00 §5.1` (Change-Id on landed-entry, distinct from idempotency-key, I3); `01` (commit metadata) |
| §2 stacks, restack-on-land | `01` (local commits); `02` (3-way merge = restack mechanism); `00 §5.1` (Change-Id match on land) |
| §3 submit→land outcomes | `02` (land FSM, fencing I7, idempotency I3); `03` (admission/ACL I6) |
| §4 conflict resolution | `02` (real git 3-way merge, structural cases) |
| §5 fast status/diff | `05` (dirstate, change journal, watcher tiers); `04` (`as-of` basis) |
| §6 monorepo/sparse | `05` (virtualized reads, sparse profile, fault-in); `04` (as-of, RYW I8) |
| §7 ACL-as-landed-change | `03` (policy-as-data, acl-version I6); `04` (revocation latency, serve-token `00 §5.3` I9) |
| §8 failover/degraded | `02` (lease/fencing, durability width I4); `04` (read replica as-of, monotonic I8) |

---

## 12. Open product edge that still needs a decision

**Stack-land atomicity / partial-land visibility.** §2.4 lands a stack bottom-up, stop-on-first-
bounce, each change as an independent trunk seq. That keeps the queue's totality (I2) simple, but it
means a stack can land **partially**: A and B land (trunk@4188, 4189), C bounces, and trunk now
*publicly contains B without C* even though the author conceived A→B→C as one logical unit. For
many stacks this is correct and desirable (each change is independently reviewable and shippable —
the whole point of Sapling-class stacks). But for a stack that is only *correct as a unit* (B
compiles only with C; a refactor split for review but not for landing), partial land publishes a
broken intermediate trunk state, and there is currently **no "all-or-nothing land this stack as one
atomic unit" option**.

The decision to make: do we (a) keep stacks strictly independent (partial land is fine; rely on
presubmit/CI to reject a B-without-C that breaks trunk), (b) add an explicit **`mvfs land --atomic
--stack`** that admits the whole chain or none (which needs the land FSM to reserve a contiguous
`seq` range and land them as one fenced critical section — a real extension to the single-change
kernel in `02`), or (c) a middle ground where the author marks a stack `--squash-on-land` so an
N-commit stack lands as **one** trunk seq. Option (b)/(c) interact with restack semantics (what is
the Change-Id of a squashed land? — likely the bottom's) and with `02`'s single-change FSM, so it's
a real cross-doc decision, not just a CLI flag. **My recommendation: ship (a) for the first
release** (independent, partial-land-allowed, CI-gated — it is the honest Sapling default and needs
no kernel change), and **spec (c) squash-on-land as the fast-follow** for the "correct only as a
unit" case, deferring (b) true multi-seq atomic land unless a concrete user need demands it.
