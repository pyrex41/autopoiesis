---
date: 2026-06-25
reviewer: Thomas Ptacek (persona)
status: review
topic: "shen-go vs all-OCaml for a trunk-only content-addressable DVCS-VFS — the LiteFS-reuse truth, ops reality, threat model, and the necessity check"
inputs:
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/13-plan-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/21-synthesis-shen-backends.md
  - thoughts/shared/plans/dvcs-vfs/06-grounding-research.md
tags: [review, ptacek, litefs, ltx, fuse, security, ops, shen, ocaml, dvcs, vfs]
---

# Ptacek review: shen-go vs all-OCaml — what I'd actually run

I run the pager rotation in my head when I read a design. That's the whole lens here. The other
reviewers already did consistency (Aphyr), VCS-purity (Torvalds), types (Minsky), and foundation
(Fukamachi). I'm not redoing those. I'm here for four things: the truth about reusing LiteFS, where
each of these designs wakes me up at 3am, where the security model leaks, and whether you should be
building this at all.

I'm going to be blunt because both of these documents are written by people who are smart and have
clearly never operated a FUSE-backed replicated thing under load. That's not an insult. It's just the
gap I'm here to close.

---

## Blunt verdict

**Neither plan should ship as written, but if you put a gun to my head: all-OCaml.** Not because
OCaml is better at anything that matters to your users — it isn't — but because *the thing that will
page you lives in one place you control*, and a small team can actually operate one runtime. The
shen-go plan's headline ("reuse the real, battle-tested litefs daemon") is the single most dangerous
sentence in either document, and I say that as someone whose colleagues built litefs and ltx. **You
do not want to reuse litefs for this. It is the wrong tool, reused for the wrong reason, and it
imports a two-process consistency model that will produce the worst bug in the system.**

And the deeper verdict, the one neither plan wants to hear: **most of this is a science project.**
The kernel worth building is small. The edifice around it (Shen, a custom DVCS, a bespoke VFS, a
hand-rolled replication authority) is mostly there because building it is more fun than using
git + sparse-checkout or Sapling. I'll name the real kernel at the end.

---

## The LiteFS reuse premise — I know the truth, and the truth is "don't"

shen-go's entire risk-reduction story rests on: *go-git + the actual `superfly/litefs` + `ltx` are
real, mature, in-tree code, so we get the body for free.* The synthesis already killed half of that
(go-git can't 3-way merge — it's alpha, fast-forward only; you'd vendor libgit2 or port gix-merge).
Good. But nobody on the panel has stood inside litefs in production and told you what reusing it
actually costs. Let me.

### What litefs *is*, and why that's a mismatch for you

litefs is a **FUSE filesystem that replicates a SQLite database by watching the journal/WAL for
transaction boundaries and packaging changed 4KB pages into LTX files.** Read that again. It is a
machine for one job: detect "a SQLite transaction committed" by watching FUSE write/fsync patterns
on a `.db` file, and ship the page delta. Every hard-won line of litefs is about *that* detection
and *that* page shipping.

You are not replicating a SQLite database. You're replicating a linear log of git commits. So what
exactly are you reusing?

The plan is honest-ish about this — it says (15 §4.1) "we are not replicating SQLite pages — we are
reusing LTX's *format and chaining invariant* as our landed-log." **Fine. But that means you are NOT
reusing litefs.** You're reusing `ltx` (a file format library — header/pages/trailer, CRC64-XOR
chain), which is genuinely reusable and ~nobody's-going-to-page-you code. The *litefs daemon* — the
part that is "battle-tested," the part the thesis leans on — is the FUSE-transaction-detection
engine and the Consul lease machinery, and **you're using essentially none of its actual value while
inheriting all of its operational baggage.** You've kept the wrapper and thrown away the candy.

