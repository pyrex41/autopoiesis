# mvfs — ruled architectural decisions

Each decision below was reached deliberately (usually by *running* the candidate and
by adversarial expert-panel review), and is recorded normatively in the spec. This is
the index; follow the links for the full evidence.

## D1 — Language: shen-lua (Shen on LuaJIT) — *keystone*
**Ruling:** the brain is **Shen**, running on the **shen-lua** port (LuaJIT 2.1).
**Why:** Shen's sequent type system makes illegal land states unconstructible, and its
built-in decidable Datalog/Prolog (a native soa32 engine on LuaJIT) is the ACL
matcher; shen-lua is JIT-compiled and fast, and `lua.call` gives a clean FFI to the
trusted shell (git/pijul/libcrypto/fs). The Shen program *is* the executable spec.
**Evidence:** the corpus shen-go/rust/ocaml comparison + the shen-lua correction (the
earlier assumption that shen-lua was slow was refuted by reading the real port);
verified by the whole core typechecking and running. Corpus docs 15–25, 32.

## D2 — Storage: git CAS source-of-truth; lore as the large-binary tier
**Ruling:** **git** plumbing (`hash-object`/`cat-file`/`mktree`/`commit-tree`) is the
content-addressed source-of-truth + merge oracle host; **lore** (EpicGames) is adopted
as an *optional second backend* for the large-binary / sparse-hydration fragment tier;
**rvcs rejected**. **Why:** decided by actually running lore v0.8.4 locally — it's a
real BLAKE3 Merkle store with chunked dedup, but it's server-of-record, pre-1.0
(unstable formats), ships no CLI 3-way text merge, and brings a competing control
plane; git is the stable, embeddable, daemon-free CAS + merge oracle for a trunk-only
text monorepo. **Where:** [spec/01], corpus **doc 33**; `storage-backend` (git-be/
lore-be) in `boundary.shen`, `host-lore.shen`.

## D3 — Merge oracle: Pijul (patch theory), not git's heuristic merge
**Ruling:** the merge oracle is **pijul** (a second pluggable axis, `merge-oracle`,
orthogonal to storage); git-merge is the kept-warm fallback. **Why:** git-as-CAS is
fine but git-*merge* is a heuristic line diff3 — the soft spot for a system whose
pitch is provability. Pijul's merge is **sound by construction**, proven by *running*
pijul 1.0.0-beta.15: independent changes commute (byte-identical file *and* identical
state hash in either order), conflicts are deterministic first-class graph states, and
a change recorded against an old base applies cleanly onto an advanced trunk
(rebase dissolved). Conflict detection is **structural** (pijul's own `archive` report,
not marker-grep). We **exec the CLI, never link libpijul** (GPL). **Where:**
corpus **doc 34** (+ the Aphyr/Torvalds/Fukamachi panel); `boundary.shen` merge-oracle.

## D4 — Rootfs image: composefs, not a home-grown squashfs pipeline
**Ruling:** the durable-execution rootfs base is **composefs** (EROFS metadata +
content-addressed object store + fs-verity), with kernel overlayfs on top; **no FUSE
in the live I/O path**; **squashfs-per-revision rejected**. **Why:** the doc-42 panel
(Torvalds) — squashfs has no incremental mode (a 3-file change rebuilds a multi-GB
image per checkpoint); composefs is the production content-addressed rootfs and a
3-file change writes 3 objects + a tiny metadata image. The real engineering is the
**overlay-upper → delta serializer** (char-device whiteouts, opaque/redirect xattrs),
which plain-file checkout would silently get wrong. **Where:** [spec/08] §0/§1,
corpus **doc 42**; `deploy/`, `host/host-composefs.lua`.

## D5 — Durable-execution runtime: Firecracker default, gVisor for trusted ML
**Ruling:** the P-D1 memory-snapshot runtime is **Firecracker by default**, **gVisor**
as a pluggable second backend for trusted first-party large-memory ML/Python, **CRIU**
last resort. A boundary-backend choice, not foundational. **Why:** restore deserializes
attacker-reachable state into the runtime → Firecracker's hardware-VMX containment +
small TCB win (Ptacek S3); 0.8–8 ms restore (100–1000× gVisor) makes fork/fan-out
cheap; the vmstate+mem blob is the cleanest thing to hash/encrypt(I10)/sign(I11)/land.
gVisor wins for trusted big-memory ML (background restore) and KVM-less hosts.
**Flip condition:** gVisor default only if single-tenant + fully-trusted +
ML-cold-start-dominated. **Where:** [spec/08] **§1a**.

## D6 — Durable execution model: snapshot/restore, not Golem-style replay
**Ruling:** for *general* (non-WASM) durable workers, use **snapshot/restore** + an
intent→outcome oplog, **not** fine-grained deterministic replay. **Why:** Golem's
oplog-replay works only because WASM is deterministic/single-threaded/sandboxed;
"deterministic computing is impossible on x86" without a determinizing hypervisor.
So content-address the snapshots; replay (P-D3) is a WASM-only luxury. The fence is
exactly-once for the *log/commit*, **not** for external effects — effects are
at-least-once + idempotency (the honest guarantee, same as Temporal/Restate), made
exactly-once-modulo-window by `durable-effect!` + the out-of-guest egress capability.
**Where:** [spec/08] §6, corpus **docs 41/42**.

## D7 — Generated-matcher conformance (accepted with controls)
**Ruling:** the decidable Datalog policy *model* is proven; any partial-eval'd hot-path
matcher is *conformance-tested, not verified* — with the interpreted oracle as a
runtime kill-switch and a CI-blocking differential diff. **Why:** the trusted-shell
side can't be type-proven, so it's gated by an oracle. **Where:** [spec/00] §6a;
`acl.shen` ships `acl-decide` + `acl-oracle` + `acl-conform?` today.

---

[spec/00]: ../../../thoughts/shared/plans/dvcs-vfs/spec/00-overview.md
[spec/01]: ../../../thoughts/shared/plans/dvcs-vfs/spec/01-data-model-and-storage.md
[spec/08]: ../../../thoughts/shared/plans/dvcs-vfs/spec/08-durable-execution.md
