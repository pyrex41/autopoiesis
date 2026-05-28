---
date: 2026-05-28T13:15:49-05:00
researcher: pyrex41 (with Claude Opus 4.7)
git_commit: 3bc659a1743808d83063407a45abd82c255ae4ce
branch: main
repository: autopoiesis
topic: "Why you can't see what an AETHER agent did — and what a useful agent-observation/interaction surface should be"
tags: [research, aether, agent-observation, rho, tool-io, interactivity, use-case-rethink]
status: complete
last_updated: 2026-05-28
last_updated_by: pyrex41
---

# Research: Why you can't see what an AETHER agent did

**Date**: 2026-05-28T13:15:49-05:00
**Researcher**: pyrex41 (with Claude Opus 4.7)
**Git Commit**: 3bc659a1743808d83063407a45abd82c255ae4ce
**Branch**: main
**Repository**: autopoiesis

## Research Question

The user cannot dig into what an AETHER agent actually did — the thinking, the inputs, the outputs, an interactive mode. Runs report "complete" in ~10 seconds, write no files, and appear to do nothing. Step back, look at what real agent tools surface, diagnose the behavior, and rethink the use case.

## Summary

AETHER is a beautiful map of the **shape** of an agent run (prompt → think → tool → tool → done) but it discards the **substance** at capture time and cannot distinguish a failed run from a real one. Three independent failures, all confirmed empirically, combine to produce "it does nothing":

1. **Failed runs report success.** A rate-limited (HTTP 429) rho run emits `{"success":true,"type":"complete"}` and exits — AETHER draws a green ✓. A no-op run is visually identical to a real one.
2. **The agent doesn't reliably honor the working directory.** A haiku run pointed at `/tmp/rho-probe2/` wrote to absolute `/tmp/hello.py` instead, and the file didn't persist — rho's tools appear to execute in an ephemeral/sandboxed FS. AETHER scans the cwd, finds nothing, shows `files: 0`.
3. **We capture shapes, not substance, by protocol.** rho's `stream-json` `tool_result` carries **only** `{success, tool_id, tool_name}` — no stdout, no file bytes, no command output. Tool *input* is in the stream but truncated to 120 chars on capture; reasoning is truncated to 80-char flushes; the 240-char `:text` metadata cap applies everywhere. There is no transcript view, no tool-output view, and no way to talk back to a running agent.

Against the field, AETHER is missing every table-stakes affordance that successful agent tools share: a scrollable transcript, full tool I/O, diffs as the review unit, permission/steering gates, and a distinction between live-watch and post-hoc review. It built the *novel* layer (forkable content-addressed history: fork, checkout, blame, compare) on top of an *absent* foundation.

Two findings make the fix reachable: rho's **`text` output format includes the tool stdout** that `stream-json` hides, and **`--resume <session-id>` supports true multi-turn** (verified: a resumed session remembered prior context). So both richer capture and genuine interactivity are achievable without leaving rho.

## Detailed Findings

### Part 1 — What AETHER captures and surfaces today

Data flow: rho subprocess → `handle-rho-event` → `aether-snapshot` → snapshot store → REST endpoints → tracks UI.

**rho events and the fields we read** (`packages/api-server/src/aether-runtime.lisp:226-264`):
- `session` → `session_id` (formatted to a label string)
- `text_delta` → `text`, accumulated in an 80-char / 800ms flush buffer (`:199-202`)
- `tool_start` → `tool_name` + `input_summary`, **input_summary truncated to 120 chars** (`:250-254`)
- `tool_result` → `tool_name` + `success` **only — no output captured** (`:255-259`)
- `complete` → `success` → "completed"/"failed" string (`:260-262`)
- `error` → from the Lisp handler catching a subprocess exception (`:307-313`)

**What a snapshot stores** (`aether-snapshot`, `:149-180`): a `metadata` plist (`:lineage :mood :event-type :session :ticks :depth :text :cwd :files`) where `:text` is capped at 240 chars, plus an `agent-state` list `(:aether-event :event-type … :text … :session … :tick …)` whose `:text` is the pre-truncated payload. **The full file content, the full command, and all tool output never enter the store.**

**FS capture** (`should-capture-fs-p`, `capture-tree-entries`, `:48-82`): on `prompt`/`tool_result`/`complete`/`error` the working dir is scanned (`scan-directory-flat`) into Merkle tree entries; blobs hashed into the content store (in-memory + LMDB mirror). This only sees files that actually landed in the cwd.

