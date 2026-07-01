# keel — Product Requirements Document

> **Provisional codename `keel`** (the structural spine a hull is built on). Repo name is
> the reader's to pick; this doc uses `keel` throughout as a placeholder.

**Status:** Draft PRD for a **new, separate repository**. `keel` is a lightweight
extraction of the proven core from `mvfs` (see `../dvcs-vfs/spec/`) — the fenced
content-addressed log + Datalog authz + zero-copy read tier — with **no** external
services in the base configuration. It ships **two deployment profiles from one codebase**,
selected by config:

- **Profile A — Standalone single-node engine.** OpenResty + shen-lua + Datalog + LMDB +
  filesystem CAS. Zero external dependencies. An embeddable, correctness-proven
  content-addressed store + policy engine + authorized zero-copy read tier in one process.
- **Profile B — Light coordinator + S3.** The same node acts as the **fenced coordinator**
  (LMDB is the fence/log/oplog) for a fleet of stateless remote workers; **S3** is the data
  plane. Replaces a distributed log (DynamoDB / S3-conditional-writes) with one fast local
  LMDB fence.

The **brain, the fence, and the policy engine are identical** across profiles. A and B
differ only in which boundary backends are wired (CAS = fs vs S3) and whether the HTTP
coordinator API is exposed to remote clients.

---

## 1. Summary (TL;DR)

`keel` is a single-node, single-writer, **proven** coordination + storage engine. The novel
claim of the parent system — *"illegal states are unconstructible; every land is fenced,
totally-ordered, exactly-once, durable-before-ack"* — is preserved, but the entire
distributed substrate collapses into **one LMDB write transaction**. Reads are served
lockless and zero-copy by OpenResty; the decision to serve is made by a pure Shen brain
compiled to LuaJIT and embedded in the nginx workers.

The insight that makes this coherent: **an LMDB write transaction *is* the fence.** It is
serialized (single writer), atomic (copy-on-write B+tree, no torn writes), durable
(`fsync` on commit → durability-before-ack), and it lets you do read-check-then-append with
an epoch CAS in one atomic step — which is exactly the land kernel's linearization point. No
consensus protocol, no external coordinator, no S3 conditional write per land.

What you give up vs. the full `mvfs`: **automatic 3-way merge** (conflicts are *rejected*,
resolve-and-resubmit — no pijul/git merge oracle) and **multi-writer / HA** (single node;
failover is a warm standby, not distributed consensus). Everything else — the fenced kernel,
Datalog ACL, exactly-once effects, time-travel, O(1) fork, zero-copy authorized serving —
carries over.

---

## 2. Problem & motivation

The full `mvfs` design is powerful but heavy to operate at the edges: pijul/git as merge
oracles (external processes), the durable-execution VM tier (Firecracker/composefs), and a
distributed fenced log for multi-node. Many real needs want only the **load-bearing middle**:

- A **fast, correct coordination primitive** — a fenced, ordered, durable log with leases
  and exactly-once effects — that runs as *one process* you can drop next to an app.
- A **policy-authorized zero-copy content server** — decide in a proven brain, serve bytes
  with the kernel — without standing up a database, a cache service, and a coordinator.
- For fleets (e.g. the crash-prone PDF/zip batch workload in `../dvcs-vfs/spec/09`): a
  **coordinator** that is far cheaper and lower-latency than an S3-conditional-write or
  DynamoDB fence on the critical path (thousands of lands per job), accepting a
  single-coordinator model.

`keel` is that middle, extracted, with the two profiles that cover "embedded/standalone" and
"coordinator for a stateless fleet" from **one build**.

---

## 3. Goals & non-goals

### Goals
1. **One codebase, two profiles** (A standalone, B coordinator+S3), selected by config; the
   proven core is byte-identical between them.
2. **Zero external services in Profile A.** A single OpenResty process + LMDB file(s) +
   a blob directory. `docker run` and it works.
