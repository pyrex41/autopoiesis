# 09 — Fargate + S3 deployment (durable batch jobs)

**Status:** Applied deployment design. Maps the durable-execution tier (`08`) and the
land kernel (`02`) onto a concrete AWS substrate — **AWS Fargate** one-shot tasks, **S3**
as the data plane, a queue for dispatch — for a real workload class: long-running,
crash-prone, browser/chart-heavy **PDF generation + zip assembly** jobs. Enforces
I3/I4/I5/I7 (land kernel) and the P-D0/P-D2 control plane (`08` §3/§6). Does **not**
require P-D1, Firecracker, composefs, or the OpenResty serve tier — see §7.

## 0. The workload and why it is crash-prone

The motivating job: render hundreds-to-thousands of PDFs (chart-heavy, headless-browser),
then assemble them into a zip. Runs for hours. Today each worker is its own image in a
Fargate task; the job is one monolithic process. The pain is **blast radius**: a crash at
PDF #1,843 of 2,000 loses the whole batch, and the final sequential zip assembly can't
resume.

The crash-proneness is **not** S3 losing data. S3 already provides storage durability —
including the zips, which are streamed from S3 and assembled on S3 via multipart upload.
The three things S3 does **not** provide, and which actually cause the pain:

1. **No consistent record of progress.** A restarted task can't cheaply learn which PDFs
   are already in S3 *and valid* (not truncated/half-written). A `LIST` is slow and
   integrity-blind; teams fall back to re-rendering or a bespoke side database.
