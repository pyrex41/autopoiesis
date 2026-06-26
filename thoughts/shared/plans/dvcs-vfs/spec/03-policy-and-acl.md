---
date: 2026-06-26
researcher: Claude
topic: "mvfs — policy & ACL control plane: decidable Datalog on soa32, policy-as-data, the acl-version fence"
status: design
layer: spec
builds_on: spec/00-overview.md
tags: [design, spec, acl, datalog, soa32, policy-as-data, fencing, I6]
last_updated: 2026-06-26
---

# mvfs — Policy & ACL Control Plane (`03`)

> Builds on the keystone `spec/00-overview.md`. This doc refines, and must not contradict, the
> keystone's invariants (esp. **I6** ACL soundness, **I9** authorization-on-every-byte-path) and the
> §5 cross-document contracts (landed-entry §5.1, `as-of` basis §5.2, the Shen↔shell boundary §5.4).
> It specifies the ACL model, the concrete Datalog rules, how they evaluate on shen-lua's native
> **soa32** substrate, the policy-as-data lifecycle, the **acl-version fence**, decision caching, the
> decidable proof obligations, and the enforcement points.

---

## 0. Thesis (one paragraph)

Authorization in mvfs is **decidable Datalog over policy-as-data**. The policy ruleset is not a config
file on a leader's disk; it is a sequence of **policy entries committed to the landed-log** (keystone
§5.1), versioned by log `seq` (`acl-version`), inspectable and time-travelable like any other value in
the trunk. Resolution of a single decision — "may principal P read path X?" — is **longest-prefix
match with explicit-deny-wins**, which is (per Norvig `../23`) a **lookup + comparator, not a
backtracking search**. We express the rules as Datalog because Datalog is **terminating, set-oriented,
side-effect-free** (per Hickey `../24`): it gives us the homoiconic policy-as-data win *and* the
guarantee that policy analysis halts. The rules compile to shen-lua's native **soa32** inference
substrate — terms as range-tagged `int32`s in FFI arrays, tag tests as `<` comparisons — so ACL
evaluation is allocation-light and JIT-friendly on the read hot path (the substrate is already measured
at **8.9× / −93% alloc** vs the legacy engine, `../32`). Because Datalog is decidable, we can
**exhaustively check policy properties at build/land time** (reachability, rule conflict, unowned
paths, access-widening deltas). And because authorization is fenced on `acl-version` at the
linearization point (**I6**), there is **no stale-allow**: not in a land, not in a read, not in the
decision cache.

---

## 1. The ACL model

### 1.1 Shape

Path-scoped, hierarchical, with three actors and three actions.

- **Principals** — identities that act: users and service accounts. A principal is named by an
  interned id (`intern-id` style; the substrate already does name↔id interning).
- **Groups** — named sets of principals. **Membership is one hop, flat** (per Norvig `../23`: this is
  not a transitive-closure problem; a group does not contain a group in the base model — see §1.4 for
  the bounded recursion option). `member-of(P, G)`.
- **Grants/denies** — a rule `(subject, action, path-prefix, effect)`, where `subject` is a principal
  or a group, `effect ∈ {allow, deny}`. A grant on `src/team/` **inherits down the subtree**: it
  applies to `src/team/`, `src/team/a.lua`, `src/team/sub/b.lua`, etc.

Actions (totally ordered by privilege, each implying the lesser for *resolution scoping* but **not**
for grants — a grant names exactly one action):

| Action  | Governs |
|---------|---------|
| `read`  | VFS visibility: every `LOOKUP`/`READ`/resolve. Denied ⇒ the path is **invisible** (§8). |
| `write` | The write path: **submit** (admission) and **land** (apply). A land touching path X needs `write` on X. |
| `admin` | Authoring policy: who may land a **policy entry** that grants/denies on a prefix. Scoped to a prefix (delegated administration). |

### 1.2 Resolution = longest-prefix match, explicit-deny-wins

The decision for `(P, action, path)` is a **total function**, computed as:

```
candidates = { rule | rule.action = action
                    ∧ (rule.subject = P  ∨  member-of(P, rule.subject))
                    ∧ prefix-of(rule.path-prefix, path) }       ; rule applies to this path

if candidates = ∅                       -> DENY      (default-deny / fail-closed)
let Lmax = max { len(r.path-prefix) | r ∈ candidates }          ; longest-prefix
let winners = { r ∈ candidates | len(r.path-prefix) = Lmax }
if ∃ r ∈ winners . r.effect = deny      -> DENY      (explicit-deny-wins at the winning depth)
else                                    -> ALLOW
```

