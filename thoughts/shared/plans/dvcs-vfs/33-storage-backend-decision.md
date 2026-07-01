# 33 — Storage backend decision: lore vs rvcs vs git (grounded)

**Status:** Decided. Verdict reached by *running the candidates*, not from docs.
**Question (user):** "https://github.com/EpicGames/lore — what about this instead of
git? Or the google drop-in replacement [rvcs]. Either meds or rvcs, let's build it right."

This document records what I actually observed running each candidate on the real
toolchain, the object-model mapping into mvfs's `boundary.shen` (spec/00 §5.4), and the
ruling. It supersedes the earlier *assumed* properties of lore/rvcs in docs 00–32.

---

## TL;DR

- **rvcs — rejected.** Wrong shape (snapshot/publish/sign/mirror), experimental, and
  explicitly *unsupported* ("not an official Google product"). It is not a blob/tree/commit
  CAS; adapting it would be all impedance and no payoff.
- **lore — adopted, but as a *second* backend, not a git replacement.** It is a real
  BLAKE3 content-addressed Merkle store with content-defined chunking, fragment-level
  dedup, and sparse/lazy working trees — exactly the **large-binary + hydration tier**
  where git (LFS bolt-on) is weakest and where mvfs was weakest. I verified the full
  loop locally (below).
- **git — stays as the trunk's source-of-truth and the merge oracle.** Three reasons,
  all confirmed empirically: (1) lore ships **no CLI 3-way text merge** — conflict
  resolution is a server-side change-request flow; a trunk-only *code* monorepo needs a
  real textual `merge-tree`, and git is the proven oracle. (2) lore is **pre-1.0 and its
  on-disk/wire formats may change** — betting the durable source-of-truth on an unstable
  format is the opposite of "build it right." (3) lore is **server-of-record**: every
  repo is registered with a `loreserver` over gRPC. mvfs's whole thesis is *provable local
  authority* (the proven-brain / trusted-shell boundary, I7 fenced authority); putting a
  separate authority server in the trust path undercuts that. lore's VFS — the feature I'd
  most want — is **roadmap, not shipped** (v0.8.4).

So: **git = trunk commit/tree/merge oracle; lore = optional content-addressed fragment
store for large/binary content and (later) VFS hydration.** Both sit behind the *same*
swappable `boundary.shen` storage interface. mvfs's verified fenced-land control plane is
unchanged and owns I1–I9 above both.

---

## What I ran (evidence)

Prebuilt v0.8.4 Linux binaries (`lore`, `loreserver`) on this sandbox; LuaJIT/shen-lua
toolchain already bootstrapped.

### rvcs
Read the README/model: `snapshot` → `publish` → `sign` → `mirror`, content-addressed
*snapshots* of a working dir, designed for signing/mirroring across hosts. No
blob/tree/commit plumbing to shell out to. Experimental, unsupported. **Out.**

### lore — full loop, locally, no cloud
```
loreserver                       # zero-config local mode: local immutable+mutable+lock
curl /health_check               # 200 OK
lore repository create lore://127.0.0.1:41337/myproj
                                 # registers repo on the gRPC server; writes .lore/
lore file hash hello.txt sample.bin
  hello.txt  -> 869c66…157b      # BLAKE3, 64-hex
  sample.bin -> 017a5a…69fb
lore dirty <paths>; lore stage <paths>
  Staged repository state 3075a3…9845        # <- Merkle tree root, content-addressed
lore commit "first commit"
  Fragmenting files and updating tree hashes
  Revision 1; Signature f10921…4470; Branch e72631…35b
lore repository store immutable query 3075a3…9845 --recurse
  Address 3075a3…9845-00000000000000000000000000000000 (local)
  Status: Stored (metadata and payload); Content: 320 bytes     # <- real tree fragment
```

