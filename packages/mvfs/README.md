# mvfs

A content-addressable, **trunk-only** (no branches) distributed version control system
with a virtual filesystem and a **durable-execution** tier — built on a
**proven-brain / trusted-shell** architecture in Shen (shen-lua / LuaJIT).

The novel core is a serialized, **fenced, single-leased-leader land queue** onto one
linear trunk. Shen's sequent type system + decidable Datalog *prove* the decisions
(admission, authorization, fencing — illegal land states don't even typecheck);
git / pijul / nginx / the filesystem are *trusted oracles* behind one audited boundary.
The same substrate (content-addressed, O(1) fork, time-travel, exactly-once under a
fence) doubles as a durable-execution platform — "Golem for WASM, but general."

## 📖 Documentation
Full docs are in **[`docs/`](docs/)** — start with [`docs/README.md`](docs/README.md):

- **[docs/PRODUCT.md](docs/PRODUCT.md)** — what it is, who it's for, positioning, status
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — the layers, the land kernel, merge
  oracle, read tier, ACL, VFS, durable execution, the pluggable backends
- **[docs/INVARIANTS.md](docs/INVARIANTS.md)** — I1–I11 with enforcement + test traceability
- **[docs/MODULES.md](docs/MODULES.md)** — the source map
- **[docs/TESTING.md](docs/TESTING.md)** — the verification matrix (every target, counts)
- **[docs/DECISIONS.md](docs/DECISIONS.md)** — the ruled choices (shen-lua, pijul, git/lore,
  composefs, Firecracker)
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — phase status (P0…P-D3)
- **[docs/GLOSSARY.md](docs/GLOSSARY.md)** — terms

Normative specs: [`../../thoughts/shared/plans/dvcs-vfs/spec/`](../../thoughts/shared/plans/dvcs-vfs/spec/)
(`00-overview` is the keystone). Design history + expert-panel reviews: the numbered
docs alongside it.

## Status
**Verified & runs in CI** (Shen `tc +` + ~137 assertions on real git / pijul / LuaJIT):
the land kernel, pijul merge oracle, read tier, decidable ACL + policy lands, the
sparse VFS, and the durable-execution control plane (**P-D0** rootfs checkpoints,
**P-D2** exactly-once effects). **Deployment-gated** (need a privileged host): the
composefs rootfs backend, the OpenResty serve tier, and **P-D1** memory snapshots.
See [docs/ROADMAP.md](docs/ROADMAP.md).

## Build & test
```sh
# build LuaJIT 2.1 + fetch shen-lua into ./.toolchain (idempotent):
eval "export SHEN=$(scripts/bootstrap-toolchain.sh)"

make typecheck            # core typechecks under Shen's sequent checker (tc +)
make typecheck-negative   # MUST FAIL: the 4 illegal programs are rejected (I7 type half)
make test                 # runtime smoke: submit->admit->base yields a `based`
```
The full suites (need `PIJUL` / `LUAJIT` / `PIJUL_CONFIG_DIR` for the merge/durable
tests; pijul needs an ssh-agent identity):
```sh
make e2e t1 t1-kill t2 t3        # kernel: merge oracle, fenced land, crash atomicity, split-brain
make read read-edge acl policy vfs   # read tier, ACL, policy lands, sparse mount
make dx t-d1 oplog               # durable execution: checkpoints, fault test, exactly-once effects
```
See [docs/TESTING.md](docs/TESTING.md) for what each proves and the pass counts.

## Layout
```
src/      the Shen core (typechecked) + host backends
host/     the Lua host implementations (the trusted shell)
serve/    the OpenResty read-tier edge (deployment artifacts)
deploy/   composefs/overlay durable-execution backend (deployment)
test/     the suites
scripts/  toolchain bootstrap
docs/     this documentation
```
