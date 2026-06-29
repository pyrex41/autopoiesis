# mvfs — glossary

**as-of basis** — the monotone pair `(seq, acl-version)` a read pins; the serving node
must be applied-≥ it or refuse/redirect (read-your-writes + monotonic reads, I8).

**checkpoint** — a durable-execution snapshot landed as a fenced commit: the overlay
rootfs delta (P-D0) and, on a real host, a memory snapshot (P-D1). A worker resumes
from its last checkpoint.

**content-addressed / CAS** — content named by the hash of its bytes (git SHA / pijul
BLAKE3). A hash names exactly one byte string (I5); dedup and integrity follow.

**durable-effect!** — the worker-facing exactly-once wrapper around an external effect:
replay the recorded outcome if it already completed, else intent→run→outcome.

**egress capability** — an out-of-guest token the lease holder mints per effect; the
egress proxy admits it iff the HMAC is valid AND its epoch ≥ the current durable epoch,
so a stale/partitioned leader's effects are rejected (effect ownership, E1).

**fence / fencing token** — the lease **epoch**, CAS'd at the durable log append; a
stale leader's append is rejected (I7). The runtime half of fenced authority.

**intent → outcome** — the durable-execution journal: land intent (with idempotency
key) before an effect, land outcome after; on replay skip effects already outcome'd.

**land / land queue** — the single, serialized write path onto the trunk. A land is the
atomic, fenced, exactly-once append that makes a change part of history.

**landed-entry / landed-log** — the append-only, checksum-chained log of decisions; the
total order (I2) and the source of truth (the pijul pristine is a rebuildable cache).

**lease / lease epoch / lease-witness** — the single-leased-leader lease; its epoch is
the fence; `lease-witness` is the unforgeable type-level capability (mintable only
inside `with-leadership`) that the `land` transition demands (I7 compile-time half).

**merge oracle** — the pluggable component that decides whether a change merges cleanly
onto the trunk and produces the merged result. Default **pijul** (sound, patch-theory);
git-merge is the fallback. Orthogonal to the storage backend.

**overlay delta** — the content-addressed diff of a working tree vs its base, with
explicit `set` (added/modified) and `del` (deletion / whiteout) nodes; the P-D0
checkpoint payload. Deletions are faithful (a deleted file does not reappear on
restore).

**pland!** — the unified two-phase land driver: I3 dedup → MF-1 dep check → MF-3
land-point conflict re-check → fenced append (linearization point) → pristine apply.

**pristine** — pijul's content-addressed graph database (Sanakirja) of changes; in
mvfs it is a *rebuildable cache* of the trunk, not the source of truth.

**proven brain / trusted shell** — the architecture: pure Shen *proves* decisions
(types + Datalog); git/pijul/nginx/fs/Firecracker are *trusted oracles* behind one
audited boundary (`boundary.shen`).

**recover!** — log-first recovery: re-apply logged changes the pristine is missing
(forward), unrecord pristine changes with no log entry (orphan sweep), restore missing
bodies from the blob store, then open the write gate (MF-4b).

**serve token** — the per-principal, expiring, single-use HMAC capability minting which
authorizes one blob read; the edge verifies it before `sendfile` (I9). No content is
reachable by hash alone.

**sparse profile** — the set of path cones a mount materializes; the rest stays virtual
and faults in on demand.

**stacked changes** — a sequence of dependent changes submitted together;
restacked-on-land (spec/06).

**status (O(changes))** — working-tree status computed by a `(size, mtime)` quickcheck
then a hash fallback, so cost is proportional to changed files, not repo size.

**storage backend** — the pluggable CAS for blobs/trees: git-be (default source-of-
truth) or lore-be (large-binary fragment tier).

**trunk-only** — no branches; the only history is one linear trunk advanced by the
land queue. Conflicts are resolved before landing, not via branch merges.

**worker** — a durable-execution unit = a trunk lineage; checkpoints are its lands,
fork is O(1) (shared pre-fork state), time-travel is restore-to-checkpoint.
