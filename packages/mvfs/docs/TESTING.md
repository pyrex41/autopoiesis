# mvfs — verification

Everything below was run on a real toolchain (LuaJIT 2.1 / shen-lua / git / pijul
1.0.0-beta.15) bootstrapped in a sandbox. ~137 dynamic assertions across 12 suites,
plus 4 typecheck gates and the end-to-end smoke.

## Toolchain bootstrap
```sh
# builds LuaJIT 2.1 + fetches shen-lua into ./.toolchain, prints the launcher:
eval "export SHEN=$(scripts/bootstrap-toolchain.sh)"
# durable/merge tests also need:
export LUAJIT=…/luajit  PIJUL=…/pijul  PIJUL_CONFIG_DIR=…   # pijul needs an ssh-agent identity
```

## The verification matrix
| `make` target | What it proves | Result |
|---|---|---|
| `typecheck` | the whole core typechecks under Shen's sequent checker (`tc +`) | ✅ 0 errors |
| `typecheck-negative` | the 4 **illegal programs** (`test/illegal.shen`) are **rejected** by `tc +` — land-without-admission, land-without-lease, base-without-admission, forge-a-witness (I7 type half) | ✅ rejected |
| `typecheck-lore` | the optional lore storage backend typechecks | ✅ |
| `typecheck-composefs` | the composefs deploy backend binds (load-check under `tc -`) | ✅ |
| `test` | runtime smoke: `submit→admit→base` yields a `based` via the git-merge oracle | ✅ |
| `e2e` | **read tier + merge oracle + I7** on real git + real pijul + a fsync'd log: pijul oracle admits clean / rejects conflict; `land!` writes a real commit + fenced append + `verify-chain`; stale/wrong fences rejected | ✅ green |
| `t1` | **two-store crash atomicity** (Aphyr's ship-decider), step-stop W1/W2 recovery | ✅ 8/8 |
| `t1-kill` | **real SIGKILL** at the post-append window (FFI `kill -9`) — fsync'd log survives, change absent from pristine, recovery restores exact state; + MF-4a blob durability survives `rm -rf .pijul/changes` | ✅ 9/9 |
| `t2` | **fenced split-brain** via `pland!`: I7 (stale leader rejected, no orphan), I3 (retry no-op), MF-3 (land-point conflict reject), MF-4b gate, MF-4a blob | ✅ 15/15 |
| `t3` | **TOCTOU race** (clean@T → conflict@T+1 with a competing land between admission and land) caught by MF-3; + MF-5 version pinning (recover refuses an incompatible-pijul log) | ✅ 8/8 |
| `read` | read-tier brain on a real git tree: §5.2 resolve; §5.3 mint/verify; replay/tamper/wrong-hash/wrong-principal/stale-acl/expired all rejected; I8 basis gate; I9 authorize-then-resolve | ✅ 15/15 |
| `read-edge` | **cross-language**: a token minted by the shen-lua brain verifies under plain LuaJIT (`serve/verify.lua`) and rejects replay/tamper/wrong-hash/wrong-principal | ✅ 5/5 |
| `acl` | decidable ACL: longest-prefix-deny-wins, deny-on-tie, group membership, default-deny, root prefix; **+ §6a conformance diff** (`acl-decide ≡ acl-oracle`) | ✅ 11/11 |
| `policy` | **policy lands**: fenced; `acl-version` from the log; `effective-policy` round-trips; landing a v2 revoke flips the decision (I6); log verifies | ✅ 9/9 |
| `vfs` | checkout-first mount: sparse materialize (only in-profile), clean `status`, modified/deleted detection (O(changes)), profile widening, **switch-revision** (keep/materialize/evict) | ✅ 17/17 |
| `dx` | **durable execution P-D0**: overlay-delta serializer + fenced `checkpoint!` + restore with **faithful deletion** (a deleted file does NOT reappear); determinism; fenced chain | ✅ 12/12 |
| `t-d1` | durable-layer fault test: fail-closed (atomic, no partial tree) on a lost delta blob **and** a lost content blob; deterministic delta; entry tampering caught by the chain (I5) | ✅ 10/10 |
| `oplog` | **durable execution P-D2**: intent→outcome journal exactly-once; `durable-effect!` — a real side effect fires **exactly once across retries**; the egress capability **rejects a stale leader** (epoch < current) | ✅ 18/18 |

**Totals:** 8+9+15+8 (kernel) + 15+5 (read) + 11+9+17 (policy/mount) + 12+10+18
(durable) = **137 assertions**, all green, plus the 4 typecheck gates and `e2e`.

## What's verified vs deployment-gated
- **Verified in CI** (git + plain dirs + LuaJIT/libcrypto + the fenced log): the land
  kernel, pijul merge oracle, read-tier decision + token contract, ACL + policy,
  the sparse VFS, and the durable-execution **control plane** (P-D0 checkpoints, P-D2
  exactly-once effects).
- **Deployment-gated** (need a privileged host): the OpenResty zero-copy serve tier
  (`serve/`), the composefs/overlay rootfs mount (`deploy/`, `host-composefs.lua`),
  and P-D1 memory snapshots (Firecracker/gVisor/CRIU). These are structured to the
  real APIs but not exercisable in a sandbox; see [ROADMAP.md](ROADMAP.md).

## Real bugs the tests caught (a sample)
- `pland!` paren imbalance and a shen-lua typechecker edge case (destructure + sibling
  construct) — worked around with field accessors.
- The delta must store content with `git hash-object -w`, not just hash it, or restore
  can't find the blob (`dx`).
- **Non-atomic restore**: a missing content blob left a partial base tree → added the
  `set-blobs-present?` pre-flight so restore is atomic-or-nothing (`t-d1`).
- `ipairs` stops at the first `nil` → the edge verifier couldn't find `host.lua`
  (`read-edge`).
- A test that wrote through the `src` symlink polluted the real source tree → switched
  to non-colliding dir names + explicit `git add` (`vfs`).

## Expert-panel review record
Every major decision was adversarially reviewed by an expert persona panel (the full
reviews are in the design corpus `../../../thoughts/shared/plans/dvcs-vfs/`):
- **Aphyr** (Jepsen): the fence/exactly-once correctness; the durable-execution
  multi-store atomicity verdict (doc 42) and the must-fix list folded into spec/08.
- **Torvalds**: systems pragmatics — "use composefs, don't reinvent squashfs; the
  overlay serializer is the real work" (doc 42).
- **Ptacek** (fly.io/Matasano): the snapshot confidentiality/provenance review →
  invariants I10/I11 (doc 42).
- **Fukamachi**: the shen-lua boundary design (the merge-oracle axis).
- **agentzh** (OpenResty): the read-tier perf constraints (bytes never in Lua,
  mlcache, `ngx.exec`, FFI HMAC).
