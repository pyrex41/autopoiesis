# mvfs — roadmap & status

Legend: ✅ built & verified in CI · 🟡 artifacts + ruled decision, deployment-gated
(needs a privileged host) · ⬜ designed, not built · ⏸ deferred.

## VCS core
| Phase | What | Status |
|---|---|---|
| P0 | Core spine: sequent-typed land FSM, fenced log, checksum chain, illegal-states-unrepresentable | ✅ (`typecheck`, `typecheck-negative`, `test`) |
| P1 land | `pland!` two-phase land (I3/MF-1/MF-3), recovery (forward reapply + orphan sweep), fault tests | ✅ (`t1` 8, `t1-kill` 9, `t2` 15, `t3` 8) |
| P1 merge | Pijul merge oracle, structural conflict detection | ✅ (`e2e`) |
| P1 read | read-tier brain: as-of basis (I8), serve tokens (I9), resolve (§5.2) | ✅ (`read` 15, `read-edge` 5) |
| P1 policy | decidable ACL (+ §6a oracle), policy lands (I6) | ✅ (`acl` 11, `policy` 9) |
| P1 VFS | checkout-first sparse mount, dirstate, O(changes) status, switch-revision | ✅ (`vfs` 17) |

## Durable execution (spec/08)
| Phase | What | Status |
|---|---|---|
| P-D0 | rootfs durability: overlay-delta serializer, fenced `checkpoint!`, faithful-delete restore, atomic fail-closed | ✅ (`dx` 12, `t-d1` 10) |
| P-D2 | exactly-once effects: intent→outcome oplog, `durable-effect!`, out-of-guest egress capability | ✅ (`oplog` 18) |
| composefs backend | real overlay-upper capture (whiteouts/xattrs) + EROFS image | 🟡 (`deploy/`, `host-composefs.lua`; needs composefs + privileged mounts) |
| serve tier | OpenResty zero-copy: `ngx.exec`→internal sendfile, mlcache, kTLS | 🟡 (`serve/`; needs OpenResty) |
| P-D1 | memory snapshots: Firecracker default, per-tenant encrypted (I10), provenance-verified (I11), fenced `restore!` | ⬜ (needs Firecracker/KVM; spec/08 §1a/§4/§5) |
| P-D3 | deterministic replay | ⏸ (WASM-only luxury) |

## The gating spikes (from spec/07), status
- **S0** read-decision-path JIT (jit.dump stays compiled) — owed on an OpenResty host.
- **S1** fenced-failover fault — ✅ covered by `t1`/`t1-kill`/`t2`.
- (durable) **T-D1** torn-artifact fail-closed — ✅ (`t-d1`); the full `dm-flakey`/
  `charybdefs` torn-write matrix is owed on a fault-injection FS.
- **T-D2** split-brain effects under partition — ✅ control-plane (`oplog` egress);
  the live egress proxy + worker network path are deployment.
- **T-D3** double-twin restore — covered in spec/08 §10 (needs the live runtime).

## Honest "what's left" (all deployment, not CI-able in a sandbox)
1. **Privileged-host harness** for P-D1: a real Firecracker VM, snapshot→encrypt→
   land→restore, with provenance signatures (I11) and per-tenant keys (I10).
2. **composefs runner**: P-D0 on a real kernel (the portable `dx.shen` model and the
   `host-composefs.lua` backend already share the delta format).
3. **OpenResty deploy** of the serve tier + the `jit.dump` "stays compiled" gate (S0).
4. **The live egress proxy** that checks `egress-ok?` on the worker's network path.
5. **Replication/HA** of the landed-log + content blobs at a stated durability width.
6. **Product surfaces**: CLI/UX for clone/submit/land/checkpoint/restore/fork; the
   stacked-change + restack-on-land flow (spec/06).

## Next reasonable increments (in priority order)
1. The **P-D1 deployment harness** on a Firecracker host (the highest-value gap).
2. The **`dm-flakey` torn-write matrix** to upgrade `t-d1` to true block-tearing.
3. Wire `effective-policy` as the **live producer** of the read tier's `allow?`
   (today `read-decide` takes `allow?` as input; `policy.can-read-at?` is the source).
4. The **CLI/product surface** (spec/06) on top of the proven core.
