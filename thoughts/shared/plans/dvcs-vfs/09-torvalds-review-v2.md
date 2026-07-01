---
date: 2026-06-25
reviewer: "Linus Torvalds (persona)"
status: review
topic: "Second VCS-design review of mvfs — did the OCaml/Irmin pivot FIX the three Showstoppers, or relocate them?"
target: thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
related:
  - thoughts/shared/plans/dvcs-vfs/03-torvalds-review.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [review, vcs, irmin, ocaml, merge, dirstate, fuse, stacked-changes, taste]
---

# Linus-style review v2 of `mvfs` — the Irmin pivot

I read the grounding research and the new direction brief. First, the thing I
rarely say: **you listened.** Last time I told you to reorder the roadmap so the
single-node, real-VCS-first work (merge, dirstate, stacks) comes before the
consensus theater, and you did exactly that — P0→P1→P2 is now "a usable
single-node trunk VCS with merge and fast status," and Raft is gone, not deferred-
then-snuck-back. You cut Shen, which I called the clearest cut in the document.
You picked a language with maintained FUSE/9P bindings instead of promising to
write four libraries in SBCL. You stopped name-dropping 10k engineers and wrote
"moderate scale" on the tin. That is most of what I asked for. Credit given, in
full, up front.

Now the job: did the pivot **fix** my three Showstoppers, or **relocate** them
behind a fashionable dependency? My read: **#3 (virtualization) is genuinely
fixed-as-honest. #1 (merge) is half-fixed and overclaimed. #2 (dirstate) is
relocated — the brief *claims* it as P1 but the mechanism that makes it fast is
P5.** Details below.

---

## Verdict (blunt, one paragraph)

This is now a VCS I'd be willing to *try*, which is more than I could say last
time. Irmin is a real CAS+history+typed-merge engine and choosing it deletes
12–18 months of plumbing you'd otherwise get wrong — that's good taste, reusing a
proven library instead of reinventing Git badly in Lisp. But the brief commits the
same sin as v1 in a new place: it equates "the dependency has a feature" with "the
hard problem is solved." **"Irmin has merge" is true; "merge is solved" is not** —
Irmin's typed merge gives you the *plumbing* (it does pass the LCA, credit), but
the part that makes merge HARD — line-level diff3, and rename-vs-edit /
delete-vs-modify across paths — is still code you write, and the brief's own §9.3
admits the custom content-type "fights Irmin's per-path merge model on
renames/deletes." That's not a footnote, that's the merge problem. On dirstate the
brief is worse: it *says* "first-class in P1" but in the same breath says it's "fed
by FUSE write-tracking once mounted" — and the mount is P5. So in P1, before any
mount, `status` is back to a stat-walk (better than v1's full re-hash, but the
EdenFS "O(files you touched)" magic is undelivered until P5). The stacked-changes
story is real in shape (local Irmin commits + Change-Id in metadata) but the brief
never says how a stack *rebases when its bottom lands* — the one operation that
makes stacks usable. And there's a fresh taste seam: Irmin objects + a separate
SQLite metadata index + the landed-log is **three sources of truth** wearing a
"derived, rebuildable" label that the brief asserts but doesn't enforce. Fix the
overclaim, move the dirstate mechanism honestly, and write the stack-rebase down,
and this is a tool I'd use on one machine. It is not there yet.

---

## Findings

### 1. [Serious] Merge: Irmin passing the LCA is real and good — but "merge is solved because Irmin has merge" is overclaiming, and the brief's own risk §9.3 knows it.

**Attacked:** §2 table "*Irmin typed 3-way merge + a diff3 text-content type. Merge
is core, not bolted-on.*" §5 "*attempt Irmin merge of the change onto tip (this is
where the typed/text 3-way merge runs — real merge, not path-overlap bounce).*"
§9.3 "*Is wrapping diff3/libgit2-xdiff as an `Irmin.Contents.S` with a `merge`
function the right seam, or does it fight Irmin's per-path merge model on
renames/deletes?*"

Let me separate what's genuinely fixed from what's relocated, because both are
true here.

