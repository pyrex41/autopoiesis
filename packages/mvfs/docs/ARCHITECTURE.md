# mvfs — architecture

## The central idea: proven brain, trusted shell
mvfs splits every operation into a **decision** and an **effect**.

- The **brain** (pure Shen) *proves* decisions: the land FSM is sequent-typed so
  illegal transitions don't typecheck; authorization is decidable Datalog; fencing is
  a type-level capability (`lease-witness`) plus a runtime epoch CAS. The Shen program
  *is* the executable specification.
- The **shell** (trusted oracles) does the bytes: git (CAS + commit), pijul (sound
  merge + content-addressed changes), the filesystem (durable log, working tree),
  nginx (zero-copy serve), Firecracker/composefs (durable execution). Every
  side-effecting primitive crosses **one audited boundary** — `src/boundary.shen` —
  and nothing else in the system has side effects.

This is why correctness is *provable for the parts that decide* and *contained for the
parts that act*. The boundary is also where backends are swapped (storage, merge,
runtime) without touching the proven core.

```
            ┌────────────────────── proven brain (pure Shen, tc +) ─────────────────────┐
 submit ──▶ │  land FSM (fsm)   ACL/Datalog (acl, policy)   read decisions (read)        │
            │  checksum chain (checksum, log)   durable-exec control (dx, oplog, vfs)    │
            └───────────────────────────────┬───────────────────────────────────────────┘
                                             │  the ONLY side-effecting surface
                                    ┌────────▼─────────┐  src/boundary.shen
                                    │ audited boundary │  (typed stubs + backend selectors)
                                    └────────┬─────────┘
            ┌────────────────────────────────▼──────────────────────────────── trusted shell ┐
            │ git (CAS, merge fallback) · pijul (merge oracle) · fs (fenced log, working tree)│
            │ libcrypto (HMAC) · nginx (serve) · composefs/overlay · Firecracker/gVisor/CRIU  │
            └───────────────────────────────────────────────────────────────────────────────┘
```

## Layers and modules
Load order (and conceptual stack), bottom to top — see [MODULES.md](MODULES.md) for
per-file detail:

| Module | Layer | Role |
|---|---|---|
| `scalars` | foundation | scalar synonyms (`hash`/`id`/`principal`/`path` = string) |
| `boundary` | **the boundary** | every side-effecting primitive (git/pijul/fs/HMAC/…), the `storage-backend` (git/lore) + `merge-oracle` (git/pijul) selectors, and erroring stubs the host backends override |
| `checksum` | log | rolling-checksum chaining (the `prev==post` chain invariant) |
| `types` | core | the `landed-entry` record + `merge-result` + accessors |
| `log` | log | the **landed-log**: framing, `append-fenced!`, `verify-chain`, the I3 idempotency-key index |
| `fsm` | **kernel** | the sequent-typed land FSM (`submitted→admitted→based→landed`), the capability types (`acl-proof`, `lease-witness`), `with-leadership`, `pland!`, `land!` |
| `read` | read tier | the brain's read decision: §5.2 resolve, §5.3 HMAC serve token, I8 basis gate, I9 authorize-then-resolve |
| `acl` | policy | decidable ACL matcher (longest-prefix-deny-wins) + an independent oracle + the conformance differential |
| `policy` | policy | policy lands (ACL into the kernel): `acl-version` from the log, `effective-policy`, `can-read-at?` |
| `vfs` | mount | checkout-first sparse mount: `checkout!`, `status` (O(changes)), `switch!` |
| `dx` | durable exec | **P-D0**: overlay-delta serializer, `checkpoint!` (fenced), `restore-checkpoint!` (faithful deletes) |
| `oplog` | durable exec | **P-D2**: intent→outcome journal, `durable-effect!`, the egress capability |
| `cli` | interface | thin `clone`/`log`/`main` entry points |
| `host-lua` | host | binds the boundary to `host/host.lua` (the real runtime backend) |
| `host-lore`, `host-composefs` | host | optional backends (lore storage; composefs/overlay deployment) |

## The land kernel (the novel core)
The single write path. A change moves `submitted → admitted → based → landed`, each
transition a typed function that **demands its precondition as a type**:

- `submit` → `submitted`. `check` mints an unforgeable `acl-proof` (carries the
  acl-version, I6). `admit` requires the proof → `admitted`.
- `base` runs OCC + the **merge oracle** onto the trunk tip → `based` (or conflict).
- `land` requires a `lease-witness` (mintable *only* inside `with-leadership`) and a
  `based` change → `landed`. So "land without admission" and "land without a held
  lease" are **unconstructible** — the negative test `test/illegal.shen` must be
  rejected by the typechecker.

The effectful driver is **`pland!`** (the unified two-phase land), in order: I3
idempotency-key dedup → MF-1 dependency check → MF-3 land-point conflict re-check
(inside the lease) → **fenced append** (lease-epoch CAS + fsync = the linearization
point) → pristine apply. A stale leader fails the fence CAS and never mutates the
pristine. Recovery (`recover!`) is log-first: the log is truth, the pijul pristine is
a rebuildable cache (forward re-apply + backward orphan sweep + body-restore + the
MF-4b recovery-before-writes gate).