3. **Preserve the invariants** the parent proves: I1–I5, I7, I8, I9, and I6 (Datalog
   acl-version), plus the P-D2 exactly-once-effects control plane. (See §8.)
4. **The brain stays pure Shen** (sequent-typed decisions + Datalog); LMDB/fs/S3/HMAC are
   the trusted shell behind one boundary module.
5. **Zero-copy serving** (OpenResty `sendfile`; bytes never enter the Lua VM).
6. **A small, versioned HTTP API** for the coordinator (Profile B) and local tooling.
7. **Verification posture inherited from `mvfs`**: `tc +` typecheck, negative typecheck of
   illegal programs, and fault tests (crash/SIGKILL/split-brain-takeover) — but single-node.

### Non-goals (explicit — see §17 for the full out-of-scope list)
- **No automatic merge.** Conflicts are rejected (land-point recheck); the user
  resolves-and-resubmits. `git-merge` may be added later as an *optional* exec backend.
- **No multi-writer / distributed consensus.** Single node, single writer. HA is a warm
  standby (§13.3), not Raft/Paxos.
- **No VM memory snapshots (P-D1), Firecracker, composefs, CRIU.** Out of weight class.
- **No large-object storage in LMDB.** Blobs live on fs (A) or S3 (B); LMDB holds
  metadata/log/oplog/cache only.

---

## 4. Users & use cases

| User | Use case | Profile |
|---|---|---|
| App developer | Embed a proven fenced log + policy-authorized content store beside a single-node app; no DB to run | **A** |
| Platform team | A cheap, fast **coordinator** for a stateless render/compute fleet (leases, exactly-once effects, progress log); S3 holds artifacts | **B** |
| Data/ML pipeline | Durable batch jobs (e.g. PDF render → zip) that must resume after crashes without redoing work or double-delivering | **B** (see `../dvcs-vfs/spec/09`) |
| Security-sensitive service | Authorized zero-copy file serving where the *decision* is a proven brain, not ad-hoc middleware | **A** or **B** |

---

## 5. The two profiles, from one codebase

```
                         ┌─────────────────────── keel core (identical) ──────────────────────┐
                         │  Shen brain (compiled → LuaJIT):                                     │
                         │    land-decide · read-decide · acl-decide (Datalog) ·               │
                         │    mint/verify serve-token · durable-effect-decide                  │
                         │  LMDB fence: log · meta(epoch,seq,acl_version) · leases · oplog ·    │
                         │    refs/resolve · cache                                              │
                         └──────────────┬───────────────────────────────────┬─────────────────┘
                                        │ CAS backend = fs                   │ CAS backend = s3
        PROFILE A (standalone)          ▼                                    ▼          PROFILE B (coordinator + S3)
   ┌──────────────────────────────────────────┐          ┌──────────────────────────────────────────────────┐
   │ OpenResty single process                  │          │ OpenResty coordinator node                        │
   │  /land /read /cas(internal) /effect ...    │          │  /lease /land /effect /checkpoint /recover /status │
   │  blobs on local fs (hash→path)             │          │  LMDB = the fence (local to coordinator)          │
   │  clients = local tools / same host         │          │  artifacts in S3; delivery via presigned/CDN      │
   └──────────────────────────────────────────┘          │  clients = remote stateless workers (Fargate…)     │
                                                          └──────────────────────────────────────────────────┘
```

**What differs (config-only):**

| Axis | Profile A | Profile B |
|---|---|---|
| `profile` | `standalone` | `coordinator` |
| CAS backend (`cas.backend`) | `fs` | `s3` (+ optional local fs read-through cache) |
| Client model | local / same-host tools | remote HTTP workers |
| Artifact delivery | OpenResty `/read`→`/cas` sendfile | S3 presigned URL / CloudFront (OpenResty `/read` optional) |
| HA | optional standby | standby coordinator + LMDB shipping (§13.3) |

**What is identical:** the Shen brain, the LMDB schema and the fence transaction, the Datalog
policy engine, the HTTP API shapes, the serve-token contract, the oplog/exactly-once logic.

