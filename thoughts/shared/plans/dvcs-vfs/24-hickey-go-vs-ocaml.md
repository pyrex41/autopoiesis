---
date: 2026-06-25
reviewer: "Rich Hickey (persona)"
status: review
topic: "shen-go vs all-OCaml for a trunk-only content-addressable DVCS-VFS — a Datomic-lens review of complecting, values, and Datalog-vs-Prolog"
inputs:
  - thoughts/shared/plans/dvcs-vfs/07-direction-brief.md
  - thoughts/shared/plans/dvcs-vfs/13-plan-ocaml.md
  - thoughts/shared/plans/dvcs-vfs/15-plan-shen-go.md
  - thoughts/shared/plans/dvcs-vfs/21-synthesis-shen-backends.md
tags: [review, hickey, datomic, simple-made-easy, complecting, datalog, prolog, values, ocaml, shen-go]
---

# shen-go vs all-OCaml — a Datomic-lens review

I'm not here to re-litigate consistency (Aphyr did that), VCS porcelain (Torvalds), types
(Minsky), or shippability (Fukamachi). I'm here for one reason: **you are building a Datomic.**
A single serialized writer, immutable accretion, content-addressing, and a declarative query
language for the control plane. I built that and ran it in production. So I'll tell you what
these two plans get right and wrong about *that* architecture, and then I'll make the call my
own vocabulary forces me to make — **simple, not easy**.

A word up front, because precision is the whole game. **Simple** is objective: how many things
are braided together (complected). **Easy** is subjective: how near-at-hand, how familiar. You
can have a simple thing that is hard (unfamiliar), and an easy thing that is complex (familiar
and tangled). Most of this review is me refusing to let those two words be substituted for each
other.

---

## Verdict

**Build all-OCaml.** It is the *simpler* system by my own definition — fewer things braided
together that you will later have to un-braid — even though shen-go is in some respects the more
*beautiful* idea and is closer to my heart on homoiconic policy-as-data.

shen-go is two languages, two type stories, two runtimes-of-concern, and — fatally for its own
thesis — it complects its central correctness claim (real merge) with a borrowed body
(`go-git`) **that cannot do the thing the claim requires** (synthesis doc 21, §2: go-git v6 is
alpha, fast-forward merge only, no 3-way, no rename detection). The plan's simplicity argument
("reuse mature Go code, no FFI tax") is partly an *easy* argument wearing a *simple* costume.
The one place shen-go is genuinely simpler than OCaml — **policy-as-data, homoiconic, versioned
in the repo** — is real and I want it, but it does not require Shen, and it does not pay for the
complecting it drags in.

---

## What you got RIGHT about the Datomic architecture (both plans)

These are not small. Most teams reaching for "git but distributed" get these wrong, and both
plans get them right.

1. **The trunk/landed-log is genuinely value-oriented and accretion-only.** Content-addressed
   blobs/trees/commits, an append-only checksum-chained log, a monotonic `landed-seq`. That is
   Datomic's spine: novelty is *accreted*, never overwritten; the past is immutable; identity
   (the trunk ref) is a succession of values, not a mutated cell. Both `07`/`13` (Irmin commits
   on one branch) and `15` (go-git commits on `refs/heads/trunk` + LTX chain) get this. **The
   database is a value, and a commit-id is a basis-point you can hand around.** That is exactly
   right and it is the single best decision in the whole document set.

2. **Reads need no coordination.** Both designs serve reads off async replicas / content-hash
   caches with no involvement from the writer. That is the property that made Datomic's peer
   model work: because storage is immutable and content-addressed, *any* node can answer from a
   value without asking the transactor's permission. shen-go's "Go-side content-hash cache that
   bypasses Shen per byte" (`15 §1.3, §8 C3`) and OCaml's `blob_cache.ml` are both this insight.
   Right.

3. **The land-leader is a transactor.** One writer serializes all novelty. This is the correct
   shape for this problem at this scale, and both plans state it without apology. Good. The
   Raft-drop in `07` is the right call — Datomic's transactor is *also* a single writer; HA is a
   storage/failover concern, not a "let's make writes multi-master" concern. Resist the urge to
   "scale" the writer. You don't need to.

