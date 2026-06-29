# mvfs — invariants (I1–I11) and their traceability

The canonical invariants are defined normatively in
[`spec/00-overview.md §4`](../../../thoughts/shared/plans/dvcs-vfs/spec/00-overview.md)
(I1–I9) and [`spec/08`](../../../thoughts/shared/plans/dvcs-vfs/spec/08-durable-execution.md)
(I10–I11). This table maps each to **how it is enforced in code** and **the test that
demonstrates it**, so a reviewer can trace a claim to a green check.

| ID | Invariant | Enforced by (module) | Demonstrated by |
|---|---|---|---|
| **I1** | Single linear trunk: one parent per change, monotonic gapless `seq` | leader assigns `seq=head+1` in `pland!`/`land!` (`fsm`) | `make t2`, `make t3` (land sequence) |
| **I2** | Total land order = landed-log append order; replicas apply in that order | append order in `log`; `recover!` replays in `seq` order | `log` framing; `make t1` (W1/W2 recovery) |
| **I3** | At-most-once landing per idempotency-key | `key-find` index in `log`; `pland!` returns prior landed on a key hit; oplog keys | `make t2` (retry → no new entry); `make oplog` (durable-effect! exactly-once) |
| **I4** | No lost *acked* land: ack ⇒ durable at the stated width | fenced fsync-before-ack in `append-fenced!`/`durable-cas-append!` | `make t1` (8/8), `make t1-kill` (real SIGKILL, fsync'd log survives) |
| **I5** | Content integrity: a hash names one byte string/tree; tamper-evident | content addressing (git/pijul) + the checksum chain (`checksum`/`log`) | `make t-d1` (entry tampering → `verify-chain` false); `verify-checkpoint?` |
| **I6** | ACL soundness: authorized against the acl-version at the linearization point; no stale-allow | `acl` matcher + `policy` lands; acl-version from the log; serve token binds acl-version | `make acl` (11/11), `make policy` (9/9: revoke flips decision), `make read` (stale-acl token rejected) |
| **I7** | Fenced authority: a stale/non-leader cannot land | type-level `lease-witness` (`fsm`) **and** lease-epoch CAS at the durable append (`log`) | `make typecheck-negative` (forge/land-without-lease rejected by tc); `make t2` (split-brain: stale leader's append rejected, no orphan) |
| **I8** | Read-your-writes + monotonic reads | enforced as-of basis `(seq, acl-version)` gate in `read` | `make read` (basis-behind → deny) |
| **I9** | Authorization on every byte path: no content by hash alone | HMAC serve token mint/verify (`read`, `serve/verify.lua`); `internal` /cas | `make read` (15/15), `make read-edge` (5/5 cross-language) |
| **I10** | Snapshot confidentiality: memory images per-tenant encrypted, distinct ACL class, no cross-tenant dedup, never CDN-cached | spec/08 §5 (deployment: per-tenant envelope encryption, crypto-shredding) | design + ruling (deployment-gated; needs Firecracker host) |
| **I11** | Restore provenance: no image resumed without verified capture-component provenance over the full chain; trust in the fenced log entry, not the hash | `dx` verify-before-resume + atomic pre-flight; spec/08 §4 (sign + provenance) | `make t-d1` (fail-closed on corrupt/lost artifact, atomic); full provenance is deployment |

## Notes
- **I7 is two halves.** The *compile-time* half is the unforgeable `lease-witness`
  capability (mintable only inside `with-leadership`); the *runtime* half is the
  lease-epoch fencing token CAS'd on the durable append. Neither substitutes for the
  other. `test/illegal.shen` proves the type half (it must fail `tc +`); `t2` proves
  the runtime half (a stale epoch's append is rejected).
- **I4 honesty for durable execution.** A memory snapshot is *not* derivable from the
  log, so I4 holds only at the granularity of the newest **fully-verifiable**
  checkpoint; `recover!` falls back to it and reports the gap (spec/08 §2). For the
  log/trunk itself, I4 is at the stated durability width (proven by `t1`/`t1-kill`).
- **I5 for execution state.** A hash names the *image* (byte string), not the
  *resumed behavior* — restore is **re-animate, not replay** (nondeterminism). "Time-
  travel to checkpoint N" means "restore the captured image at N", not "replay
  history" (spec/08 §7, H1). This is documented honesty, not a loophole.
- **I10/I11** were added after the doc-42 panel review (Ptacek): a memory image is
  integrity-addressed by hash but is **not** trusted, shareable, or confidential by
  virtue of its hash — confidentiality is encryption (I10), trust is provenance in the
  fenced log entry (I11).

See [TESTING.md](TESTING.md) for the full verification matrix and pass counts.