---

## 6. Architecture

### 6.1 Proven brain / trusted shell (unchanged principle)

Pure Shen *decides*; LMDB / fs / S3 / libcrypto *do*. One boundary module (`boundary.shen`,
declaring the `lua.call` externals) is the only place effects cross in. The brain functions
are total and sequent-typed; the four illegal programs (land-without-lease,
land-without-admission, base-without-admission, forge-a-witness) must fail `tc +` (I7 type
half). This is the same posture proven in `mvfs`.

### 6.2 shen-lua

Shen compiles to Lua; the compiled image runs on **LuaJIT 2.1 (GC64)** — the same VM
OpenResty embeds, so **the brain runs *inside* the nginx workers with no IPC**. The brain
exports (via a thin `brain.lua` shim over the compiled Shen):

| Brain function | Signature (informal) | Purpose |
|---|---|---|
| `land-decide` | witness × change → admit \| reject(reason) | I3 dedup, MF-1 deps, MF-3 land-point recheck, I7 fence check — the pure decision; the Lua shell performs the LMDB write txn |
| `read-decide` | principal × commit × path × basis → allow(hash) \| deny | I8 as-of gate + authz + resolve-to-hash (server-side; client hash never trusted) |
| `acl-decide` | principal × path × action × acl-version → allow \| deny | Datalog (soa32), longest-prefix / deny-wins (I6) |
| `mint-token` / `verify-token` | principal × hash × ttl → HMAC token / bool | I9 single-use serve capability |
| `durable-effect-decide` | witness × worker × effect-key → run \| replay(outcome) | P-D2 exactly-once (intent→outcome) |
| `lease-decide` | resource × holder × now → grant(epoch) \| deny | fenced lease acquisition / takeover |

The brain reads state through pure "oracle" inputs the shell fetches from LMDB (current
epoch, seq, tree, oplog entry) and returns a decision; the shell then commits the effect in
one LMDB write txn. This keeps the decision provable and the mutation auditable.

### 6.3 OpenResty runtime

```nginx
# nginx.conf (sketch)
worker_processes auto;
events { worker_connections 16384; }
http {
    sendfile on; tcp_nopush on; aio threads; directio 4m;
    open_file_cache max=200000 inactive=300s;   # CAS files are immutable → long cache

    lua_package_path "/opt/keel/?.lua;;";
    # NOTE: no lua_shared_dict / mlcache needed for state — LMDB is the shared store,
    # mmap'd across all workers, lockless MVCC reads, ACID, no size cap, no serialization.
    lua_shared_dict keel_lock 16m;   # lua-resty-lock: admit one lander at a time

    init_by_lua_block        { require("keel.boot").init() }        -- load Shen image, open LMDB env
    init_worker_by_lua_block { require("keel.boot").worker() }      -- per-worker txn handles

    server {
        listen 443 ssl http2;   # kTLS where available for zero-copy WITH encryption
        # ---- read path: brain decides, nginx serves ----
        location /read {
            access_by_lua_block  { require("keel.read").handle() }  -- I8 basis, authz, resolve, mint token
            # on allow: ngx.exec("/cas") with the server-derived hash
        }
        location /cas {                     # INTERNAL only
            internal;
            content_by_lua_block { require("keel.cas").serve() }    -- resolves hash→file, sendfile (fs) OR 302 presign (s3)
        }
        # ---- write / control path (single-writer LMDB txn) ----
        location /land       { content_by_lua_block { require("keel.land").handle() } }
        location /lease      { content_by_lua_block { require("keel.lease").handle() } }
        location /effect     { content_by_lua_block { require("keel.effect").handle() } }
        location /checkpoint { content_by_lua_block { require("keel.checkpoint").handle() } }
        location /recover    { content_by_lua_block { require("keel.recover").handle() } }
        location /status     { content_by_lua_block { require("keel.status").handle() } }
    }
}
```

