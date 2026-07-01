# 37 — MF-4a/b (fenced blob store + recovery gate) + real SIGKILL T1

**Status:** Built and verified (shen-lua/LuaJIT 2.1, git, pijul 1.0.0-beta.16).
Continues doc 36. Closes MF-4a/MF-4b and upgrades the crash test from
deterministic step-stops to a real `kill -9`.

---

## A sharp finding that shaped the design

Hand-restoring pijul's raw `.change` files into a fresh repo and applying by hash
**panics pijul-core** (`change.rs:1662 unwrap on NotFound`), and the
`pijul change | pijul apply` text round-trip does **not** preserve change hashes
(it re-records new ones). So poking pijul's change store is unsupported/fragile in
beta — which matches Torvalds' guardrail ("never depend on pijul internals; exit =
replay the log into another oracle"). The durable truth is therefore **the fenced
log + our own blob store of the raw change bytes**; the pijul pristine is a
rebuildable cache restored by forward re-apply from the log.

## MF-4a — fenced blob store (off-pijul byte backup)
`pland!` now mirrors each change's raw body into `<logpath>.blobs/<hash>` **before**
the fenced append (order: blob → log → apply). The blob is a faithful byte copy of
`.pijul/changes/<h[0:2]>/<h[2:]>.change`, fsync'd. Verified in `t1-kill`:
- the blob bytes equal the live change body;
- the blob **survives `rm -rf .pijul/changes`** (proving it is an independent
  off-pijul backup — the log + blobs are the durable truth, not pijul's store).

`recover!` best-effort-restores missing bodies from blobs before re-applying.

## MF-4b — recovery-before-writes gate
`pland!`'s first check is `(recovered? Logpath)`; a leader that has not run recovery
is **refused writes** (`MF-4b: recovery must run before this leader accepts
writes`). `recover!` runs forward-reapply + backward-orphan-sweep + body-restore,
then `mark-recovered!` opens the gate. Verified in `t2`: a pre-recovery land is
refused (no entry, nothing in pristine); after `recover!`, lands proceed.

(The gate token is keyed on the logpath for the test; a production gate keys on the
lease epoch so each new leadership term must re-recover. Noted, not yet done.)

## Real SIGKILL T1 (`test/t1-kill.sh`, `make t1-kill`)
`pland!` carries an inert-in-production fault seam — `(crash-point "after-append")`
between the fsync'd fenced append and the pristine apply — which the host turns
into a self-`kill -9` (FFI `kill(getpid(),9)`) iff `CRASH_AT` matches. The harness
runs `pland!` with `CRASH_AT=after-append`, so the process is genuinely SIGKILL'd
in window W1, then a **fresh** process recovers. **9 passed, 0 failed:**
- the land process died by SIGKILL (exit 137 — real `kill -9`, no flush/cleanup);
- the fenced log entry **survived** the kill (fsync'd before the crash) and still
  `verify-chain`s;
- the change was **not** in the pristine (the apply never ran — the W1 window);
- after recovery, the change is present **and** the trunk state equals the entry's
  recorded `Root` (I4/I5/I8 across a real crash);
- plus the MF-4a blob-durability assertions above.

This is the fidelity upgrade over `t1-crash.sh`: one process actually dies mid-land
(not separate per-step processes), leaving real on-disk state for recovery.

---

## Suite status (all green on the real toolchain)
```
make typecheck            OK          (tc + ; pland! + gates typecheck)
make typecheck-negative   OK          (4 illegal programs rejected)
make typecheck-lore       OK
make e2e                  oracle clean/conflict + land + I7
make t1                   8 passed    (step-stop W1/W2 recovery)
make t1-kill              9 passed    (REAL SIGKILL W1 + MF-4a durability)
make t2                  15 passed    (MF-4b gate, MF-4a blob, I7, I3, MF-3, forward progress)
```

## Must-fix scoreboard (doc 34)
- MF-1 no silent transitive apply — DONE (doc 36)
- MF-2 structural conflict detection — DONE (doc 35)
- MF-3 land-point re-check — DONE (doc 36)
- **MF-4a** change bodies in fenced blob store before append — **DONE**
- **MF-4b** recovery before writes — **DONE** (gate; key on lease epoch = TODO)
- MF-4c confirm Sanakirja fsync-on-commit — TODO (pijul config audit)
- MF-5 pin libpijul version / hash-algo id in the entry — TODO
- I3 authoritative key dedup — DONE (doc 36)
- Tests: T1 (step-stop) + T1-kill (SIGKILL) + T2 (split-brain) green; **T3**
  (dedicated TOCTOU race with a competing land between admission and land) and a
  `dm-flakey`/`charybdefs` torn-write matrix remain.

## Run it
```sh
export SHEN=… PIJUL=… PIJUL_CONFIG_DIR=…
make typecheck typecheck-negative typecheck-lore
make e2e t1 t1-kill t2
```
