# 38 — Close-out: MF-4c + MF-5 + T3 (the must-fix list is done)

**Status:** Built and verified (shen-lua/LuaJIT 2.1, git, pijul 1.0.0-beta.15).
Continues doc 37. Closes the last two must-fixes (MF-4c, MF-5) and adds T3, so the
full doc-34 must-fix list and the T1–T3 fault tests are complete and green.

---

## MF-4c — pristine durability (best-effort) + the honest finding
**Finding:** pijul beta.15 has **no fsync-on-commit knob** — the `--sync-data` flag I
first reached for belongs to *lore*, not pijul (`pijul --sync-data` → "unexpected
argument"), and Sanakirja's commit durability isn't CLI-controllable. So:

- Correctness does **not** depend on pijul fsyncing the pristine: the log is truth
  and recovery forward-re-applies any logged change missing from the pristine
  (proven by T1/T1-kill). The pristine is explicitly a rebuildable cache.
- As defense-in-depth we fsync the pristine **at our layer**: after the land-path
  apply, `pland!` calls `sync-pristine!`, which fsyncs every file under
  `.pijul/pristine` (host FFI `fsync`). Coarse but real; reduces recovery work
  after a crash. Documented as best-effort, not the correctness guarantee.

## MF-5 — version-pin the state-hash audit chain
The order-independent state hash (entry `Root`) is in the audit chain and depends on
pijul's (pre-1.0) hash construction. The log now carries a meta sidecar
`<logpath>.meta` recording the **producing pijul version** (written at genesis by
`version-pin!`). `recover!` checks `version-ok?` first and **refuses** a log whose
meta names a different pijul version — a different pijul's state hashes wouldn't
match the recorded `Root`s, so we don't silently operate on an uninterpretable
audit chain. (Pinning the version string is the proxy for the hash-algo id; pijul
exposes no finer algo identifier.)

## T3 — TOCTOU race + MF-5 (`test/t3-toctou.sh`, `make t3`)
A candidate clean at admission (tip = T) can conflict at land (tip = T+1) after a
competing change lands in between. **8 passed, 0 failed:**
- `clean@T`   — `pijul-admits? CA` against the base tip is **true**;
- competing `CB` (same line) lands via `pland!`, advancing the tip;
- `conflict@T+1` — `pijul-admits? CA` against the advanced tip is now **false**;
- `pland! CA` is **rejected at the land point** (MF-3): CA not in the pristine, log
  unchanged — the race did not land a conflict;
- MF-5 — the meta records the running pijul version; after corrupting the meta to a
  fake version, `recover!` **refuses** the log.

This proves the land-point re-check is *necessary* (not redundant with admission):
it catches exactly the window admission can't see.

---

## Must-fix scoreboard — COMPLETE
| # | item | status |
|---|---|---|
| MF-1 | no silent transitive apply | ✅ `pijul-deps-in-trunk?` gate (doc 36) |
| MF-2 | structural conflict detection | ✅ `pijul archive` stderr probe (doc 35) |
| MF-3 | land-point re-check | ✅ in `pland!` (doc 36); proven necessary by T3 |
| MF-4a | change bodies in fenced blob store before append | ✅ (doc 37) |
| MF-4b | recovery before writes | ✅ gate (doc 37) |
| MF-4c | pristine fsync | ✅ best-effort host fsync + recovery backstop |
| MF-5 | pin pijul hash-algo/version in the audit chain | ✅ log meta + `recover!` refusal |
| I3 | authoritative idempotency-key dedup | ✅ `key-find` in `pland!` (doc 36) |

## Fault tests — COMPLETE for the modeled fault classes
| test | what | result |
|---|---|---|
| e2e | oracle clean/conflict + land path + I7 | green |
| t1 | two-store crash atomicity (step-stop W1/W2) | 8/8 |
| t1-kill | REAL `kill -9` at post-append window + MF-4a durability | 9/9 |
| t2 | fenced split-brain + I3 + MF-3 + MF-4a/b | 15/15 |
| t3 | TOCTOU race (MF-3 necessity) + MF-5 version pin | 8/8 |

## What remains (beyond the must-fix list)
- A `dm-flakey`/`charybdefs` **torn-write** matrix (true mid-write block tearing,
  not just process death between steps). Needs a fault-injection FS in the env.
- MF-4b gate keyed on the **lease epoch** (today: keyed on logpath), so each new
  leadership term must re-recover.
- Folding `land!` (the git-commit path) and `pland!` into a single configurable
  driver, or retiring `land!` if git-commit-of-record is dropped in favor of the
  pijul state hash as the sole trunk identity.
- The read tier (OpenResty/shen-lua zero-copy serve) and the VFS materialization
  path — the next big build phase (docs 26–31).

## Run it
```sh
export SHEN=… PIJUL=… PIJUL_CONFIG_DIR=…
make typecheck typecheck-negative typecheck-lore
make e2e t1 t1-kill t2 t3
```
