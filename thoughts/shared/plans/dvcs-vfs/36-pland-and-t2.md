# 36 — `pland!`: the unified two-phase land + T2 (fenced split-brain)

**Status:** Built and verified (shen-lua/LuaJIT 2.1, git, pijul 1.0.0-beta.15).
Continues doc 35. Folds the merge oracle + fenced log + two-store discipline into
one typed driver, closing MF-1 and MF-3, and lands T2 green.

---

## `pland!` — one driver, log-first, all guards (in `fsm.shen`, typed core)

```
pland! : lease -> id -> id -> hash -> principal -> number -> string -> string -> landed
         (lease  cid   key   change   author      aclv      trunk     logpath)
```

Order (Aphyr, log-first — the log is truth, the pristine is a cache):

1. **I3 (authoritative idempotency).** If the idempotency-`key` is already in the
   log, return the prior `landed` — a retried submission is a no-op. This is the
   real I3 guard; pijul's apply-idempotency is only a merge-layer backstop (a
   re-recorded change can get a different hash, so hash-equality is not enough).
2. **MF-1 (no silent transitive apply).** Reject if the candidate has pijul
   dependencies not yet in the trunk — else `apply` would pull un-`seq`'d changes
   into the trunk (I1/I2 violation). `pijul-deps-in-trunk?` parses the candidate's
   `# Dependencies` and checks each is in `pijul log --channel trunk`.
3. **MF-3 (land-point re-check).** Re-run the speculative conflict probe against
   the **committed** tip *inside the lease* (`pijul-admits?`). Admission-time
   conflict-freedom is not stable across tip advance; this is the OCC validation.
4. **(B) fenced append = linearization point.** Build the entry with
   `Commit = change-hash`, `Root =` the probed would-be trunk state
   (`pijul-probe-state`, fork+apply+state+discard — no trunk mutation), and
   `Fence = lease epoch`; `append-fenced!` does the CAS + fsync.
5. **(C) pristine apply** — only on a successful fenced append.

A stale leader fails the fence CAS at (B) and **never reaches (C)** — log-first
means a rejected land leaves the pristine untouched. No orphan to sweep: the
rejection is clean, which is *stronger* than T1's "swept on recovery."

The driver typechecks under `tc +`:
`(lease --> string --> string --> string --> string --> number --> string --> string --> landed)`.
All side effects stay behind the boundary verbs; `pland!` itself is pure control
flow over them. New typed support added: `entry-cid/key/commit/root` accessors
(`types.shen`), `key-find`/`key-present?` I3 index (`log.shen`),
`pijul-probe-state` + `pijul-deps-in-trunk?` (`boundary.shen`).

---

## T2 — fenced split-brain + idempotency (`test/t2-split-brain.sh`, `make t2`)

Drives real lands through `pland!` against a real pijul trunk. **12 passed, 0
failed**, all with real state-hash witnesses:

```
leader B (epoch 2) lands C1            -> C1 in pristine; log 1 entry; state S1
I7  stale leader A (epoch 1) lands C2  -> C2 NOT in pristine (log-first: no orphan);
                                          log still 1; state still S1
I3  leader B retries C1 (same key k1)  -> returns prior landed; NO new entry; state S1
live leader B lands C2 for real        -> C2 in pristine; log 2 entries; state S2
MF-3 leader B lands CX (conflicts C2)  -> CX NOT in pristine; log still 2; state S2
```

This is the split-brain story end to end: the fence (lease epoch CAS at the
durable append, I7) is the single arbiter of who may land; a stale leader cannot
append and — because the apply is downstream of the append — cannot even dirty
the pristine. Idempotent retries collapse to the prior result. Conflicts are
rejected by pijul's structural oracle at the committed tip.

---

## Must-fix status (doc 34) after this increment
- **MF-1** no silent transitive apply — **DONE** (`pijul-deps-in-trunk?` gate in `pland!`).
- **MF-2** structural conflict detection — DONE (doc 35).
- **MF-3** land-point re-check — **DONE** (`pijul-admits?` inside the lease in `pland!`).
- **MF-4** log-first two-phase + recovery — demonstrated (T1); remaining 4a/4b/4c
  (change bodies in the fenced blob store before append; sweep-before-writes;
  Sanakirja fsync-on-commit) still TODO.
- **MF-5** pin libpijul version / hash-algo id in the entry — TODO.
- **I3** authoritative idempotency-key dedup — **DONE** (`key-find` in `pland!`).
- Tests: **T1** (W1/W2 recovery) and **T2** (split-brain) green; **T3** is now
  largely subsumed by T2's MF-3 case but a dedicated TOCTOU race (clean@T,
  conflict@T+1 with a concurrent competing land between admission and land) is
  still worth adding; the SIGKILL+page-cache fault matrix (vs deterministic
  step-stops) remains the durability fidelity step.

## Run it
```sh
export SHEN=… PIJUL=… PIJUL_CONFIG_DIR=…
make e2e && make t1 && make t2     # oracle/land/I7 ; crash-atomicity 8/8 ; split-brain 12/12
```