So the honest framing the plan never quite makes: **reuse `ltx` (yes, it's a nice format), do NOT
reuse the litefs daemon.** Once you say that out loud, shen-go's "reuse the real battle-tested
daemon" advantage evaporates. What's left is: a format library (good), a merge engine that doesn't
exist (bad), and a FUSE binding (`bazil/fuse`, fine).

### What actually breaks with litefs in production (the stuff I got paged for)

Even setting aside the mismatch, here's what the plan treats as solved that isn't:

1. **The Consul lease is a TTL lease, not a fence.** This is Aphyr's whole point and he's right, but
   let me give you the operational texture. The lease is `lease_TTL` (default 10s). On a GC pause, a
   VM migration, a noisy-neighbor CPU steal on a shared host, or an NTP step, the "leader" thinks it
   holds the lease for several seconds *after Consul has already handed it to someone else*. litefs's
   own answer to this is "async replication + checksum chain detects the fork and the loser
   resyncs-away its divergent pages." That's acceptable for a cache-y SQLite replica. **It is
   categorically unacceptable for a VCS land authority**, because "resync away the loser" means *a
   developer's landed commit silently disappears.* The plan tries to fix this (CAS the fence on the
   durable append, refuse the stale appender) — but to do that *it has to reach past litefs and own
   the append itself*, which means **you are no longer using litefs's replication; you've reimplemented
   the authority and demoted litefs to a lease-holder you don't trust.** At which point: why is litefs
   here at all? Use Consul/etcd directly for the lease and own your log. The plan backs into this
   conclusion (21 §4 "own the fence") without admitting it deletes the reuse premise.

2. **The async replication window is real and subsecond — and it eats committed work.** litefs acks a
   write when it's durable *on the leader*, then ships LTX asynchronously. Leader's disk/host dies in
   that window → the data is gone. For SQLite-backed web apps that's a known, accepted, "you lost the
   last few writes" trade. **For a VCS, "I landed it, CI saw it, then it vanished" is a
   trust-destroying event.** The plan's mitigation (fsync-before-ack + an optional 1-replica-ack
   width knob + return the achieved width) is the *correct* mitigation and it's the same one I'd
   write — but notice it's identical in OCaml and shen-go. **This window is a property of the
   single-leader-async distribution model, not of litefs.** So it is not a reason to pick shen-go;
   it's a tax both plans pay equally. The OCaml plan (13 §3.2, §7 residual #4) states it just as
   honestly. Call it a wash, and stop crediting litefs for code you're not running.

3. **The ~100 TPS FUSE write ceiling.** litefs's write throughput is gated by FUSE round-trips on the
   journal — call it ~100 transactions/sec. shen-go's plan doesn't replicate SQLite so it doesn't
   inherit *that exact* number, but it does mount a FUSE filesystem (`bazil/fuse`) for the VCS working
   tree, and **FUSE userspace round-trip cost is the same physics.** Every `getattr`, `readdir`,
   `read`, `open` is a kernel→userspace→kernel hop. The plan waves at this with "the read path is
   served from a Go-side content-hash cache that mostly bypasses Shen per byte" (15 §1.3, §5) — good
   instinct, but the cache doesn't remove the FUSE syscall hop, it only removes the *Shen interpreter*
   from the hop. **Your p99 on a cold `find` / `grep -r` / IDE-indexer walk across a big tree is a
   FUSE-storm question, and it is identical in both plans** (OCaml's 9p default is arguably *better*
   here — see ops). The plan's Spike A (go-git concurrent multi-reader behind a mount) is the right
   spike and it should be gating. It is the single most important measurement in either document and
   it has nothing to do with Shen.

4. **Why LiteFS Cloud was sunset (Oct 2024) — and what it tells you.** LiteVFS (the lazy per-page
   `xRead` fetch, the architecturally-elegant "don't mount, fetch pages on demand" model) depended on
   LiteFS Cloud as its backend, and **that service was shut down.** The honest read: the *most elegant*
   part of the litefs lineage — lazy page fetch, which is *exactly the "lazy file materialization in a
   sparse checkout" pattern this whole VCS wants* (06 §1 table calls it "Strong architecturally") —
   **did not survive contact with the economics of operating it.** That should make you deeply
   suspicious of any plan whose elegance depends on a lazy-fetch-from-a-remote mount being cheap to
   run. Both plans have this exposure (lazy trees over the mount); neither has costed the operational
   reality of serving cold reads to N developers' editors hammering the mount. LiteFS Cloud's tombstone
   is the warning label.

**Net on the LiteFS premise:** It's a trap, and specifically it's a *marketing* trap inside the
plan. "Reuse battle-tested litefs" reads as de-risking; in reality you reuse a 200-line format
library, reimplement the only part that matters (the fenced authority), inherit a FUSE cost you'd
have anyway, and adopt — if you're not careful — a **two-process split-authority** (litefs daemon
owns the mount + lease; your go-git process owns the objects + merge) that is the highest-severity
design smell in the document.

