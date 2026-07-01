# mvfs — source map

~2,200 lines of Shen + Lua. The Shen core typechecks under `tc +` (one `mvfs`
package, exporting nothing — Shen only shares a function's signature with callers
when it is *not* exported). Load order matters: `scalars` first (synonyms), then
callee-before-caller. The `CORE` list in the `Makefile` is the authoritative order.

## `src/` — the Shen core (typechecked)
| File | Purpose |
|---|---|
| `scalars.shen` | Scalar synonyms inside the package: `hash`/`id`/`principal`/`path` = `string`. Loaded first. |
| `boundary.shen` | **The audited Shen↔shell surface** (spec/00 §5.4) — the *only* side-effecting primitives. Host stubs that error by default (overridden per backend): `shell-run`, durable log (`durable-head`, `durable-cas-append!`), `crc64`/`xor64`, git CAS verbs (`git-hash-object`/`cat-file`/`mktree`/`commit-tree`/`merge-tree`), pijul verbs (`pijul-record`/`apply`/`fork`/`state`/structural conflict probe), read-tier verbs (`resolve-path`, `hmac-sha256`, `b64url`, `nonce-*`), VFS verbs (`git-ls-tree-r`, `write-blob!`, `hash-file`, `file-size/mtime`, `rm-file!`, `blob-exists?`), durable-exec hooks (`crash-point`, `blob-put!`, `recovered?`, `sync-pristine!`, `version-*`), and the composefs/overlay deploy verbs. Also the **`storage-backend`** (git-be/lore-be) and **`merge-oracle`** (git-merge/pijul-merge) datatypes + `cas-*`/`oracle-*` dispatch. |
| `checksum.shen` | The rolling-checksum **chaining protocol**: `contrib` (US-joined cells), `roll = xor64(prev, crc64(contrib))`, the `prev==post` chain invariant, `join`. |
| `types.shen` | The frozen `landed-entry` record (`mk-entry`, 13 fields) + the public `merge-result` + entry accessors (`entry-seq/cid/key/commit/parent/root/paths/aclv/fence/prev/post`). |
| `log.shen` | The **landed-log**: framing (`frame`/`unframe`, US/RS-delimited), head accessors (`head-seq/post/fence`, genesis 0), **`append-fenced!`** (re-read head, epoch CAS, roll checksum, atomic append+fsync), `verify-chain` (`fold-chain`), and the **I3 idempotency-key index** (`key-find`/`key-present?`). |
| `fsm.shen` | **The land kernel.** The sequent-typed state datatypes (`submitted-t`/`admitted-t`/`based-t`/`landed-t`) with package-internal constructors; the capability types `acl-proof` & `lease-witness`; transitions `submit`/`check`/`admit`/`base`/`land`; `with-leadership` (the only minter of a witness); **`pland!`** (unified two-phase land: I3→MF-1→MF-3→fenced-append→apply) and `land!` (the git-commit land path); `recover!`-supporting accessors. |
| `read.shen` | **Read-tier brain.** `read-decide` (I8 basis gate → I9 authorize-then-resolve → §5.2 resolve → §5.3 mint), `mint-token`/`verify-token` (HMAC serve token, single-use nonce, expiry, constant-time). |
| `acl.shen` | **Decidable ACL.** `acl-decide` (longest-prefix-deny-wins, default-deny, one-hop groups), the independent `acl-oracle`, `acl-conform?` (the §6a differential / kill-switch), `can-read?`. |
| `policy.shen` | **Policy lands.** ruleset↔blob serialization, `policy-land!` (fenced), `acl-version-of`, `effective-policy`, `can-read-at?` (ACL evaluated at the log's current policy). |
| `vfs.shen` | **Checkout-first mount.** `in-profile?` (cone prefixes), `want-set`, `checkout!`, `status` (O(changes), `(size,mtime)` quickcheck), `switch!` (rebase the working tree). |
| `dx.shen` | **Durable execution P-D0.** `compute-delta`/`serialize-delta`/`store-delta!` (the overlay-delta serializer: `set`/`del` nodes, deterministic), `checkpoint!` (fenced land of the delta), `restore-checkpoint!` (base+delta, faithful deletes, atomic pre-flight via `set-blobs-present?`). |
| `oplog.shen` | **Durable execution P-D2.** intent→outcome journal (`land-intent!`/`land-outcome!`/`effect-status`/`should-emit?`/`outcome-of`), **`durable-effect!`** (the worker-facing exactly-once activity wrapper), and the **egress capability** (`mint-egress` under leadership, `egress-ok?` epoch-fenced). |
| `cli.shen` | Thin `clone`/`log-cmd`/`main` entry points (P0 stubs). |

## `src/` — host backends (runtime, loaded under `tc -`)
| File | Purpose |
|---|---|
| `host-lua.shen` | The **default runtime host**: rebinds the boundary stubs to `host/host.lua` via `(lua.call …)` (declared external so the package doesn't prefix it). git/pijul/HMAC/fs/dx/oplog/recovery primitives. |
| `host-lore.shen` | Optional **lore** storage backend (large-binary fragment tier); shells to the `lore` CLI. `make typecheck-lore`. |
| `host-composefs.shen` | Optional **composefs/overlay** deployment backend (binds the deploy verbs). `make typecheck-composefs`. |

## `host/` — the Lua implementations
| File | Purpose |
|---|---|
| `host.lua` | The real backend: `shell_run` (errors on rc>1), CRC/xor (normalized to fit Shen doubles), the durable fenced log (CAS append + flush + FFI fsync), HMAC-SHA256 via libcrypto FFI, base64url, the single-use nonce store, the pijul structural conflict probe (`pijul archive` stderr), recovery + blob-store + version-pin + crash-seam (FFI self-`kill -9`) + VFS + dx + oplog primitives. |
| `host-composefs.lua` | The composefs/overlay **deployment** backend: `mkcomposefs`/EROFS image build, in-kernel overlay mount, and the load-bearing `overlay-capture!` (real upper: char-device whiteouts → `del`, `trusted.overlay.opaque/redirect` xattrs → nodes) + `overlay-apply!`. Not runnable without privileged mounts. |

## `serve/` — the read-tier edge (deployment artifacts)
`nginx.conf` (sendfile + `internal` /cas + kTLS + open_file_cache), `access.lua`
(the `access_by_lua` decision: mlcache, single-flight, `ngx.exec`), `verify.lua` (the
edge serve-token verifier — cross-language verified against the Shen brain).

## `deploy/` — durable-execution deployment
`README.md` — how to run P-D0 on a real kernel (composefs + overlayfs +
CAP_SYS_ADMIN), and the overlay-upper → delta mapping.

## `test/` — the suites
Shen negative/positive (`illegal.shen`, `log-test.shen`) + shell-driven end-to-end
suites (`e2e`, `t1-crash`, `t1-kill`, `t2-split-brain`, `t3-toctou`, `read`,
`read-edge`, `acl`, `policy`, `vfs`, `dx`, `t-d1`, `oplog`). See [TESTING.md](TESTING.md).

## `scripts/`
`bootstrap-toolchain.sh` — builds LuaJIT 2.1 + fetches shen-lua into `.toolchain`,
prints the `shen` launcher path.