**Writer serialization.** A land takes a short LMDB **write** transaction. LMDB permits one
writer process-wide, so concurrent lands would serialize inside LMDB — which is *correct*
(the land queue is a queue) but would occupy nginx workers while they block. We therefore
admit one lander at a time with `lua-resty-lock` (`keel_lock`) and keep the LMDB write txn
tiny (read epoch/seq → validate via brain → append entry → bump seq → commit+fsync). Reads
never take the write lock: they use lockless MVCC **read** txns.

**Why LMDB replaces the mlcache/shdict stack.** In `mvfs`'s OpenResty tier, cross-worker
state lived in `lua_shared_dict` + `lua-resty-mlcache` (serialized into shmem, size-capped).
Here LMDB is *already* a shared, mmap'd, ACID store visible to every worker with lockless
reads and no serialization — so it is simultaneously the source of truth **and** the cache.
This is a genuine simplification and a differentiator.

### 6.4 LMDB schema (the fence + log + oplog + cache)

Single environment, several named DBIs:

| DBI | Key | Value | Role / invariant |
|---|---|---|---|
| `meta` | fixed keys | `epoch` (u64), `seq`/HEAD (u64), `acl_version` (u64), `format_version` | the fence counters (I7), the trunk head (I1) |
| `log` | `seq` (big-endian u64) | landed-entry: `{seq, prev_checksum, checksum, change_id, author, ts, kind, payload_ref, acl_version}` | total order (I2), checksum chain (I5) |
| `refs` | logical `(commit,path)` or name | content hash | resolve (read §6.2); the tree/index |
| `leases` | resource / worker id | `{epoch, holder, expiry}` | per-resource fence (I7) |
| `oplog` | `(worker, effect_key)` | `{state: intent\|outcome, result_ref, epoch}` | exactly-once effects (P-D2) |
| `acl` | path / principal | materialized policy datoms | Datalog input; `acl_version` fence (I6) |
| `cache` | content-addressed key | decision | optional; LMDB reads are already fast |

**The fence, in full (the entire novel core):**

```lua
-- land: the linearization point is txn:commit()
local txn = env:begin_write()                 -- serialized: LMDB single writer
  local cur_epoch = meta_get(txn, "epoch")
  if witness.epoch ~= cur_epoch then return reject("stale-fence") end   -- I7
  if log_has_change(txn, change.change_id)  then return ok(idempotent) end -- I3
  if not deps_satisfied(txn, change)        then return reject("deps")  end -- MF-1
  if conflict_at_head(txn, change)          then return reject("conflict") end -- MF-3
  local seq  = meta_get(txn, "seq") + 1
  local prev = log_checksum(txn, seq-1)
  local entry = build_entry(seq, prev, change)  -- checksum = H(prev || payload) → I5
  log_put(txn, seq, entry)
  meta_put(txn, "seq", seq)
txn:commit()                                  -- fsync (default) → I4 durability-before-ack
return ok(entry)
```

LMDB is **crash-proof by construction** (copy-on-write, double meta page; the DB is always
consistent on reopen — no WAL, no fsck). So `recover!` collapses to: reopen LMDB (already
consistent) + reconcile the CAS (ensure every `payload_ref` in `log` exists in fs/S3;
fail-closed if a referenced blob is missing). There is no pijul-pristine to sweep — **LMDB is
the single source of truth.**

### 6.5 Datalog policy engine

ACL/policy is the shen-lua native soa32 Datalog engine, in-process. Policy is landed through
the log (policy-as-data), materialized into the `acl` DBI, and versioned by `acl_version`
(I6): a read pins `(seq, acl_version)` as its as-of basis and is decided at that version.
Longest-prefix, deny-wins, default-deny, group membership — as proven in `mvfs`'s `acl`/
`policy` suites. The interpreted decision is the runtime oracle; any partial-eval'd hot-path
matcher is conformance-tested against it (D7).

### 6.6 CAS backend (the pluggable axis that distinguishes A from B)

