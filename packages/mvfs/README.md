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

## Invariants embodied (see `spec/00` §4)

- **I1** linear trunk · **I3** at-most-once (idempotency-key in the entry) · **I4** no-lost-acked-land
  (fsync-before-ack) · **I5** content integrity (re-hash assert in the git boundary) · **I6** acl
  fence (the `acl-proof` carries `acl-version`) · **I7** fenced authority (the fence = lease *epoch*,
  CAS'd at the durable append; `lease-witness` is the type-level half).

## Building (on your toolchain)

> ⚠️ This sandbox has no Shen toolchain; the code here is written to spec and **has not been
> compiled/typechecked in this environment**. Run it where `pyrex41/shen-lua` and shen-cl live.

```sh
# point these at your installs:
export SHEN_LUA=/path/to/shen-lua      # the LuaJIT port
export SHEN_CL=/path/to/shen-cl        # the Common Lisp port (for the land tier)

make typecheck            # typecheck the core (must pass)
make typecheck-negative   # MUST FAIL: rejects test/illegal.shen (the 4 illegal programs)
make test                 # run positive tests
make cl                   # build the land-tier image (shen-cl)
make lua                  # build the read-tier artifact (shen-lua)
```

The `boundary.shen` host primitives (`shell-run`, `fsync-append`, `cas-head`, `crc64`, `xor64`) are
the **per-backend** extension point: shen-lua provides them via LuaJIT FFI / `os`/`io`; shen-cl via
`uiop`/`ironclad`. P0 ships portable signatures + a reference behavior; wire the backend impls in
`src/host-lua.shen` / `src/host-cl.shen` (next).

## Status

P0 skeleton, design-faithful, **unbuilt in this environment**. Next per `spec/07`: run **spike S0**
(`jit.dump` the read decision path) and wire the two host backends, then P1 (dirstate + git 3-way
merge + stacks).