---

## Operational reality — where do you get paged

This is the section the type theorists skip. It's the one that decides whether your team survives
year two.

### The two-process / two-language problem in shen-go

shen-go's actual deployed shape, if you reuse litefs as written, is **two processes**: the litefs
daemon (FUSE mount + Consul lease + LTX shipping) and your shen-go binary (go-git objects, merge,
land FSM). The plan's own §1.3 and the synthesis (21 §3) flag the "two-process authority split."
Here's what that means at 3am:

- **A torn land is now a distributed transaction across two processes you have to reason about
  together.** The commit landed in go-git's object store but the litefs daemon hadn't shipped the LTX
  entry, or vice versa. Which one is truth? The plan's answer (derive the LTX entry from the commit,
  one critical section) is right *only if you own both*, which again means *not using litefs's daemon.*
- **Two crash domains, two restart orders, two sets of logs in two formats.** When the mount wedges,
  is it the FUSE layer, the lease, the go-git read, or the Shen evaluator? You're correlating across a
  process boundary at 3am.
- **Three failure vocabularies in one binary** even in the single-process version: a Go panic, a Shen
  type error, and a KL-runtime error are three different things with stack traces that cross a
  Shen→KL→IR→Go translation layer (15 §12.1 admits this). When prod is down, "what does this stack
  trace mean" should take seconds, not a Shen-internals spelunk.
