---
date: 2026-06-25
reviewer: "Linus Torvalds (persona)"
status: review
topic: "VCS-design review of metavfs — workflow, data model, performance, taste (NOT the consensus fault model)"
target: thoughts/shared/plans/dvcs-vfs/00-architecture.md
related:
  - thoughts/shared/plans/dvcs-vfs/01-aphyr-review.md
  - thoughts/shared/plans/dvcs-vfs/02-roadmap.md
tags: [review, vcs, workflow, monorepo, performance, dirstate, merge, packfiles, taste]
---

# Linus-style review of `metavfs` — the VCS, not the Raft

I read Kingsbury's review first so I don't waste anyone's time re-litigating
linearizability. He did that job well. I'm here for everything he *didn't* touch:
whether this thing is a good **version control system** and whether it would be
fast and pleasant to use at the scale it claims to target. He reviewed the
plumbing's distributed-systems correctness. I'm reviewing whether the porcelain
is something a developer would tolerate, and whether the data structures have
good taste.

---

## Verdict (blunt, one paragraph)

The consensus skeleton is fine and the *one* genuinely good idea — content in
CAS, hashes through Raft, verify by re-hash — is correct and reused tastefully.
But as a **version control system** this design is half-built and the wrong half
got built first. It has a beautiful replicated answer to "what is the trunk tip"
and almost nothing to say about the things developers actually spend their day
on: how a change *evolves under review*, how you work on three approaches at
once, how a conflict is *resolved* rather than merely *detected*, and — the part
that made me wince — how `status`/`diff` cost anything less than O(entire-repo)
when the whole premise is "millions of files." There is no merge. Path-overlap
is not conflict detection, it's conflict *paranoia*. There is no dirstate, so
the EdenFS value prop (the kernel tells you what changed) is asserted and then
quietly dropped — P1 ships `git sparse-checkout` with a Lisp accent. And the
roadmap front-loads Raft (P3) before it has *proven the VCS is nice to use*,
which is exactly backwards: Git won because branching and merging were cheap and
fast on one machine, not because of distribution. Build the thing people touch,
measure it, *then* replicate it. Right now you're plating a consensus protocol
and forgetting the meal.

---

## Findings

### 1. [Serious] "No branches, only a trunk submission queue" is dogma dressed as a goal — and the design forgets the entire lifecycle of a change under review

**Attacked:** §1.1 goal 2 "*Single linear trunk, no branches. The only durable
write path is submit → land.*" §0 "*a developer's uncommitted local edits are an
ephemeral fork of the trunk tip — but a fork can never become part of the durable
history except by landing.*" §1.2 "*No branches, no merges, no rebasing of
published history.*"

Let me steelman it properly first, because I'm not going to pretend trunk-based
development is stupid — it isn't. Piper/Google, Perforce shops, and trunk-based
CI-gated development are real, they work, and they ship at enormous scale. A
single linear history with no long-lived branches genuinely eliminates a class of
merge-hell and "which branch is prod" confusion. Forbidding branches in the
*durable* history is a defensible product decision. Fine.

But here's where the design confuses "no branches in *published* history" with
"no branches *anywhere*," and that's the tell of someone who has read about
trunk-based development but hasn't *done* feature work in one. The published
history being linear is a Piper property. But Piper developers do not live with
"uncommitted local edits are the only fork." They have **Critique CLs that
iterate across dozens of revisions before landing**, and Google built
**Sapling/`sl` with stacked changes** precisely because "one flat dirty working
copy" is not enough to do real work. Sapling's *entire reason to exist* is stacked
commits — a developer building feature X as commit A, then B-on-top-of-A, then
C-on-top-of-B, sending each for review independently, rebasing the stack as
earlier parts land. This design has **literally none of that**. Read §4 and §7.4
again: a change is a `:land-job` with a `root-node` and `paths`, and the only
local state is "dirty working copy." There is no notion of:

- A change that exists *as a named, reviewable, evolving object* before it lands.
  Where does code review iteration live? A reviewer says "fix this," the author
  edits — is that a new `:land-job`? A new idempotency key (§4.4 says exactly
  this: "*new idempotency key for the new content*")? So every review round-trip
  is a *fresh, identity-less submission*? You've thrown away the thing every
  modern code-review tool is built around: a stable change-id that accretes
  revisions.