`boundary.shen` declares a `cas-backend` with two implementations:

- **`fs` (Profile A):** blobs are files at `blobs/aa/bb/<hash>`. Writes are write-temp +
  fsync + atomic rename. Reads are `open` + `sendfile` (kernel zero-copy). Integrity: the
  path *is* the hash (I5); verify on ingest.
- **`s3` (Profile B):** blobs are S3 objects keyed by hash (or by the app's existing key,
  with `(key, version-id, hash)` recorded as the outcome — see spec/09). Serve = **302 to a
  presigned URL** (or CloudFront), so bytes never transit the coordinator. Optional local fs
  **read-through cache** for hot blobs.

The brain is identical; only the shell backend changes. Both satisfy I5 (hash = integrity)
and I9 (authorize before yielding a URL/fd).

---

## 7. Profile B — coordinator specifics

- **The coordinator** is one OpenResty+Shen+**LMDB** node. LMDB is local to it (the fence
  can't be sharded without consensus — that's the single-node boundary).
- **Workers** (e.g. Fargate one-shot tasks) are **stateless HTTP clients**: `POST /lease`
  (acquire, get epoch/witness), then `POST /effect` (exactly-once wrapper), `POST /land`
  (record an S3 ref as a landed outcome), `POST /checkpoint`, `POST /recover` on restart.
- **Dispatch** is a queue in front of the workers (SQS standard is sufficient — the fence
  makes at-least-once delivery safe; see spec/09 §2). The coordinator does not need the
  queue; the workers do.
- **Delivery** of artifacts (PDF, zip) is direct S3 (presigned / CDN). The coordinator only
  arbitrates and records; it does not stream artifacts.
- **Exactly-once + resumable multipart** (the PDF/zip case): the oplog records the multipart
  `UploadId` and a part cursor; `CompleteMultipartUpload` is a fenced `/effect` so only the
  epoch-current worker completes; the zombie is rejected (spec/09 §5).

---

## 8. Invariants preserved / dropped

| Inv | Statement | In `keel`? | How |
|---|---|---|---|
| I1 | linear trunk | ✅ | `meta.seq` monotone; one log |
| I2 | total land order | ✅ | `log` keyed by contiguous `seq` |
| I3 | at-most-once (idempotency key) | ✅ | `change_id` check in the write txn |
| I4 | no lost acked land | ✅ | LMDB `fsync` on commit *before* the HTTP ack |
| I5 | content integrity | ✅ | checksum-chained log + hash-addressed blobs |
| I6 | ACL/acl-version fence | ✅ | Datalog + `acl_version` in `meta`, pinned by basis |
| I7 | fenced authority | ✅ | epoch in `meta`/`leases`, CAS in the write txn; witness type (compile-time half) |
| I8 | read-your-writes / monotonic | ✅ | as-of basis `(seq, acl_version)` gate on `/read` |
| I9 | authz on every byte path | ✅ | HMAC single-use serve token (fs) / presign gate (s3) |
| I10 | snapshot confidentiality | n/a | only relevant to memory snapshots (out of scope) |
| I11 | restore provenance | n/a | as above |
| — | **sound automatic merge** | ❌ **dropped** | conflicts rejected (MF-3), resolve-and-resubmit |
| — | **multi-writer / HA** | ❌ **dropped** | single-node LMDB fence; warm standby only |

---

## 9. HTTP API (v1)

All bodies JSON; auth via a principal established by an upstream auth phase (never a client
header). Errors are uniform (`403` fail-closed, `409` conflict/fence, `412` idempotent-noop).