---

## What's WRONG or muddled about the transactor model

Here's where I get to use what I learned the hard way.

### Finding 1 — shen-go *splits the transactor*, which complects authority across two processes

**Complected:** the *act of landing* (one logical transaction) is braided across **two
independent authorities** — the `go-git` process that writes the commit object, and the
`superfly/litefs` daemon that owns the durable append and the lease. Two processes, two fsync
domains, two notions of "did it happen." (Synthesis 21 §3, §4 flagged this from the consistency
lens; I name it as a *simplicity* defect: the transactor is supposed to be **the one place**
where time advances. Splitting it means the question "what is the latest value of trunk?" has
two custodians who can disagree.)

**all-OCaml:** Irmin commit + landed-log append happen **in one serialized critical section,
against one store handle, in one process** (`13 §3.1`, P3/M4). One transactor, one
linearization point. That is the un-complected version. Datomic has exactly one transactor for
exactly this reason: time is a single thing; do not give it two clocks.

- Simpler option: **all-OCaml.** This is the cleanest Datomic-shaped difference between the two.

### Finding 2 — Both treat "the database as a value" well, but only shen-go *also* puts policy in that value

**Not complected (and this is the good kind):** `15 §7` stores the Prolog ACL rules as
`.shengo/policy.shen` *inside the trunk*, content-addressed like any file, landed through the
same queue, blame-able and time-travelable. **This is the most Datomic/Clojure thing in either
document** and shen-go does it more naturally than OCaml. Policy is *information*, a value in the
log, not a place (a side table, an etcd key, a config file on the leader's disk). I built
Datomic precisely so that your *schema and your rules* are data in the same immutable store as
your facts. shen-go nails this; OCaml's `13` does it too (`/.mvfs/acl/` in Irmin) but treats it
as plumbing rather than as the point.

**The honest tension:** this is the one axis where my heart pulls toward shen-go. Homoiconic
policy-as-data, versioned with the code it governs, is *information over place* in its purest
form, and it is *simple* — policy and history are the same kind of thing (values in the log),
not two kinds of thing in two places.

- Simpler-on-this-axis: **shen-go** (marginally; OCaml achieves the same with ACL-in-Irmin, just
  less idiomatically). But note: **this does not require Shen.** You can store a Datalog rule set
  as a data file in Irmin and get the identical property. The win is "policy is data in the log,"
  not "the host language is a Lisp." Don't let the genuinely-good idea smuggle in the language.

### Finding 3 — shen-go complects *language*, *runtime*, and *deployment* and calls it integration

**Complected:** shen-go is Shen *and* Go (`15 §12.6`: "two-language cognitive surface"). The
plan's defense is "no FFI, one heap, one GC, one binary" (`15 §1.1`). That defense is true and
also beside the point I care about. The absence of a *marshaling* boundary does not mean the
absence of *complecting*. You still have:

- two languages to know, two type systems (Shen's sequent checker *and* Go's),
- a Shen→KL→IR→Go *build pipeline* (`15 §12.4`) that is itself a thing that can break,
- a `gobody/` shim layer whose entire job is to keep Go's rich types *out* of Shen — i.e., a
  membrane you maintain forever to prevent the two halves from leaking into each other.

A membrane you must actively maintain to keep two things separate is the *signature* of two
things that are complected at the build/runtime level even when they share a heap. "One binary"
is an *easy* property (deployment familiarity). It is not a *simple* property.

**all-OCaml:** one language, one type system, one toolchain, store and logic co-resident
(`13 §0`). The merge type, the lease witness, the land FSM GADT, and the Irmin seam are all
*the same kind of thing in the same checker*. Minsky's value-correspondence point (synthesis 21
§3) is the type-theoretic version of my simplicity point: in shen-go the one value that matters
— the merged tree — crosses the Shen↔Go boundary **as an opaque hash both ways**, so Shen's
sequent checker is verifying a *story about* the body, not the body. That is complecting dressed
as a clean seam.

- Simpler option: **all-OCaml**, clearly.

### Finding 4 — shen-go's reused litefs daemon is a *second process*, i.e., place over information

