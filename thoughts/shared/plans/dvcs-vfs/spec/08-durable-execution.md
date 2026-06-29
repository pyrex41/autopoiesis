# 08 — Durable execution tier (normative)

**Status:** Revised authoritative design, incorporating the doc-42 panel review
(Aphyr/Ptacek/Torvalds). Supersedes the exploration in `../41` and its verdict in
`../42`. Enforces I3/I4/I5/I7 (reused from the land kernel) plus **I10** (snapshot
confidentiality) and **I11** (restore provenance), defined in `00-overview.md §4`.

## 0. Thesis and scope

mvfs already provides the *versioning spine* of a durable-execution platform —
content-addressed state, O(1) fork, time-travel, replication — and the *one
primitive the field works hardest to get right*: an exactly-once, split-brain-proof
**fenced land** (lease-epoch CAS + idempotency-key; proven by T1/T2/T1-kill). What it
lacks is **live-state capture** (memory, registers, fds). This tier adds that by
*gluing off-the-shelf runtimes* (composefs, Firecracker/gVisor/CRIU, KVM, overlayfs)
under the fenced-land kernel — **building only the moat**, not the substrate.

**Build vs reuse (normative — do not reinvent):**

| Concern | Decision |
|---|---|
| Rootfs image / per-file dedup / integrity | **composefs** (EROFS metadata + content-addressed object store + fs-verity). **Do NOT** build squashfs-per-revision. |
| Read-only base + writable layer in the I/O path | **in-kernel EROFS + overlayfs. NO FUSE under a live rootfs** (FUSE only for one-time materialize; inside a VM the guest sees a block device — moot). |
| Memory snapshot / COW fork / hypervisor | **off-the-shelf**: Firecracker (default), gVisor (trusted first-party Python/ML only), CRIU (last resort), KVM. |
| **Overlay-delta → CAS serializer** | **BUILD** (the real new component — §3). |
| **Fenced 3-artifact checkpoint commit** | **BUILD** on the existing fence (§2) — the moat. |
| Lineage / O(1) fork / time-travel | **already have** (pijul/CAS) + thin extension (§7). |
| **Intent→outcome oplog + egress capability** | **BUILD** (shape from Restate/Temporal; binding to *our* fence is novel — §6). |
| Deterministic replay | off-the-shelf / defer; WASM-only (P-D3). |

## 1. Architecture

A **worker** is a trunk lineage. Its state is split into artifacts, each
content-addressed and landed:

```
rootfs:  composefs base (digest = a trunk revision's tree)   ── immutable, fs-verity, page-cache-shared
         + kernel overlayfs upper (mutable scratch)          ── captured as the rootfs DELTA
memory:  Firecracker vmstate + guest-memory file (P-D1)      ── per-tenant ENCRYPTED (I10)
oplog:   intent→outcome journal tail (effectful workers)     ── §6
```

**No FUSE in the live I/O path.** The base is an in-kernel EROFS/composefs mount; the
overlay is kernel overlayfs; reads/writes never cross into userspace. The VFS
(`05`) does the *one-time materialize* of the base only. Inside a Firecracker VM the
guest sees a virtio-block device, so the host-FS question disappears entirely.

### 1a. RULED DECISION — isolation runtime: Firecracker default, gVisor trusted-ML backend

**Ruling:** the P-D1 memory-snapshot runtime is **Firecracker by default**, with
**gVisor as a pluggable second backend** for trusted, first-party, large-memory ML/
Python workloads, and **CRIU only as a last resort** for bare processes (accepting the
TCP/GPU sharp edges). This is a **boundary-backend choice** (`vm-snapshot!`/`vm-restore!`,
§9), NOT foundational — both emit a content-addressed snapshot blob the *same* fenced
checkpoint kernel lands, so the platform can ship both. Decision applies only at P-D1;
P-D0 (rootfs) and P-D2 (effects) are runtime-agnostic.

**Why Firecracker is the default for THIS system (ranked):**
1. **Restore is the deciding case.** We content-address, land, replicate, and *restore*
   memory images; restore deserializes attacker-reachable state into the runtime.
   Firecracker's hardware-VMX boundary contains a malicious restored guest; gVisor's
   restore reconstitutes kernel objects **in-process** in the large Go Sentry the guest
   can reach — restore widens that surface more (panel doc 42, Ptacek S3). Firecracker is
   the security default for restoring attacker-influenceable snapshots.
2. **Restore latency 0.8–8 ms** (MAP_PRIVATE COW; Zeroboot 0.79 ms p50) vs gVisor's
   ~1–3.5 s p50 for ML-scale — 100–1000×, which also makes fork/fan-out cheap.