**What's genuinely fixed (and I want this on the record):** the grounding research
(§3) quotes the actual Irmin Merge signature —
`old:'a promise -> 'a -> 'a -> ('a, conflict) result` — and the key fact is **the
LCA is passed**. `old` *is* the common ancestor (lazily, as a promise, because
computing it can be expensive and some merges don't need it). Store-level
`merge_into` computes the LCA and drives the merge path-by-path. So when you write
a custom `Irmin.Contents.S` whose `merge` calls diff3, **diff3 gets its three
inputs: base (`old`), ours, theirs.** That is a *real* 3-way merge, not the
two-input clobber I feared. This directly kills my v1 Showstopper #2's core
complaint — "there is no operation in this entire design that produces a new blob
combining base→mine diff applied onto trunk." Irmin gives you exactly that
operation, with the right LCA wired in. Two disjoint-line edits to one file will
*merge*, not bounce. That's the single most important fix in the pivot and it's
real. Good.

**What's relocated, not solved — and the brief half-admits it:**

1. **The line-merge content type is still yours to write, and it's where merge is
   hard.** The research is blunt (§3): "*for raw blobs the default merge is
   'conflict if both touched.' Real line-level text 3-way merge still needs a
   custom content type calling diff3/libgit2 xdiff — hundreds to low-thousands of
   LOC. So merge is enabled and structured, not free.*" The brief's §2 table
   ("Merge is core, not bolted-on") papers over this. Irmin didn't bring you a text
   merge; it brought you a *socket* to plug one into, with the LCA pre-wired. That
   socket is worth a lot. But "Irmin has merge" → "merge is solved" skips the
   diff3/xdiff implementation, conflict-marker generation, the merge-resolution UI,
   and the encoding/normalization edge cases (CRLF, encodings, trailing newline,
   binary detection) that are 80% of why real merge tools are big. **Call it what
   it is: Irmin solves the *3-way merge framework*; you still build the *text merge
   engine*.** Don't let the brief read like the latter is free.

2. **Per-path merge is the wrong shape for rename-vs-edit and delete-vs-modify —
   the cases that make merge actually hard — and §9.3 admits the fight.** This is
   the deep one. Irmin's `merge_into` merges **path by path**: it diffs the two
   trees against the LCA tree and, for each path, calls the content merge. That
   model is *fine* for "both edited `foo.ml`." It is **structurally blind** to the
   cross-path cases:

   - **Rename-vs-edit.** Ours: `git mv foo.ml bar.ml`. Theirs: edited `foo.ml`.
     Per-path, Irmin sees `foo.ml` deleted on our side and modified on theirs
     (delete/modify conflict) and `bar.ml` added on our side — it has **no concept
     that `bar.ml` IS `foo.ml` renamed**, so theirs' edits to `foo.ml` are silently
     dropped (they land on a path that no longer exists) or surface as a spurious
     delete/modify conflict. Git's `ort` does rename *detection* (similarity
     scoring across the whole tree) precisely so the edit follows the rename to
     `bar.ml`. A path-keyed merge cannot do that without a rename-detection pass
     *above* the per-path merge — which Irmin does not give you and the brief does
     not mention.
   - **Delete-vs-modify.** Per-path Irmin can *detect* this (path present-modified
     on one side, absent on the other → conflict), which is correct behavior, but
     the *resolution* (keep the file with the edits? honor the delete? which
     wins?) is policy you implement, and the brief's "clean merge → commit, conflict
     → reject with paths/hunks" model has no slot for "structural conflict that
     isn't a text hunk."
   - **Add-vs-add / mode changes / symlink-vs-file** — same story: these are
     tree-level structural conflicts, not content hunks, and a per-path content
     merge doesn't model them.

   The brief's §9.3 *names* this exact risk ("does it fight Irmin's per-path merge
   model on renames/deletes?") — so the team already smells it. Good instinct. But
   naming a Showstopper-class gap in the "open risks" appendix while the §2 summary
   table says "Merge is core, not bolted-on" is having it both ways. **Rename and
   delete handling is not an open question to resolve later; it's the definition of
   whether you have a merge.**

