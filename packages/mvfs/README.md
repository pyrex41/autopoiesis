# mvfs — P0 (core spine)

`mvfs` is a content-addressable, **trunk-only** (no branches), monorepo distributed VCS with a
virtual filesystem. Design spec: [`../../thoughts/shared/plans/dvcs-vfs/spec/`](../../thoughts/shared/plans/dvcs-vfs/spec/)
(read `spec/00-overview.md` first — it is normative).

This directory is **P0** from `spec/07-build-plan.md`: the core spine, written in **Shen**.

## What P0 contains

| File | Spec | Purpose |
|---|---|---|
| `src/types.shen` | `02` §1 | The **sequent-typed land FSM** (`submitted → admitted → based → landed`) + the unforgeable capability types (`acl-proof`, `lease-witness`, `merge-result`). Illegal transitions don't typecheck. |
| `src/boundary.shen` | `00` §5.4 | The **audited Shen↔shell surface**: git CAS verbs (`hash-object`/`cat-file`/`mktree`/`commit-tree`/`merge-tree`), durable fsync-append, fence CAS, `crc64`/`xor64`. The *only* side-effecting primitives. |
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