- **Stacked changes.** I want to send A for review, and *while A is in review*
  start B on top of A. In this design B can't be based on A because A isn't in
  the trunk yet and there are no branches. So I'm blocked on every review. At a
  10,000-engineer monorepo with multi-hour review latency, serializing your own
  work behind your own review queue is a non-starter. This is *the* daily
  workflow and the design has no answer.
- **"I want to try three approaches."** Local experimentation across more than
  one line of development. With one dirty working copy I get *one* approach at a
  time. `git worktree`, `git stash`, three branches — gone. The design's answer
  is implicitly "make three checkouts in three directories," which is the 1998
  answer.
- **Long-lived refactors / release stabilization.** A tree-wide refactor that
  takes three weeks and 200 lands needs a way to be developed and tested as a
  unit before the pieces hit trunk. "No branches" says: land it piece by piece
  into the trunk everyone else is building on, half-finished. That's how you
  wedge a 10,000-engineer trunk.

**Why it's wrong from a real-VCS standpoint:** the published history being linear
and the *developer's working set* being linear are different requirements, and
the design conflated them. Piper/Sapling keep the trunk linear AND give
developers stacked, named, iterating local commits. You kept the first half and
deleted the half people actually touch.

**What I'd do instead:** keep the linear *trunk*, but introduce **local commits**
and **stacks** as first-class client-side objects (they're just `:change` records
with a parent chain that hasn't landed — you already have content-addressed change
records, §3.3, this is nearly free). A change gets a **stable change-id** at
creation that survives every revision (the land idempotency key is the wrong
tool; you want a Gerrit-style `Change-Id` that's stable across rebases and review
rounds). Landing a stack lands its commits bottom-up. This is the Sapling model
and it is the *only* one that makes trunk-based dev tolerable above ~50 engineers.
Until the doc says how a change evolves across review revisions, this isn't a VCS,
it's a deployment pipeline.

---

### 2. [Showstopper] There is no merge. Path-overlap "conflict detection" + content rebase with no 3-way textual merge is not a version control system.

**Attacked:** §4.4 "*Conflict = path overlap between job.paths and the union of
paths-touched of the interfering set.*" "*No overlap → auto-rebase: re-parent the
job onto tip, recompute the root-node by replaying the job's tree-diff onto the
tip's manifest. The blobs are unchanged (content-addressed), so rebase is a
manifest re-stitch, not a byte copy.*" "*Overlap → reject with needs-rebase.*"
§1.2 "*No ... merges.*"

I have merged, conservatively, *millions* of patches. Let me explain why this
model is broken at the most fundamental level, because it's not a tuning problem,
it's a category error.

**Path-overlap is the wrong conflict primitive in both directions:**

- **False positives (paranoia):** two developers edit *disjoint lines* of the
  same 5,000-line `BUILD` file, or two functions at opposite ends of one source
  file. Zero textual conflict. Git merges this without a human ever knowing.
  This design says: same path → overlap → **reject, needs-rebase**. So in a busy
  monorepo, every popular file (`BUILD`, `OWNERS`, the big `__init__`, a shared
  registry, a generated barrel file) becomes a **global mutex**. The second
  person to touch it always loses and resubmits. This is the single most common
  monorepo pain and the design *institutionalizes* it. At Google/Meta scale,
  high-traffic files are touched dozens of times an hour; under path-overlap they
  serialize completely and half the lands bounce.

