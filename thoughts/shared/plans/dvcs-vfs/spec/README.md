# mvfs — Design Specification

The **committed design** for `mvfs` (provisional name): a content-addressable, **trunk-only**
(no branches), monorepo distributed VCS with a virtual filesystem, at moderate scale — built in
**Shen** (compiled per-path on the author's own toolchain), shelling out to **git** for content
storage and 3-way merge, with a **Datalog** policy plane on shen-lua's native soa32 engine.

This `spec/` set supersedes the exploration in `../00`–`../32` (decision + findings consolidated).
Read `00` first — it is normative.

## Read in order

| Doc | Layer | One line |
|---|---|---|
| [`00-overview.md`](./00-overview.md) | **keystone (normative)** | Decisions, the proven-brain/trusted-shell principle, invariants **I1–I9**, the frozen §5 contracts (landed-log entry, as-of basis, serve token, Shen↔shell boundary), scope, open decisions. |
| [`01-data-model-and-storage.md`](./01-data-model-and-storage.md) | data & storage | Git-object CAS via shell-out; recursive trees; linear trunk; the checksum-chained fenced **landed-log**; Change-Id; stacks; idempotency. |
| [`02-land-queue-kernel.md`](./02-land-queue-kernel.md) | **the novel core** | Sequent-typed land FSM; leased leader; the **fencing-token protocol** (epoch CAS'd on fsync); OCC + git 3-way merge; durability-width acks; idempotency-across-handoff; per-invariant Jepsen tests. |
| [`03-policy-and-acl.md`](./03-policy-and-acl.md) | policy/authz | Decidable **Datalog** on soa32; path model (prefix-inherit / deny-wins); admission; conflict-class; policy-as-data landed through the queue; the **acl-version fence** (I6); provable policy queries. |
| [`04-read-boundary-consistency-security.md`](./04-read-boundary-consistency-security.md) | read boundary | Consistency (enforced **as-of**, RYW, monotonic, two cache classes) **and** security (**HMAC serve tokens**, public/private tiers, revocation, `/cas` lockdown) — they meet at `basis=(seq,acl-version)`. |
| [`05-serving-and-vfs.md`](./05-serving-and-vfs.md) | serving + VFS | shen-lua/OpenResty read tier (mlcache, GC64, kTLS, single-flight, trie matcher, brain-decides/nginx-serves); EdenFS-shape thin mount + dirstate; sparse/lazy checkout; latency budget. |
| [`06-product-edges.md`](./06-product-edges.md) | product | Change lifecycle + Change-Id; stacked changes + **restack-on-land**; submit→land UX; real conflict resolution; sparse monorepo; ACL-as-landed-change; CLI surface; non-goals. |
| [`07-build-plan.md`](./07-build-plan.md) | build | VCS-first phased plan on the Shen toolchain; the four gating spikes (S0–S3); the three-pillar test strategy; reimplement-later/oracle; traceability. |
| [`08-durable-execution.md`](./08-durable-execution.md) | durable execution (extension) | Checkpoint = a **fenced 3-artifact commit** (composefs rootfs delta + encrypted memory snapshot + oplog); reuse Firecracker/composefs/CRIU, build only the moat; **I10** snapshot confidentiality + **I11** restore provenance; effects are at-least-once (egress capability + oplog); restore = re-animate, not replay. Panel-reviewed (doc 42). |
| [`09-fargate-s3-deployment.md`](./09-fargate-s3-deployment.md) | deployment (applied) | The durable tier on **AWS Fargate + S3 + a standard queue** for crash-prone long-running PDF/zip batch jobs. **S3 = data plane, mvfs = control plane**; one-shot disposable tasks; the lease epoch makes at-least-once SQS safe (no split-brain); all-S3 fenced log (conditional writes) or DynamoDB; **resumable S3 multipart zip assembly** via the oplog cursor; needs *no* Firecracker/composefs/OpenResty. |

## The core idea in five lines

1. **Trunk-only**, content-addressed; the sole write path is a **serialized, fenced, single-leased-leader land queue**.
2. **Proven brain, trusted shell**: Shen sequent types + decidable Datalog prove the *decisions*; git/nginx/fs are trusted oracles; the Shen program is the executable spec/oracle.
3. **Fencing**: the fence is the monotonic **lease epoch**, CAS'd at the durable append + re-checked post-fsync → a stale leader's land is a hard error, never a silent fork (`02`).
4. **Real merge** via git 3-way; **policy-as-data** landed through the same queue, versioned by `acl-version`.
5. **Fast reads**: shen-lua decides, nginx serves bytes zero-copy; immutable content caches to the edge; the as-of basis keeps reads consistent.

## Status & next step

Design is squared (`00`–`07`). Two items need your input: the **stack-land atomicity** ruling
(`00` §6a / `06` §12) and confirmation of the **generated-matcher kill-switch** posture (`00` §6a /
`04` T14). The build starts at **P0** (`07`): the Shen skeleton, the git-shell-out CAS boundary, the
fenced landed-log, and the sequent-typed land-FSM with the four illegal programs asserted
non-constructible — plus spike **S0** (LuaJIT trace of the read decision path) and, early, spike
**S1** (the fenced-failover Jepsen run — the highest-consequence correctness work).
