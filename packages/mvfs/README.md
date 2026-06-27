# mvfs — P0 (core spine)

`mvfs` is a content-addressable, **trunk-only** (no branches), monorepo distributed VCS with a
virtual filesystem. Design spec: [`../../thoughts/shared/plans/dvcs-vfs/spec/`](../../thoughts/shared/plans/dvcs-vfs/spec/)
(read `spec/00-overview.md` first — it is normative).

This directory is **P0** from `spec/07-build-plan.md`: the core spine, written in **Shen**.

## What P0 contains

| File | Spec | Purpose |
|---|---|---|
| `src/types.shen` | `02` §1 | The **sequent-typed land FSM** (`submitted → admitted → based → landed`) + the unforgeable capability types (`acl-proof`, `lease-witness`, `merge-result`). Illegal transitions don't typecheck. |
| `src/boundary.shen` | `00` §5.4 / [doc 34](../../thoughts/shared/plans/dvcs-vfs/34-pijul-merge-oracle.md) | The **audited Shen↔shell surface**: git CAS verbs, the pluggable **`storage-backend`** (git/lore) + **`merge-oracle`** (git/pijul) axes, pijul patch-theory verbs (`record`/`apply`/`fork`/`state`/structural conflict probe), durable fsync-append, fence CAS, `crc64`/`xor64`. The *only* side-effecting primitives. |
| `src/checksum.shen` | `01` §5 | The rolling-checksum **chaining protocol** (contrib field set, `prev==post` chain invariant) over the trusted `crc64`/`xor64` host primitives. |
| `src/log.shen` | `01`/`02` | The **landed-log**: serialize entry, `durable-append-fenced!` (fence-epoch CAS at the durable head + fsync + post-fsync lease re-check), `verify-chain`. |
| `src/fsm.shen` | `02` | The transitions: `admit` (needs `acl-proof`), `base` (OCC + git 3-way merge), `land` (needs `lease-witness`); `with-leadership` (the only minter of a witness). |
| `src/cli.shen` | `06` | Thin `clone` / `log` entry points (P0 stubs). |
| `test/illegal.shen` | `02` §1 | The **four illegal programs** that MUST be rejected by the typechecker (land-without-admission, land-without-lease, base-without-admission, forge-a-witness). |
| `test/log-test.shen` | `01` | Positive tests: checksum chaining, append/verify round-trip. |
| `src/host-lore.shen` | `00` §5.4 / [doc 33](../../thoughts/shared/plans/dvcs-vfs/33-storage-backend-decision.md) | **Optional** lore fragment-store backend host (BLAKE3 CAS + chunking + sparse hydration), over the verified `lore` CLI. Loaded only when `lore-be` is enabled. |

## Storage backend (doc 33 — grounded by running the candidates)

mvfs's storage tier is **pluggable** behind `boundary.shen` (a `storage-backend` datatype:
`git-be` | `lore-be`, with generic `cas-read-blob` / `cas-locate` / `cas-put-blob`).
The decision, reached by actually running EpicGames/lore v0.8.4 and reading rvcs:

- **git = trunk source-of-truth + merge oracle** (default, daemon-free). `git-commit-tree`
  / `git-merge-tree` are **git-only by design** and are *not* routed through the selector —
  a trunk-only code monorepo needs real 3-way text merge and lore has none (server-side CR).
- **lore = optional large-binary / sparse-hydration fragment tier** (BLAKE3 48-byte
  addresses, content-defined chunking, lazy working trees). Adopted as a *second* backend,
  not a git replacement: it is pre-1.0 (unstable formats), server-of-record (needs a
  `loreserver`), and its VFS is roadmap-not-shipped.
- **rvcs = rejected** (snapshot/publish/sign/mirror model; experimental & unsupported).

See [doc 33](../../thoughts/shared/plans/dvcs-vfs/33-storage-backend-decision.md) for the
full evidence, object-model mapping table, and impedance notes.

## Merge oracle (doc 34 — Pijul / patch theory replaces git's heuristic merge)

Merge is a **second pluggable axis**, orthogonal to storage (a `merge-oracle` datatype:
`git-merge` | `pijul-merge`; `base` routes through `oracle-admits?` / `oracle-merged`).
git-as-CAS is fine; git-as-*merge* was the un-principled part — `merge-tree` is a heuristic
line diff3. **Pijul's merge is sound by construction**, proven by running pijul
1.0.0-beta.15:

- **Commutativity** — independent changes in either order → byte-identical file *and*
  identical cryptographic state hash (order-independent discrete-log multiset hash).
- **Conflict determinism** — same-line edits → identical conflict state + state hash in
  both orders; a conflict is a first-class graph state, detected **structurally** (never by
  grepping `>>>>>>>` markers).
