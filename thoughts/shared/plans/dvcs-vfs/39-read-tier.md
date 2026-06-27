# 39 — Read tier: the brain decision path + OpenResty serve artifacts

**Status:** Brain built & verified (shen-lua/LuaJIT, git); serve half structured to
spec and cross-language-verified. New phase per docs 26–31 + spec/04 + spec/05.
Driven with subagents: an Explore agent extracted the normative read spec (§5.2
as-of, §5.3 serve token, I8/I9), and an agentzh-persona agent distilled the
perf-critical OpenResty constraints. Both digests are folded in below.

---

## The architecture (agentzh's load-bearing rule)
**Bytes never enter the Lua VM.** The brain DECIDES (resolve + authorize + mint
token); nginx MOVES the payload via `sendfile` (kernel zero-copy). Blob size is
irrelevant to the VM. Violate this and every perf number collapses. So the read
tier splits cleanly into two pieces:

- **brain** (`src/read.shen`, typed core) — the decision; fully verifiable here.
- **edge** (`serve/`) — OpenResty `access_by_lua` + an INTERNAL sendfile location;
  deployment artifact, with the token verifier cross-language-tested under luajit.

## The brain — `src/read.shen` (verified, `make read` 15/15)
`read-decide : key → principal → root-tree → path → req-seq → req-acl →
applied-seq → applied-acl → allow? → nonce → read-result` returns `[serve blob
token]` or `[deny reason]`, doing, in order:

1. **I8 as-of basis gate** (`basis-behind?`): refuse unless `applied ≥ request`
   componentwise (`(seq, acl-version)`); the edge blocks ≤ T_ryw then
   redirects/fails-closed — never serves stale.
2. **I9/I6 authorize-then-resolve**: deny BEFORE resolving (a deny must not reveal
   whether the path exists; the edge maps every deny to a uniform 403).
3. **§5.2 resolve** (`resolve-path`, git tree walk via `git rev-parse tree:path`):
   `(root-tree, path) → blob hash`, `""` if absent.
4. **§5.3 mint** (`mint-token`): `b64url(msg) "." HMAC-SHA256-hex(key, msg)` where
   `msg = US-join(hash, principal, acl-version, expiry=now+30, nonce)`. The token
   is per-principal, expiring, single-use, bound to the blob hash and the applied
   acl-version.

`verify-token` (the edge contract, also in Shen for the negative tests) recomputes
the MAC (constant-time), then checks: this hash, this principal, acl-version ≥
required, not expired, nonce unused (then records it). `make read` proves the
happy path plus every deny: replay, tamper, wrong-hash, wrong-principal,
stale-acl, expired, basis-behind, acl-deny, not-found — all on a real git tree.

Host primitives added (boundary.shen typed stubs; host.lua real impls):
`resolve-path` (git), `hmac-sha256` (libcrypto FFI — matches `openssl dgst`
exactly), `b64url`/`unb64url`, `consttime-eq`, `now-secs`, `str->num`,
`random-nonce` (/dev/urandom), `nonce-seen?`/`nonce-record!` (single-use store).

## The edge — `serve/` (deployment artifacts, agentzh-structured)
- `serve/access.lua` — `access_by_lua` handler: mlcache (L1 lrucache + L2
  shared_dict, content-addressed keys → ~infinite TTL) for resolve & ACL,
  lua-resty-lock single-flight, then `ngx.exec("/cas/serve")` (in-process internal
  jump — NOT `X-Accel-Redirect`, which is for a separate upstream). Hash derived
  server-side, never from the client.
- `serve/verify.lua` — the INTERNAL-location token verifier; FFI HMAC, constant-
  time compare, single-use nonce, fail-closed. **Cross-language verified** (`make
  read-edge` 5/5): a token minted by the shen-lua brain verifies under luajit and
  rejects replay/tamper/wrong-hash/wrong-principal — identical wire contract.
- `serve/nginx.conf` — `sendfile`/`aio threads`/`directio 4m` (large-blob HOL
  guard), `open_file_cache` (safe because CAS is immutable & append-only),
  `internal;` on `/cas/serve` (CI-asserted, I9), inbound `X-Accel-*`/serve-token
  stripping, kTLS `ssl_conf_command` (zero-copy WITH encryption), and `/cas/`→404
  for public requests (no hash-only byte path).

## Verified vs deployment-only
- **Verified on the real toolchain:** the entire decision path (resolve, mint,
  verify, I8 gate, I9 authorize-then-resolve, single-use/expiry/tamper rejection),
  the FFI HMAC against `openssl`, and the brain↔edge cross-language token contract.
- **Deployment-only (no nginx in this env):** the OpenResty wiring itself
  (`ngx.exec`, the internal location, sendfile, mlcache, kTLS). Structured to the
  real APIs and agentzh's constraints; the jit.dump "decision path stays compiled"
  gate (agentzh's week-one spike) runs when OpenResty is present.

## VFS materialization — designed, next to build
spec/05's model (extracted): git tree objects as the manifest; lazy fault-in
(trees on `readdir`/`getattr`, blobs on `read`); sparse profiles (path globs);
git-index-style dirstate (`status` = O(changed files)); batched cold-subtree fetch
multiplexed over one HTTP/2 conn (~1 RTT); checkout-first v1 then FUSE fast-follow.
The brain's `resolve-path` + serve-token already provide the per-blob fetch
primitive the mount needs; the mount client (dirstate + fault-in + sparse) is the
next build.

## Suite (all green)
```
typecheck / -negative / -lore     OK
read        15/15   read-edge  5/5
t1 8/8   t1-kill 9/9   t2 15/15   t3 8/8
```

## Open / deferred
- mlcache/jit.dump perf validation needs OpenResty (deployment).
- Per docs 31, the synthesis floated an OCaml brain for the hot path; we kept
  shen-lua (the keystone choice; the decision logic is table-lookups + one FFI
  HMAC, exactly what JITs well). Revisit only if a jit.dump spike shows NYI.
- VFS mount client (dirstate, fault-in, sparse profiles) — next phase.
- ACL is passed to `read-decide` as a boolean `allow?`; wiring the decidable
  Datalog matcher (spec/03) as the producer of that boolean is its own phase.
