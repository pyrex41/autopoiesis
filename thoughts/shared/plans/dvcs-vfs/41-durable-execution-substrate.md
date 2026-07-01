# 41 — Durable execution on the mvfs substrate (Golem-general, via Firecracker/gVisor/CRIU + squashfs)

> **⚠ CORRECTED BY [doc 42](42-durable-execution-panel-verdict.md) (panel review).** Three
> claims below are RETRACTED there: (1) "the fence is the exactly-once primitive" — it is
> exactly-once for the *log append* only, not for external effects; (2) "rootfs is nearly
> free / reuse checkout!/switch! / squashfs per revision" — use **composefs**, not
> squashfs-per-revision, and the overlay-upper→CAS path is a NEW serializer (plain-file
> reuse silently loses deletions); (3) memory snapshots are NOT just CAS blobs — they need
> per-tenant encryption (I10) + provenance-verified-before-resume (I11). Read doc 42 for the
> revised architecture, the must-fix list, and the corrected phasing. The **authoritative
> revised design** now lives in [`spec/08-durable-execution.md`](spec/08-durable-execution.md)
> (composefs-centered, I10/I11). This doc is kept as the original exploration only.

**Status:** Design exploration (no code yet); superseded by doc 42 on the points above. Grounded by a cited research sweep of
Golem, gVisor, Firecracker, CRIU, squashfs/composefs, and the durable-execution
field (Temporal/Restate/Antithesis). Question from the user: *"how could this be
adapted to support durable state — like Golem does for WASM runtimes but more
generally, maybe gVisor or Firecracker; squashfs could be a component."*

---

## Thesis

**mvfs is already the versioning spine of a durable-execution platform; what it
lacks is the live-state-capture half — and the fenced land kernel turns out to be
the exact primitive the whole field works hardest to get right (exactly-once).**

A durable-execution platform = (1) a versioned, replicated, forkable store of state
+ (2) a way to capture & resume live process/VM state + (3) an exactly-once story
for external effects. We have built #1 and most of #3; #2 is what Golem/Firecracker/
gVisor/CRIU provide.

| Durable-execution need | mvfs already provides |
|---|---|
| Immutable history / time-travel | content-addressed blobs/trees; restore any past state by hash |
| Versioning + O(1) fork/branch | pijul/CAS structural sharing; fork shares all pre-fork blobs |
| Dedup | identical blobs/subtrees/images stored once |
| **Checkpoint = atomic, exactly-once, split-brain-proof** | a **fenced land** (lease-epoch CAS + idempotency-key; proven by T1/T2/T1-kill) |
| Replication / geo | content-addressed objects sync by hash; the durable log replicates |
| Who may resume/read a checkpoint | the ACL matcher + serve tokens (I6/I9) |
| Read-your-writes / monotonic restore point | as-of basis `(seq, acl-version)` |

What's **missing** is visibility into the volatile half: guest address space, CPU
registers, fd table, kernel socket/pipe state. None of that is in the VFS/CAS.
Capturing it needs CRIU (native processes), gVisor C/R (sandboxed), or a
Firecracker VM snapshot. **The rootfs/disk half is ours; the memory half is theirs.**

---

## Why Golem is WASM-specific, and what that means for "more general"

Golem makes WASM workers durable with an **oplog** (append-only journal of every
WASI host-call, tiered Redis→blob) + **deterministic replay**: on crash it
re-instantiates the component and replays recorded host-call results to reconstitute
the heap/stack, then continues. This works *only* because WASM is **deterministic,
single-threaded, capability-sandboxed, ASLR-free** — the computation between host
calls is guaranteed reproducible, so recording I/O is enough (WebAssembly
Nondeterminism spec enumerates the few exceptions: NaN bits, relaxed SIMD, shared
memory, OOM).