| Method + path | Body | Returns | Notes |
|---|---|---|---|
| `POST /lease` | `{resource, holder, ttl}` | `{epoch, witness}` | acquire/renew/takeover; bumps epoch on takeover (I7) |
| `POST /land` | `{witness, change_id, deps, payload_ref, kind}` | `{seq, checksum}` \| `409/412` | the fenced append (§6.4) |
| `GET  /read` | query `commit,path` + basis headers | `302`/stream \| `403`/`503` | I8 gate, authz, resolve, serve (§6.3/§6.6) |
| `POST /effect` | `{witness, worker, effect_key, intent}` | `{state, outcome}` | exactly-once (P-D2); replay if already outcome'd |
| `POST /checkpoint` | `{witness, worker, refs}` | `{seq}` | fenced land of a worker's state refs |
| `POST /recover` | `{worker}` | `{cursor, done[]}` | replay oplog; what's done / where to resume |
| `GET  /status` | — | `{seq, epoch, acl_version, health}` | the applied basis, for clients & LB checks |

A thin CLI (`keel land|read|lease|effect|status …`) wraps these for Profile A / local use.

---

## 10. Configuration (selects A vs B)

```toml
# keel.toml
profile        = "standalone"     # "standalone" (A) | "coordinator" (B)

[lmdb]
path           = "/var/lib/keel/db"
mapsize_gb     = 64
sync           = true             # I4: fsync on commit for the log (never disable for `log`)

[cas]
backend        = "fs"            # "fs" (A) | "s3" (B)
fs_root        = "/var/lib/keel/blobs"
# --- s3 (Profile B) ---
# s3_bucket    = "keel-artifacts"
# s3_region    = "us-east-1"
# s3_presign_ttl = 300
# local_cache  = "/var/lib/keel/cache"   # optional read-through

[serve]
token_key_env  = "KEEL_SERVE_KEY"        # HMAC key for serve tokens (I9)
ktls           = true

[lease]
default_ttl    = 30
```

Flipping `profile` + `cas.backend` is the whole difference between A and B. The binary,
the Shen image, and the LMDB schema are the same.

---

## 11. Repo layout (the new repository)

```
keel/
  README.md
  keel.toml.example
  src/                      # the Shen brain (typechecked)
    boundary.shen           # the one audited effect boundary (lua.call externals)
    types.shen              # sequent types: witness, landed, basis, decision …
    land.shen  fence.shen   # the fenced land FSM (illegal states unconstructible)
    read.shen  token.shen   # as-of basis, serve tokens
    acl.shen   policy.shen  # Datalog authz (soa32), policy-as-data, acl-version
    effect.shen oplog.shen  # exactly-once effects (P-D2)
    checksum.shen scalars.shen
  lua/                      # the trusted shell (OpenResty handlers + FFI)
    boot.lua                # init_by_lua / init_worker_by_lua: load Shen image, open LMDB
    brain.lua               # shim over the compiled Shen image
    lmdb.lua                # FFI binding to liblmdb (the fence txns)
    land.lua read.lua cas.lua lease.lua effect.lua checkpoint.lua recover.lua status.lua
    cas_fs.lua cas_s3.lua   # the two CAS backends
    hmac.lua hash.lua       # FFI: libcrypto HMAC, BLAKE3/SHA256
  nginx/nginx.conf          # the OpenResty config (profile-templated)
  cli/keel                  # thin CLI over the HTTP API
  deploy/Dockerfile         # single-image build (OpenResty + LuaJIT/GC64 + liblmdb + Shen image)
  test/
    illegal.shen            # the 4 non-constructible programs (typecheck-negative)
    *.sh                    # fault tests: crash, SIGKILL@commit-window, lease-takeover, exactly-once
  scripts/bootstrap-toolchain.sh
  Makefile                  # typecheck | typecheck-negative | test | <suites> | image
```

---

## 12. Build & toolchain

- **LuaJIT 2.1 (GC64)** + **shen-lua** (compile the Shen brain to a Lua image at build time).
- **OpenResty** (nginx + the LuaJIT above; verify `resty -v`).
- **liblmdb** (FFI-bound; `lightningmdb`-style binding or hand-rolled FFI).
- **libcrypto** (HMAC for I9; SHA256/BLAKE3 for content addressing).
- Build produces a **single Docker image** (Profile A runs it as-is; Profile B runs the same
  image with `profile="coordinator"` + S3 config).