- **Bus factor on the runtime.** This is the killer. The entire plan rests on `shen-go`
  (tiancaiamao/shen-go) being production-ready (15 §12.4 — "the one assumption the whole plan rests
  on"). If the KL runtime has a goroutine-safety bug on your pure read path, a GC pathology, or a
  primitive-registration gap, **you cannot file a ticket with a vendor and you cannot hire someone who
  knows this code.** Shen's contributor pool is single-digits. When that runtime mis-behaves under
  your load, you are the world's leading expert on it by default, whether you wanted to be or not. I
  have operated systems on niche runtimes. It is a tax you pay every single incident, forever.

### all-OCaml: one runtime, one binary, one set of logs

The OCaml plan is **one language, one toolchain, one runtime, deployable as a `mvfs` core CLI that
doesn't even drag libfuse into its closure** (13 §1 — separate `mvfs-mount` package). That packaging
discipline is the single most operationally mature thing in either document. The mount being a 9p
server by default (13 P5) rather than FUSE is *also* the better ops call: 9p sidesteps the
libfuse/macFUSE version matrix entirely, the client is the kernel's `-t 9p`, and the server is a
plain process you can restart without unmounting-the-world. FUSE mounts wedge into `D` state
(uninterruptible sleep) when the userspace server hangs, and you cannot `kill -9` your way out — you
reboot the box or the editor that's blocked on it. 9p degrades more gracefully.

OCaml's debuggability isn't free — the Lwt/Eio bridge is a genuine hazard (Minsky's point, and the
plan wisely puts a P0 spike to *avoid* taking it, 13 Spike S2). But it's a hazard *in a language you
can hire for, with a compiler maintained by Jane Street and Tarides, in one process.* When OCaml
pages you, you can reason about it. The bus factor is "OCaml," not "the one Shen→Go transpiler one
person maintains."

**Ops verdict: all-OCaml is the only one of the two a small team can actually operate.** It's not
close. The shen-go plan is more *intellectually* coherent (one heap, no FFI marshaling — genuinely
nice) but more *operationally* fragile (niche runtime bus factor, transpiler in the failure path, and
— if it reuses litefs — a second process).

---

## Security / threat model (Matasano hat on)

A VFS mount is a syscall-reachable attack surface and your path-scoped ACLs are an authorization
system. Both of those are where I'd spend a pentest day. Here's where each design leaks. Most of these
are *the same in both plans* because they're inherent to "path-prefix ACLs over a virtual filesystem,"
which is the part that should scare you.

### Finding S1 — Path normalization / `..` / symlink ACL bypass — **HIGH — both options**

Both plans gate access by **path prefix**: OCaml's `predicates.ml` does "longest-prefix, deny-wins"
over grants; shen-go's `defprolog prefixp` does `gobody.string-prefix?`. **Prefix matching on paths is
a classic confused-deputy generator.** Concretely:

- If the ACL check runs on a *requested* path string but the VFS resolves a *different* canonical
  path (because of `..`, `.`, doubled slashes, trailing-slash, Unicode normalization, or
  case-folding on a case-insensitive client), an attacker reads `src/secrets/key` by asking for
  `src/app/../secrets/key` or `src/secrets/../secrets/key` or `src//secrets/key`. The grant table
  says "eng denied on `src/secrets/`"; the string `src/app/../secrets/key` doesn't have that prefix,
  but the file it resolves to does.
- **Deny-by-prefix is especially dangerous**: the OCaml example (implicit) and the shen-go example
  (15 §3.5: `eng read "src/secrets/" deny`) rely on the deny rule's prefix matching the *effective*
  path. Any normalization gap between "the string the ACL saw" and "the inode the VFS served" is a
  silent deny-bypass.
- **Symlinks**: if the working tree can contain a symlink `src/app/link -> ../secrets`, and the mount
  follows it, then a read under `src/app/link/key` is authorized by the `src/app/` allow grant but
  serves `src/secrets/key`. A content-addressed tree *can* contain symlink entries (git mode 120000).
  Does the VFS follow them? Does the ACL check happen before or after symlink resolution? **Neither
  plan says.** This is the bug I'd write the PoC for first.

The fix is the same in both languages and neither plan specifies it: **canonicalize to a normalized,
symlink-resolved, repo-relative path FIRST, then authorize the canonical path, then serve exactly
that canonical inode — never authorize one string and serve another.** Make `Path.of_string`
(OCaml has the right instinct — it returns `(t, [\`Invalid])`, 13 §2) the *only* constructor and make
it reject/normalize `..`, absolute paths, and NUL bytes; make the VFS incapable of serving a path
that didn't come from that constructor. shen-go's `Path` discipline is weaker as written (raw string
prefix ops in Prolog). **Slight edge to OCaml** because it already models `Path.t` as a validated
abstract type; but both must treat this as a P0 invariant, not a P3 ACL detail.

### Finding S2 — The mount as a confused deputy / who is the subject — **HIGH — both options**

A FUSE/9p mount is served by **one server process** that makes upstream object-store reads. The kernel
hands the server a request with a `uid`/`gid` (FUSE `fuse_context`) — *if* the server is configured
to read it and *if* `allow_other` semantics are set up correctly. **The hard question neither plan
answers: when the VFS serves a `read()`, whose ACL subject is it evaluating?**

- If the mount runs as a service account and serves all local users, then **local UNIX permissions on
  the mountpoint are the only thing between user A and user B's path-scoped data**, and the
  path-scoped ACL is evaluated as "the service," i.e., it's *not enforced per-user at the mount at
  all.* That's a multi-tenant isolation hole big enough to drive a truck through.
- The plans clearly intend ACLs enforced at *two* points: VFS read and land admission (15 §3.5
  "one rule base, two enforcement points"; 13 §0 item 9). But the VFS-read enforcement only means
  something if the mount knows *which authenticated subject* is reading, and a local FUSE/9p mount's
  notion of "subject" is a kernel `uid`, which is trivially not the same as your VCS identity.
  **Mapping kernel uid → VCS subject securely is unspecified in both, and it is THE multi-tenant
  question.** On a shared dev host this is a real boundary; on a one-user-per-machine model it's moot
  but then the VFS-read ACL is theater and only the *land* ACL matters. **The plans need to pick a
  deployment model and say so**, because the threat model is completely different between
  "one mount per user, ACL enforced server-side on authenticated pulls" and "one shared mount, ACL
  enforced by UNIX perms." This is equal in both and unaddressed in both.

### Finding S3 — Content-addressing as a side channel — **MEDIUM — both options**

Content addresses are deterministic hashes of content. In a multi-tenant repo with path-scoped read
ACLs, **a user who can't read `src/secrets/key` may still be able to confirm its contents** if they
can observe object existence or dedup behavior:

- *Existence oracle*: "does blob with hash H exist?" If an unauthorized user can ask the object store
  whether a hash is present (e.g., during a push, "you already have this blob, skip it"), they can
  confirm a guess of the secret file's contents by hashing it and probing. Git's smart protocol and
  any dedup'ing push will leak this unless object existence is itself ACL'd.
- *Dedup timing*: if writing a blob that already exists is faster (dedup short-circuit), the timing
  confirms content. The shen-go land path's `has_blob` presence check (15 §5) and OCaml's
  `has_blob`/`history_find_idem` (13 §2) are exactly these oracles.

Mitigation: the *content store* must itself be path/permission-aware for existence queries, or you
accept that anyone who can talk to the store can do confirm-by-hash on guessable secrets. **Neither
plan models the object store as an authorization boundary** — both treat ACLs as a layer *above* a
fully-readable CAS. For "secrets in the monorepo" this is a real leak. Same in both languages.

### Finding S4 — Shen-Prolog ACL evaluation vs OCaml predicate ACLs — **MEDIUM — shen-go worse**

Does the engine change the attack surface? Yes, a little, and not in shen-go's favor:

- **Prolog evaluation is harder to bound.** shen-go evaluates ACLs via `defprolog` with `findall`
  over `applies` + `prefixp` (15 §3.5). Prolog resolution can be expensive and, with a bad rule
  base, non-terminating or super-linear. Since **policy is data loaded from the repo**
  (`.shengo/policy.shen`, 15 §7) and policy changes go through the same land queue, **a malicious or
  buggy policy commit is an attacker-controlled program fed to a logic engine on the authorization
  hot path.** That's a DoS surface (a crafted rule set that makes `findall` blow up) and a
  correctness surface (subtle resolution-order bugs that grant more than intended). Prolog's
  expressiveness is exactly what makes it hard to *audit* "what can this subject actually access."
- **OCaml's plain predicate evaluator (13 §0 item 9, `predicates.ml`) is a bounded, total
  longest-prefix/deny-wins function** — auditable, terminating, easy to fuzz, easy to write an
  exhaustive test for. The plan keeps the *optional* Shen-Prolog oracle strictly **off the hot path,
  off by default, only at land admission, with a plain-OCaml fallback, verdict reduced to the same
  proof type** (13 §2 `shen_oracle.ml`). **That is exactly the right way to use a logic engine for
  policy: as an optional, sandboxed, non-load-bearing advisor, never as the hot-path authorizer.**

So on the security of the authz system specifically: **OCaml's design is materially easier to get
right.** A bounded total function you can exhaustively test beats a Turing-ish logic engine eval-ing
repo-controlled rules on every check. shen-go's homoiconic-policy elegance is a genuine *audit and DoS
liability* the OCaml plan structurally avoids. This is the clearest security differentiator between
the two.

### Finding S5 — Both plans authenticate the chain but not the authority — **MEDIUM — both**

LTX's CRC64-XOR chain (06 §1) detects *corruption and accidental forks*. **It is not cryptographic
and not an authentication mechanism.** Neither plan says how a replica *authenticates* that an LTX
stream came from the legitimate leader vs. an attacker who can talk to the replica's pull endpoint.
"Verify the checksum chain" stops bit-rot and split-brain, not a malicious peer feeding a valid-looking
chain. You need transport auth (mTLS) + signed log heads if the replication network isn't fully
trusted. Equal gap in both.

### Security verdict

The *inherent* VFS/ACL leaks (S1, S2, S3, S5) are **equal in both plans and underspecified in both** —
which tells you the security thinking is immature regardless of language, and these are P0 invariants,
not P3 features. The one place language choice clearly moves the needle is **S4: OCaml's bounded
predicate authorizer is far easier to get right than shen-go's repo-controlled Prolog on the hot
path.** Security edge: **all-OCaml**, decisively, on the authz engine; tie (and both need work)
everywhere else.

---

## The honest "is any of this necessary" check

Now the part I'm actually known for. Step back from both documents.

**You are building a content-addressable, trunk-only, monorepo DVCS with a virtual filesystem, for
hundreds of developers, with path-scoped ACLs and lazy materialization.** Strip the language wars and
ask: does this exist already, well, that you could just *use*?

- **Sapling + EdenFS** (Meta) is *exactly this*: a Git-compatible DVCS designed for monorepos, with a
  virtual filesystem (EdenFS) doing lazy materialization, real merges, stacked diffs as a first-class
  workflow, and proven at the largest monorepo scale on the planet. It is open source. The "trunk-only
  / stacked changes / lazy VFS" trifecta this whole document set is reinventing **is the Sapling
  product thesis.**
- **git + sparse-checkout + partial clone + `git maintenance`** gets a *lot* of teams with big repos
  to "fine" without any of this. Sparse-checkout is the no-mount sparse profile (the OCaml plan's P1
  deliverable) shipped and battle-tested. Partial clone is your lazy blob fetch.
- For the path-scoped ACL requirement specifically — which is the one genuinely non-git-native
  requirement here — **Gerrit and Gitea/GitLab already do path/branch-scoped access control** server
  side, and Google's internal model (Piper/CitC) is the reference design you're cribbing from anyway.

So what's the honest kernel that *isn't* served by "use Sapling" or "use git + sparse-checkout +
Gerrit"? I can find exactly **one** thing in this pile that's both real and not off-the-shelf:

> **A single-leader, fenced, append-only *land queue* with path-scoped admission ACLs and an honest
> durability-width ack, sitting in front of an ordinary content-addressed object store.**

That's it. That's the kernel. It's the trunk-land-authority + ACL-admission + read-your-writes-cookie
machinery. Everything else — the object store, the merge engine, the VFS mount, sparse checkout,
stacked changes, blame/history — **either exists in mature form (go objects, libgit2 merge, EdenFS/9p,
sparse-checkout) or is a reimplementation for its own sake.** And notice: that kernel is a few
thousand lines of *careful distributed-systems code* whose hard parts (the fence, the idempotency, the
RYW-under-partition, the durability honesty) are **identical regardless of whether the brain is Shen,
OCaml, or a Python script.** The language religion is irrelevant to the only novel, hard, valuable
part.

**My actual recommendation if this were my company:** build the land-queue kernel as a small,
boring service (any memory-safe language with a real ecosystem — Go or Rust or OCaml, doesn't matter)
in front of **plain git object storage** (or Sapling's storage), use **EdenFS or 9p** for the mount
instead of writing one, use **libgit2 or Sapling's merge** instead of writing one, and enforce ACLs
at the land-admission point (where it's a bounded total function, easy to get right) and at the
*authenticated pull* boundary (not at a local FUSE inode). That deletes 80% of both plans and keeps
the 20% that's actually a contribution. **Shen earns nothing in this picture.** The sequent types are
nice for the FSM, but the FSM is the easy part; the hard part is the I/O-and-failure behavior that no
type system makes correct.

If — *if* — there's an org-political or research reason the homoiconic/Shen brain is the actual goal
(the autopoiesis lineage suggests it might be), then it's a research project, and you should *call it
one*, scope it as one, and not pretend "reuse battle-tested litefs" is de-risking a production system.

---

## Findings table

| # | Severity | Option(s) | Finding |
|---|---|---|---|
| L1 | **High** | shen-go | "Reuse battle-tested litefs" is misleading: you reuse `ltx` (a format lib), not the litefs daemon, and you must reimplement the fenced authority anyway — deleting the reuse premise. |
| L2 | **High** | shen-go | Consul TTL lease ≠ fence; litefs's native "loser resyncs away" silently drops a landed commit — unacceptable for a VCS. Fixing it means *not* using litefs's replication. |
| L3 | Medium | both | Async-replication subsecond data-loss window. Property of single-leader-async, not litefs. Equal tax; both mitigate identically (fsync-before-ack + width knob + honest ack). |
| L4 | Medium | both | FUSE round-trip cost (litefs's ~100 TPS ceiling is the same physics) hits the VFS read path; Spike A is correctly gating and is language-independent. 9p (OCaml default) degrades better than FUSE. |
| L5 | Medium | both | LiteFS Cloud's Oct-2024 sunset is a warning: lazy-fetch-over-a-remote-mount (the elegant core both plans lean on) did not survive its own operating economics. Cost the cold-read path. |
| O1 | **High** | shen-go | Two-process (litefs daemon + go-git proc) split authority = distributed txn across two crash domains/log formats at 3am. |
| O2 | **High** | shen-go | Bus factor: entire plan rests on a single-maintainer Shen→Go transpiler runtime in the prod failure path. No vendor, no hires, no second expert. |
| O3 | Medium | shen-go | Three failure vocabularies (Go panic / Shen type error / KL runtime error) across a transpile layer. |
| O4 | Plus | all-OCaml | One runtime/one binary; mount as separate package (no libfuse in core closure); 9p default avoids the FUSE wedge-into-D-state failure. Operable by a small team. |
| S1 | **High** | both | Path-prefix ACL bypass via `..`/normalization/symlinks: authorize-one-string-serve-another. Must canonicalize+resolve before authz. OCaml's validated `Path.t` is a slight head start; shen-go's raw-string Prolog prefix is weaker. |
| S2 | **High** | both | The mount is a confused deputy: kernel uid ≠ VCS subject. Multi-tenant isolation (whose ACL does a local `read()` evaluate?) is unspecified in both. Pick a deployment model. |
| S3 | Medium | both | Content-addressing existence/dedup oracle leaks secret-file contents to users lacking read ACL, unless the CAS itself is an authz boundary. Modeled in neither. |
| S4 | Medium | **shen-go worse** | Repo-controlled Prolog policy on the authz hot path = DoS + audit liability. OCaml's bounded total predicate evaluator (Shen only as optional off-hot-path oracle) is far easier to get right. |
| S5 | Medium | both | CRC64 chain detects corruption, not malice; replica stream lacks authentication (needs mTLS + signed heads on untrusted networks). |
| N1 | **High** | both | Necessity: Sapling+EdenFS / git+sparse-checkout+partial-clone+Gerrit already deliver ~90% of this. The novel kernel is just the fenced land-queue + admission ACLs. The rest is reimplementation. |

---

## shen-go or all-OCaml — what I'd actually run, and why

**If the choice is strictly these two: all-OCaml.**

Reasoning, in priority order:

1. **Operability.** One language, one runtime, one binary, one set of logs, a 9p mount that doesn't
   wedge the box, a compiler with real backing, and a hireable talent pool. shen-go puts a
   single-maintainer transpiler runtime in the prod failure path and (if it reuses litefs as
   advertised) a second process across a second crash domain. A small team can run the OCaml thing.
   It cannot reliably run the Shen thing under incident pressure.
2. **The security of the authorization system.** OCaml's bounded total predicate ACL is auditable and
   testable; shen-go's repo-controlled Prolog on the hot path is a DoS-and-audit liability. The authz
   engine is the part most likely to be the actual breach, and OCaml's is the one you can get right.
3. **The LiteFS premise is a trap, not an asset.** shen-go's headline de-risking is illusory: you
   reuse a format library, reimplement the authority, and inherit FUSE physics you'd have anyway. Once
   that's stripped, shen-go's remaining "advantages" are the one-heap/no-FFI elegance (real, but an
   *engineering nicety*, not an *operational* one) and the Shen brain (a research goal, not a
   production need).

The shen-go plan is the more *beautiful* document. The all-OCaml plan is the one whose 3am behavior I
can predict, whose authz I can audit, and whose runtime I can hire for. I pick the one I can operate
every time.

**Caveat I'd put in writing:** even all-OCaml is, per N1, mostly reinventing Sapling/EdenFS +
Gerrit-style path ACLs. If I had budget authority I'd build only the fenced land-queue kernel in front
of off-the-shelf storage and an off-the-shelf mount, in *whatever* memory-safe language has the best
ecosystem fit, and skip the rest. The DVCS, the VFS, and Shen are the parts you should be buying, not
building.

---

## The single "this will page you at 3am" concern for each option

- **shen-go:** *A leadership flap (GC pause / VM migration / NTP step) makes a stale leader land a
  commit that the litefs-derived replication then silently discards as the losing fork — a
  developer's landed, CI-acknowledged commit vanishes, and to even diagnose it you're correlating a
  Go panic, a Shen runtime error, and the litefs daemon's logs across two processes while nobody on
  the team can read the transpiler's internals.* The fence-CAS repair (21 §4) is supposed to prevent
  the land, but it only works if you've already stopped trusting litefs's lease — i.e., the very
  reuse that was the plan's selling point is the thing you had to throw away to be safe.

- **all-OCaml:** *The 9p/FUSE mount server hangs (or the Lwt↔Eio bridge deadlocks if Spike S2 went
  the wrong way) and every developer's editor/build that's blocked on `read()` against the mount goes
  into uninterruptible wait at once — a thundering, correlated, "the whole office is frozen" outage
  whose blast radius is "every active reader," gated entirely by the irmin-pack-concurrent-multi-reader
  performance unknown that the plan itself flags as its #1 residual risk (13 §8).* It's a perf-cliff
  page, not a data-loss page — recoverable, but loud, and it lands on the one empirical unknown
  (Spike S1) that no amount of type-system or language choice de-risks.