### lore object model (confirmed)
- **Address = `<32-byte BLAKE3 hash>-<16-byte context>`** = 48 bytes, rendered
  `64hex-32hex`. "Two fragments with the same address are the same fragment." Whole small
  files use an all-zero context.
- **Fragment** = content-addressed chunk (content-defined or fixed chunking) → dedup at
  the *byte* level, as effective on a multi-GB binary as on a kB of text.
- **Immutable store** (fragments/trees, content-addressed, sharded `.lore/immutable/index/<2hex>/`)
  + **mutable store** (branch pointers/metadata). Backends are replaceable behind documented
  interfaces (reference impls: S3 immutable, DynamoDB mutable).
- Trees are themselves content-addressed and **recurse** into subfragments → a true Merkle DAG.
- Local/remote status is **first-class** on every address (sparse/lazy: a fragment can
  exist remotely with 0 local payload until hydrated).
- "Normal editing — staging, committing, branching, diffing — never requires a network
  round trip" (local stores); the server is the durability/ACL/conflict authority.

---

## Object-model mapping → `boundary.shen` (spec/00 §5.4)

| mvfs storage verb        | git (oracle backend)                  | lore (fragment backend)                              |
|--------------------------|---------------------------------------|------------------------------------------------------|
| `cas-put-blob` (bytes→addr) | `hash-object -w --stdin`           | working-tree write → `dirty`+`stage`; addr via `file hash` |
| `cas-read-blob` (addr→bytes)| `cat-file -p`                      | `file write --address <ADDR> --output -`             |
| `cas-query` (addr→status)| `cat-file -e`                         | `repository store immutable query <ADDR>`            |
| `cas-put-tree` (spec→root)| `mktree`                             | `stage` → staged-state hash                          |
| `commit-tree` (commit)   | `commit-tree T -p P -m M`             | `commit` → revision + signature                      |
| **3-way text merge**     | `merge-tree --write-tree --merge-base`| **— none (server-side CR)** → *use git*              |
| sparse hydration / VFS   | — (LFS bolt-on)                       | sparse lazy working tree (**VFS = roadmap**)         |

**Impedance notes (honest):**
1. lore's *write* path is working-tree-oriented (`stage`/`commit`), not a stdin plumbing
   verb like git's `hash-object --stdin`. A lore blob put = materialize → dirty → stage.
   Fine for the file/large-binary tier; awkward as a general bytes→addr primitive.
2. lore addresses carry a 16-byte **context**; mvfs's `hash` synonym is the 64-hex digest.
   The fragment backend must round-trip the full 48-byte address (store both, or always
   use the zero-context form for whole objects).
3. lore requires a **running loreserver**. That is a *deployment* dependency for the
   fragment tier only — the trunk land path (git) has no daemon. Captured as host config
   in `src/host-lore.shen`, not in the proven core.

---

## Decision

1. **Trunk source-of-truth + merge = git.** `git-commit-tree` / `git-merge-tree` remain
   the merge oracle in `fsm.shen` and are **not** placed behind the storage selector —
   merge is git, always, by design (recorded here so it isn't mistaken for an oversight).
2. **Storage is pluggable.** `boundary.shen` gains a `storage-backend` datatype
   (`git-be` | `lore-be`) and generic `cas-*` verbs that dispatch to it. The git backend
   is the default and is self-contained (no daemon). The lore backend shells out to the
   verified `lore` CLI and targets the **large-binary / sparse-hydration tier**.
3. **lore is wired but optional.** `src/host-lore.shen` provides the lore connection/config
   host and the working-tree-oriented put helper. Enabling it is a deployment choice; the
   proven core and the verified P0 typecheck are unchanged.
4. **Revisit when lore ships VFS and hits 1.0.** At that point lore can take a larger share
   of the materialization path; until then git carries the trunk and lore carries bytes.

This is "build it right": each tool does what it is provably best at, behind one audited
boundary, with mvfs's fenced-land control plane (I1–I9) owning correctness above both.
