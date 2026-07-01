# 35 — P1: real host backend + end-to-end run + T1 crash-atomicity

**Status:** Built and verified on the real toolchain (shen-lua/LuaJIT 2.1, git,
pijul 1.0.0-beta.15). This is the "wire the host backend and run T1 first" step
identified at the end of doc 34.

The core was typechecked but inert (every host primitive errored by default). P1
makes it **run**, against real git + real pijul + a real fsync'd log, and lands
Aphyr's ship-decider (T1, two-store crash atomicity) green.

---

## What was built

### 1. The real host backend (`host/host.lua` + `src/host-lua.shen`)
shen-lua's typed Lua bridge (`lua.call`) lets the boundary's erroring host stubs
delegate to a real Lua backend — the **only** side-effecting code:
- **shell-out** to git/pijul (errors only on exit >1, so git's rc=1
  "conflict/diff" doesn't raise);
- **checksums** — CRC normalized to `[0,2^32)` so it round-trips exactly through
  Shen numbers (doubles); xor;
- **durable fenced log** — framed US/RS records, `cas_append` = re-read head fence
  + CAS + `flush`/`close` + best-effort FFI `fsync`;
- **log scan/parse** back into `landed-entry`s (the frozen cell order);
- the **structural pijul conflict probe** (below);
- **two-store recovery** helpers (below).

`src/host-lua.shen` redefines the stubs over `lua.call` (declared external so the
package doesn't prefix it). Loaded under `tc-` (runtime), after the core.

### 2. The structural conflict probe (Aphyr MF-2)
beta.15's CLI has **no direct "is-conflicted" predicate**. The finding that made
MF-2 satisfiable without grepping working-copy markers: **`pijul archive` of a
conflicted channel prints pijul's OWN conflict report to stderr** —
`There were conflicts: - Order conflict in "" starting on line 2` — naming the
conflict *class*. That is a structural signal from pijul's detector, needs no
working-copy materialization, and is what `pijul_conflicted` keys on.

Verified the probe is faithful, not trigger-happy: **separated independent edits
= CLEAN; same/adjacent-line edits = CONFLICT** (pijul's conservative line-ordering
is genuine, reproduced directly on the CLI, not a probe artifact).

### 3. End-to-end (`test/e2e.sh`, `make e2e`)
The real FSM against a real git+pijul repo:
- **(A) pijul merge oracle** — clean candidate onto an advanced trunk →
  `admits? true`; same-line conflict candidate → `admits? false`.
- **(B) fenced land path** — `land!` writes a real git commit, `append-fenced!`
  chains + fsyncs the entry, `verify-chain → true`.
- **(C) I7** — `append-fenced!` at a stale epoch and `durable-cas-append!` with a
  wrong expected-fence are both rejected by the CAS.

### 4. T1 — two-store crash atomicity (`test/t1-crash.sh`, `make t1`)
The ship-decider. A land touches two durable stores — the fenced landed-log
(**truth**) and the pijul pristine (**rebuildable cache**) — which must crash-
agree. A pijul land records the **change-hash in the entry's `Commit` field** and
the **post-apply trunk state in `Root`** (reusing the frozen schema — no change).

`recover!` (in `src/host-lua.shen`) implements Aphyr's discipline:
- **forward** — re-apply every logged change to the trunk (idempotent: a present
  change is a no-op). Fixes **W1** (log fsync'd, pristine apply lost).
- **backward** — unrecord any trunk change with **no** log entry. Fixes **W2**
  (orphan from a post-apply-pre-log crash, or a stale leader). You can always
  drop an un-blessed pristine change; you can never invent a log entry for one.

Crash injected by running the land as discrete steps and stopping mid-sequence,
then running recovery and asserting (with **real** state-hash witnesses, guarded
against empty-string false-passes):

```
W1  C1 absent from pristine before recovery; log verifies (truth survived);
    after forward recovery C1 present AND trunk state == entry.Root (I5/I8).
W2  orphan C2 applied to pristine with no log entry; after backward sweep C2
    gone (I1/I2), C1 kept, trunk state back to the log's last Root.
T1 result: 8 passed, 0 failed.
```

---

## Honest scope / what's modeled vs real
- **Real:** git CAS + commit; pijul record/apply/fork/archive/unrecord/state; the
  structural conflict oracle; the durable fenced log (CAS + fsync); the
  log-first forward-reapply + backward-orphan-sweep recovery; the
  order-independent state hash as a checkable witness.
- **Modeled / deterministic-stop, not SIGKILL:** the crash is injected by stopping
  between land steps (each step is a separate process), which exercises every
  on-disk window boundary deterministically. A `dm-flakey`/`charybdefs` +
  page-cache-drop SIGKILL matrix (true torn writes) is the next fidelity step.
- **Not yet wired into `land!`:** the two-phase pijul land is driven by the T1
  harness; folding it into a single `pland!` driver (speculative re-check at the
  land point = MF-3, then log-append, then pristine-apply, then ack) is the next
  code step. `land!` today is the git-commit + fenced-append path.
- **Lease epoch** is a counter file (single-process model); a real lease service
  is deployment.

## Remaining must-fixes (from doc 34) and their status
- **MF-1** no silent transitive apply — not yet enforced (admission must check a
  candidate's pijul deps are already at `seq<N`). TODO.
- **MF-2** structural conflict detection — **DONE** (archive-stderr probe).
- **MF-3** land-point re-check — partially: `pijul-admits?` exists and is cheap;
  it must be re-run at the land point inside the lease in `pland!`. TODO.
- **MF-4** log-first two-phase + recovery — **demonstrated** by T1 (forward +
  backward). Remaining: store change bodies in the fenced blob store before the
  log append (4a), run the sweep before accepting writes (4b), confirm Sanakirja
  fsync-on-commit (4c).
- **MF-5** pin libpijul version / hash-algo id in the entry — TODO (the state
  hash is in the audit chain).
- **T2** fenced split-brain, **T3** conflict-admission under tip advance — TODO.

## Run it
```sh
export SHEN=… PIJUL=… PIJUL_CONFIG_DIR=…   # ssh-agent identity for pijul record
make e2e      # (A) oracle, (B) land path, (C) I7 — all green
make t1       # two-store crash atomicity — 8/8
```