A **native** process can `rdtsc`/`rdrand`/`cpuid`, make raw syscalls, fork, thread,
and gets kernel `AT_RANDOM`/ASLR — *"deterministic computing is impossible on x86"*
without a controlling hypervisor (Antithesis's Determinator) or heavy binary
rewriting (Facebook Hermit). **Conclusion: for general processes you cannot do
Golem-style fine-grained replay; you lean on full-state snapshot/restore and
content-address the snapshots.** Replay becomes optional, layered on top for
exactly-once — not the base mechanism.

---

## The architectural seam

```
CHECKPOINT(worker) = ONE fenced land of:
    rootfs-delta-hash   (overlay upper layer)   ── our VFS/CAS (squashfs/composefs)
    memory-snapshot-hash(es)                     ── Firecracker vmstate+mem | gVisor | CRIU
    [oplog-tail-hash]   (external-effect journal, for exactly-once)
  committed atomically: the land succeeds iff all three are durable in CAS before
  the fence commits. Pause the guest (VM pause / SIGSTOP) before capture so the
  rootfs delta and the memory snapshot are a consistent cut.

RESTORE(checkpoint) =
    CAS-fetch rootfs squashfs base + apply overlay upper  → loop-mount
    CAS-fetch memory snapshot → Firecracker MAP_PRIVATE load | gVisor restore | CRIU restore
    resume
```

The **rootfs part is already mvfs.** The **memory part** is one opaque blob set we
hash and land. The **fence makes the two halves one linearizable, exactly-once
checkpoint** — the thing Firecracker/gVisor snapshots lack on their own (they give
you the bytes; we give you the *commit*).

Mapping to what we built: a **worker = a trunk lineage**; **checkpoint = `pland!`**
of the snapshot blobs (idempotency-key = checkpoint id; fence = no split-brain);
**fork = pijul O(1) fork** of that lineage (and Firecracker COW-forks the memory
file in lockstep — both are structural sharing); **time-travel = restore any landed
checkpoint**; **replication = the durable log**; **authz to resume = the ACL + serve
token**.

---

## Runtime choice (grounded)

| | Firecracker (KVM microVM) | gVisor (runsc/Systrap) | CRIU (native) |
|---|---|---|---|
| Snapshot | vmstate file + guest-memory file; MAP_PRIVATE COW restore | Sentry-owned C/R (state + page files); `--background` async restore | protobuf image set (mem/fd/tcp) |
| Restore latency | **0.8–8 ms** (Zeroboot 0.79 ms p50; Lambda SnapStart sub-sec) | ~1–3.5 s p50 ML-scale w/ background restore (Modal: 13 s→3.5 s) | seconds; depends on image size |
| Isolation | hardware VMX (host kernel unreachable) | userspace kernel (virtualizes time/RNG → better determinism) | none (bare process) |
| Determinism | none enforced (fork-from-point, not replay-safe) | partial (Sentry controls time/RNG) | none post-restore |
| CAS fit | hash vmstate+mem; **MAP_PRIVATE is already CAS-by-reference** (N VMs share one read-only mem file) | hash state+page bundle | hash image set (no native dedup) |
| Sharp edges | mem file must outlive VM; CPU-feature match for migrate | ISA nondeterminism still present; CPU-feature match | TCP (TCP_REPAIR), GPU (experimental), external fds |

**Recommendation:** Firecracker as the default general runtime (cleanest opaque-blob
snapshot, sub-10 ms restore, COW fork that mirrors our O(1) fork); gVisor for
Python/ML (background restore + virtualized time = best "time to first instruction"
and better determinism); CRIU only where a bare process must be captured (accept TCP/
GPU caveats). All three produce blobs we content-address and land identically.

## Rootfs layer (the part that's nearly free)

- **squashfs**: read-only, compressed, **deterministic** (bit-identical from the
  same tree+flags → SHA-256-addressable), page-cache-shared (mmap, zero-copy) — the
  exact "bytes never enter the VM" property our serve tier already enforces.
- **overlayfs**: squashfs lower (immutable base = a trunk revision) + writable upper
  (the mutable state captured on checkpoint).
- **composefs** (production in Fedora/RHEL): EROFS metadata + a SHA-256 object store +
  overlayfs + fs-verity — i.e. *content-addressed, integrity-verified, page-cache-
  deduped rootfs*. This is essentially our CAS + VFS, at the kernel image layer; our
  "land" is composefs's "seal." Strong candidate to back the rootfs tier.
- **EdenFS/Sapling**: confirms the lazy-materialize pattern our VFS already
  implements (materialized vs hash-addressed inodes).

## Exactly-once: where the fence shines

Neither Firecracker nor gVisor gives exactly-once for *external* effects. The field's
answer (Temporal/Restate/Golem) is an **intent→outcome journal**: write intent before
the effect, write outcome after, on restore skip effects that already have an
outcome. **Our fenced-linearizable log is exactly that journal, and the fence is the
exactly-once primitive** — only the land that wins the lease-epoch CAS may commit the
outcome, so a restored twin cannot double-fire. Restate independently arrived at the
same shape ("epoch-bump for split-brain"); we have it already (I7).

## Hardest correctness problems (and our handle on each)
1. **Post-restore nondeterminism / fork divergence** — two resumed twins diverge.
   Fork is fine for state, dangerous for *effects*. Handle: **effect ownership = the
   fence**; only the lineage holding the land lease may emit external effects. (This
   is why fenced-land, not just CAS-fork, matters.)
2. **TCP / live connections** — invalid after restore (peer seq moved / IP changed).
   Handle: drain/close before checkpoint, or reconnect on restore; never bake live
   sockets into a durable checkpoint (Lambda SnapStart says the same).
3. **fs/memory atomicity** — the rootfs upper delta and the memory snapshot must be
   one cut. Handle: pause the guest before capture; the fenced land commits both
   atomically.
4. **Oplog growth** (if you want replay) — replay-from-zero is O(history). Handle:
   periodic snapshot checkpoints (Golem's own fix) = our lands; replay only the tail.
5. **Exactly-once across restore** — effect committed but outcome unrecorded pre-
   crash. Handle: intent (with idempotency key) landed before the effect, outcome
   landed after, under the fence — plus idempotent external APIs.

---

## Proposed phasing
- **P-D0 — rootfs-only durability (general, no determinism needed; the easy big
  win).** Worker rootfs = squashfs/composefs base (a trunk revision) + overlay upper;
  checkpoint = land the upper delta; restore/fork = materialize via the VFS we have.
  Works for *any* process; gives durable, versioned, forkable *disk* state today.
  Reuses `checkout!`/`switch!`/`pland!` almost verbatim. **Recommend starting here.**
- **P-D1 — full-system snapshot (Firecracker).** Add `vm-snapshot!`/`vm-restore!`
  host verbs behind the §5.4 boundary; checkpoint lands (rootfs-delta, vmstate, mem)
  atomically; fork via MAP_PRIVATE COW. Sub-10 ms restore; true isolation.
- **P-D2 — exactly-once external effects.** Intent→outcome oplog as policy-style
  lands on the fenced log; the fence is effect ownership.
- **P-D3 — deterministic replay (optional).** Only for WASM workers (Wasmtime
  deterministic mode) or under a determinizing hypervisor; gives Golem-grade
  fine-grained replay where the workload allows it.

## New boundary surface (sketch, all behind spec/00 §5.4)
```
squashfs-build! : tree-hash -> image-hash         (deterministic mksquashfs/composefs)
overlay-open!   : image-hash -> mount             ; overlay-diff! : mount -> upper-delta-hash
vm-snapshot!    : vm -> [vmstate-hash mem-hash]   (pause; Firecracker/gVisor/CRIU)
vm-restore!     : [vmstate-hash mem-hash] rootfs -> vm
checkpoint!     : lease worker-id rootfs+mem+oplog logpath -> landed   (≈ pland!)
restore!        : checkpoint-entry -> running worker
```
The control plane (`checkpoint!`/`restore!`) is pure decision + a fenced land,
exactly like `pland!`; the capture/restore mechanics are audited host primitives.

## What to steal (condensed)
Golem: tiered oplog + snapshot-checkpoint-within-oplog. Restate: epoch-bump = our
fence; hot/cold journal tiers. Firecracker/Zeroboot: MAP_PRIVATE COW as CAS-by-
reference, sub-ms fork for agent fan-out. gVisor/Modal: background page restore;
GPU lifecycle separated from snapshot. composefs: whole-image digest + per-file CAS
+ fs-verity = our land/seal at the kernel layer. CRIU: TCP_REPAIR, external-fd
declaration. Antithesis/Hermit: how far determinism can go if ever needed.

## Open questions / recommendation
- **Start P-D0** (rootfs durability) — it's general, needs no determinism, and reuses
  the VFS+land we already have; it's a real product (durable, forkable workspaces).
- Pick **composefs vs plain squashfs+overlay** for the rootfs tier (composefs gives
  fs-verity + per-file dedup but is newer).
- Decide the **snapshot scope** per workload: rootfs-only (P-D0) vs full-memory
  (P-D1). Most "durable agent workspace" use cases are satisfied by P-D0 + reconnect.
- Determinism (P-D3) is a WASM-only luxury; do not block the general path on it.

Citations in the research transcript (Golem persistence/oplog; WebAssembly
Nondeterminism; gVisor C/R + Modal numbers; Firecracker snapshot-support + Zeroboot/
SnapStart; CRIU images/TCP; composefs/OSTree/EdenFS; Temporal/Restate/Antithesis).