## The merge oracle (pluggable; pijul by ruling)
`base` routes through a `merge-oracle` (git-merge | pijul-merge) — orthogonal to the
`storage-backend`. The ruling (see [DECISIONS.md](DECISIONS.md)) is **pijul**: merge
is *sound by construction* (commutative, order-independent, conflicts are first-class
deterministic graph states), detected **structurally** (via `pijul archive`'s own
conflict report, not by grepping markers). git stays the kept-warm fallback + the CAS
source-of-truth.

## The read tier (brain decides, nginx serves zero-copy)
The brain (`read.shen`) makes the read decision and **never touches blob bytes**:
1. **I8** as-of basis gate — refuse unless the node's applied `(seq, acl-version)` ≥
   the request's.
2. **I9/I6** authorize-then-resolve — ACL check before resolve (a deny never reveals
   existence).
3. **§5.2** resolve `(root-tree, path) → blob`.
4. **§5.3** mint a per-principal, expiring, single-use **HMAC serve token** bound to
   the blob hash + acl-version.
The edge (`serve/access.lua`, `serve/verify.lua`, `serve/nginx.conf`) verifies the
token in `access_by_lua` then `ngx.exec`s to an `internal` location that `sendfile`s
the blob — bytes never enter the Lua VM. The token contract is **cross-language
verified**: a token minted by the Shen brain verifies under plain LuaJIT
(`make read-edge`).

## ACL and policy
`acl.shen` is decidable Datalog as a total function: longest-prefix-deny-wins,
default-deny, one-hop groups. Per spec §6a it ships **two structurally-different
implementations** (the fast `acl-decide` and an independent `acl-oracle`) plus
`acl-conform?` (the runtime differential / kill-switch). `policy.shen` lands policy
changes through the *same fenced kernel* as code (a `landed-entry` marked
`.mvfs/policy` whose Commit is a CAS ruleset blob); `acl-version` is derived from the
log, and reads evaluate against `effective-policy` at the current version (I6).

## The VFS (checkout-first mount)
`vfs.shen` is **trusted shell**, not a brain. Sparse cone profiles, a git-index-style
dirstate (`.mvfs/dirstate`), `checkout!` (materialize in-profile blobs), `status`
(a `(size,mtime)` quickcheck then hash → O(changed files)), and `switch!` (rebase the
working tree: keep unchanged, materialize added/changed, evict dropped). No FUSE in
the I/O path; the VFS does one-time materialize only.

## The durable-execution tier (spec/08)
The same substrate, extended. A **worker = a trunk lineage**; a **checkpoint = a
fenced land** of state artifacts.
- **P-D0 (`dx.shen`)**: the rootfs half. The overlay-delta serializer diffs the
  working tree vs the base git tree → `set`/`del` nodes (deletions are faithful — a
  deleted file does **not** reappear on restore, the bug plain-file checkout has),
  content stored in CAS; `checkpoint!` lands the deterministic content-addressed
  delta; `restore-checkpoint!` reconstructs base + delta with an **atomic pre-flight**
  (verify every referenced blob before materializing → fail-closed, no partial tree).
- **P-D2 (`oplog.shen`)**: exactly-once effects. The intent→outcome journal on the
  fenced log + `durable-effect!` (replay a recorded outcome, else intent→run→outcome)
  + the **out-of-guest egress capability** (the lease holder mints a per-effect token;
  the proxy admits it iff HMAC-valid AND epoch ≥ the log's current fence — a stale
  leader's effects are rejected where the fence can't reach).
- **P-D1 / composefs / runtime (deployment)**: memory snapshots (Firecracker default,
  encrypted per-tenant I10, provenance-verified I11) and the composefs/overlay rootfs
  backend (`deploy/`, `host/host-composefs.lua`) — runnable only on a privileged host.

## The pluggable boundary backends
The boundary makes the trusted oracles swappable without touching the proven core:

| Axis | Choices | Where |
|---|---|---|
| **storage-backend** | `git-be` (default, CAS source-of-truth) · `lore-be` (large-binary fragment tier) | `boundary.shen`, `host-lore.shen` |
| **merge-oracle** | `pijul-merge` (default, sound) · `git-merge` (fallback) | `boundary.shen`, `host-lua.shen` |
| **host runtime** | `host-lua` (shen-lua via `lua.call`) — git/pijul/HMAC/fs/dx/oplog | `host-lua.shen`, `host/host.lua` |
| **durable rootfs** | composefs/overlay (deployment) | `host-composefs.shen`, `host/host-composefs.lua` |
| **durable runtime** (P-D1) | Firecracker (default) · gVisor (trusted ML) · CRIU (last resort) | spec/08 §1a (deployment) |

## How it all coheres (the cross-document contracts)
The frozen contracts that make the layers fit (spec/00 §5): the landed-log entry
shape (§5.1), the as-of basis `(seq, acl-version)` (§5.2), the HMAC serve token
(§5.3), and the Shen↔shell boundary (§5.4). The invariants **I1–I11** ride on these —
see [INVARIANTS.md](INVARIANTS.md) for each one's enforcement and its test.