- **False negatives (silent corruption):** Kingsbury already nailed the
  rename-vs-add case (his Finding 5), so I won't repeat the interleaving. The
  VCS-level point is broader: two changes to *different* files that are
  *semantically coupled* (you change a function signature in `foo.c`, I add a
  caller in `bar.c`) have zero path overlap, auto-rebase cleanly, and land a
  **broken trunk**. Path-overlap has no idea these are related. That's what
  *presubmit tests* are for, and the design barely mentions them (§4.2 "presubmit
  validation" is blob-presence + ACL, not "did the build pass against tip").

Now the part that actually made me put the document down: **"auto-rebase by
replaying tree-diff onto the new tip" is not a merge. It's a manifest re-stitch
with no 3-way textual merge at all.** Walk it: the developer based their work on
file `foo` at version `H_base`, producing `H_mine`. Trunk has moved `foo` to
`H_trunk`. The design's "rebase" replaces the *manifest entry* for `foo`. But
which blob does it point at? It can only point at `H_mine` (the whole-file blob
the developer produced against `H_base`) or `H_trunk`. There is **no operation in
this entire design that produces a new blob combining `H_base → H_mine` diff
applied onto `H_trunk`.** Whole-file blobs (§3.1) plus "blobs are unchanged
during rebase" (§4.4) means there is *no line-level merge anywhere in the system*.
So either:

1. Same-file edits always count as "overlap" → bounce to developer (the §4.4
   path). In which case there is no merge because there's no concurrent same-file
   editing allowed at all — every same-file race is resolved by "you go redo it
   by hand." That's CVS with a queue.
2. Or you let the rebase pick `H_mine`, silently **clobbering** every concurrent
   change to that file that landed in the window. Data loss.

Either way: **this VCS cannot merge two concurrent changes to one file.** That's
not a missing feature, that's the core competency of version control and it's
absent. Git's `diff3`/`merge-recursive`/`ort` exists for exactly this. You can't
hand-wave it with "content-addressed blobs make rebase free" — content addressing
makes *moving unchanged blobs* free; it does precisely *nothing* for combining two
changes to the same bytes.

**Why it's wrong:** a version control system's defining job is to combine
concurrent work. This design detects that concurrent work exists and refuses to
combine it. At low concurrency you won't notice. At the 10,000-engineer scale this
doc keeps invoking, the busy files are *always* concurrently edited and the trunk
will spend its life bouncing lands.

**What I'd do instead:** you need a real textual 3-way merge on the blob bytes
when two changes touch the same file with non-overlapping *line* ranges. Reuse a
real merge algorithm (diff3 / Myers + 3-way, or the Git `ort` semantics). Conflict
is then defined at **line granularity within a file** plus the structural
rename/delete cases, not "same path." Auto-rebase only succeeds when the 3-way
merge applies cleanly; otherwise it's a *real* conflict the developer resolves —
and "resolve" means an actual merge UI, not "resubmit from scratch." This is more
work than a manifest re-stitch, and it's the work that makes it a VCS. Until then,
call the product what it is: a serialized single-writer queue with optimistic
locking, not a DVCS.

---

### 3. [Showstopper] No dirstate / watchman. `status` and `diff` are O(entire repo) by construction — which is the exact thing EdenFS exists to kill.

**Attacked:** §1.1 goal 3 "*Millions of files.*" §7 "*EdenFS-style.*" §3.2 reuses
`filesystem-tree.lisp`. The doc cites `scan-directory` (`filesystem-tree.lisp:66`)
as a reuse "bone."

I read the code (`filesystem-tree.lisp`, `content-store.lisp`). Let me walk the
actual hot path, because this is the difference between a toy and a monorepo tool.

`scan-directory` (`:66`) → `scan-directory-recursive` (`:83`): for **every file**
it calls `read-file-bytes` (`:148`, reads the *entire file* into memory) then
`store-put-blob` (`content-store.lisp:86`) which does `blob-hash` → a full SHA-256
over **all the bytes**. There is no mtime/size short-circuit, no skip-if-unchanged.
So a single `status` against trunk tip is:

> **read + SHA-256 every byte of every file in the working copy, every time.**

At a million files and tens of GB that is *minutes per `status`*. Git `status` on
the kernel tree is sub-second because of the **index/dirstate**: it stat()s files,
compares (mtime, size, inode) against cached values, and only re-hashes the
handful that look changed — O(changes), not O(repo). EdenFS goes further: the
**kernel/VFS tells Eden which inodes were written**, so `status` is O(files you
touched), often single digits. That kernel-change-journal is *the entire reason
EdenFS was built* — checking out and statusing a Google monorepo with stock Git is
impossible, and Eden's answer is "stop walking the tree; the filesystem already
knows what changed."

This design has **no dirstate, no index, no watchman integration, no inode change
journal** — anywhere. §7.1 mentions an "inode/attr cache (LRU)" for *manifest
nodes*, which is the read side. There is nothing on the **dirty-detection** side.
So `status`/`diff` of the working copy fall straight back to `scan-directory`,
which re-hashes the world. The doc's recursive manifest (§3.2) is a genuinely good
instinct and fixes the *server-side tree* scaling — fetching a subtree is O(depth)
not O(files), credit where due — but it does **nothing** for the *client-side*
"what did I change locally" problem, which is the one a developer hits 200 times a
day.

**Why it's wrong:** the entire monorepo value proposition is "operations cost
O(what changed), not O(repo size)." The design delivers that for *server tree
fetch* and completely fails it for *the client's working-copy status*, which is
the most frequent operation in the system. You cannot claim "EdenFS-style" and
then re-hash every file on `status`. That's not EdenFS-style, that's `find | sha256sum`.

**What I'd do instead:** a real **dirstate** is table stakes, ship it in P1, not
"someday." Cache (path, size, mtime, inode, ctime, hash) per file; `status`
stat()s and only re-hashes entries whose (size,mtime,ctime,inode) moved — this is
Git's index and it's a few hundred lines. Then, when you build the actual VFS
(§7), the dirstate is *fed by the VFS write-tracking* (Eden's model): every write
through the mount marks the inode dirty, so `status` consults a change-set the VFS
maintained, never the disk. Without this, the monorepo claim is marketing.

---

### 4. [Serious] Whole-file blobs, no delta, no packfiles, no chunking — storage and network will explode, and the wire protocol fetches one blob at a time.

**Attacked:** §3.1 "*A blob is raw file bytes addressed by SHA-256.*" §5.4 blob
replication "*a node that needs blob H ... fetches H from any peer.*" §7.1 "*On the
first read() of a file, the VFS resolves its blob hash ... and pulls it via
store-get-blob, fetching cross-node if absent.*" Code: `content-store.lisp` stores
each blob as a standalone `(unsigned-byte 8)` array in a hash table; `store-put-blob`
copies the whole array.

Git has packfiles and delta compression for a reason, and that reason is "storing
every version of every file whole is insane." Consider the monorepo realities this
doc keeps invoking:

- **Small edits to big files.** A 50 MB generated `.pb.go` or a vendored lockfile
  or a checked-in dataset. Change one line. This design stores a **brand new 50 MB
  blob** — full copy, SHA-256'd over all 50 MB (§code), no delta against the prior
  version. Do that across thousands of generated files and a year of history and
  your CAS is orders of magnitude larger than Git would be. Git would store a
  delta of a few bytes.
- **Generated code / large files.** The monorepo is *full* of these and they
  churn constantly. Whole-blob-per-version is the pathological case for them.
- **No content-defined chunking.** Tools that handle big files at scale (Eden's
  backing stores, restic, Sapling's blob handling, even Dropbox's CAS) chunk files
  with a rolling hash (CDC / FastCDC) so that an insert near the front doesn't
  invalidate the whole file's storage. None of that here. One byte changed = one
  whole new object.

And the **network story is worse than the storage story.** §5.4 / §7.1 describe
**one-blob-at-a-time pull on demand**. Git learned in its first year that
round-tripping per object is death — that's why there's `git fetch` with packs,
thin packs, delta bases sent together, and the v2 protocol that batches "want"
sets. EdenFS batches blob fetches and prefetches whole directories. This design
faults in **one blob per read(), one cross-node RTT each** (§5.4 admits exactly
this in §10.6: "*a cold follower reading a never-fetched subtree pays a cross-node
round trip per blob*"). A cold `grep` across a subtree = thousands of serial
RTTs. That's not a performance footnote, that's unusable.

**Why it's wrong:** "measured, not asserted" — nobody measured this, and the
asymptotics are obviously bad. Whole-file CAS is fine for source files that are a
few KB and rarely huge. It is catastrophic for the large/generated/binary files
that dominate real monorepo *bytes*, and the one-at-a-time wire protocol turns
every cold operation into an RTT storm.

**What I'd do instead:** (a) **batch the wire protocol** from day one — a
`fetch-blobs([H...])` that returns a pack, with the server side coalescing; never
one RTT per blob. This is not optional at scale. (b) Introduce **delta/pack
storage** for the CAS: store popular base blobs whole and deltas against them
(Git's exact trick), or do **content-defined chunking** so big-file edits store
only changed chunks. (c) **Prefetch by manifest subtree** — when you fault a
directory, fetch its blobs as one batch, not lazily one at a time. The doc's own
§10.6 flags prefetch as "open"; it's not open, it's mandatory. The
out-of-band-blobs idea is good (keep it); the *granularity and batching* of that
plane is where the design is naive.

---

### 5. [Taste-nit] Entity sprawl and a manifest format that reinvents Git's tree object with worse ergonomics.

**Attacked:** §3.3–§3.5 the `:change` / `:land-job` / `:trunk` / `:manifest-node`
/ `:acl-rule` entity zoo, plus the Raft log command set §3.5, plus §3.2's
`:manifest-node` format.

Most of this is *fine* and even good taste — `:change` collapsing the snapshot DAG
to a linear chain is clean, and demoting `find-common-ancestor`/`find-branch-point`
to dead code (§3.3) is the right kind of ruthless simplification. I like that.

Two taste complaints:

- **`:trunk` as a 3-field entity (`:trunk/tip-seq`, `:trunk/tip-hash`,
  `:trunk/tip-root-node`) that is *also* the Raft RSM register that is *also* a
  substrate projection.** You have the same fact in three places: the RSM
  in-memory register (authoritative), the Raft snapshot, and a substrate `:trunk`
  entity (projection). Kingsbury hit the correctness angle; my taste angle is
  simpler — **three representations of one pointer is three things to keep in
  sync and three places to have a bug.** The `:trunk` entity earns its keep only
  as a queryable cache; say so loudly and make it derived, never written by hand.

- **The `:manifest-node` format is just a worse Git tree object.** Git's tree
  object is `mode SP name NUL 20-byte-hash`, sorted, hashed. It's tiny, canonical,
  and battle-tested. This design's `(:manifest-node :entries ((:file "foo" :blob
  "ab12…" :mode 33188 :size 1234) (:dir "sub" :node "cd34…") ...))` is a Lisp
  plist-in-a-list with **redundant fields baked into the hash input** — `:size`
  in particular. Why is `:size` in the manifest node? It's derivable from the
  blob. Putting it in the canonical hashed form means the same content at the same
  path can have *different manifest hashes* if size accounting drifts, and it
  bloats every tree object. `canonical-entry-string` (`filesystem-tree.lisp:237`)
  already commits `F:path:hash:mode:size` — the `:size` is along for the ride.
  Keep manifest nodes to the *minimum* that determines content identity: type,
  name, mode, child-hash. Metadata like size/mtime is a property of the blob or a
  side cache, not part of the Merkle identity. Sapling and Git both learned this.

**What I'd do instead:** trim the manifest node to `(type name mode hash)` per
entry, sorted, canonical. Pull `size`/`mtime` out of the hashed identity. Make
`:trunk` an explicitly-derived projection. The rest of the entity model is
acceptable.

---

### 6. [Serious] The roadmap builds Raft (P3) before proving the VCS is even pleasant to use. That's backwards.

**Attacked:** §11 phasing and `02-roadmap.md` §4. P0 manifest → P1 linear trunk +
land FSM → **P3 Raft** is "the spine." VFS checkout is P5, *after* Raft. The actual
merge/status/review-workflow work is nowhere on the critical path.

Git did not win because of distribution. Git won because **on a single laptop,
branching was instant, merging was good, and `status`/`diff`/`log` were fast.**
The distributed part was almost a side effect of the data model. This roadmap
inverts that lesson: it pours the hardest engineering (a from-scratch Raft in
SBCL, P3, with a Jepsen suite) into making the trunk pointer linearizable *before*
anyone has demonstrated that the developer-facing VCS is something a human would
choose to use.

Look at what's *missing* from the critical path entirely:

- No phase produces a **real merge** (Finding 2). Ever. It's not even listed.
- No phase produces a **dirstate / fast status** (Finding 3). The "VFS checkout"
  P5 is materialize-on-demand, which §7.3 itself admits is "git sparse-checkout
  with extra steps" — it does *not* deliver fast incremental status.
- No phase produces **stacked changes / review iteration** (Finding 1).
- The **actual virtualization** — the thing that makes a 100GB repo feel local —
  is P6 NFS-loopback, dead last, and §10.4 calls it "a real research-grade
  subproject."

So the roadmap ships, in order: a clever tree format, a queue, ACLs, a consensus
protocol, and *then* — maybe — starts on the parts a developer touches, with merge
and dirstate not scheduled at all. You will have a provably-linearizable trunk
that nobody can pleasantly commit to.

**Why it's wrong:** you're optimizing the part that's intellectually exciting
(distributed consensus) over the part that determines adoption (does `status`
return in 200ms, can I merge, can I stack my work). Раft is *table stakes
infrastructure* for the eventual multi-node story; it is not where the product
risk lives. The product risk is "is this nicer than Git/Sapling for a developer,"
and the roadmap never tests that.

**What I'd do instead:** reorder. P0 manifest (fine, keep). Then **single-node,
real-VCS-first**: dirstate + fast status/diff, real 3-way merge, local
commits/stacks, review-iteration identity. Get a developer using it on one machine
and *measure* status/diff/merge latency on a synthetic million-file tree. Only
once the VCS is demonstrably nice do you spend a quarter on Raft. Distribution of
a tool nobody wants to use is wasted consensus. Prove the meal before you build
the kitchen brigade.

---

### 7. [Serious] "Monorepo + VFS" — P1 delivers sparse-checkout, not virtualization. The thing that justifies the whole project shows up last and might not work.

**Attacked:** §7.3 "*Phase-1 fallback ... a materialize-on-demand CLI/checkout (no
kernel mount at all) that writes a sparse subtree to a real directory via
materialize-tree/materialize-diff ... This delivers the lazy/sparse semantics
without any mount protocol, and is what we ship first.*" §10.4 "*NFS/FUSE in SBCL
is genuinely hard ... the mount is a real research-grade subproject.*"

EdenFS exists for one reason: **you cannot check out a Google/Meta monorepo** —
it's hundreds of GB, tens of millions of files, materializing it to disk is
physically impossible on a dev machine. Virtualization is the answer: the
filesystem *looks* fully present, but files fault in on access and most never
touch disk. That's the magic. That's the value prop. That's the only reason to
build a VFS instead of just using Git with sparse-checkout.

What does P1/P5 actually ship? `materialize-on-demand` that **writes a sparse
subtree to a real directory** (§7.3). That is `git sparse-checkout`. It is a good,
honest, realistic thing to ship first — I'm not mad at the realism — but the doc
should be brutally clear that **P1 does not deliver the monorepo value prop at
all.** A sparse checkout still materializes everything in your profile to disk,
still can't present "the whole repo is here" semantics, still makes you declare
your sparse profile up front and re-sync on changes. The thing that makes a 100GB
repo *feel local* — lazy fault-in of any path without pre-declaring it, no disk
materialization — is the **actual virtualization**, and that's P6 NFS-loopback,
which §10.4 admits is research-grade and might not be performant in SBCL.

So the honest read of the roadmap is: **the project's entire reason for existing
(virtualize an un-checkout-able monorepo) is the last thing built, is flagged as
maybe-infeasible in SBCL, and everything before it is sparse-checkout you could
get from Git today.** That's a serious framing problem. If the NFS mount doesn't
pan out, you've built a slow distributed sparse-checkout and called it EdenFS.

On the NFS-loopback plan specifically: it's the *right* call over FUSE-in-SBCL
(credit — see good-taste section), but a userspace NFSv3 server that's fast enough
to back a developer's working tree is genuinely hard: attribute coherence,
`READDIR` on huge directories, the SBCL GC pausing mid-`READ` and stalling a
syscall the kernel is blocked on. EdenFS is a mature C++ codebase and *still*
fights these. Betting the monorepo value prop on "we'll write a performant NFS
server in Common Lisp, last, as a research subproject" is the riskiest bet in the
document and it's buried.

**What I'd do instead:** (a) Be honest in §1 that P1–P5 are "fast sparse
checkout," and that *virtualization* (the differentiator) is P6 and load-bearing —
don't let it read like a nice-to-have. (b) **De-risk the mount early.** Build a
throwaway NFS-loopback spike *before* committing to the roadmap, measure
`READDIR`/`READ` latency and GC-pause behavior under load on a synthetic tree. If
SBCL can't serve a mount fast enough, you want to know in week 2, not in P6.
(c) Consider whether the dirstate+sparse-checkout path (Findings 3, 6) is actually
"good enough" for your real users — if it is, the VFS is a science project and you
should cut it (see below). If it isn't, it's the most important thing and must not
be last.

---

### 8. [Annoying] Throughput of the single-leader land queue is never modeled — and at the scale this doc keeps invoking, it's the obvious bottleneck.

**Attacked:** §4.3 "*only the Raft leader runs a land worker ... applies lands in
strict seq order.*" §1.1 goal 3 "*Millions of files*" and the doc's repeated
"10,000-engineer monorepo" framing (mine, but it's the implied target).

The doc spends pages on Raft *safety* and **zero sentences on land *throughput*.**
That's a tell. A single leader, applying lands one at a time in strict seq order,
each land doing: presubmit + Shen ACL (cached) + conflict check (manifest walk) +
**a Raft round-trip to a majority (fsync on each follower)** + tip advance +
substrate projection write. Let's be generous: an intra-datacenter Raft commit
with fsync is single-digit milliseconds; the conflict/manifest work adds more.
Call it 5–20ms per land *if nothing bounces*. That's **50–200 lands/second
ceiling**, serialized, before you count the lands that bounce on path-overlap
(Finding 2) and resubmit, multiplying the offered load.

Google's monorepo takes tens of thousands of commits per day. Meta's similar. At
the high end that's order ~1 land/second *sustained* but with *bursty* peaks far
higher, and — critically — **a busy file serializes ALL lands that touch it under
path-overlap.** A single-leader serialized queue at 50–200/s *might* be okay for
average throughput, but the doc never checks, never states a target, and never
addresses the bounce-amplification. Piper does **not** serialize all lands through
one global lock — it shards and allows concurrent lands to disjoint paths to
commit in parallel. This design's strict-seq single leader can't.

**Why it's annoying not showstopping:** for a *moderate* monorepo (hundreds of
engineers) a single-leader queue is genuinely fine and simpler, and I won't
pretend otherwise. It becomes a wall only at the 10k-engineer scale the doc keeps
gesturing at. The sin is **not measuring it** — "performance, measured not
asserted" — and designing the conflict model (path-overlap) to *maximize* bounce
amplification on exactly the hot files that stress the queue.

**What I'd do instead:** state a target lands/sec and model it. If the target is
modest, single-leader is fine — *say so and stop name-dropping 10k engineers.* If
the target is large, you need **parallel landing of disjoint-path changes** (the
manifest already makes disjointness cheap to prove — §4.4's structural fast path),
committing batches per Raft round instead of one land per round. And fix the
conflict model (Finding 2) so hot files don't serialize the world.

---

## Good taste — keep this

Credit where it's earned. I'm not just here to break furniture.

- **CAS reuse: hashes through Raft, bytes out of band, verify by re-hash (§5.4).**
  This is the one genuinely load-bearing good idea and it's *correct*. It's why
  the RSM snapshots stay tiny (§5.5). Reusing the existing `content-store` /
  `filesystem-tree` Merkle layer instead of inventing a new one is exactly the
  right instinct. Don't let anyone talk you out of this.
- **Recursive content-addressed manifest (§3.2)** replacing the flat sorted entry
  list. This is the Git/Sapling tree object and it's *mandatory* for server-side
  scale — O(depth) subtree fetch, O(1) unchanged-subtree comparison by hash. Good
  instinct, properly motivated. (Just trim the format — Finding 5 — and remember
  it does nothing for client-side status — Finding 3.)
- **Demoting the DAG to a linear chain and deleting the dead multi-parent code**
  (`find-common-ancestor`, `find-branch-point`, the branch registry — §3.3, §3.4).
  Ruthless removal of code that the product doesn't need is good taste. I do this
  constantly. More of this.
- **NFS-loopback over in-kernel FUSE in SBCL (§7.3), and shipping no-mount
  checkout first.** The right risk call. Writing a libfuse FFI correct under SBCL's
  GC/thread model is a nightmare; userspace NFS is at least a clean protocol. And
  refusing to *promise* in-kernel FUSE is honest. (Just de-risk it early —
  Finding 7.)
- **The honesty of §9.3 and §10.** Naming the `take!` durability gap, the
  substrate-is-non-authoritative inversion, the Shen lock, and the GC-during-
  mutation problem *before* a reviewer had to drag it out of you is the behavior I
  want. Kingsbury said the same. The hazards are correctly located even where the
  fixes are thin.
- **Datalog (terminating) on the hot ACL path, Shen as authoring surface (§6.3).**
  Keeping the global-lock, possibly-non-terminating engine off the per-operation
  path is correct. Good engineering discipline.

---

## What I would cut

The complexity budget here is enormous: Raft + Shen + Prolog/Datalog + fset +
substrate EAV + a homegrown NFS server, all in Common Lisp. A lot of it is
résumé-driven. Here's the knife:

1. **Shen, entirely, from this product.** This is the clearest cut. The doc itself
   (§6.3, §10.3, and Kingsbury's Finding 9) spends enormous energy keeping Shen's
   global lock *off* every hot path, falling back to Datalog for actual evaluation,
   and admitting Shen is really just "the authoring/verification surface." If
   Datalog evaluates the ACLs and Shen is never on the read or apply path, then
   **Shen is a liability with no load-bearing role.** ACL rules are
   prefix-inheritance + group membership + deny-wins — that's a dozen lines of
   straight Common Lisp or a tiny Datalog ruleset. You do not need a second
   programming-language runtime with a global lock to express "longest-prefix
   match, deny wins." Cut Shen; author the rules as Datalog (or plain CL) directly.
   This removes a whole package, a whole lock-contention chapter, and a whole class
   of "did apply accidentally call Shen" bugs.

2. **The whole distributed/Raft layer — *defer it*, don't build it third.** Not
   cut forever, but cut from the critical path (Finding 6). Build the single-node
   VCS, make it nice, measure it. A single-node metavfs with a durable local land
   log is a complete, useful, *shippable* product for one team. Raft is the answer
   to "multi-datacenter HA," which is a problem you have *after* you have users.
   Building a from-scratch Raft + Jepsen suite in SBCL before the VCS is pleasant
   is the biggest misallocation in the plan.

3. **The NFS mount — gate it behind a spike, cut it if SBCL can't perform.**
   (Finding 7.) If a 2-week NFS-loopback spike can't hit acceptable `READDIR`/`READ`
   latency under GC, the *virtualization* dream dies and you ship fast
   sparse-checkout + dirstate, which — honestly — covers a large fraction of real
   monorepo users. Don't build a research-grade NFS server on faith.

4. **Keep but de-scope: the substrate EAV projection of trunk/change state.** Don't
   maintain `:change`/`:trunk`/`:land-job` as authoritative substrate entities
   *and* RSM state *and* Raft log (Finding 5, and Kingsbury's dual-authority
   Finding 1). Pick the log/RSM as truth and make the substrate a pure,
   rebuildable read cache or cut it from the write path entirely.

**What's essential and must stay:** the CAS layer, the recursive manifest, a
**real merge**, a **dirstate**, and a **batched wire protocol**. Notice that two
of the five essentials (merge, dirstate) **aren't in the roadmap at all**, and one
(batched fetch) is dismissed as "open." That's the headline: the design has
lovingly built the parts a VCS researcher finds interesting and skipped the parts a
VCS *user* cannot live without.

---

## Bottom line

The plumbing has good bones and one genuinely correct big idea. But somebody fell
in love with the distributed-systems problem and forgot they were building a tool
that developers have to *use all day*. There is no merge. `status` re-hashes the
universe. A change under review has no identity and can't be stacked. And the
hardest, riskiest engineering (Raft, then a Lisp NFS server) is scheduled *before*
anyone has shown the VCS is nicer than what people already have. Fix the data
structures and the special cases — build the merge, build the dirstate, give
changes an identity, batch the wire — and *then* go distribute it. Right now you've
got a beautiful answer to a question developers don't ask, and silence on the
questions they ask two hundred times a day.