3. **CAS fit:** the mem file + MAP_PRIVATE COW *is* content-addressing-by-reference,
   mirroring our O(1) fork; the vmstate+mem blob is the cleanest thing to hash, encrypt
   per-tenant (I10), sign (I11), and land.

**When gVisor wins (the second backend):** trusted first-party large-memory ML/Python,
where its **background restore** (execute before memory finishes paging in — Modal's
13 s → 3.5 s Stable Diffusion cold start) is the win and snapshot provenance is fully
controlled (so the bigger TCB isn't exposed to hostile images); also where KVM/nested
virt is unavailable (gVisor Systrap needs no hardware virt). gVisor also virtualizes
time/RNG, giving marginally better baseline determinism.

**Flip condition:** make gVisor the *default* only if the platform is **single-tenant /
fully-trusted-code-only AND dominated by big-memory ML cold-starts** — then background
restore outweighs a VMX boundary you don't need.

## 2. Checkpoint = a fenced 3-artifact commit

A checkpoint lands ONE log entry referencing the (verified, durable) artifact hashes.
The land is the linearization point and the exactly-once *commit* (I7). Discipline,
generalizing doc-37's blob→log→apply:

1. **Quiesce the guest, take a consistent cut** (C4). Pause the vCPU, then **drain
   guest I/O** (`fsync` / virtio-blk drain) so the overlay upper reflects all writes,
   *then* capture overlay delta, *then* capture memory. "Pause = consistent" is FALSE
   for a writeback page cache — the drain step is mandatory.
2. **Capture + hash outside the lease** (C3). Multi-GB fsync cannot block a short
   lease. Capture artifacts, compute **our** content hash over each (never trust the
   runtime's filename/hash), fsync each in CAS at the stated **durability width**.
3. **Verify-before-append** (C1): re-hash every artifact; only then build the entry.
4. **Publish under the lease**: a tiny fenced append (epoch re-check → CAS → fsync)
   records the verified hashes + provenance signature (§4). This is the commit.
5. **Ack** only after the append is durable; the worker may resume.

**Durability granularity (C6, honesty about I4).** A memory image is **not** derivable
from the log (unlike the pijul pristine, which `recover!` rebuilds). Therefore I4
holds only at the granularity of the **newest fully-verifiable checkpoint**: every
referenced artifact must be replicated to the durability width *before* the checkpoint
acks; on recovery, `recover!` falls back to the newest checkpoint whose every artifact
re-verifies and **reports the gap**. The platform promises durability at *that*
granularity — not "any landed seq is restorable."

**Pin runtime + CPU identity (C7).** The entry records Firecracker/gVisor/CRIU
version, guest kernel, and CPU-feature mask; restore refuses on mismatch.

## 3. The overlay-delta → CAS serializer (the real new component)

An overlayfs upper layer is **not** a plain file tree. Capturing it with the VFS's
plain-file `checkout!`/`switch!` **silently loses deletions** (a deleted file
reappears on restore). The serializer MUST handle:

- **whiteouts** (deletions): kernel overlayfs uses **char-device `0/0`** whiteouts →
  serialize as an explicit *deletion node* in the CAS tree (NOT an OCI `.wh.` file;
  convert if interoperating).
- **opaque directories** (`trusted.overlay.opaque="y"`) and **redirect xattrs**
  (renames) → explicit opaque/redirect nodes.
- **metadata copy-ups** and per-entry **xattr maps**.
- **normalization for stable hashing**: zero/normalize mtime, uid/gid, inode numbers,
  and hardlink identity, or the same content hashes differently every capture.

Represent the delta as a **CAS tree with whiteout/opaque node types + an xattr map per
entry** (preferred — dedups across checkpoints) rather than an opaque tar. Restore
reconstructs whiteouts/opaque markers faithfully. **Determinism is a discipline, not a
property**: a CI harness rebuilds the same tree twice and asserts bit-identical
composefs metadata + object set (parallel compression, mtimes, inodes, xattrs all
break it).

## 4. Restore — fenced, verified, provenance-checked

```
restore! : lease --> checkpoint-entry --> running-worker      (C5: lease-witness, at-most-once per epoch)
```

- **Fence `restore!`** (C5): it takes a `lease-witness` and is at-most-once per epoch,
  or a re-run recovery animates **two divergent live twins** (nondeterministic resume).
- **Verify-before-resume** (C2): re-hash every referenced artifact against the entry;
  fail closed on mismatch (the I9 discipline applied to checkpoint artifacts).
- **Provenance over the full chain (I11)**: verify the capture-component signature on
  the entry, and that the requesting principal owns the lineage, across base + all
  deltas (a fork inherits its ancestors' artifacts — taint is transitive). Trust is in
  the **fenced log entry**, never in the hash. A worker may only restore checkpoints in
  its own lineage; no "restore arbitrary hash."

## 5. Memory-snapshot confidentiality (I10) and the capture component

A memory image is the worst blob to content-address: cleartext secrets, possibly the
serve HMAC key, possibly other tenants' leaked bytes. Controls:

- **Per-tenant authenticated encryption at rest**: envelope (per-checkpoint DEK wrapped
  by a per-tenant KEK in a KMS/HSM); the CAS stores **ciphertext**, addressed by the
  ciphertext hash.
- **No cross-tenant dedup**: per-tenant keying makes identical plaintext hash
  differently across tenants — which is the *desired* outcome (cross-tenant page dedup
  is an **existence oracle**: same secret ⇒ same hash). **Intra-tenant** fork/COW
  sharing survives (same key ⇒ same ciphertext within the lineage) — that is where the
  O(1)-fork win actually is.
- **Distinct ACL resource-class + serve-token type** from code (`checkpoint:<lineage>`,
  default-deny). Code-read access must NOT implicitly grant "read this process's RAM."
  **Never CDN-cacheable.**
- **Crypto-shredding for revocation (S1)**: I6's acl-version fence cannot expunge revoked
  plaintext already inside an image. The only real revocation is key scope = revocation
  granularity: shred the KEK ⇒ dependent checkpoints become undecryptable. Plus a
  checkpoint **TTL / forced re-capture** — memory images are not eternal artifacts.
  *(I6 explicitly does NOT provide content-level revocation for memory snapshots.)*
- **Isolate the capture/restore component per tenant (S2)**: least-privilege, jailed;
  it reads guest memory as opaque bytes, never parses guest-controlled structures with
  privilege; its signing key never appears in a snapshot.
- **Firecracker is the security default (S3)** for restoring attacker-influenceable
  snapshots (hardware VMX, small TCB). gVisor only for fully-trusted first-party
  snapshots (its Go Sentry reconstructs kernel state in-process on restore — a bigger,
  softer target for a hostile image).

## 6. Effects and exactly-once (honest vocabulary, H1)

**The fence is exactly-once for the LOG APPEND, not for external effects.** A worker can
emit an effect, crash before landing the outcome, and a restored twin re-emits. That is
at-least-once + idempotency — the same as Temporal/Restate. End-to-end effect
exactly-once requires:

- **Intent→outcome oplog (E2, mandatory for effectful workers — a P-D1 prerequisite,
  not "later"):** land intent (with idempotency key) *before* the effect, land outcome
  *after*; on restore, skip effects that already have an outcome. Without it,
  restore-from-checkpoint re-fires every interval effect nondeterministically.
- **Idempotency keys carried to the external API**; an unavoidable replay window exists
  between durable-intent and durable-outcome that the external endpoint must dedupe.
- **Effect ownership is OUT-OF-GUEST (E1):** a restored twin has a live network stack
  the fence is not on. Route all guest egress through a proxy that requires a per-effect
  capability minted by the lease holder at epoch E; the proxy rejects tokens whose epoch
  < current durable epoch — auto-revoking a partitioned old leader's effects. (Or:
  tap-device only attached to the lease-holder + STONITH on epoch bump.) The fence alone
  does **not** enforce effect ownership.

## 7. Lineage, fork, and time-travel (H1)

- **Fork** = O(1) pijul/CAS lineage fork + Firecracker `MAP_PRIVATE` COW of the memory
  file — both structural sharing, **scoped within a tenant** (never cross-tenant, §5).
- **Time-travel = restore-and-rerun, NOT replay.** Restoring checkpoint N re-animates
  the captured *image*; subsequent execution is a fresh nondeterministic continuation
  (rdtsc/rdrand/scheduling). I5/as-of guarantee a byte-identical **image**, never a
  behaviorally-identical **worker**. Honest replay-of-history is P-D3 (WASM-only, or a
  determinizing hypervisor recording rdtsc/rdrand/syscalls).

## 8. Phasing

**P-D0 status: the BUILD half is implemented & verified** (`packages/mvfs/src/dx.shen`,
`make dx`, 12/12 on shen-lua/LuaJIT): the overlay-delta serializer (set/del nodes,
deterministic content-addressed delta), `checkpoint!` (fenced land of the delta, C1
store-before-append), and `restore-checkpoint!` (base + delta with **faithful
deletions** — a deleted file does NOT reappear; C2 verify-before-resume). The REUSE
half (composefs base image, kernel overlay mount) is deployment — not exercisable
without privileged mounts. A real-fix found in the spike: the delta must store working
content with `git hash-object -w` (not just hash it), or restore can't find the blob.

**T-D1 (durable-layer fault test) is implemented & green** (`make t-d1`, 10/10):
fail-closed on a lost delta blob *and* a lost content blob — with an **atomic
pre-flight** (`set-blobs-present?` verifies every referenced blob *before*
materializing, so a missing blob yields NO partial tree; a real fix the test forced),
deterministic delta (the CI bit-identity check), and entry tampering caught by the log
checksum chain (I5). **The composefs/overlay deployment backend exists as artifacts**
(`deploy/README.md`, `host/host-composefs.lua`, `src/host-composefs.shen`; boundary
verbs `composefs-build!`/`overlay-mount!`/`overlay-capture!`/`overlay-apply!` typecheck):
it reads a REAL overlay upper (char-device whiteouts → `del`, `trusted.overlay.*`
xattrs → `opaque`/`redirect`) and emits the same delta the kernel lands — runnable only
on a composefs-capable kernel with privileged mounts, not in CI.

- **P-D0 — rootfs-only durability (ship first; general, no determinism, no hypervisor).**
  composefs base (digest = a trunk revision) + kernel overlay upper, no FUSE in the I/O
  path. **Checkpoint = land(overlay-upper-delta)** via the §3 serializer with verify-
  before-append/resume and guest quiesce. Fork = lineage fork + fresh upper. This is the
  honest product: durable, forkable, versioned *disk* state for any process. Rootfs
  deltas get the snapshot ACL class if they can hold runtime credentials.
- **P-D1 — full memory snapshot (gate on I10/I11 + C1–C7).** Firecracker vmstate+memory,
  per-tenant encrypted, provenance-verified, fenced `restore!`. Guest disk = block
  device (simplifies the overlay questions).
- **P-D2 — exactly-once external effects (prerequisite for effectful workers). IMPLEMENTED
  & green** (`src/oplog.shen`, `make oplog`, 14/14): E2 intent→outcome journal on the
  fenced log (`land-intent!`/`land-outcome!`/`effect-status`/`should-emit?`/`outcome-of`
  — skip an effect whose outcome already landed; "pending" = the at-least-once re-attempt
  window the external endpoint must dedupe); E1 out-of-guest egress capability
  (`mint-egress` under leadership; `egress-ok?` admits iff HMAC valid AND token epoch ≥
  the log's current head fence — a STALE leader's token is rejected, so effect ownership
  is enforced outside the guest where the fence cannot reach). The actual egress *proxy*
  + the worker network path are deployment (P-D1-adjacent).
- **P-D3 — deterministic replay (optional).** WASM (Wasmtime det-mode) or a determinizing
  hypervisor only.

## 9. Boundary surface (sketch, all behind `00 §5.4`)

```
composefs-build! : tree-hash -> image-digest            (deterministic; CI bit-identity harness)
overlay-open!    : image-digest -> mount
overlay-capture! : mount -> upper-delta-hash            (§3 serializer: whiteouts/opaque/xattr, normalized)
overlay-apply!   : upper-delta-hash mount -> ok         (faithful whiteout reconstruction)
vm-snapshot!     : vm -> [vmstate-hash mem-hash]        (pause+quiesce; encrypt per-tenant; sign)
checkpoint!      : lease worker-id artifacts logpath -> landed   (verify-before-append; ≈ pland!)
restore!         : lease checkpoint-entry -> worker     (fenced, verify+provenance before resume)
egress-token     : lease-witness effect -> capability   (epoch-bound; E1)
```
`checkpoint!`/`restore!` are pure decision + a fenced land/verify, like `pland!`; the
capture/restore mechanics are audited host primitives (the isolated capture component).

## 10. Fault tests owed (Jepsen-style, analogous to T1/T2)

- **T-D1 torn memory artifact**: corrupt/truncate one page file (dm-flakey/charybdefs);
  assert verify-before-append refuses; post-commit corruption → `restore!` fails closed;
  `recover!` falls back to the newest verifiable checkpoint and reports the gap.
- **T-D2 split-brain effects under partition**: old leader (epoch E) still running with
  egress + new leader (E+1); assert with the egress capability the external endpoint sees
  exactly one effective delivery (and *without* it, two — the test must show the bug).
- **T-D3 non-idempotent restore / double-twin**: crash recovery mid-`restore!`, re-run;
  assert fenced `restore!` yields exactly one live twin; separately show two restores of N
  diverge (rdtsc) → proves restore-is-rerun-not-replay.

## 11. Invariants embodied
- **I3/I4/I5/I7** reused from the land kernel (`02`): checkpoint = a fenced, idempotent,
  content-integrity-checked, split-brain-proof land — with I4 at the durability-granularity
  of §2 (newest fully-verifiable checkpoint).
- **I10** (snapshot confidentiality) — §5.
- **I11** (restore provenance) — §4.
- **Honesty (H1)**: the fence is exactly-once for the *log*, not for *effects*; restore is
  *re-animate, not replay*.