**Severity:** Serious, not Showstopper, *because the LCA-passing framework is real*
— you have the bones of a true 3-way merge, which you did NOT have in v1. It's
Serious because the brief overclaims completion and the rename/delete story is
unwritten.

**What I'd do:** (a) Rewrite §2/§5 to stop saying "merge is core/solved" and say
"Irmin provides the 3-way merge *framework* with LCA; mvfs implements (i) a diff3
text content type and (ii) a **rename-detecting tree merge pass** above Irmin's
per-path merge." (b) Make P1's "text 3-way merge content type" deliverable
explicitly include rename detection and delete/modify resolution, or split them
into a P1.5 with a real spec — don't let them hide. (c) Steal `ort`'s rename-
detection design (similarity over the changed-path set, not the whole tree) so it
stays O(changes). (d) Write down what a *conflict* looks like to the user: hunks
for text, but also "structural conflict: foo.ml renamed and edited" — and a
resolution path that isn't "resubmit from scratch."

---

### 2. [Showstopper] Dirstate: the brief *claims* O(changes) status in P1, but the mechanism that delivers it (FUSE write-tracking) is P5. In P1 you're back to a stat-walk of a huge tree.

**Attacked:** §2 table "*Dirstate is a first-class P1 deliverable, fed by the FUSE
write-tracking once mounted (EdenFS model).*" §7 "*Dirstate: a real index `(path,
size, mtime, ctime, inode, blob-hash)`; `status`/`diff` stat and only re-hash
changed entries → O(changes). Once the mount exists, FUSE write-tracking feeds the
dirstate (EdenFS model). First-class in P1 — not 'someday.'*" §10 P1 ships
"*no-mount sparse checkout*"; P5 ships "*FUSE write-tracking → dirstate.*" §9.6
"*P1 ships no-mount; can dirstate be fast (O(changes)) before the FUSE write-
tracking exists, or is P1 status still doing a stat-walk of a huge tree?*"

Read those two sentences from §7 together: "*O(changes)*" and "*Once the mount
exists, FUSE write-tracking feeds the dirstate.*" Those describe **two different
dirstates** and the brief blurs them into one "first-class P1" claim. Let me
separate them, because this is the exact relocation move.

**There are three tiers of `status` cost, and the brief conflates the top two:**

| Tier | Mechanism | Cost | Available |
|---|---|---|---|
| Re-hash the world (v1) | scan + SHA every file | **O(repo bytes)** | — (the v1 sin) |
| Git index / stat-walk | stat every file, re-hash only (size,mtime,ctime,inode)-changed | **O(repo files)** to stat + O(changes) to hash | **P1** (no mount needed) |
| EdenFS journal | kernel/VFS tells you which inodes were written | **O(files you touched)** | **P5** (needs mount) |

The v1 fix — a real index that stats and only re-hashes changed entries — **is a
genuine improvement and it IS available in P1 without a mount.** That kills the v1
Showstopper's worst form (re-hashing every byte). Credit: P1 `status` is no longer
`find | sha256sum`.

**But the brief writes "O(changes)" against P1, and that's not what a stat-walk
delivers.** A stat-walk is **O(repo files) just to `stat()` them all** — at a
million files that's a multi-second `getattr` storm every `status`, even when
nothing changed, even though you only re-hash the handful that moved. Git lives
with this on the kernel tree (~80k files, sub-second) but the brief's whole premise
is trees too big to check out. The thing that makes `status` *actually* O(changes)
— "stop walking the tree; the filesystem already knows what changed" — is the
**EdenFS change journal, and that requires the mount, which is P5.** So:

- **P1 `status` is O(repo files to stat)**, not O(changes). On a moderate tree
  (hundreds of thousands of files) that's tolerable-to-sluggish; on the "feels like
  the whole monorepo is here" tree the project exists to serve, a full stat-walk is
  exactly the cost EdenFS was built to avoid.
- The brief's §7 sentence "*O(changes)*" is only true **after P5**. As written, it
  promises P5's performance in P1's phase.