Inherited verification targets (single-node):
- `make typecheck` — the brain typechecks under Shen `tc +`.
- `make typecheck-negative` — the 4 illegal programs are **rejected** (I7 type half).
- `make test` — smoke: `lease → land → read` round-trips through LMDB + fs CAS.
- `make crash sigkill takeover exactly-once` — fault tests (§16).

---

## 13. Deployment

### 13.1 Profile A
`docker run -v keeldata:/var/lib/keel keel` → one process, one LMDB file, one blob dir.
No other services. Back it up by snapshotting the volume (LMDB is always crash-consistent).

### 13.2 Profile B
The coordinator image with `profile="coordinator"`, `cas.backend="s3"`, IAM for the bucket.
Front the workers with SQS; workers call the coordinator's HTTP API. Artifacts delivered via
presigned S3 / CloudFront.

### 13.3 HA & the SPOF (honest)
The fence is a **single-node** LMDB writer — that is the architectural boundary and the SPOF.
Mitigations, in increasing order of effort:
1. **Warm standby** + fast failover: ship the LMDB env to a standby (periodic `mdb_copy` or
   block-level replication of the volume); on primary loss, promote. **Bounded data loss =
   the replication lag** — state this SLO explicitly; do **not** claim zero-RPO.
2. **Synchronous log shipping** (stream each committed entry to the standby before ack) for
   RPO≈0 on the *log*, accepting the latency cost. This is the ceiling of what a single-writer
   design should attempt; true multi-writer HA means adopting the distributed backend
   (DynamoDB/consensus) from the full `mvfs` — out of scope for `keel`.

The PRD's position: `keel` is **deliberately single-writer**; if you need multi-writer HA,
you have outgrown `keel` and should use the full distributed backend. This boundary must be
stated in the product README so no one deploys `keel` expecting Raft.

---

## 14. Performance targets

- **Read decision + serve:** brain decision in-worker (no IPC) + LMDB lockless read (mmap,
  ~hundreds of ns) + `sendfile`. Target p99 decision < 1 ms; bytes at line rate (kTLS).
- **Land (write txn):** read epoch/seq + validate + append + `fsync`. Target p99 < a few ms,
  dominated by `fsync`; batchable (group-commit) if land rate rises.
- **Lease/effect:** one small write txn each; same envelope as land.
- **Cache:** none needed as a separate tier — LMDB mmap *is* the cache (§6.3).

A gating spike (inherited S0): confirm the read decision path **stays JIT-compiled** under
`jit.dump` on the OpenResty host.

---

## 15. Security

- **Authz on every byte** (I9): `/read` authorizes (Datalog, at the pinned `acl_version`)
  and only then yields a **single-use, expiring HMAC serve token** (fs) or a short-TTL
  presigned URL (s3). No content reachable by hash alone; `/cas` is `internal`.
- **Principal** is set by an upstream auth phase, never a client header.
- **Serve key** from env (`KEEL_SERVE_KEY`), rotatable.
- **Fence** prevents a stale/partitioned actor from landing or completing effects (I7).
- **Integrity** (I5): every blob verified against its hash on ingest; the log is
  checksum-chained; tampering is detected on read/recover.

---

## 16. Verification strategy

Inherit the `mvfs` three-pillar posture, single-node:
1. **Type-level:** `tc +` on the brain; `typecheck-negative` proves the 4 illegal land
   programs are unconstructible (I7 compile-time half).
2. **Runtime fault tests** (the moat):
   - **crash / `SIGKILL` at the commit window** — LMDB reopens consistent; an un-acked land
     is absent, an acked land is present (I4); `recover` reconciles CAS.
   - **lease takeover** — a new holder bumps the epoch; the old witness is fenced out (I7);
     no split-brain land.
   - **exactly-once effect** — a side effect fires once across retries; the oplog replays the
     recorded outcome (P-D2).
   - **integrity** — a tampered `log` entry / blob is caught by the chain / hash (I5).