2. **No fence / coordination.** S3 is storage, not a lease manager. Even with S3
   conditional writes, nothing stops two tasks from assembling the same zip and both
   completing — split-brain (I7's domain).
3. **No resumable sequential assembly.** The zip is a sequential stream; a mid-assembly
   crash restarts from zero because nothing recorded the resume cursor.

**Thesis:** S3 is the **data plane** and stays exactly as-is. mvfs supplies only the
missing **control plane** — a fenced, totally-ordered, integrity-checked log of which S3
objects are committed, by whom, in what order — and nothing else. It sits *beside* S3, not
in front of it. Bytes never move into mvfs.

## 1. Architecture

```
[API] --enqueue--> [SQS standard] --> [Lambda dispatcher] --RunTask--> [Fargate one-shot task]
                                                                          │  mvfs durable worker
                                                acquire lease (epoch CAS) ├──> landed-log + lease  (§3)
                                                loop: durable-effect! render ├──> [S3] PDFs (content refs)
                                                      checkpoint! every N    │
                                                zip = resumable multipart ───┤──> [S3] zip (multipart)
                                                deliver = fenced complete ───┘
   spot-kill / OOM / deploy → SQS visibility timeout → redeliver → NEW task, higher epoch
                            → recover! → replay oplog → skip done PDFs → resume at #1,843
   zombie old task → stale epoch → every land + the multipart Complete REJECTED  (no split-brain)
```

The Fargate task is **stateless and disposable**. All durable state — oplog, lease,
content references — lives outside the task (§3). The task is a body that runs the proven
loop (§4); if it dies, the next task resumes from the log.

## 2. The queue: standard at-least-once is sufficient — the fence is why

You need a queue (one-shot tasks must be dispatched and re-dispatched), and **SQS standard
is enough**. You do **not** need SQS FIFO / exactly-once: it is slower, throughput-capped,
and unnecessary, because the fence makes duplicate delivery *safe*.

SQS standard will, under normal operation, sometimes deliver the same job to two consumers
(the visibility-timeout window + at-least-once semantics). In a naive "one-shot task writes
to S3" design that means **two tasks assembling the same zip and both completing** —
duplicate deliverables, a corrupted/overwritten zip, double customer notifications. This is
the bug that surfaces weeks after the "simple" version ships.

The **lease epoch (the fence, I7)** is what makes one-shot-task + at-least-once-queue
correct:

- On start, a task acquires the job's lease via an **epoch compare-and-swap** (§3),
  obtaining the `lease-witness` capability the `land` transition demands.
- The latest acquirer wins the **higher epoch**.
- The stale task is **fenced out**: its log appends fail the CAS, and its `deliver`
  (multipart `Complete`) is rejected because the outcome-land it depends on is gone. The
  zombie cannot double-deliver.

This is the `t2` split-brain suite (15 assertions) and the `oplog` egress test (18
assertions), applied to the queue.

**Heartbeat.** Hours-long jobs renew the lease (and extend the SQS visibility timeout)
while healthy. A slow-but-alive task keeps its lease; a stalled task lets the lease lapse so
a competitor can take over at a higher epoch. Standard lease design — I7 is the fenced
version.

## 3. State placement: the control plane over S3

mvfs records **S3 references as effect outcomes**; it never re-stores bytes. The landed-log
becomes the fenced, totally-ordered, checksum-chained (I5) **index over S3 objects** that is
missing today:

```
land outcome: page #843 -> { key: "s3://bucket/job/843.pdf", version-id: …, sha256: …, seq: N }
```

`recover!` replays *this* (fast, consistent, integrity-checked via the recorded hash)
instead of a flaky `LIST`. The division is exact: **S3 = durable bytes; mvfs = which bytes
are allowed to exist, exactly once, under partition.**

### 3a. Where the fenced log + lease live — two backends

The fenced append needs a **linearizable compare-and-swap** (the epoch CAS, the
linearization point of every land). Two options; the brain is identical for both — only the
boundary backend differs (the `storage-backend` / log-append seam in `boundary.shen`):

| Backend | Mechanism | When |
|---|---|---|
| **All-S3** (recommended start) | S3 conditional writes (`If-None-Match` / CAS, GA 2024): write log entry `N` (epoch embedded) iff it does not exist; the loser gets `412` and backs off | S3-centric ops, no new service; land rate is low (thousands/job, not millions/s). **Default for this workload.** |
| **DynamoDB** | `ConditionExpression` conditional update; the epoch CAS maps 1:1 | lower per-land latency; adopt if land rate climbs or you want sub-ms leases |

For PDF-batch cadence, start **all-S3**: conditional writes are plenty and it matches the
existing footprint. The boundary work is a thin `host-s3.lua` (conditional-write append +
object presence/etag/version checks); add `host-dynamo.lua` only if you outgrow it.

## 4. The worker loop (integration surface)

What the renderer must expose — four things:

1. **A unit of work with a stable id** (the idempotency key, I3):
   `render(page_spec) -> pdf_bytes`. The `page.id` must be **stable across retries** — it
   is the dedup/replay key. Side-effect-free except producing bytes. Need not be
   byte-deterministic; if it is, you also get dedup (§6).
2. **A manifest** = the ordered `(id, page_spec)` list. `recover!` walks it to know what is
   done.
3. **Effect declarations** for the genuinely-external steps (the multipart `Complete`, a
   notification webhook, an email), each wrapped in `durable-effect!` with a stable key so
   it is fenced and exactly-once-modulo-window.
4. **A checkpoint cadence**: `checkpoint!` every N renders. Tradeoff: more checkpoints =
   less rework on crash, slightly more land overhead. For thousands of short renders, every
   25–50 is reasonable.

```
worker = acquire-lease-or-recover(job)        ; epoch CAS (§3a) → lease-witness; recover! marks done
for (id, spec) in manifest:                   ; outcome'd entries are skipped
    durable-effect!(lease, id, render-to-s3, [spec])   ; intent→render→record S3 ref as outcome
    every 50: checkpoint!(worker)
zip-multipart-assemble(lease, job, manifest)  ; §5 — resumable
durable-effect!(lease, "deliver:"+job, complete-multipart, [upload-id])  ; fenced (§5)
ack-sqs(job)                                  ; only after the deliver outcome is landed
```

## 5. Resumable S3 zip assembly

You already stream PDFs from S3 into an **S3 multipart upload** (`Initiate` → `UploadPart`
×N → `Complete`). Multipart gives resumable *storage* — parts persist until `Complete`/
`Abort`, and `ListParts` reports what landed. It does **not** give you (a) which task owns
the in-flight `UploadId`, or (b) the *logical* resume cursor (which manifest entries a part
covered). mvfs supplies both via the oplog:

- At `Initiate`: land `{ upload-id, manifest-range }`.
- Per part: land `{ part#, ETag, entries [a..b], byte-offset, central-dir-so-far }`.
- On crash → `recover!` reads the cursor → the new task **resumes the same `UploadId`** from
  part `K+1`, not from zero.
- `CompleteMultipartUpload` is the **exactly-once egress effect**: gated on the fenced
  outcome-land. The winner of that append completes; the loser/zombie sees the outcome
  already landed and **aborts** its own `UploadId`. No duplicate zip.

**STORED, not deflate.** PDFs are already compressed. Zip the entries with `STORED` (no
recompression): the archive is then concatenation + headers, with **no stateful deflate
window to checkpoint**. Part boundaries align to entry boundaries and the oplog cursor is
just "entries done + byte offset." Resume becomes nearly free. (Recompressing already-
compressed PDFs also wastes CPU for ~0 gain.)

## 6. Content addressing over S3 (optional)

Recording `(key, version-id, hash)` as the outcome already gives you **integrity** (I5: a
truncated/corrupt upload is detected because bytes ≠ recorded hash) without changing your
keys. Going further to **content-addressed keys** (`key = hash`) buys **dedup** — the same
chart PDF generated in two jobs is stored once — at the cost of a key-scheme change. Adopt
it only if dedup is worth it; the control plane works either way.

## 7. What this deployment does NOT need

The Fargate + S3 shape **sidesteps** most of the deployment-gated parts of `08`:

| `08` component | Needed here? | Why |
|---|---|---|
| **P-D1 memory snapshots / Firecracker** | **No** | Fargate gives no KVM anyway; and the expensive unit (one PDF render) is short and individually checkpointed, so re-warming headless Chrome on resume is cheap. Live-process snapshot is unnecessary. |
| **composefs rootfs** | **No** | That is for the snapshot-the-filesystem runtime. State lives in S3; the task is stateless. |
| **OpenResty serve tier** | **No** (for the job pipeline) | That is the read edge. Batch delivery is direct S3 (presigned URL / CloudFront). |
| **Large ephemeral disk / EFS** | **No** | The task holds only the working set (the PDF being rendered now); completed PDFs are pushed to S3 as outcomes immediately. |

What you **do** adopt is the **control plane**, which is the built-and-CI-verified part:
`durable-effect!`, the intent→outcome oplog, `checkpoint!`/`recover!`, the lease-epoch fence
+ egress gating, dedup, fork.

## 8. Honest limits

- The fence is enforced at the **mvfs log append** (the S3/Dynamo conditional write), not by
  S3 validating an HMAC. The HMAC egress *capability* (`08` §6) matters when there is a
  separate egress proxy (deployment-gated); on pure-S3 the fenced outcome-land + a
  conditional final-object write give the same exactly-once-modulo-window without it.
- "Exactly-once" for the external steps remains **at-least-once + idempotency** (the honest
  guarantee, `08` §6 / DECISIONS D6). Renders are idempotent by construction
  (write-blob-to-CAS); the multipart `Complete` is made single-winner by the fenced
  outcome-land. There is still a crash window between effect and outcome-land — recovery
  re-checks `ListParts` / object presence to close it.
- mvfs does not make S3 faster or cheaper. Its entire contribution is **coordination + a
  consistent committed-log over storage you already trust.**

## 9. What to build

In dependency order:

1. **`host-s3.lua`** — the all-S3 boundary backend: conditional-write log append (§3a),
   object presence/version/etag checks, multipart `Initiate`/`UploadPart`/`ListParts`/
   `Complete`/`Abort` shims. (Add `host-dynamo.lua` only if §3a calls for it.)
2. **The worker entrypoint** — `acquire-lease-or-recover` + the §4 loop, wrapping the
   existing renderer; emits S3-ref outcomes.
3. **The dispatcher** — SQS consumer (Lambda) → `RunTask`; visibility-timeout = lease TTL;
   heartbeat → extend both.
4. **The resumable zip assembler** (§5) — `STORED`, part-aligned, oplog cursor.
5. **A fault test** mirroring `t-d1`/`oplog`: kill the task mid-batch and mid-multipart;
   assert no re-render of done pages, single `Complete`, no duplicate deliverable, zombie
   fenced.

Items 1–4 are the integration; item 5 is the proof, in the style the rest of the system is
proven.
