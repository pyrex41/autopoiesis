# mvfs P-D0 deployment — composefs/overlay backend

The portable P-D0 (`src/dx.shen`, `make dx`) models a durable-execution checkpoint
on **git + plain dirs** and runs in CI. This directory is the **production backend**
that runs the same design on a real kernel using off-the-shelf, in-kernel pieces —
the *reuse* half of [`spec/08`](../../../thoughts/shared/plans/dvcs-vfs/spec/08-durable-execution.md).

## Requirements (not present in CI sandboxes)
- **composefs** (`mkcomposefs`, `composefs-info`) — content-addressed EROFS image +
  object store + fs-verity. (Fedora/RHEL ship it; else build from source.)
- **EROFS + overlayfs** kernel modules (mainline).
- **CAP_SYS_ADMIN** (privileged mounts) — `attr`/`getfattr`/`setfattr`, `mknod`.

## The pieces
- `host/host-composefs.lua` — implements the spec/08 §9 boundary verbs over the real
  tools: `composefs-build!` (mkcomposefs → digest), `overlay-mount!` (EROFS ro base +
  overlayfs upper, **in-kernel — no FUSE in the I/O path**), `overlay-capture!`
  (walk the upper), `overlay-apply!` (reconstruct it).
- `src/host-composefs.shen` — binds those verbs (load it instead of/with `host-lua.shen`
  when the composefs backend is enabled). `make typecheck-composefs` typechecks it.

## The load-bearing part: overlay-upper → delta
A kernel overlayfs **upper** layer is not a plain file tree. `overlay-capture!`
translates its semantics into the **same content-addressed delta** the checkpoint
kernel lands (so `checkpoint!`/`restore-checkpoint!`/the fenced log are unchanged):

| overlay upper artifact | detected by | delta node |
|---|---|---|
| modified/new file | `find -type f` | `set path <git-hash-object -w>` |
| **deletion** | char-device, `rdev 0,0` (`find -type c` + `stat`) | `del path` |
| opaque directory | `getfattr trusted.overlay.opaque == y` | `opaque path` |
| rename redirect | `getfattr trusted.overlay.redirect` | `redirect path <target>` |

`overlay-apply!` is the inverse: `set` → write blob; `del` → `mknod c 0 0` (a kernel
whiteout); `opaque`/`redirect` → `setfattr`. **Plain-file checkout would silently lose
the `del`/`opaque` cases** — which is exactly why this backend, not `vfs.shen`
`checkout!`, owns real-overlay capture (panel doc 42, Torvalds).

## Flow on a real host (P-D0)
```
base image  = composefs-build!(trunk-revision-tree)        # EROFS, fs-verity, page-cache-shared
merged      = overlay-mount!(base-image, workdir)          # in-kernel ro-base + rw-upper
  ... worker runs against `merged`, writing to the upper ...
delta       = overlay-capture!(workdir/upper, base-image)  # whiteouts+xattrs -> delta nodes
checkpoint! = land(delta) via the fenced kernel            # C1 store-before-append (unchanged)
restore     = overlay-mount!(base) ; overlay-apply!(delta) # deletions honored; C2 verify-before-resume
```

## Not yet here (next, per spec/08)
- P-D1 Firecracker memory snapshot (encrypted per-tenant, I10; provenance-verified, I11).
- P-D2 intent→outcome oplog + the out-of-guest egress capability (exactly-once effects).
- A CI determinism harness on a composefs-capable runner (mkcomposefs bit-identity).