This is the same disease as v1, relocated: v1 asserted EdenFS-style and shipped
`find|sha256sum`; v2 asserts "O(changes), first-class P1" and ships a stat-walk,
with the real O(changes) mechanism quietly living in P5. The brief's §9.6 *asks
itself this exact question* — which means someone knew — but the §2 and §7 prose
answers it optimistically.

**Severity:** Showstopper *on the claim*, Serious *on the substance*. I'm calling
it Showstopper because the brief states a performance property (O(changes) status,
first-class P1) that the P1 architecture cannot deliver, and a developer choosing
this tool for monorepo `status` speed in P1 will be misled. The *fix* is cheap —
it's mostly honesty plus an optional early win.

**What I'd do:** (a) Rewrite §7 to say P1 dirstate is **Git-index-class
(stat-walk + re-hash-changed, O(repo-files to stat))**, and that **O(changes)
status arrives with the P5 mount's write journal.** Two tiers, named, not blurred.
(b) If you want O(changes) *before* P5 without the mount, the EdenFS-independent
answer is a **filesystem watcher** (Watchman / inotify / FSEvents — and the
research already notes `irmin-watcher` ships inotify/FSEvents). A watcher gives you
an O(changes) dirty set on a no-mount checkout in P1, decoupling fast-status from
the mount entirely. That's the move: don't make fast `status` hostage to P5.
(c) Stop writing "O(changes)" next to "P1" until one of (b)'s mechanisms is in P1.

---

### 3. [Good — was Showstopper #3] Virtualization: OCaml's maintained FUSE/9P bindings make the mount *real*, and the no-mount-first ordering is honest. This one is fixed.

**Attacked:** §2 table "*OCaml has maintained FUSE (`ocamlfuse`) + 9P (`ocaml-9p`).
The mount is real, not research-grade; no-mount checkout still ships first.*" §7
VFS. §10 P5.

This was my v1 Showstopper #3 — "virtualization ships last and is infeasible in
SBCL; you'll write a research-grade NFS server in Lisp last, on faith." The pivot
**fixes the feasibility** and **keeps the honest ordering**. Two things changed and
both are right:

1. **The binding is real, not a research project.** The research (§3) is specific:
   `ocamlfuse` is maintained against libfuse 2/3 and `google-drive-ocamlfuse` is the
   existence proof — a shipping, used FUSE filesystem in OCaml. `mirage/ocaml-9p` is
   maintained and Lwt-native, and Linux mounts `-t 9p` natively, which is arguably a
   *cleaner* server-controls-client story than FUSE. That's the difference between
   "we'll write an NFS server in SBCL and hope the GC doesn't stall a blocked
   syscall" (my v1 nightmare) and "we bind a maintained C library that other people
   already ship filesystems on." The OCaml GC and threading story is also saner
   under a libfuse loop than SBCL's was. **Feasibility: fixed.**

2. **No-mount-checkout-first is still honest about NOT delivering the monorepo
   value prop until P5 — mostly.** §7 says the VFS "ships second; P1 is a no-mount
   materialize-on-demand checkout." §10 puts the mount at P5. Good: you're not
   pretending sparse-checkout is virtualization. **But be even more honest in §1:**
   like v1, P1–P4 deliver "fast sparse checkout," and the thing that makes a 100GB
   repo *feel local* (lazy fault-in of any path, no disk materialization) is P5.
   The brief is better than v1 here but still soft-pedals that **the differentiator
   is P5.** Say it in the thesis, not just the phase table.

**The one caveat I'll hold you to (it's a real risk, correctly flagged):** "*a
maintained binding*" is not yet "*a performant lazy VFS for a big repo.*" Your own
§9.1 nails it: Tezos proves irmin-pack for **sequential single-writer ledger
writes**, NOT for "thousands of concurrent client reads of different path subsets
behind a FUSE mount." A FUSE mount turns every `read()`/`readdir()` into an
irmin-pack lookup under concurrency irmin-pack was never benchmarked for, plus the
Lwt↔Eio bridge (§9.2) sitting in the hot read path. So: the *binding* is real; the
*performance of Irmin-behind-a-mount* is unproven. That's a P5 risk to spike early,
not a reason to doubt the pivot. **De-risk it the way I told you to de-risk the NFS
server last time: a throwaway mount over a synthetic tree, measure
`readdir`/`read` latency and the Lwt/Eio bridge under concurrent load, in week 2 of
P5 — not at the end.**