**Endpoints** (`:644-801`): `/content` returns the (untruncated) `agent-state :text` — but for a `tool_result` it returns the *parent tool_start's* input summary (≤120 chars), not output; `/files` returns path/size/hash, no bytes; `/blame` does return full file text line-by-line from blobs; `/compare` returns metadata + sexpr-diff + FS diff (paths/sizes, no bytes).

**UI** (`frontends/command-center/src/pages/AetherMap.tsx`): hover HUD (`:1052`), detail panel with classification/topology/provenance/content/filesystem sections (`:1082`), tracks renderer (`drawTracks :803`). The "content" section shows ≤80–120 chars depending on event type. **There is no turn-by-turn transcript, no tool stdout view, and no interactive input** — the prompt bar (`:1530`) only POSTs `/spawn` or `/spawn-batch`, creating new sessions; it cannot message a running one.

**rho invocation** (`run-rho-thread`, `:266-313`): one-shot — `rho -C <cwd> -p <prompt> --output-format stream-json --model <model>`, launched via `/bin/sh -c "<cmd> </dev/null"`. **stdin is `/dev/null`** and the prompt is fixed at spawn. No follow-up channel; on stream EOF the status is set `:complete` regardless of whether the task actually succeeded.

### Part 2 — Empirical diagnosis of "10s, nothing happened"

Captured raw rho output (`/tmp/rho-raw*.jsonl`):

- **Rate-limit → false success.** `claude-sonnet` 429'd immediately; rho emitted only `session` + `complete` with `success:true`. The 429 was on stderr only; the stream looked clean. AETHER cannot tell this from a real completion.
- **Ephemeral/escaped FS.** `claude-haiku` made real `write` + `bash` tool calls (`input_summary` showed `{"content":"print(\"Hello World\")","path":"/tmp/hello.py"}`), all `success:true` — yet no file existed in the cwd or at `/tmp/hello.py` afterward. The agent used an absolute path outside the cwd, and the write did not persist to the host FS the scanner reads.
- **Output exists but is dropped.** rho `--output-format text` printed the `echo` stdout inline (`DIAGNOSTIC_MARKER_42`), proving the tool output is available from rho — `stream-json` simply omits it from `tool_result`.
- **Interactivity is available.** `rho --resume <session-id> -p "follow up"` recalled prior context ("You asked me to remember the number 7"). Multi-turn steering is a real, supported path.

### Part 3 — What real agent tools surface (comparative)

From a survey of Claude Code, Cursor, Devin, OpenHands, Zed/Aider, LangGraph Studio/LangSmith, OpenAI Agents traces. Seven consensus patterns:

1. **The scrollable transcript is the dominant end-user surface** (Claude Code, Cursor, Zed, OpenHands). The span/trace tree (LangSmith, OpenAI) is for developer debugging, not end-user watching.
2. **Full tool I/O is table-stakes** — every tool shows at minimum the exact command/path and its output/error. Devin and OpenHands show everything by default (live Shell/Browser tabs; typed action/observation pairs with full stdout/stderr); Claude Code/Cursor summarize and require opt-in for detail. Community pressure consistently pushes toward *more* default transparency.
3. **The diff is the canonical review unit for coding agents** — Cursor per-file accept/reject, Zed multi-buffer hunks, Aider unified diffs, Devin editor highlights. Tools that write files without showing diffs get pushback.
4. **Permission gates are the dominant HITL pattern** (Claude Code prompts, OpenHands `WAITING_FOR_CONFIRMATION`, Zed tool confirmation) — risk-tiered: silent reads, prompt on writes, block on destructive.
5. **Live-watch and post-hoc review are separate design problems.** Devin separates them explicitly (Following toggle for live; timeline scrubber for review). LangSmith/OpenAI are pure post-hoc.
6. **Mid-run steering is the hardest, least-solved problem.** Most tools answer "interrupt, restate, restart from checkpoint." LangGraph's `interrupt()` is the cleanest API construct. Claude Code has an open feature request for priority mid-run messaging.
7. **Reasoning visibility is an afterthought in end-user tools, first-class in debug platforms.** No end-user coding tool shows chain-of-thought by default; LangSmith/LangGraph treat intermediate state as primary.

