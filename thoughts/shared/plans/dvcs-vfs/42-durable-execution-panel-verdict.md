# 42 — Panel verdict on the durable-execution design (doc 41), and the revised architecture

**Status:** Panel review of doc 41. Three adversarial lenses — **Aphyr** (correctness),
**Ptacek** (security/isolation), **Torvalds** (systems pragmatics). They converge hard.
This doc is the authoritative correction; doc 41's overclaims are retracted here.

## Convergent verdict
- **P-D0 (rootfs-only durability): CONDITIONAL SHIP** — after the fixes below. All three
  agree it's the honest first product (durable, forkable, versioned *disk* state; no
  determinism, no hypervisor).
- **P-D1 (full memory snapshot): REWORK / BLOCKED** — Aphyr: the "atomic three-store
  checkpoint" is asserted, not engineered; Ptacek: a memory image is the worst blob to
  content-address and the doc treats it like a source file. Not buildable as written.
- **doc 41 over-described the off-the-shelf runtimes and under-specified the two things
  that are actually ours to build** (Torvalds): the overlay-delta serializer and the
  fenced 3-blob checkpoint commit. Invert that ratio.

---

## The three load-bearing errors (each reviewer, independently)

1. **"The fence is the exactly-once primitive."** FALSE (Aphyr). The fence is exactly-once
   for the **log append** (split-brain, proven by T2). It does nothing for the **external
   effect** — a worker can emit, crash, and a restored twin re-emits. This is
   at-least-once + idempotency, i.e. *the same as Temporal/Restate*, not better. The doc's
   own "hardest problems #5" already says this and contradicts the thesis. **Retract the
   claim.** End-to-end effect exactly-once needs intent→outcome journaling + idempotency
   keys carried to the external API + an unavoidable replay window the external endpoint
   must dedupe.

2. **"squashfs per revision, nearly free, reuse checkout!/switch! verbatim."** WRONG
   (Torvalds). squashfs has no incremental mode — a 3-file change rebuilds a multi-GB
   image (minutes of CPU, GBs written) **per checkpoint**. And an overlayfs upper is NOT a
   plain file tree: it has **char-device whiteouts** (deletions), opaque/redirect xattrs,
   metadata copy-ups. `checkout!`/`switch!` write plain files → **they silently lose
   deletions on restore** (a deleted file reappears — a correctness bug). The overlay
   delta → CAS path is a **new serializer**, not reuse.