- **Rebase dissolved** — a change recorded against the old base applies cleanly onto an
  advanced trunk, hash unchanged — exactly what a totally-ordered land queue wants.

Pijul is a **sealed merge subroutine**: we **exec the `pijul` CLI, never link libpijul**
(GPL-2.0); **one channel** only (trunk-only); no pijul branches/remotes/identity leak up.
git stays the **kept-warm fallback** oracle + CAS source-of-truth; lore = large binary
bytes; mvfs = control plane (I1–I9). The hard P1 problem is **two-store crash atomicity**
(fenced log = truth, Sanakirja pristine = rebuildable cache) — see doc 34's must-fix list.

See [doc 34](../../thoughts/shared/plans/dvcs-vfs/34-pijul-merge-oracle.md) for the grounded
experiments, the Aphyr/Torvalds/Fukamachi panel synthesis, and the MF-1..5 / T1–T3 list.

## Invariants embodied (see `spec/00` §4)

- **I1** linear trunk · **I3** at-most-once (idempotency-key in the entry) · **I4** no-lost-acked-land
  (fsync-before-ack) · **I5** content integrity (re-hash assert in the git boundary) · **I6** acl
  fence (the `acl-proof` carries `acl-version`) · **I7** fenced authority (the fence = lease *epoch*,
  CAS'd at the durable append; `lease-witness` is the type-level half).

## Building

```sh
# build LuaJIT 2.1 + fetch shen-lua into ./.toolchain (idempotent):
eval "export SHEN=$(scripts/bootstrap-toolchain.sh)"   # adds luajit to PATH internally
# (or point SHEN at your own shen-lua launcher: export SHEN=/path/to/shen-lua/bin/shen)

make typecheck            # typecheck the core under Shen's tc + (must pass)
make typecheck-lore       # typecheck the optional lore backend host (must pass; no server needed)
make typecheck-negative   # MUST FAIL: rejects test/illegal.shen (illegal programs)
make test                 # positive runtime smoke: submit->admit->base yields a `based`

# P1 — the FSM running for real (needs SHEN, PIJUL, PIJUL_CONFIG_DIR + git/pijul):
make e2e                  # real git + real pijul + fsync'd log: oracle, land path, I7
make t1                   # two-store crash atomicity (Aphyr ship-decider): 8/8
```

The `boundary.shen` host primitives (`shell-run`, `durable-cas-append!`, `crc64`, `xor64`, …) are
the **per-backend** extension point: shen-lua provides them via LuaJIT FFI / `os`/`io`; shen-cl via
`uiop`/`ironclad`. P0 ships portable signatures + erroring stubs; wire the backend impls in
`src/host-lua.shen` / `src/host-cl.shen` (P0.5).

## Status — VERIFIED on shen-lua / LuaJIT 2.1

Built and run on the real toolchain (bootstrapped via `scripts/bootstrap-toolchain.sh`):

- ✅ **Core typechecks** under Shen's sequent-calculus checker (`tc +`), 0 errors.
- ✅ **Illegal programs rejected**: loading `test/illegal.shen` under `tc +` fails with
  `type error in rule 1 of mvfs.illegal-1` — i.e. `land` applied to a `submitted` change does not
  typecheck. The I7 "illegal states unrepresentable" property is demonstrated by the typechecker.
- ✅ **FSM runs**: `submit → check → admit → base` yields
  `[mvfs.mk-based c1 k1 ttree tbase alice [mvfs.mk-proof alice [] 0]]`.

### Notes learned wiring this to the real typechecker
- All core modules live in **one `mvfs` package, exporting nothing** — Shen's `tc` only shares a
  function's `{ }` signature with callers when the function is *not* exported (internal/prefixed).
- `synonyms` must be declared **inside** the package; functions must be defined **callee-before-caller**.
- Datatype constructors are list terms `[tag ..]`; comments cannot appear inside a `(datatype ...)` body;
  `if`-guarded rules can't be mixed with `[tag ..]` rules in one datatype.
- **shen-lua typechecker edge case (worth a `pyrex41/shen-lua` issue):** a function that *both*
  destructures a datatype constructor in its rule head *and* constructs a state value, while a sibling
  also constructs that constructor, fails to typecheck. Minimal repro: a `base` that builds `[mk-based …]`
  plus a `land` whose head matches `[mk-based …]`. Worked around by reading `based`'s fields via accessor
  functions (`based-tree`/`based-onto`/…) instead of head-destructuring — type discipline unchanged.

Next per `spec/07`: spike **S0** (`jit.dump` the read decision path), wire the host backends
(`crc64`/`xor64`/`shell-run`/`durable-cas-append!`), then P1 (dirstate + git 3-way merge + stacks).