3. **Conformance:** any partial-eval'd ACL matcher is diffed against the interpreted Datalog
   oracle in CI (D7).

Because there is no pijul/git and no VM, **all of this is CI-able in a plain sandbox** — a
stronger position than the full `mvfs`, whose merge/durable tests need pijul / a privileged
host.

---

## 17. Explicitly out of scope

- Automatic 3-way / patch merge (pijul/git). Conflicts → reject + resubmit. *(Optional
  future: `git-merge` exec backend.)*
- Multi-writer, distributed consensus, cross-region HA with RPO=0. *(Future: adopt the
  `mvfs` distributed backend.)*
- VM memory snapshots (P-D1), Firecracker, gVisor, composefs, CRIU.
- Large blobs in LMDB (blobs live on fs/S3).
- A rich VCS product surface (stacks, restack-on-land, rich CLI) — `keel` is the engine, not
  the DVCS UX (that stays in `mvfs`).

---

## 18. Milestones

| # | Milestone | Exit criteria |
|---|---|---|
| M0 | Repo + toolchain + boundary skeleton | `bootstrap-toolchain.sh`; `tc +` on an empty brain; Docker image builds |
| M1 | The fence on LMDB | `land.lua`+`fence.shen`; the write-txn CAS (§6.4); `typecheck-negative` green; crash + SIGKILL fault tests green |
| M2 | Read tier | `/read`→`/cas` sendfile (fs); as-of basis (I8); serve tokens (I9); `read-edge` cross-lang verify |
| M3 | Datalog authz | `acl`/`policy` lands; `acl_version` fence (I6); conformance diff |
| M4 | Exactly-once effects | `/effect`, oplog, `/checkpoint`, `/recover`; exactly-once fault test (P-D2) |
| M5 | Profile B | `cas_s3.lua` (presign serve); coordinator API for remote workers; resumable multipart (spec/09 §5); lease-takeover fault test |
| M6 | Package | single image, `keel.toml` profiles, README with the SPOF/HA boundary stated, CLI |

M0–M4 deliver **Profile A** fully. M5 adds **Profile B** with no change to the core.

---

## 19. Risks & open questions

- **SPOF / HA expectations (highest).** Must be stated loudly (§13.3) or someone deploys
  `keel` as if it were HA. *Open:* ship warm-standby log-shipping in v1, or document-only?
- **Writer occupancy under load.** If land rate is high, the single writer + `fsync` is the
  bottleneck. *Mitigation:* group-commit; *open:* is group-commit in v1 scope?
- **LMDB `mapsize`** is set at open and caps DB growth (metadata only, so bounded, but must
  be sized). *Open:* auto-grow policy.
- **Presign vs proxy (Profile B).** Presigned URLs leak object identity/lifetime to the
  client; some tenancies want the coordinator to proxy instead (losing zero-copy). *Open:*
  offer both `serve.mode = presign|proxy`?
- **shen-lua image build** in CI (compile Shen → Lua reproducibly, pin the port). *Open:*
  vendor the shen-lua toolchain in-repo?
- **Name.** `keel` is provisional.

---

## 20. Relationship to `mvfs`

`keel` is the **proven middle** of `mvfs` extracted and made dependency-light. It shares the
architecture (proven brain / trusted shell), the invariants, the verification posture, and
much of the Shen source (the land FSM, Datalog authz, serve tokens, oplog). It **omits** the
two heaviest pillars (the pijul merge oracle and the distributed/VM substrate). A team can
start on `keel` (single-node, embeddable, fully CI-verifiable) and graduate to `mvfs` when
they need sound automatic merge or multi-writer HA — the brain and the contracts carry over.
Normative source for the shared concepts: `../dvcs-vfs/spec/` (`00` keystone; `02` land
kernel; `03` policy; `04` read boundary; `08` durable execution; `09` Fargate+S3).
