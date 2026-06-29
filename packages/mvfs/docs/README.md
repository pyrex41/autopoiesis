# mvfs documentation

**mvfs** is a content-addressable, **trunk-only** (no branches) distributed version
control system with a virtual filesystem and a durable-execution tier — built on a
**proven-brain / trusted-shell** architecture in Shen (shen-lua / LuaJIT).

This directory is the complete, current documentation. Read in this order:

| Doc | What it covers |
|---|---|
| [PRODUCT.md](PRODUCT.md) | What mvfs is, who it's for, the three product pillars, positioning vs git/Sapling/Piper/Golem/Temporal, status. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | The proven-brain/trusted-shell model, the layers, the land kernel, merge oracle, read tier, ACL/policy, VFS, durable execution, the pluggable boundary backends. |
| [INVARIANTS.md](INVARIANTS.md) | The canonical invariants **I1–I11**, how each is enforced, and the test that proves it (traceability). |
| [MODULES.md](MODULES.md) | The source map — every `src/*.shen`, `host/*.lua`, `serve/`, `deploy/`. |
| [TESTING.md](TESTING.md) | The verification matrix — every `make` target, what it proves, pass counts; the toolchain bootstrap; the expert-panel review record. |
| [DECISIONS.md](DECISIONS.md) | The ruled architectural decisions (shen-lua, pijul merge oracle, git/lore storage, composefs, Firecracker) with rationale and where ruled. |
| [ROADMAP.md](ROADMAP.md) | Status of every phase (P0…P-D3), what's verified-in-CI vs deployment, what's next. |
| [GLOSSARY.md](GLOSSARY.md) | Terms: land, fence, lease epoch, as-of basis, serve token, pristine, overlay delta, checkpoint, … |

## Where the normative specs and design history live
- **Normative specs:** [`../../../thoughts/shared/plans/dvcs-vfs/spec/`](../../../thoughts/shared/plans/dvcs-vfs/spec/)
  (`00-overview` is the keystone; `01`–`08` are the layer specs). These are the source
  of truth for contracts and invariants; the docs here summarize and index them.
- **Design history / reviews:** `../../../thoughts/shared/plans/dvcs-vfs/00`–`42` — the
  full exploration corpus, including the expert-panel reviews (Aphyr, Torvalds,
  Fukamachi, Minsky, Ptacek, Norvig, Hickey, agentzh) and the decision syntheses.

## One-minute orientation
- **The novel core** is a serialized, **fenced, single-leased-leader land queue** onto
  a single trunk. The Shen sequent type system + decidable Datalog *prove* the
  decisions (admission, authorization, fencing); git / pijul / nginx / the filesystem
  are *trusted oracles* behind one audited boundary (`src/boundary.shen`).
- **It runs.** ~2,200 lines of Shen + Lua, typechecked under Shen's `tc +`, with
  ~137 dynamic assertions across 12 test suites + 4 typecheck gates, exercised on a
  real toolchain (LuaJIT 2.1 / git / pijul). See [TESTING.md](TESTING.md).
- **Build & test:** see [TESTING.md](TESTING.md) (`scripts/bootstrap-toolchain.sh` then
  `make typecheck && make <suite>`).
