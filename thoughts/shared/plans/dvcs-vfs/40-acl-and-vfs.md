# 40 — Decidable ACL matcher (spec/03) + VFS mount client (spec/05)

**Status:** Both built & verified (shen-lua/LuaJIT, git). Scoped with subagents: one
Explore agent extracted the spec/03 ACL model, another the spec/05 VFS model; shen-
lua's native Prolog was probed (works). These are the two halves the read tier was
waiting on — the *policy* that produces `allow?`, and the *mount* that consumes the
resolve/serve primitive.

---

## ACL matcher — `src/acl.shen` (`make acl` 11/11)
The authorization half of the proven brain. The spec is explicit that the decision
is **"filter + max + any over a finite candidate set — NOT a search"** (§1.2), so
the faithful decidable form is a total, terminating function (default-deny,
longest-prefix-deny-wins).

- **Policy** = list of `[Subject Action Prefix Effect]` rules (`Effect ∈ {allow,
  deny}`), with one-hop group membership `[Principal Group]`. A dir-prefix
  (trailing `/`) inherits down the subtree; `""` is the root prefix (covers all).
- **Decision**: among rules matching `(action, subject-or-group, prefix-of path)`,
  take the longest prefix; if any deny at that depth → DENY; else ALLOW; empty →
  DENY. Deny wins on ties.
- **§6a conformance**: per spec/00 §6a the hot-path matcher is *conformance-tested
  against an oracle, not verified*. So we ship **two structurally-different
  implementations** — `acl-decide` (fast: allow-max vs deny-max) and `acl-oracle`
  (gather candidates → winning depth → deny?) — plus `acl-conform?` (the runtime
  differential / kill-switch). `make acl` runs the §1.2 cases (deny-wins, specific-
  allow-overrides-broad-deny, deny-on-tie, group membership, default-deny, root
  prefix) **and** the differential `acl-decide ≡ acl-oracle` over a 10-query matrix.
- **`can-read?`** is the read-tier entry point: it produces the `allow?` boolean
  that `read.shen`'s `read-decide` consumes (I9). I6 acl-version fencing is already
  carried by the read path (the serve token binds acl-version; reads pin it).

Decidability is structural: finite EDB (the policy list), bounded recursion (over
the rule list / path prefix), no negation-as-failure that can diverge — exactly the
spec's "decidable Datalog over policy-as-data."

## VFS mount client — `src/vfs.shen`, checkout-first v1 (`make vfs` 12/12)
The mount is **trusted shell** (§5.4): a sparse, lazy, content-addressed materialize
helper + git-index dirstate — *not* a brain (no authz/ordering here). It sits on the
git-CAS + resolve primitives.

- **Sparse profile** (§B4): cone prefixes; `in-profile?` reuses `prefix-of?` from
  acl.shen. Only in-profile paths materialize; the rest stays virtual.
- **want-set** (§B5): `git-ls-tree-r` the tree, keep entries that are in-profile and
  not already tracked — the batch to fetch (in production multiplexed over one
  HTTP/2 conn; here `git cat-file` per blob).
- **materialize** writes each blob to `<workdir>/<path>` and records a dirstate row
  `[path hash size mtime]`. **`checkout!`** = clone+materialize, and widening =
  `checkout!` over the existing dirstate (want-set skips tracked paths).
- **dirstate** persists at `.mvfs/dirstate` (tab-joined rows, §2.3).
- **status** (§B6) is **O(changes)**: a `(size, mtime)` quickcheck short-circuits
  unchanged files; only stat-mismatched files are re-hashed (`git hash-object`)
  and compared. Reports `modified` / `deleted`; clean entries omitted.

`make vfs` proves: sparse materialize (only `app/` in profile; `docs/`,`tools/`
absent), correct content, clean status after checkout, `modified` after an edit,
`deleted` after a remove, and profile-widening faulting in `docs/c.txt` while
`tools/` stays excluded.

**FUSE fast-follow** (§B2/B7) reuses all of this — `open`/`read`/`readdir` turn the
explicit `checkout!` into transparent on-demand fault-in; checkout-first is the
v1 stable path.

---

## A bug caught and fixed
vfs.sh first used `src/` as a content-dir name, which **collided with the `src`
loader symlink** (→ the real source tree), so `printf > src/a.txt` wrote into
`packages/mvfs/src/`. Caught via `git status`, removed the leaked files, and fixed
the test to use non-colliding names (`app/`) with explicit `git add app docs tools`
(never `git add .`, so the symlinks never enter the tree). Source tree confirmed
clean.

## Suite (all green on the real toolchain)
```
typecheck / -negative / -lore   OK
acl 11/11    vfs 12/12
read 15/15   read-edge 5/5
t1 8/8   t1-kill 9/9   t2 15/15   t3 8/8
```

## What this completes / what's next
The read path now has both ends: `can-read?` (ACL) feeds `read-decide`'s `allow?`,
and the VFS mount consumes `resolve-path` + the serve token. Remaining:
- **Integrate** can-read? as the live producer of read-decide's allow? in the edge
  handler (today access.lua calls `brain.acl_allow`; wire it to `can-read?`).
- **Policy lands**: a `kind=:policy` landed-entry whose payload is a ruleset delta,
  bumping acl-version (spec/03 §4) — ties the ACL into the land kernel.
- **VFS**: switch-revision (diff old/new tree → materialize changed, evict removed),
  the HTTP/2 batched want-set against the real serve tier, and the FUSE increment.
- The matcher's **trie partial-eval** (agentzh) for the hot path, gated by the
  `acl-conform?` differential already in place.