**Severity:** this is the **clean win.** Showstopper #3 is fixed. The residual is a
known, named, spike-able performance risk, not a feasibility cliff. Keep the
no-mount-first ordering; just put "P5 is the differentiator and its perf is
unproven" in §1 where nobody can miss it.

---

### 4. [Serious] Stacked changes: the *shape* is credible (local commits + Change-Id), but the brief never says how a stack rebases when its bottom lands — which is the whole point of a stack.

**Attacked:** §2 table "*Local Irmin commits are cheap; a stable Change-Id rides in
commit metadata. Stacks are a client concern over Irmin history.*" §4 "*A
developer's local work is local Irmin commits (a stack); they become trunk only by
landing.*" §5.1 "*Client builds local Irmin commits; submits a change (base-commit,
paths, change-id, idempotency-key).*"

This was my v1 Finding 1: "a change under review has no identity and can't be
stacked." The pivot's answer is the *right shape* — and I want to credit it, because
it's the Sapling/Gerrit model done correctly:

- **Local Irmin commits as a stack** — yes. Irmin commits are cheap and content-
  addressed; a stack is a parent-chain of unlanded commits. Correct primitive.
- **Stable Change-Id in commit metadata, distinct from the land idempotency-key** —
  yes. §5.1 carries *both* `change-id` and `idempotency-key`, which means someone
  read my v1 complaint that the idempotency key is the wrong tool for review
  identity. The Change-Id survives revisions; the idempotency-key dedups a single
  land attempt. That's the Gerrit distinction, done right. Good.