(Sources: Claude Code permissions/verbose docs; Cursor Composer/Cloud docs; Devin interactive-planning docs; OpenHands ICLR'25 + SDK papers; Zed agent panel; Aider git docs; LangGraph time-travel + LangSmith observability; OpenAI Agents tracing. Full links in the agent transcript.)

### Part 4 — The gap

| Table-stakes affordance | Field norm | AETHER today |
|---|---|---|
| Scrollable transcript | Primary surface | Absent (track blocks only) |
| Full tool input | Shown | Truncated to 120 chars |
| Full tool output / stdout | Shown | **Never captured** (protocol) |
| File diffs as review unit | Canonical | FS file-list only; diff buried in `/compare` |
| Failed-vs-succeeded clarity | Explicit | **Failures show as ✓** |
| Permission / HITL gates | Dominant | None (fire-and-forget) |
| Mid-run steering | Hard but present | None (`-p` fixed, stdin `/dev/null`) |
| Live-watch vs review split | Recognized | Conflated |
| Forkable, content-addressed history | Rare (LangGraph time-travel) | **AETHER's unique strength — already built** |

AETHER built the rare/novel layer on top of an absent foundation. The substrate superpowers (fork, checkout, blame, compare) are real and differentiated, but they are unusable when you can't first see what the agent did.

## Use-case rethink (responding to the explicit request)

The strategic error: AETHER was designed as a *novel spatial visualization first*. The field has converged on transcript + tool-I/O + diff + steering because that is what lets a human actually see and control an agent. AETHER should be a **competent agent session client first**, with the content-addressed substrate as the layer that makes it do things no one else can (fork a run, check out any past state, blame a line to the step that wrote it, compare two attempts).

Reordered priorities, foundation before superpowers:

1. **Capture the substance.** Switch to (or additionally parse) rho's richer output so tool stdout/stderr and full tool input are stored; stop truncating reasoning/inputs at capture. Persist the real transcript.
2. **Tell success from failure.** Detect 429/provider errors (stderr + heuristics: a "complete" with zero tool calls and zero text is suspect) and mark the run failed/empty, loudly.
3. **Pin the filesystem.** Make rho actually write into the captured cwd (sandbox config / absolute-path guard), so files land where the scanner looks.
4. **Add the transcript + tool-I/O view.** A scrollable per-session transcript: prompt, reasoning, each tool's full input and output, diffs for writes. This is the thing the user is missing.
5. **Add interactivity via `--resume`.** Let the user send a follow-up into a session; spawn becomes a conversation, not a one-shot.
6. **Then** the spatial/substrate layer (tracks, fork, checkout, blame, compare) sits on top of a foundation that actually shows what happened.

## Code References

- `packages/api-server/src/aether-runtime.lisp:226-264` — rho event parsing; the fields read and dropped
- `packages/api-server/src/aether-runtime.lisp:149-180` — `aether-snapshot`; metadata + agent-state; 240-char `:text` cap
- `packages/api-server/src/aether-runtime.lisp:250-259` — tool_start truncated to 120; tool_result captures only success
- `packages/api-server/src/aether-runtime.lisp:266-313` — `run-rho-thread`; one-shot, stdin `</dev/null`, status `:complete` on EOF
- `packages/api-server/src/aether-runtime.lisp:406-423` — `content-alist-for`; tool_result returns parent input, not output
- `frontends/command-center/src/pages/AetherMap.tsx:1082-1237` — detail panel; content section ≤120 chars
- `frontends/command-center/src/pages/AetherMap.tsx:1530-1578` — prompt bar; spawn-only, no resume

## Open Questions

- Does rho's `text` format expose tool output in a machine-parseable way, or only inline prose? Does rho's `server` mode emit richer structured events than `stream-json`?
- Where do rho's tools actually execute (sandbox vs host)? Why didn't `/tmp/hello.py` persist? This governs whether "pin the cwd" is a flag or a deeper integration.
- Is the 429 a transient quota issue or a persistent key/limit problem? (Affects whether failure-detection alone is enough.)

## Related Research

- `thoughts/shared/plans/star-dream-plan.md` — original AETHER vision (spatial-first)
- `thoughts/shared/research/2026-05-21-rethinking-usability-layer-star-map-inspiration.md` — the star-map premise
- `thoughts/shared/handoffs/aether-experiment/` — Week-1 + three-agent-sprint handoffs