Two rules to internalize (both straight from Norvig `../23`, Finding 2):

1. **This is a `filter` + `maximum` + `any`** — a comparator over a finite candidate set, not a
   search. There is no clause-ordering semantics, no cut, no backtracking that can change the answer.
2. **Deny-wins is resolved at the winning depth.** A broad `allow` on `src/` does **not** override a
   specific `deny` on `src/secret/` (the deny is longer-prefix, so it wins outright). A `deny` on
   `src/` and an `allow` on `src/secret/` ⇒ ALLOW for `src/secret/...` (the allow is more specific).
   A tie at the same depth (one `allow`, one `deny` on the *same* prefix, e.g. group-allow +
   principal-deny) ⇒ **DENY** (deny-wins on ties). This is the only place "wins" needs a tie-break,
   and it is a `∃ deny` test, not a search.

### 1.3 Datalog, not full Prolog

We use **Datalog** (terminating, decidable), **not** full Prolog. The distinction is load-bearing and
is the explicit guidance of both Hickey (`../24`) and Norvig (`../23`):

- **No cut, no clause-order semantics, no negation-as-failure that can diverge.** Negation is
  *stratified* (the only negated predicate, `acl-deny-more-specific`, is computed over a lower stratum
  and never recurses through negation — see §2.6).
- **Finite EDB.** The extensional database is the set of grant/deny/member facts from the committed
  policy entries; it is finite and known at evaluation time.
- **Bounded recursion only.** The lone recursive predicate (`prefix-of`, and optionally group-of-group
  in §1.4) recurses over **path depth** / a **bounded membership depth**, both finite. Every rule
  **terminates** by construction.
- **The resolution comparator (longest-prefix/deny-wins) is a total function layered on top of the
  Datalog `candidates` set** — exactly as Norvig prescribes: Datalog produces *the candidate facts*,
  the comparator produces *the decision*. We do not ask Prolog to "find the decision" via findall +
  search; we ask Datalog for the applicable facts and fold them deterministically. This is why the
  decision is provably correct by inspection and why it cannot loop.

### 1.4 Optional bounded group-of-group (kept off the hot path)

The base model is one-hop membership. If org structure later needs nested groups (team-of-teams), we
admit a **depth-bounded** transitive `member-of`:

```
member-of(P, G)  :- direct-member(P, G).
member-of(P, G)  :- direct-member(P, H), group-in-group(H, G), depth-lt(H, G).   ; bounded
```

`depth-lt` enforces a fixed max nesting depth (a config constant, e.g. 8), preserving termination and
keeping the closure finite. This stays **Datalog** (still terminating). Per Norvig's steelman
(`../23`, Finding 2), nested membership is the *one* place a closure is real — and even here it is
bounded, computed off the read hot path (materialized into the EDB at policy-land time, see §3.4), and
never a search. The hot read path always sees a **flattened** membership relation.

---

## 2. The Datalog rules (concretely)