**But "stacks are a client concern over Irmin history" is doing a LOT of
hand-waving, and the hardest part of stacks is missing entirely: restacking.** The
defining operation of a stacked workflow is: I have A ← B ← C in review. **A lands**
(possibly *modified* by review, so trunk's version of A ≠ my local A). Now B and C
are based on a commit that no longer matches trunk. Sapling's entire reason to
exist is that `sl` **automatically restacks B and C onto the new trunk tip** — it
rebases the orphaned children, re-running 3-way merge per commit, preserving each
commit's Change-Id, and tells me about conflicts per-commit. The brief says
**nothing** about this. Specifically unanswered:

- When A lands, **how does the client learn its local B,C are now orphaned**, and
  what re-parents them onto the new trunk tip? (This is a rebase = a sequence of
  3-way merges — see Finding 1; if your merge can't handle rename/delete, neither
  can your restack.)
- If A was **amended during review** (trunk's A differs from local A), restacking B
  onto trunk-A is a real merge, not a fast-forward. Does the Change-Id let the
  client recognize "trunk's commit with Change-Id X is my A, landed" so it drops
  local A and rebases B onto trunk? The brief has the Change-Id but never uses it
  for this.
- **Landing a stack:** §5 lands *one change* at a time. Does landing a stack land
  A, then B, then C bottom-up, each through the queue, each able to bounce
  independently? What happens to C if B conflicts on land? The brief's land FSM is
  single-change; the stack-land protocol is unspecified.

Without restacking, "stacks" is just "you can have multiple local commits" — which
is `git commit` x3, not a stacked-changes workflow. The value of Sapling-class
stacks is *the tool maintains the stack for you as its parts land and mutate.* That
machinery is the deliverable, and it's currently one sentence in a table.

**Severity:** Serious. The shape is right (real credit — this is no longer "changes
have no identity"), but the load-bearing operation (restack-on-land) is
unspecified, and it's not free — it's a loop of the 3-way merges from Finding 1.

**What I'd do:** (a) Add a "Stacks" section: a stack is an ordered chain of local
commits each with a stable Change-Id; **landing a stack lands bottom-up through the
queue**; on land, the client **restacks orphaned children onto the new trunk tip
via per-commit 3-way merge**, matching landed commits by Change-Id to drop the
local copies. (b) Spell out the amended-on-land case (trunk-A ≠ local-A → restack B
onto trunk-A is a merge). (c) Make P1's stack support include restack, or it's a
demo, not a workflow. (d) Note the dependency: restack quality == merge quality
(Finding 1), so rename/delete handling is *doubly* load-bearing.

---

### 5. [Serious] Taste: Irmin objects + SQLite metadata index + landed-log is **three sources of truth** again — the brief asserts "derived, rebuildable" but doesn't enforce it.

**Attacked:** §1 thesis "*Optionally keep a Fossil-style SQLite index ... and that
SQLite database is where your litevfs work is directly reusable.*" §3 Meta layer
"*SQLite: commit graph, blame, path history, ACL rows (derived, rebuildable;
replicate via litevfs/LiteFS).*" §4 "*Landed-log = the LiteFS-inspired append-only,
checksum-chained log ... This is the replication + read-your-writes substrate, and
the audit trail.*" §7 ACLs "*Stored as rows in the SQLite metadata index.*" §9.8
"*is that worth the second replication system, or should the landed-log replicate
everything and SQLite be a pure local cache?*"

In v1 I hit "three representations of one pointer" (RSM register + Raft snapshot +
substrate `:trunk` entity). The pivot killed Raft, which kills that specific
triangle — good. But a **new triangle** grew in its place, and the brief's §9.8
*sees it* without resolving it:

1. **Irmin trunk** — the authoritative object store and commit history. Truth.
2. **The landed-log** — append-only, checksum-chained, "*the replication + read-
   your-writes substrate, AND the audit trail.*" This is a **second** record of the
   same landed commits, with its own checksum chain.
3. **The SQLite metadata index** — commit graph, blame, path history, **and ACL
   rows.** Labeled "derived, rebuildable."

Three places that all encode "what landed and in what order." The brief *says* #3
is derived from #1 and #2 say it's rebuildable — and if that discipline holds,
fine, a derived query index is good taste (it's the Fossil model, which I respect).
But two things in the brief break the discipline:

- **ACL rows live ONLY in SQLite (§7), and ACLs are enforced at land admission and
  VFS read.** If SQLite is "derived and rebuildable," **derived from what?** ACL
  grants are not derivable from Irmin trunk content unless you also store them in
  Irmin (as files? as commit metadata?). As written, the **authoritative ACL state
  is the SQLite index** — which makes SQLite NOT a pure derived cache, it's a
  primary store for ACLs. That's a real source-of-truth split: object/history truth
  in Irmin, **ACL truth in SQLite.** Pick one. Either ACLs live in Irmin (versioned,
  rebuildable, replicated with the objects — my preference, they're security policy
  and want history) and SQLite indexes them, or you admit SQLite is a second
  authority and own the dual-write/consistency problem (which is exactly the
  dual-authority mess Aphyr and I both flagged in v1, reborn).

- **The landed-log vs Irmin overlap, and §9.8's "second replication system."** The
  landed-log is the replication substrate AND the audit trail AND (with its
  checksum chain) a parallel integrity record to Irmin's own Merkle DAG. Irmin
  *already* has a hash-chained history (that's what a commit DAG is). So the
  landed-log's `(seq, commit-hash, prev/post-checksum)` is partly re-deriving
  integrity Irmin already guarantees. That can be fine (you want the monotonic
  `landed-seq` and the LTX-style stream for replication, which Irmin push/pull
  doesn't give you for free) — but the brief should state crisply: **landed-log
  holds the linear ordering + replication stream; Irmin holds object truth; neither
  duplicates the other's job.** §9.8 asks whether you need the second replication
  system at all — and the honest answer the brief should commit to is: **landed-log
  replicates the Irmin objects + ordering; SQLite is a pure local cache rebuilt
  from the landed Irmin history, replicated by nobody.** One replication path, one
  object truth, one derived cache. The brief leaves it as an open question; for
  good taste it has to be a decision.

**Severity:** Serious. Not a correctness Showstopper at single-leader moderate
scale (one writer means you won't get the *races* that made v1's triangle deadly),
but it's a bad-taste seam that will rot: ACLs secretly authoritative in SQLite,
landed-log/Irmin integrity overlap unowned, and "derived/rebuildable" asserted but
not enforced anywhere.

**What I'd do:** (a) **ACLs live in Irmin** (versioned files or a typed contents
type under a reserved path), enforced from there; SQLite indexes them for fast
queries and is rebuildable. Now SQLite is *honestly* derived. (b) **One replication
system:** landed-log streams Irmin objects + ordering to replicas (the LiteFS
pattern applied to the object store, not to SQLite); SQLite is a **local** cache
each node rebuilds from its landed history — replicate *nothing* about SQLite.
Delete the "replicate SQLite via litevfs" idea unless you have a measured reason; it
*is* the second replication system §9.8 fears. (c) State the rule in §3: "Irmin =
object/history/ACL truth; landed-log = ordering + replication stream; SQLite =
derived local query cache, never authoritative, never replicated." Three roles, one
truth.

---

### 6. [Annoying] The Lwt↔Eio bridge in the hot read path is named (§9.2) but not budgeted — and it sits under both the mount and the land queue.

**Attacked:** §9.2 "*Irmin is Lwt-internally; the server wants Eio (io_uring,
multicore). The lwt_eio bridge in a long-lived multi-domain server — operational
hazard?*" Plus §9.1 (irmin-pack concurrency behind the mount).

Minsky and Fukamachi own the depth here, so I'll keep it short and in my lane:
**every `read()` through the P5 mount, and every land in P2, goes Irmin→Lwt→`lwt_eio`
bridge→Eio.** That bridge is in the two hottest paths in the system. The research
(§3) calls the FUSE/Lwt/Eio integration "fiddly but solved — ~a week of plumbing."
A week to *integrate* is not a week to make it *fast under concurrent multi-domain
load*. This isn't a Showstopper and it's the right language choice anyway — but the
brief should **budget a perf spike for the bridge under concurrent mount reads**
alongside the irmin-pack concurrency spike (§9.1), because they're the same hot
path and the same P5 risk. Measure it early; don't discover it in hardening.

---

## Showstoppers: fixed or relocated? — scorecard for my original three

| v1 Showstopper | v2 status | One-line judgment |
|---|---|---|
| **#1 No merge** (path-overlap is paranoia, no 3-way textual merge, no blob exists combining base→mine onto trunk) | **HALF-FIXED / OVERCLAIMED** | Irmin gives a *real* 3-way merge framework **and passes the LCA** (the operation v1 lacked now exists). But the diff3 text engine is still yours to write, and **rename-vs-edit / delete-vs-modify are unsolved** — per-path merge is structurally blind to them, and §9.3 admits the fight. "Merge is core, not bolted-on" overclaims. → **Finding 1 (Serious).** |
| **#2 No dirstate, O(repo) status** | **RELOCATED** | P1 dirstate is a genuine win over v1's full re-hash (it's a Git-class index now). But the brief writes **"O(changes), first-class P1"** while the mechanism that delivers O(changes) — FUSE write-tracking — is **P5**. In P1 `status` is an **O(repo-files) stat-walk**, not O(changes). The EdenFS magic is undelivered until the mount. → **Finding 2 (Showstopper on the claim).** |
| **#3 Virtualization last / infeasible in SBCL** | **FIXED (as honest)** | OCaml's **maintained** `ocamlfuse`/`ocaml-9p` make the mount a *real binding*, not a Lisp NFS research project — feasibility fixed. No-mount-checkout-first is honest that the monorepo value prop is P5. Residual: "maintained binding" ≠ "performant lazy VFS for a big repo" — irmin-pack-behind-a-mount perf is unproven (§9.1) and must be spiked early. → **Finding 3 (the clean win).** |

**Net:** one fixed, one half-fixed-and-overclaimed, one relocated-behind-a-phase-
boundary. The pivot moved the showstoppers from "this language/design can't do it"
to "the dependency has the feature but the hard 20% and the honest phasing are
still on you." That's *real progress* — it's the difference between an infeasible
plan and an over-optimistic one. But "Irmin has it" is not "it's done," in three
places.

---

## Good taste — keep this

Credit where it's earned, and there's more of it than last time.

- **Choosing Irmin instead of reinventing Git in Lisp.** This is the headline good
  call. Reusing a production-proven (Tezos) content-addressed store with a *typed
  merge framework that passes the LCA* deletes the 12–18 months of CAS/Merkle/commit/
  GC/merge plumbing you'd have built badly. Reusing a real library over a résumé-
  driven reimplementation is exactly the taste I want.
- **Cutting Shen.** I called it the clearest cut in v1. It's gone, ACLs are plain
  OCaml predicates (or tiny Datalog). A whole language runtime with a global lock,
  removed. Good.
- **Dropping Raft for a single leased leader + async replicas + a durability-width
  knob, AND saying "moderate scale" out loud.** This is right-sizing instead of
  name-dropping hyperscale. A single-leader serial land queue is *fine* for hundreds
  of developers and you finally just *say so* (§5) instead of gesturing at 10k
  engineers. The durability knob (fsync-on-leader, optional 1-replica-ack) is an
  honest, sized-down answer to the byte-durability problem, presented as a config
  knob not a consensus protocol. Honest.
- **The reordered roadmap: P0→P1→P2 is single-node-VCS-first.** This is *exactly*
  the reordering I demanded in v1 Finding 6 — prove the VCS is nice on one machine
  (merge, fast status, stacks) before you build distribution and the mount. The
  critical path is now "a usable single-node trunk VCS," with Raft gone and the
  mount after. You built the meal before the kitchen brigade. Keep this ordering
  even when P5 looks shiny.
- **Conflict is the 3-way-merge result, not path-overlap (§5).** The single most
  important conceptual fix from v1: two disjoint-line edits to one file *merge*
  instead of bouncing. The hot-file global-mutex pathology of v1 is gone *in
  principle* (modulo the diff3 engine you still owe).
- **Change-Id distinct from idempotency-key (§5.1).** You carry both, which means
  review identity (stable across revisions) is finally separate from land dedup
  (per-attempt). That's the Gerrit distinction done right — the v1 "every review
  round-trip is identity-less" sin is fixed in the data model.
- **Naming your own open risks in §9.** §9.1 (irmin-pack read concurrency), §9.2
  (Lwt/Eio bridge), §9.3 (per-path merge fights rename/delete), §9.6 (dirstate
  without a mount), §9.8 (two-replication-systems) — you flagged every gap I'd
  attack *before* I had to drag it out of you. That's the behavior I want. My
  findings are mostly "now *resolve* the risk you correctly named," not "you missed
  this." That's a good place to be.

---

## Bottom line

The pivot is real and most of it is right: you reordered the roadmap the way I
asked, killed Shen and Raft, picked a language whose FUSE bindings actually exist,
and bought a merge *framework* that — credit — passes the LCA, so the core
operation v1 lacked now exists. Showstopper #3 is genuinely fixed; you can build
the mount. But the brief repeats v1's deepest habit in a new costume: it mistakes
"the dependency has the feature" for "the hard part is done." Merge isn't solved
until diff3 and **rename/delete** are written, and §9.3 already knows the per-path
model fights them. Dirstate isn't O(changes) in P1 — the brief says it is, but the
mechanism that makes it so is P5; in P1 you're stat-walking a tree the project
exists to be too big for. Stacks have the right shape but no restack-on-land, which
is the only operation that makes a stack worth having. And three stores —
Irmin, landed-log, SQLite (with ACLs secretly authoritative in the last one) — are
a source-of-truth seam your own §9.8 flags and doesn't close. Fix the three
overclaims (say "merge framework, text+rename engine still owed"; say "P1 status is
stat-walk, O(changes) is P5 or a watcher"; say "ACLs live in Irmin, SQLite is a
pure derived cache, one replication path"), write down restack-on-land, and spike
the irmin-pack-behind-a-mount perf in week 2 of P5. Do that and this is a VCS I'd
put on my own machine. As written, it's a markedly better plan that still oversells
its three hardest parts.
