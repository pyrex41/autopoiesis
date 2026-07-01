# mvfs — product

## What it is
**mvfs** is a content-addressable **monorepo** version control system + virtual
filesystem, with a **durable-execution** tier layered on the same substrate. One
sentence: *a trunk-only, EdenFS-style monorepo with a provably-correct land queue,
that doubles as the storage + checkpoint substrate for durable, forkable, versioned
execution.*

Three product pillars, one substrate:

1. **A trunk-only monorepo VCS.** No branches — the only write path is a serialized,
   fenced **land queue** onto a single linear trunk. Content-addressed storage, real
   3-way merge, stacked changes, idempotent submit. The model large monorepos
   converge on (Google Piper, Meta's Sapling/EdenFS), made small and provable.

2. **A virtual filesystem.** A sparse, lazy, content-addressed working tree: clone is
   instant, you materialize only the paths you touch, `status` is O(changed files),
   and reads are served zero-copy. EdenFS experience without the EdenFS-sized team.

3. **Durable execution.** Because the substrate already content-addresses state,
   forks in O(1), time-travels, replicates, and **commits exactly-once under a fence**,
   it is most of a durable-execution platform. A *checkpoint* is a fenced land of a
   rootfs delta (+ optionally a memory snapshot); a worker is a trunk lineage;
   fork/restore/replay come for free from the VCS. "Golem for WASM, but general."

## Who it's for
- **Monorepo teams** who want trunk-based development with provable land semantics,
  sparse checkout, and fast `status` — without standing up Piper/EdenFS-scale infra.
- **Platform builders** who need **durable, forkable workspaces**: agent runtimes that
  must survive restarts and fork cheaply; CI/build farms that checkpoint and resume;
  any "long-running job that must not lose work and must be exactly-once."
- **Security-sensitive orgs**: every byte path is authorized (no content reachable by
  hash alone), ACL is decidable Datalog, policy changes land linearizably with a
  version fence.

## The differentiators
- **Provable core, not just tested.** The land FSM is sequent-typed: illegal states
  (land without admission, land without a held lease, forge a capability) **don't
  typecheck** — demonstrated by a negative test the typechecker must reject. ACL is
  decidable Datalog with an oracle-conformance check.
- **A real fence.** The write path is a single-leased-leader queue with a lease-epoch
  fencing token CAS'd at the durable append — split-brain-proof, exactly-once at the
  log, proven by Jepsen-style fault tests (including a real `kill -9`).
- **Patch-theory merge.** The merge oracle is **Pijul**, whose merge is *sound by
  construction* (commutative, order-independent, deterministic conflicts) — not git's
  heuristic 3-way diff. Chosen by running it, not from docs.
- **The same substrate does durable execution.** Checkpoints are lands; the fence is
  the exactly-once primitive; forks are O(1). Nobody else ships a fenced, content-
  addressed checkpoint commit.

## Positioning
| | mvfs | git | Sapling/EdenFS | Piper | Golem | Temporal/Restate |
|---|---|---|---|---|---|---|
| Trunk-only, fenced land queue | ✅ | ✗ | ✗ | ✅ | — | — |
| Content-addressed + sparse VFS | ✅ | partial | ✅ | ✅ | — | — |
| Provable land/authz core | ✅ | ✗ | ✗ | ✗ | — | — |
| Sound (patch-theory) merge | ✅ (pijul) | ✗ | ✗ | ✗ | — | — |
| Durable execution on the same store | ✅ | ✗ | ✗ | ✗ | ✅ (WASM only) | ✅ (no FS state) |
| Exactly-once via a fence | ✅ | — | — | — | ✅ | ✅ |
| General (non-WASM) durable workers | ✅ (design) | — | — | — | ✗ | ✅ |

mvfs's niche: the **intersection** — a provable trunk-only monorepo VCS *and* a
content-addressed durable-execution substrate, sharing one fenced land kernel.

## Status (what's real today)
- **Verified, runs in CI** (Shen `tc +` + ~137 assertions on git+pijul+LuaJIT): the
  land kernel, pijul merge oracle, read tier (serve tokens, as-of basis), decidable
  ACL + policy lands, the sparse VFS (checkout/status/switch), and the durable-
  execution control plane **P-D0** (rootfs checkpoints) and **P-D2** (exactly-once
  effects via `durable-effect!`). See [TESTING.md](TESTING.md).
- **Designed + ruled, deployment-gated** (need a privileged host with Firecracker/
  KVM/composefs): **P-D1** memory snapshots (encrypted, provenance-verified) and the
  composefs/overlay rootfs backend; the OpenResty zero-copy serve tier.
- **Deferred**: **P-D3** deterministic replay (WASM-only luxury).

See [ROADMAP.md](ROADMAP.md) for the phase-by-phase status and [DECISIONS.md](DECISIONS.md)
for the ruled architecture choices.

## The product story, concretely: "durable, forkable agent workspaces"
A worker (an agent, a build, a long job) gets a **sparse, content-addressed rootfs**
materialized from a trunk revision. As it runs it writes to an overlay; a
**checkpoint** lands the overlay delta (and, on a real host, a memory snapshot) as a
fenced, content-addressed commit. The worker can **crash and resume** from the last
checkpoint, **fork** in O(1) (speculative agent fan-out shares all pre-fork state),
**time-travel** to any checkpoint, and **replicate** by hash. External effects are
**exactly-once** via `durable-effect!` (intent→outcome journal) and an egress
capability tied to the lease epoch (a partitioned old worker's effects are rejected).
The VCS guarantees — linear history, provable authz, sound merge — apply to the
workspace itself.