3. **"A memory snapshot is just another CAS blob; ACL/serve-token already cover it."**
   FALSE (Ptacek). A memory image is cleartext secrets (keys, tokens, TLS session keys,
   possibly the serve HMAC key, possibly other tenants' leaked bytes), now served by the
   same sendfile path as source, cacheable, replicated, **deduped — and dedup of memory
   pages is a cross-tenant existence oracle** (same secret ⇒ same hash). Content-addressing
   gives integrity, not confidentiality or provenance; restore that trusts "valid hash =
   trusted bytes" loads attacker-controlled CPU/page/device state into the runtime.

---

## Consolidated MUST-FIX list (deduped across the panel)

**Correctness (Aphyr):**
- **C1 verify-before-append**: `checkpoint!` re-reads, hashes (with *our* hasher), and
  fsyncs every artifact in CAS *before* the fenced append — never trust runtime filenames.
- **C2 verify-before-resume**: `restore!` re-hashes every referenced artifact vs the log
  entry and fails closed on mismatch (I9 discipline applied to checkpoint artifacts).
- **C3 capture outside the lease, publish under it**: multi-GB fsync can't block a short
  lease; capture+hash speculatively, then a tiny fenced append publishes the already-durable
  hashes after an epoch re-check (mirrors `pland!` blob→log→apply). (or lease heartbeat.)
- **C4 guest quiesce before the cut**: under pause, drain guest I/O (`fsync`/virtio-blk
  drain) → snapshot overlay → snapshot memory. "Pause = consistent" is false for a
  writeback page cache.
- **C5 fence `restore!`**: it must take a `lease-witness` and be at-most-once per epoch, or
  a re-run recovery animates two divergent twins. (`restore! : lease → entry → worker`.)
- **C6 redefine durability granularity**: memory is NOT derivable from the log; I4 holds
  only at the newest *fully-verifiable* checkpoint; `recover!` falls back to it and *reports
  the gap*. Replicate memory blobs to the stated width *before* the checkpoint acks.
- **C7 pin runtime + CPU-feature/ABI identity** in the entry (extends MF-5); refuse restore
  on mismatch.

**Effects (Aphyr):**
- **E1 effect ownership is OUT-OF-GUEST**: route guest egress through a proxy that requires a
  per-effect capability minted by the lease holder at epoch E; reject tokens with epoch <
  current durable epoch (auto-revokes a partitioned old leader). Or tap-device-only-to-leader
  + STONITH. The fence alone does NOT enforce this.
- **E2 oplog is mandatory for effectful workers** (promote P-D2 to a P-D1 prerequisite):
  without intent→outcome, restore-from-checkpoint re-fires every interval effect
  nondeterministically with no idempotency key.

**Security (Ptacek) — new invariants:**
- **I10 snapshot confidentiality**: memory images are **per-tenant authenticated-encrypted
  at rest** (envelope: per-checkpoint DEK wrapped by per-tenant KEK in a KMS); CAS stores
  ciphertext; **no cross-tenant dedup** (per-tenant encryption kills cross-tenant hash
  equality — which is the desired outcome; intra-tenant fork sharing survives); snapshot
  blobs get a **distinct ACL resource-class and serve-token type** from code; never
  CDN-cacheable.
- **I11 restore provenance**: no blob is resumed without **verified capture-component
  provenance over the full chain** (base + all deltas). Trust lives in the **fenced log
  entry** (signed by the capture component, carrying captured-by/epoch), NOT in the hash.
  Restore verifies signature + lineage ownership, not just hash integrity.
- **S1 crypto-shredding for revocation**: I6 cannot expunge revoked plaintext already inside
  a memory image. The only real revocation is key scope = revocation granularity; shred the
  KEK ⇒ dependent checkpoints become undecryptable. Plus checkpoint TTL / forced re-capture.
- **S2 isolate the capture/restore component per tenant** (least-priv, jailed); it reads
  guest memory as opaque bytes, never parses guest-controlled structures with privilege; its
  signing key never appears in a snapshot.
- **S3 Firecracker is the security default** for restoring attacker-influenceable snapshots
  (hardware VMX; small TCB). gVisor only for fully-trusted first-party snapshots (larger Go
  Sentry TCB reconstructs kernel state in-process on restore).

**Honesty (all):**
- **H1**: replace "fence = exactly-once" → "fence = exactly-once *log commitment* +
  split-brain"; "time-travel to N" → "restore the captured *image* at N; subsequent
  execution is a fresh nondeterministic continuation, **not a replay**." as-of/I5 guarantee
  a byte-identical *image*, not a behaviorally-identical *worker*.

---

## The revised architecture (what the panel actually endorses)

**Build on production substrate; build only the moat.** (Torvalds' reuse-vs-build, merged.)

| Layer | Decision |
|---|---|
| Rootfs image format / per-file dedup / integrity | **composefs (EROFS + content-addressed object store + fs-verity)** — do NOT build squashfs-on-git-blobs. A 3-file change writes 3 objects + a tiny metadata image. |
| Read-only base in the I/O path | **in-kernel EROFS/overlayfs — NO FUSE under a live rootfs** (FUSE is fine only for the one-time materialize; inside Firecracker the guest sees a block device, moot). |
| Mutable layer | kernel overlayfs upper (P-D0) or the VM block device delta (P-D1). |
| Memory snapshot / COW fork / hypervisor | **off-the-shelf: Firecracker (default), gVisor (trusted Python/ML), CRIU (last resort), KVM.** |
| **Overlay-delta → CAS serializer** | **BUILD** — whiteouts→explicit deletion nodes, opaque/redirect xattrs preserved, mtime/inode/uid/gid normalized for stable hashing. The real, under-budgeted work. |
| **Fenced 3-blob checkpoint commit** (rootfs-delta, mem, oplog) | **BUILD on the existing fence** — the actual moat; nobody ships this. |
| **Lineage / O(1) fork / time-travel of checkpoints** | **already have** (pijul/CAS) + thin extension. |
| **Intent→outcome oplog bound to the fence + egress capability** | **BUILD** (shape borrowed from Restate/Temporal; binding to *our* fence is the novel part). |
| Deterministic replay (P-D3) | off-the-shelf / defer; WASM-only luxury. |

**Determinism harness in CI** (Torvalds): rebuild the same tree twice, assert bit-identical
composefs metadata + object set — reproducibility is a *discipline*, not a property
(parallel mksquashfs/compression, mtimes, inodes, xattrs all break it).

## Revised phasing
- **P-D0 (ship first):** composefs base (digest = a trunk revision) + kernel overlay upper,
  no FUSE in the I/O path. **Checkpoint = land(overlay-upper-delta)** via the new
  overlay-aware serializer (C-correctness: verify-before-append/resume; quiesce before
  capture). Fork = lineage fork + fresh upper. This is the honest product. Rootfs deltas
  still get the snapshot ACL class if they can hold runtime creds.
- **P-D1 (after I10/I11 + C1–C7):** Firecracker memory snapshot, per-tenant encrypted,
  provenance-verified, fenced `restore!`. Guest disk = block device (simplifies overlay).
- **P-D2 (prerequisite for effectful workers, not "later"):** intent→outcome oplog + the
  out-of-guest egress capability tied to the lease epoch (E1/E2).
- **P-D3:** deterministic replay, WASM-only, optional.

## New fault tests owed (Aphyr), analogous to T1/T2
- **T-D1 torn memory artifact**: corrupt/truncate one page file (dm-flakey/charybdefs);
  assert verify-before-append refuses, post-commit corruption → `restore!` fails closed,
  `recover!` falls back + reports the gap. (Also the doc-37-owed torn-write matrix.)
- **T-D2 split-brain effects under partition**: old leader (epoch E) still running with
  egress + new leader (E+1); assert with the egress capability the external endpoint sees
  exactly one effective delivery (and without it, two — the test must show the bug).
- **T-D3 non-idempotent restore / double-twin**: crash recovery mid-`restore!`, re-run;
  assert fenced `restore!` yields exactly one live twin; separately show two restores of N
  diverge (rdtsc) → proves restore-is-rerun-not-replay (H1).

## One-line summary
The fenced-land kernel + content-addressed lineage is a genuinely novel durable-execution
substrate and the panel agrees it's the moat — but doc 41 borrowed the *words* "atomic" and
"exactly-once" from the log (where they're proven) and applied them to memory blobs and
external effects (where they're not), and it reinvented composefs while under-specifying the
overlay serializer that's the actual work. Build P-D0 on composefs with the verify gates and
the honest vocabulary; gate P-D1 on I10/I11 + C1–C7; make the oplog/egress-capability a
prerequisite for effects, not an afterthought.