These are the actual rules. `P` = principal, `G`/`S` = subject (group or principal), `Path`/`Pre` =
path, `Paths` = a sorted pathset (a landed change's `paths-touched`, keystone §5.1). EDB predicates
(facts from policy entries): `grant/4`, `direct-member/2`, `group-in-group/2`. IDB predicates (derived)
are everything else.

### 2.1 `prefix-of` (the path-hierarchy spine)

A path-prefix `Pre` covers `Path` iff `Pre` is `Path` or an ancestor directory. Paths are normalized
(trailing `/` on directory prefixes; `""`/`/` is the repo root prefix, covering everything).

```
prefix-of(Pre, Path) :- Pre = Path.
prefix-of(Pre, Path) :- is-dir-prefix(Pre), starts-with(Path, Pre).
```

`starts-with` is a primitive on the soa32 string representation (interned path-component vectors —
§3.2); recursion is bounded by `Path`'s component count. Terminates.

### 2.2 `member-of` (one hop; bounded recursion optional)

```
member-of(P, G) :- direct-member(P, G).
; + the bounded transitive clause from §1.4 if nested groups are enabled
```

### 2.3 `applies` (which grants govern a (subject, action, path))

```
applies(P, Action, Pre, Effect) :-
    grant(S, Action, Pre, Effect),
    ( S = P  ;  member-of(P, S) ),
    prefix-of(Pre, _Path).        ; bound to the queried Path at call site
```

In practice `applies` is parameterized by the concrete `Path` under decision; the engine specializes it
(see §3.3 partial-eval-to-trie). The set `{ (Pre, Effect) | applies(P, Action, Pre, Effect) }` for a
fixed `Path` is exactly the `candidates` set of §1.2.

### 2.4 `acl-deny-more-specific` (the deny-wins witness — stratified negation)

We need a predicate that holds when, at the winning (longest) depth for `(P, Action, Path)`, an
explicit deny exists. Computed as: there is an applicable `deny` rule whose prefix is at least as long
as every applicable rule's prefix.

```
; the depth of the most-specific applicable rule
max-applies-len(P, Action, Path, L) :-
    applies-at(P, Action, Path, Pre, _),
    L = len(Pre),
    not exists-longer(P, Action, Path, L).        ; stratified negation over a lower stratum

exists-longer(P, Action, Path, L) :-
    applies-at(P, Action, Path, Pre2, _), len(Pre2) > L.

acl-deny-more-specific(P, Action, Path) :-
    max-applies-len(P, Action, Path, L),
    applies-at(P, Action, Path, Pre, deny),
    len(Pre) = L.
```

(`applies-at` is `applies` with the `Path` bound.) The negation is **stratified**: `exists-longer` sits
in a strictly lower stratum than `max-applies-len`, and nothing recurses *through* the `not`. This is
the standard, decidable, terminating Datalog-with-stratified-negation. It encodes the §1.2 comparator
declaratively; the runtime evaluates it as the fold described in §3.3 (it does not actually search).

### 2.5 `can-read` (the read-tier predicate; I9 / §8)

```
can-read(P, Path) :-
    applies-at(P, read, Path, _, allow),          ; at least one applicable allow
    not acl-deny-more-specific(P, read, Path).     ; and no winning-depth deny
; default: if no applicable allow at all, can-read is simply not derivable -> DENY (fail-closed)
```

### 2.6 `can-submit` / `can-land` (the write-tier predicates)

A change touches a **pathset** (sorted `paths-touched`). Authorization is **all-paths-must-pass**:

```
can-write-path(P, Path) :-
    applies-at(P, write, Path, _, allow),
    not acl-deny-more-specific(P, write, Path).

; can-submit / can-land hold iff every touched path is writable.
can-submit(P, Paths) :- not some-path-unwritable(P, Paths).
can-land(P, Paths)   :- not some-path-unwritable(P, Paths).

some-path-unwritable(P, Paths) :-
    member(Path, Paths), not can-write-path(P, Path).
```

`can-submit` and `can-land` are the **same predicate** over the same `write` action — the names mark
the two enforcement points (admission vs apply, §8). The fence (§5) is what makes them differ
operationally: `can-submit` is evaluated at submit-time `acl-version`; `can-land` is **re-evaluated**
at apply against the RSM's current ruleset. A change that was submittable can still be rejected at land
if policy tightened in between — that is I6 working as designed, not a bug.

### 2.7 `can-admin` (who may land policy)

A **policy entry** that touches grants on prefix `Pre` requires `admin` on `Pre`:

```
can-admin(P, Pre) :-
    applies-at(P, admin, Pre, _, allow),
    not acl-deny-more-specific(P, admin, Pre).

; a policy land is authorized iff the author has admin over every prefix the delta touches
can-land-policy(P, Deltas) :-
    not some-prefix-unadminned(P, Deltas).
some-prefix-unadminned(P, Deltas) :-
    member(d(_S,_A,Pre,_E), Deltas), not can-admin(P, Pre).
```

This gives **delegated administration**: an `admin` grant on `src/team/` lets a team lead author policy
for their subtree without root authority. Policy changes go through the **same fenced land path** as
code (§4), gated by `can-land-policy`.

### 2.8 `conflict-class` (policy on top of the structural git-merge check)

The land kernel (`02`) uses **git's 3-way merge** to detect *textual/structural* conflicts. `conflict-class`
is **policy layered on top of that**: it declares, as data, pathset pairs that must **serialize** even
when git reports no textual conflict (e.g. a generated-code dir and its generator; a lockfile and its
manifest; an interface and its mandated co-update), or pathset pairs that **never** conflict (an
explicit override to *allow* concurrent landing where git would be over-cautious but policy knows it is
safe — used sparingly).

EDB facts (from policy entries):

```
must-serialize(PreA, PreB).     ; declared: touching both classes must land in series
never-conflicts(PreA, PreB).    ; declared: explicitly independent, policy override
```

Derived relation over two concrete pathsets (e.g. an in-flight landed change `A` vs a candidate `B`):

```
; structural conflict comes from git (an oracle fact asserted by the merge step, see §5.4 keystone)
git-conflict(PathsA, PathsB) :- member(X, PathsA), member(X, PathsB).   ; same path = structural overlap
                                                                        ; (real 3-way result asserted by git oracle)

policy-conflict(PathsA, PathsB) :-
    must-serialize(PreA, PreB),
    pathset-touches(PathsA, PreA), pathset-touches(PathsB, PreB).
policy-conflict(PathsA, PathsB) :-                 ; symmetric
    must-serialize(PreA, PreB),
    pathset-touches(PathsA, PreB), pathset-touches(PathsB, PreA).

pathset-touches(Paths, Pre) :- member(Path, Paths), prefix-of(Pre, Path).

; the kernel's eligibility question: may A and B land concurrently / out of order?
conflict-class(PathsA, PathsB) :-
    git-conflict(PathsA, PathsB),
    not policy-override-clears(PathsA, PathsB).
conflict-class(PathsA, PathsB) :-
    policy-conflict(PathsA, PathsB).

policy-override-clears(PathsA, PathsB) :-          ; never-conflicts can clear a *structural* flag
    never-conflicts(PreA, PreB),
    pathset-touches(PathsA, PreA), pathset-touches(PathsB, PreB).
```

`conflict-class(A, B)` derivable ⇒ **A and B must serialize** (the land FSM in `02` must not land them
concurrently / must re-base B on A). Not derivable ⇒ independent. This is decidable Datalog over finite
pathsets and a finite policy EDB; it **terminates**. Note the careful scoping: `never-conflicts` can
only clear a *structural git overlap that policy asserts is safe* — it can **never** clear a
`policy-conflict`, and (critically) **never** weakens an ACL decision. Conflict-class governs ordering,
not authorization.

---

## 3. Running on the soa32 engine

### 3.1 Why soa32 (the substrate)

shen-lua's Datalog/inference engine is the native **soa32** substrate (`../32`): terms are plain Lua
numbers, **range-tagged over `int32` FFI arrays**, with tag tests done by `<` comparisons (no bit ops,
no 64-bit cdata, no boxing). This is the engine the ACL runs on, and it is already measured at
**8.9× faster, −93% allocation per inference** vs the legacy engine. Because the read hot path
(every `LOOKUP`/`READ` → `can-read`) is the most latency-sensitive surface in the system, the ACL
*must* run allocation-light and JIT-friendly — soa32 is precisely that.

### 3.2 Term/EDB representation

Everything the ACL touches is interned to an `int32` and stored in flat FFI arrays — a
**structure-of-arrays**, not an array-of-structs:

- **Principals, groups, path components** → interned ids (`int32`). Path interning reuses the
  substrate's name↔id machinery; a path is a small `int32` vector of component ids.
- **Range-tagging**: the `int32` id space is partitioned into contiguous ranges by kind
  (`[0, P_max)` = principals, `[P_max, G_max)` = groups, `[G_max, …)` = path-components, …). A "type
  test" is then a single `<`/range comparison on the int — no tagged box, no metatable dispatch. This
  is exactly the soa32 design point (`../32`: "`<` comparisons for tag tests").
- **`grant/4` EDB** → four parallel `int32` arrays (`subj[]`, `act[]`, `prefix_id[]`, `effect[]`),
  indexed by rule number. `effect` is `0`/`1` (allow/deny) — a branch-free fold can test it.
- **`direct-member/2`** → two parallel `int32` arrays, plus a sorted index for `member-of(P, _)`
  lookup.

### 3.3 Evaluation sketch (the hot read path)

`can-read(P, Path)` evaluates as a tight scan/fold over the soa32 arrays — **not** a backtracking
search (this is the whole Norvig point made operational):

```lua
-- pseudocode over soa32 int32 arrays; one decision, allocation-free
function can_read(P, path_ids)            -- P:int32, path_ids: int32[] (interned components)
  local best_len = -1
  local best_deny = false
  local groups = member_index[P]          -- precomputed flattened set (int32 range), §3.4
  for i = 0, n_read_rules - 1 do          -- iterate read-action grant slice (range-tagged contiguous)
    local s = subj[i]
    if s == P or in_set(groups, s) then   -- in_set = range/bitset test, branch-light
      local pre = prefix_id[i]
      if prefix_covers(pre, path_ids) then            -- starts-with on int32 component vectors
        local L = prefix_len[pre]
        if L > best_len then
          best_len = L; best_deny = (effect[i] == DENY)
        elseif L == best_len and effect[i] == DENY then
          best_deny = true                            -- deny-wins on tie
        end
      end
    end
  end
  if best_len < 0 then return false end   -- no applicable allow -> fail-closed DENY
  return not best_deny                     -- ALLOW iff winning depth has no deny
end
```

Properties:

- **Allocation-light**: no cons cells, no tagged boxes, no intermediate candidate list — the
  comparator (`best_len`, `best_deny`) is two locals folded in a single pass. This is what the
  −93%-alloc result buys on the per-decision path.
- **JIT-friendly**: a monomorphic loop over FFI `int32` arrays with `<`/`==` tests is a clean LuaJIT
  trace (no NYIs, no megamorphic dispatch — the trace-killers `../32` documents the substrate
  avoiding).
- **Terminating by construction**: bounded by `n_read_rules` × `path` depth. No search frontier.

The grant array is **range-partitioned by action** (`read` rules contiguous, then `write`, then
`admin`), so `can-read` scans only the `read` slice — a contiguous sub-range, cache-friendly, selected
by two `<` bounds.

### 3.4 Partial-eval to a trie (per agentzh)

For the matcher, the optional optimization is **partial evaluation of the prefix rules into a trie**,
per agentzh's guidance (a **trie lookup, not branchy generated code**). At policy-land time we
specialize the grant EDB for a fixed `(P or group)` view into a path-component trie keyed by interned
component ids; each trie node carries the `(best_len, deny?)` decision for the principal-set that
reaches it. A `can-read` then becomes: **walk the trie by path component, read the decision at the
deepest matched node** — O(path-depth) array indexing, no per-rule scan. The trie is itself a flat
soa32 structure (node arrays of `int32` child pointers + decision tags), keyed off `acl-version`, and
is a *rebuildable derived index* of the policy EDB (never authoritative — same discipline as the SQLite
index in `02`/`13`). The flattened `member-index[P]` (§3.3) is built in the same materialization pass,
absorbing the bounded group-of-group closure (§1.4) **off the hot path**.

---

## 4. Policy-as-data, landed through the queue

### 4.1 Policy is a distinguished landed-entry

Per keystone §5.1: a **policy entry** is a `landed-entry` whose payload is a **Datalog ruleset delta**
(adds/removes of `grant/4`, `direct-member/2`, `group-in-group/2`, `must-serialize/2`,
`never-conflicts/2` facts). It is content-addressed, checksum-chained, and fenced **exactly like a code
land** — same `seq`, same `fence`, same `prev/post-checksum` chain. There is no side table, no etcd
key, no leader-local config file (this is Hickey's "information over place," `../24` Finding 2, made
normative).

```
policy-delta := {
  kind        : :policy
  ruleset-ops : sorted[ op ]        ; op := (:add|:del, fact)
  fact        : grant(S,Act,Pre,Eff) | direct-member(P,G) | group-in-group(H,G)
              | must-serialize(A,B)  | never-conflicts(A,B)
  author      : principal           ; must satisfy can-land-policy (§2.7) at apply
}
```

`acl-version := the seq of the most recent committed policy entry` (keystone §5.1). The **effective
ruleset at any seq** is the fold of all policy deltas with `seq ≤ that seq` — a pure function of the log
prefix. This makes policy **inspectable** (`git`-blame a grant to the land that introduced it),
**versioned** (`acl-version` names a ruleset value), **time-travelable** (evaluate ACLs as-of any past
`acl-version`), and **self-describing** (the rules are data in the same store as the code they govern).

### 4.2 Policy changes go through the same fenced land path

A policy land is submitted, admitted (gated by `can-land-policy`, §2.7), and applied through the **same
land FSM and fencing protocol** as code (`02`). Consequences:

- Policy edits are serialized in total land order (I1/I2) — no two conflicting policy deltas race.
- A policy land is durable-before-ack at the stated width (I4) before it can affect any decision.
- Policy is replicated to read replicas via the **same** landed-log stream — replicas learn the new
  `acl-version` exactly when they apply the policy entry. No separate policy-distribution channel
  (which would be a second authority / a place — exactly what we refuse).

---

## 5. The acl-version fence (I6 — Aphyr's stale-allow fix)

> **I6 (keystone):** a land/read is authorized against the **acl-version current at its linearization
> point**; no stale-allow.

The hazard: principal P is authorized under ruleset v=10, then a policy land at v=11 **revokes** P's
write on `src/secret/`. A naive system that authorized P at submit-time and applied later would let a
**stale-allow** slip through — P's change lands under the old ruleset after the revocation. I6 forbids
this. The fence:

### 5.1 What each operation carries

- **A land** carries the `acl-version` it was **authorized against** at submit/admission time
  (recorded in the landed-entry's `acl-version` field, §5.1).
- **A read** carries its `as-of := (seq, acl-version)` basis (keystone §5.2). ACLs are evaluated at
  exactly that `acl-version`.

### 5.2 Apply re-checks against the current RSM ruleset

At **apply** (inside the serialized land critical section, after `seq` is assigned), the leader
re-evaluates `can-land(author, paths)` (and `can-land-policy` for policy entries) against the
**RSM's current effective ruleset** — i.e. the ruleset at the latest applied `acl-version`, which is the
linearization point of *this* land. This is the linearization point per I6.

```
; in the land FSM apply step (02), serialized, fenced (I7)
apply(entry):
    assert holds-fence(entry.fence)                          ; I7: only the leased leader, fresh token
    cur := current-acl-version(RSM)                          ; latest applied policy seq
    ruleset := effective-ruleset(RSM, cur)                   ; pure fold of log prefix
    ; pure Datalog, side-effect-free, decidable -> ALLOWED inside apply
    if not can-land(ruleset, entry.author, entry.paths-touched):
        reject(entry, :stale-or-revoked-authorization)       ; the change submitted under v_old is
                                                             ; rejected because policy changed under it
    if entry.kind = :policy and not can-land-policy(ruleset, entry.author, entry.ruleset-ops):
        reject(entry, :policy-admin-denied)
    ; entry.acl-version (what it was authorized against) is recorded for audit/divergence detection
    commit(entry with acl-version := cur)
```

**Why pure Datalog is allowed in apply.** Apply must be deterministic, side-effect-free, and clock-free
(keystone §5.1 `ts` note; I2 requires all replicas to apply identically). Datalog evaluation is
**decidable, terminating, and side-effect-free** — it is a *pure function of (ruleset, author, paths)*.
Therefore re-checking authorization in apply is safe: every replica, folding the same log prefix to the
same `ruleset`, computes the same decision. This is the precise reason we insisted on Datalog (not
Prolog): Prolog's potential non-termination / clause-order sensitivity would make apply
non-deterministic and unsafe; Datalog's decidability makes apply re-check **sound**.

### 5.3 No stale-allow — the three closures

1. **Land:** authorized at submit under `v_old`, **re-checked at apply** under `v_cur`. If policy
   tightened (`v_cur` revoked the grant), the land is **rejected**. The recorded `entry.acl-version`
   lets audit detect that it was authorized under an older version and confirm the re-check ran.
2. **Read:** a read's `as-of.acl-version` pins the ruleset; a serving node MUST evaluate at that
   version or refuse/redirect (keystone §5.2). A read cannot be answered under a *newer-but-not-yet-the-client's*
   or a *stale* ruleset that would allow what the pinned version denies.
3. **Cache:** the decision cache key **includes `acl-version`** (§6) — a stale ruleset's allow can
   never be served from cache after a policy bump.

---

## 6. Decision caching & invalidation (read tier)

The read tier caches ACL decisions to keep `can-read` off the per-byte critical path where possible.

### 6.1 Cache key (acl-version is mandatory)

```
cache-key   := (principal, path-prefix, acl-version)
cache-value := allow | deny           ; the resolved §1.2 decision for that prefix
```

The key **MUST** include `acl-version`. This is the cache-layer enforcement of I6: a cached `allow`
computed under `v=10` is keyed `(P, src/team/, 10)`; after a revoking policy land bumps `acl-version`
to `11`, the live read carries `as-of.acl-version = 11`, the key `(P, src/team/, 11)` **misses**, and
the decision is recomputed under the new ruleset. **No stale-allow at the cache layer.** Omitting
`acl-version` from the key would reintroduce exactly the stale-allow I6 forbids.

### 6.2 Invalidation = acl-version bump

Invalidation is **implicit and total**: a policy land bumps `acl-version`, so *every* cache entry keyed
on the old version is instantly unreachable (a key miss), without any explicit purge. Old entries age
out by LRU. This is the mlcache pattern (keystone diagram: L1 lrucache + L2 shared/disk): immutable
keys, version-bumped invalidation — the same discipline that makes content-addressed blob caching safe.
Caching at `path-prefix` granularity (the resolved decision node, ideally the soa32 trie node of §3.4)
amortizes across all paths under a prefix.

### 6.3 What is NOT cached

The **apply-time re-check** (§5.2) is **never** served from a read-tier cache — it runs fresh against
the RSM ruleset inside the land critical section. The cache is a read-path optimization only; the land
authority always recomputes.

---

## 7. Provability / proof obligations

Because the policy language is **decidable Datalog over a finite EDB**, the effective ruleset at any
`acl-version` is a finite structure we can **exhaustively analyze at build/land time** — *before* a
policy delta is committed. Each obligation is a query that **terminates**:

### 7.1 Reachability — "can principal X ever reach path Y?"

```
?- can-read(x, y).          ; decidable: ground query, terminates -> {true|false}
?- can-write-path(x, y).
```

Exhaustive variant (all paths a principal can reach, materialized over the finite path/prefix set in
the trunk tree at a given `seq`):

```
?- can-read(x, Path).       ; enumerates the finite set of reachable paths (bounded by tree size)
```

### 7.2 Rule conflict — "do two rules conflict / is a grant dead?"

A rule is **shadowed/dead** if no `(principal, path)` makes it the winning rule (e.g. an `allow` always
dominated by a longer `deny`). Decidable because the candidate space per path is finite:

```
?- shadowed(grant(S, Act, Pre, allow)).    ; true iff ∀ Path covered by Pre,
                                            ;   acl-deny-more-specific(_, Act, Path) at >= len(Pre)
```

Conflicting deny/allow at the *same prefix and subject* (a contradictory pair) is a direct EDB scan:

```
?- grant(S, Act, Pre, allow), grant(S, Act, Pre, deny).   ; flag at land-time as authoring error
```

### 7.3 Unowned path — "is there a path with no owner?"

A path is **unowned** for `admin` (no principal can author policy for it) — usually a misconfiguration:

```
unowned(Path) :- in-tree(Path), not exists-admin(Path).
exists-admin(Path) :- can-admin(P, Pre), prefix-of(Pre, Path).
?- unowned(Path).           ; enumerates unowned paths over the finite tree
```

### 7.4 Access-widening delta — "does this policy delta widen access unexpectedly?"

The most important land-time gate. Given the current ruleset `R` and a proposed delta producing `R'`,
compute the **difference of the decision relations**. Because both are finite and decidable, the diff
is computable:

```
widened(P, Path) :- can-read'(P, Path), not can-read(P, Path).     ; allowed under R' but not under R
?- widened(P, Path).        ; enumerates every (principal, path) the delta newly grants

; symmetric for writes / admin; surfaced in the policy-land review/diff UX (06)
```

A policy land can be **required to declare** its intended widening; the gate rejects (or flags for
elevated review) any `widened(P, Path)` not in the declared set — catching accidental access expansion
before it lands. This is only possible because Datalog is decidable; with full Prolog the diff could
fail to terminate.

### 7.5 The partial-eval-to-trie note

Per agentzh (§3.4): the matcher can be partially evaluated into a **trie lookup**, not branchy
generated code. The same partial evaluation that produces the fast runtime trie also produces the
**finite object** these proof queries analyze — the trie *is* the materialized decision relation, so
"reachability" and "widening" become trie-walks/diffs over a bounded structure. Provability and the hot
path share one representation.

### 7.6 The strongest claim — and its precise limits

**What is provable (and the strongest honest claim):**

> For any fixed `acl-version`, mvfs can **exhaustively and terminatingly decide** the full
> authorization relation `can-read` / `can-write-path` / `can-admin` over the finite set of
> (principal, path) pairs, and therefore can **exhaustively** answer reachability, detect rule
> conflicts/shadowing, find unowned paths, and compute the **exact set** of (principal, path) pairs a
> proposed policy delta would newly allow or deny — *all at build/land time, with a guarantee the
> analysis halts*. This is a property of the **policy model**, guaranteed by Datalog's decidability;
> it does not depend on tests or runtime sampling.

**What is NOT provable by the Datalog model (be precise):**

- It does **not** prove the *implementation* matches the model — the soa32 evaluator, the trie
  partial-eval, and the caching layer are conformance-tested (differentially, against the rules as
  executable spec, keystone §2), **not** proven. (Datalog gives a checkable *specification*, not a
  verified compiler.)
- It does **not** prove anything about the **trusted shell** (keystone §5.4): `git`'s merge,
  HMAC serve-token minting/nginx enforcement (I9, doc `04`/`05`), the OS, LuaJIT. Those are oracles we
  trust, not prove. In particular, **byte-path** authorization soundness (I9) is a property of the
  serve-token protocol in `04`, *not* of this Datalog model — this doc proves *who may read a path*,
  doc `04` proves *no bytes flow without a fresh authorized token*.
- It does **not** prove **liveness or timing** — only the logical decision. Latency/cache-hit
  guarantees are empirical (`05`).
- Reachability/widening are exhaustive **over the finite path/prefix universe at a given `seq`**; they
  do not quantify over hypothetical future paths not yet in the tree (though prefix-level grants do
  cover future descendants, and the widening check correctly accounts for prefix coverage).

In short: **the model is decidably analyzable; the mechanism is trusted, not verified.** That boundary
is the keystone's "proven brain, trusted shell" (§2) applied to authorization.

---

## 8. Enforcement points

Authorization is enforced at exactly two surfaces, and **audited on every decision**.

### 8.1 Read (VFS) — every LOOKUP/READ → `can-read`; denied = invisible

- Every VFS `LOOKUP`, `READDIR`, `READ`, and every resolve step (`(commit, path) → hash`, keystone
  diagram `DEC`) is gated by `can-read(P, path)` at the read's `as-of.acl-version`.
- **Denied ⇒ invisible.** A denied path does **not** return `EACCES`; it is omitted from `READDIR` and
  `LOOKUP` returns "no such entry." Denial leaks no existence information (no probing for the presence
  of `src/secret/`). This is stronger than a permission error and is the VFS-correct behavior.
- `can-read` runs on the soa32 hot path (§3.3), behind the decision cache (§6). A successful decision is
  what authorizes minting the **serve-token** (keystone §5.3) — the byte path itself is gated by I9 in
  `04`/`05`; this doc gates *whether the resolve/token-mint is allowed at all*.

### 8.2 Submit / Land — `can-submit` / `can-land`, fenced at apply

- **Submit (admission):** `can-submit(P, paths)` at submit-time `acl-version` — a fast fail so authors
  learn early. Advisory w.r.t. the final decision.
- **Land (apply):** `can-land(P, paths)` (and `can-land-policy` for policy entries) **re-evaluated at
  apply** against the RSM's current ruleset, inside the fenced critical section (§5.2, I6). This is the
  authoritative decision. A change authorized at submit under `v_old` is rejected here if `v_cur`
  revoked it — **no stale-allow** (§5.3).

### 8.3 Audit on every decision

Every authorization decision — read, submit, land, policy-land, and every cache hit/miss that resolves
a decision — emits an audit record:

```
audit-record := {
  principal     : id
  action        : :read | :write | :admin
  path | paths  : path | sorted[path]
  decision      : :allow | :deny
  reason        : :no-applicable-allow | :deny-more-specific | :allowed
                | :stale-or-revoked   ; apply re-check rejection (I6)
  acl-version   : u64                  ; the version the decision was made at
  basis-seq     : u64                  ; the as-of seq (reads) / assigned seq (lands)
  at            : :read-tier | :land-apply
  ts            : i64
}
```

Audit records are themselves accretive (append-only), consistent with the value-oriented spine. Because
`acl-version` and `basis-seq` are recorded, an auditor can **replay** any past decision against the
exact ruleset it was made under — closing the loop on time-travelable, inspectable policy (§4) and
giving a complete answer to "why was this allowed/denied, under which version, at which basis."

---

## 9. Cross-references

- **Keystone `00`**: invariants **I6** (this doc's center), **I9** (byte-path, owned by `04`/`05`),
  I1/I2 (land order for policy entries), I4 (durable-before-ack for policy); contracts §5.1
  (landed/policy entry), §5.2 (`as-of`), §5.3 (serve token), §5.4 (Shen↔shell boundary — the git merge
  oracle feeding `git-conflict`).
- **`02` land-queue kernel**: the land FSM / fenced apply where `can-land` re-check (§5.2) and
  `conflict-class` (§2.8) are consumed; fencing token (I7).
- **`04` read boundary**: `as-of.acl-version` enforcement (I8), serve-token minting (I9), revocation —
  the consistency+security half of read authorization.
- **`05` serving/VFS**: where `can-read` (§8.1) sits on the OpenResty/shen-lua hot path.
- **`06` product edges**: ACL admin UX, the policy-land review surfacing `widened` (§7.4).
- **Findings**: Hickey `../24` (Datalog over Prolog; policy-as-data), Norvig `../23`
  (longest-prefix+deny-wins = comparator, not search; trie via agentzh), shen-lua perf `../32` (soa32,
  8.9× / −93% alloc).
```