**Complected:** the LiteFS daemon is a separate long-lived process that owns replication and the
lease (`15 §1.2`, the body diagram). Reusing it is presented as "real code, not a reimplemented
pattern" (`15 §0`). But from the transactor lens, you've now got the writer's authority living
*next to* a daemon whose async lease is **not** the fence you need (synthesis 21 §3, Aphyr's
"lease ≠ fence" Critical). The plan then has to *add back* a CAS fence in `gobody/ltxlog.go`
(`15 §4.2`) to repair the very thing it reused litefs to avoid building. That's the tell:
**when you have to re-implement the core invariant on top of the thing you reused, you didn't
actually reuse the thing — you reused its file format and inherited its process boundary.**

all-OCaml owns the append and the fence in-process (`13 §3.1`). Fewer moving places.

- Simpler option: **all-OCaml.**

---

## What to steal from Datomic

Independent of which plan you pick, these are the things I'd insist on, because I learned them
running this architecture:

1. **Separate the transactor from query and from storage — as three concerns, not three
   processes you can't reason about.** Datomic's transactor does *writes only*; peers do *queries
   only*, reading immutable storage with no coordination; storage is a dumb durable value store.
   Your land-leader = transactor. Your replicas/caches = peers. Your CAS = storage. Both plans
   approximate this; **all-OCaml keeps the transactor a single in-process authority, which is the
   version that actually matches Datomic.** Steal the *separation of roles*, but do not let the
   transactor itself become two processes (shen-go's defect, Finding 1).

2. **Reads take no locks, ever.** You both have this. Keep it sacred. The moment a read needs to
   ask the writer "is this current?", you've lost the property that makes immutable+CAS worth it.
   The RYW cookie (both plans) is the right shape — it's a *basis-point* ("serve me a value at
   least as new as seq N"), which is exactly Datomic's `(d/as-of db t)` / `(d/sync conn t)`. That
   is the right primitive. Name it as such.

3. **The database-as-a-value, passed by basis-point.** A `commit-id` (or `landed-seq`) *is* a
   database value you can hand to another process and get identical answers. Lean into this. It's
   your time-travel, your reproducible build input, your audit anchor. Both plans have the
   material; make the *value* (not the connection, not the "current state") the thing your API
   hands around.

4. **Accretion only; never update-in-place.** You have this. The danger is in the *derived
   index* (SQLite in both plans). Datomic keeps derived indexes as *rebuildable functions of the
   log*, never as independent authorities. Both plans say "SQLite is a rebuildable local cache,
   never replicated, never authoritative" (`13 §0.2`, `15 §8 C2`). **Hold that line absolutely.**
   The day someone writes to the index without going through the log, you've re-introduced
   place-oriented state and the whole value-orientation collapses. This is the most common way
   these systems rot.

5. **Schema/policy as data in the store.** This is Finding 2, and it's the one thing I'd steal
   *into* the OCaml plan *from* the shen-go plan: keep ACL/policy as a data value landed through
   the same queue (both already do — make it a first-class principle, not plumbing).

---

## The Datalog-vs-Prolog call

This is the question I have the most standing to answer, because I made exactly this call for
Datomic and I made it deliberately.

**I chose Datalog over full Prolog for Datomic's query language on purpose.** Datalog is:

- **terminating** (it always halts — no infinite resolution),
- **set-oriented / declarative-of-results** (you describe *what*, order doesn't change meaning),
- **side-effect-free**,
- and crucially, **a sub-language whose power is matched to the problem** (querying facts,
  recursive rules) rather than a general-purpose logic programming engine.

Full Prolog gives you: clause ordering that matters, cut, potential non-termination, and the
ability to encode arbitrary computation. That is *more power than a control plane needs*, and
more power is not free — it's more ways for a policy author to write something that loops, that
depends on clause order, that does something surprising under negation.

shen-go uses **Shen's full Prolog** for ACLs/admission/conflict-class (`15 §3.5`). Look at what
the policy actually *is*: `member(Subject, Group)`, `grant(Subject, Action, Prefix, Effect)`,
longest-prefix-deny-wins resolution. **That is Datalog.** It is bounded, set-oriented, recursive
over a finite EDB, terminating. It does not need cut, does not need clause-order semantics, does
not need Turing-completeness. The plan even admits the type-checker side of Shen is
Turing-complete and "can loop" (`15 §12.4`) — that is the *exact* failure mode I removed from
Datomic by not shipping full Prolog.

**So my call: full Prolog is the wrong tool here, for the same reason I rejected it for
Datomic.** The ACL/admission problem is a Datalog problem. A few hundred lines of OCaml
predicates (`13 §0.9`, `acl/predicates.ml`) — longest-prefix, deny-wins — is *also* a perfectly
honest realization of that same bounded Datalog, with the bonus that it can't loop and a junior
engineer can read it.

**Does this tilt the decision? Yes, against shen-go's headline.** shen-go's marquee feature is
"homoiconic Prolog policy-as-data." But the *policy* part (data in the log) is the good idea, and
the *Prolog* part is over-powered for the problem. You can keep the good idea — declarative,
versioned, homoiconic policy — with a **Datalog** rule set stored as a data value, in *either*
language. Shen's full Prolog is solving a problem you don't have while exposing you to
non-termination you don't want. That's incidental complexity in its purest form.

> If you want the declarative-policy idea done right: ship a small, terminating **Datalog**
> evaluator over path-prefix grants, store the rules as data in the trunk. That's the Datomic
> move. It needs neither Shen nor full Prolog.

---

## shen-go or all-OCaml — which is simpler (not easier), and which I'd build

Let me tally strictly on *complecting* (objective), not familiarity (subjective):

| Axis | shen-go | all-OCaml | Simpler |
|---|---|---|---|
| Number of languages braided | 2 (Shen + Go) | 1 | OCaml |
| Number of type systems | 2 (sequent + Go's) | 1 | OCaml |
| Transactor authority | split (go-git + litefs daemon) | single in-process | OCaml |
| Build pipeline | Shen→KL→IR→Go + Go | dune | OCaml |
| Membrane to maintain | `gobody/` shim, forever | none (one language) | OCaml |
| Replication authority | reused litefs daemon (2nd process) + re-added fence | owned in-process | OCaml |
| Policy-as-data in the log | yes, idiomatic | yes, as plumbing | shen-go (marginal) |
| Merge correctness vs claim | **claim is false** (go-git can't 3-way) | hand-rolled diff3, honestly scoped | OCaml |
| Control-plane logic power | full Prolog (over-powered, can loop) | bounded predicates (= Datalog) | OCaml |

shen-go wins **one** axis (idiomatic policy-as-data), and that axis is achievable in OCaml and
does not require Shen. It loses every other *simplicity* axis. Its remaining appeal is **easy**,
not simple: "one static binary," "no FFI marshaling," "reuse mature code" — these are
familiarity/at-hand arguments, and one of them ("reuse mature merge code") is *factually broken*
(synthesis 21 §2). When the easy argument is also partly false, there's nothing left to weigh
against the simplicity deficit.

**all-OCaml is the simpler system.** One language, one type system, one transactor, one process
that owns time, one toolchain, no membrane. Its honest weaknesses — hand-rolled diff3, the
Lwt/Eio question, irmin-pack-under-a-mount — are all **contained, single-language, measurable
unknowns** (the `07/13` plans gate them with spikes). They are *hard* (unfamiliar, empirical),
not *complex* (braided). I'll take hard-and-simple over easy-and-complex every time; that's the
entire thesis of Simple Made Easy.

**Which I'd build: all-OCaml.** And I'd steal exactly one thing from the shen-go plan into it —
make **policy a Datalog data-value landed through the same queue** a first-class, named principle,
not plumbing — because *that* idea (information over place, schema-as-data, the Datomic move) is
the genuinely good one shen-go surfaced, and it deserves to survive the language it arrived in.

---

### One-line simple-vs-easy judgment

shen-go is *easier to feel good about* (one binary, "reuse mature code," a homoiconic brain) but
*more complex* (two languages, a split transactor, a reused daemon, and a merge claim that isn't
true); **all-OCaml is the simpler system — fewer things complected — and simple is what survives
contact with year three.**
