---
date: 2026-02-17T16:11:53Z
researcher: reuben
git_commit: 12a7db1
branch: main
repository: pyrex41/autopoiesis
topic: "PR #3 Bevy Holodeck Integration Review"
tags: [research, pr-review, holodeck, bevy, websocket, api-contract, monorepo]
status: complete
last_updated: 2026-02-17
last_updated_by: reuben
---

# Research: PR #3 Bevy Holodeck Integration Review

**Date**: 2026-02-17T16:11:53Z
**Researcher**: reuben
**Git Commit**: 12a7db1
**Branch**: main
**Repository**: pyrex41/autopoiesis

## Research Question

Review PR #3 ("Add Bevy-based 3D frontend (Holodeck) for Autopoiesis platform") and how it integrates with the current codebase, given that core substrate/orchestration changes have landed since the PR was created. Determine whether the PR's API contract still holds.

## Summary

**PR #3 is safe to merge with minor structural adjustments.** The PR does two things:

1. **Monorepo restructuring**: Moves all CL code into `platform/` subdirectory
2. **New Bevy/Rust holodeck**: Adds `holodeck/` with a 3D frontend that speaks WebSocket to the CL backend

The core concern — whether the Bevy frontend's protocol contract conflicts with the substrate/orchestration/conversation changes that landed since — is a **non-issue**. The PR's frontend talks exclusively through the WebSocket API layer (`src/api/`), which remains unchanged. The substrate, orchestration, and conversation layers are internal implementation details that sit beneath the API and don't affect the wire protocol.

## Detailed Findings

### 1. What PR #3 Contains

**3,475 additions, 12 deletions.** Two logical units:

#### A. Monorepo restructuring (path moves only)
- Moves `src/` → `platform/src/`, `test/` → `platform/test/`, `autopoiesis.asd` → `platform/autopoiesis.asd`
- Moves `scripts/`, `Dockerfile`, `docker-compose.yml` into `platform/`
- Updates `CLAUDE.md` paths and adds holodeck build instructions
- Adds Rust entries to `.gitignore`

#### B. Bevy/Rust holodeck (entirely new code in `holodeck/`)
```
holodeck/
  Cargo.toml           # Bevy 0.15, tungstenite, rmp-serde, crossbeam
  src/
    main.rs            # App entry
    protocol/          # WebSocket client, codec, message types, Bevy events
    state/             # Resources (AgentRegistry, ConnectionStatus), Components
    systems/           # ECS: agents, thoughts, snapshots, layout, selection, animation
    rendering/         # Materials, environment, postprocessing (bloom)
    ui/                # egui: HUD, command bar, agent panel, notifications, thought inspector
    plugins/           # ConnectionPlugin, ScenePlugin, AgentPlugin, UiPlugin
```

### 2. The Protocol Contract (Core of the Review)

The Bevy frontend connects to `ws://localhost:8080/ws` and communicates via:
- **Text frames (JSON)**: Client → Server requests, Server → Client responses
- **Binary frames (MessagePack)**: Server → Client push notifications (events, thoughts, state changes)

#### Client → Server messages (PR's `ClientMessage` enum):
| Message Type | Fields | Current Backend Handler |
|---|---|---|
| `ping` | — | `handle-ping` (handlers.lisp:434) |
| `system_info` | — | `handle-system-info` (handlers.lisp:438) |
| `set_stream_format` | `format` | `handle-set-stream-format` (handlers.lisp:377) |
| `subscribe` | `channel` | `handle-subscribe` (handlers.lisp:392) |
| `unsubscribe` | `channel` | `handle-unsubscribe` (handlers.lisp:400) |
| `list_agents` | — | `handle-list-agents` (handlers.lisp:108) |
| `get_agent` | `agentId` | `handle-get-agent` (handlers.lisp:114) |
| `create_agent` | `name`, `capabilities` | `handle-create-agent` (handlers.lisp:126) |
| `agent_action` | `agentId`, `action` | `handle-agent-action` (handlers.lisp:144) |
| `step_agent` | `agentId`, `environment?` | `handle-step-agent` (handlers.lisp:179) |
| `get_thoughts` | `agentId`, `limit?` | `handle-get-thoughts` (handlers.lisp:200) |
| `inject_thought` | `agentId`, `content`, `thoughtType` | `handle-inject-thought` (handlers.lisp:217) |
| `list_snapshots` | `limit?` | `handle-list-snapshots` (handlers.lisp:261) |
| `get_snapshot` | `snapshotId` | `handle-get-snapshot` (handlers.lisp:276) |
| `create_snapshot` | `agentId`, `label` | `handle-create-snapshot` (handlers.lisp:288) |
| `list_branches` | — | `handle-list-branches` (handlers.lisp:316) |
| `create_branch` | `name`, `fromSnapshot` | `handle-create-branch` (handlers.lisp:323) |
| `switch_branch` | `name` | `handle-switch-branch` (handlers.lisp:334) |
| `list_blocking_requests` | — | `handle-list-blocking` (handlers.lisp:348) |
| `respond_blocking` | `requestId`, `response` | `handle-respond-blocking` (handlers.lisp:354) |
| `get_events` | `limit?`, `eventType?`, `agentId?` | `handle-get-events` (handlers.lisp:412) |

**Every single message type in the PR has a corresponding handler in the current backend.** The contract is 1:1.

#### Server → Client messages (PR's `ServerMessage` enum):
| Response Type | Current Backend Source |
|---|---|
| `pong` | handlers.lisp:436 |
| `system_info` | handlers.lisp:438-445 |
| `subscribed`/`unsubscribed` | handlers.lisp:392-406 |
| `stream_format_set` | handlers.lisp:377-390 |
| `agents` | handlers.lisp:108-112 |
| `agent` | handlers.lisp:114-124 |
| `agent_created` | handlers.lisp:126-142 |
| `agent_state_changed` | handlers.lisp:144-177 |
| `step_complete` | handlers.lisp:179-194 |
| `thoughts` | handlers.lisp:200-215 |
| `thought_added` | handlers.lisp:217-255 |
| `snapshots` | handlers.lisp:261-274 |
| `snapshot` | handlers.lisp:276-286 |
| `snapshot_created` | handlers.lisp:288-310 |
| `branches` | handlers.lisp:316-321 |
| `branch_created` | handlers.lisp:323-332 |
| `branch_switched` | handlers.lisp:334-342 |
| `blocking_requests` | handlers.lisp:348-352 |
| `blocking_request` | events.lisp:91-113 (push) |
| `blocking_responded` | handlers.lisp:354-371 |
| `events` | handlers.lisp:412-428 |

**Complete match.** All response types the Rust client expects are produced by the current backend.

#### Data shape compatibility:
| Object | PR Expects (Rust struct) | Backend Produces (serializers.lisp) | Match? |
|---|---|---|---|
| Agent | `{id, name, state, capabilities, parent, children, thoughtCount}` | `agent-to-json-plist` (serializers.lisp:13-24) | **Yes** — exact field match |
| Thought | `{id, timestamp, type, confidence, content, provenance?, source?, rationale?, alternatives?}` | `thought-to-json-plist` (serializers.lisp:30-67) | **Yes** — base + subclass fields match |
| Snapshot | `{id, parentId?, branch, label?, timestamp}` | `snapshot-to-json-plist` (serializers.lisp:73-80) | **Minor diff** — backend sends `parent`, `hash`, `metadata`; PR expects `parentId`, `branch`, `label` |
| Branch | `{name, head?}` | `branch-to-json-plist` (serializers.lisp:86-90) | **Yes** — `name`, `head`, `created` |
| BlockingRequest | `{requestId, agentId, prompt, options}` | `blocking-request-to-json-plist` (serializers.lisp:116-124) | **Minor diff** — backend uses `id` not `requestId`, sends `context`, `default`, `status`, `createdAt` |
| Event | `{eventType, agentId?, timestamp, data}` | `event-to-json-plist` (serializers.lisp:96-103) | **Minor diff** — backend sends `type` not `eventType`, plus `id`, `source` |

### 3. Identified Mismatches (All Minor, Easily Fixed)

These are small naming/shape differences between what the Rust `#[serde(rename_all)]` expects and what the CL serializers produce. All are trivially fixable on either side:

1. **Snapshot: `parent` vs `parentId`** — The backend sends `"parent"` (serializers.lisp:77), the Rust struct uses `#[serde(rename_all = "camelCase")]` expecting `"parentId"`. Fix: rename backend key to `"parentId"` or add `#[serde(rename = "parent")]` in Rust.

2. **Snapshot: missing `branch`/`label` fields** — Backend sends `hash` and `metadata` instead. The Rust struct has `#[serde(default)]` on both, so it won't crash — they'll just be empty. Fine for now.

3. **BlockingRequest: `id` vs `requestId`** — Backend sends `"id"` (serializers.lisp:118), Rust expects `"requestId"`. The Rust struct uses `#[serde(rename_all = "camelCase")]` so it would look for `"requestId"`. Fix: add alias.

4. **BlockingRequest: missing `agentId`** — Backend's `blocking-request-to-json-plist` doesn't include `agentId`. The Rust struct has no `#[serde(default)]` on this field. This would cause deserialization failures. Fix: add `agentId` to the CL serializer, or add `#[serde(default)]` in Rust.

5. **Event: `type` vs `eventType`** — Backend sends `"type"`, Rust struct has `event_type` which with `camelCase` becomes `"eventType"`. The Rust struct has `#[serde(default)]` so it won't crash — it'll just be empty string.

### 4. Core Changes That Don't Affect the PR

The substrate, orchestration, and conversation layers that have been added/changed since the PR was created are **entirely internal** to the CL backend:

| New/Changed Layer | Files | Impact on PR |
|---|---|---|
| **Substrate** (16 files) | `src/substrate/*.lisp` — datom store, LMDB, Linda, entity types, blob store | **None** — provides backing store for agents, events, workers. API layer unchanged. |
| **Orchestration** (4 files) | `src/orchestration/*.lisp` — conductor, timer heap, Claude CLI workers | **None** — internal tick loop and worker management. No API exposure. |
| **Conversation** (3 files) | `src/conversation/*.lisp` — turns, context | **None** — conversation management, not exposed via WebSocket API. |
| **ASDF restructuring** | `autopoiesis.asd` — added substrate, orchestration, conversation modules; added `autopoiesis/api` subsystem | **Needs merge attention** — PR moves .asd to `platform/`, current .asd has new modules. |
| **Test additions** | `test/substrate-tests.lisp`, `test/orchestration-tests.lisp`, `test/conversation-tests.lisp`, etc. | **Needs merge attention** — PR moves tests to `platform/test/`. |

### 5. Monorepo Restructuring Conflicts

The PR's monorepo restructure (CL code → `platform/`) will conflict with post-PR changes, but **only in a mechanical sense** (file moves, not logic conflicts):

| Conflict Area | Nature | Resolution |
|---|---|---|
| `autopoiesis.asd` | PR copies old version to `platform/`; current has new modules (substrate, orchestration, conversation) | Re-do the move with current .asd |
| `CLAUDE.md` | PR version reflects old 8-layer architecture; current has 11-layer with substrate/orchestration | Re-do the move with current CLAUDE.md |
| New source files | `src/substrate/`, `src/orchestration/`, `src/conversation/` don't exist in PR branch | Add them to `platform/src/` |
| New test files | `test/substrate-tests.lisp`, `test/orchestration-tests.lisp`, etc. | Add them to `platform/test/` |

**None of these are semantic conflicts.** They're purely "the PR branched before these files existed, so it doesn't include them in its moves."

### 6. PR's Bevy Client Architecture

For reference, the Bevy frontend has a clean architecture that doesn't assume anything about CL internals:

- **WebSocket thread** (`protocol/client.rs`): Background thread with `tungstenite`, exponential backoff reconnection, lock-free `crossbeam` channels to Bevy main loop
- **Connection system** (`systems/connection.rs`): Drains channel each frame, converts `ConnectionEvent` → typed Bevy events
- **On connect**: Sends `set_stream_format: "json"`, subscribes to `"agents"` and `"events"` channels, requests `system_info` and `list_agents`
- **State caches** (`state/resources.rs`): `AgentRegistry`, `SnapshotTree`, `ThoughtCache`, `BlockingRequests` — all populated from WebSocket messages
- **ECS entities**: Agents become icospheres, thoughts become particles, snapshots become DAG nodes

## Architecture Documentation

The integration boundary is clean:

```
                    ┌──────────────────────┐
                    │  Bevy/Rust Holodeck   │
                    │  (PR #3 - new code)   │
                    └──────────┬───────────┘
                               │ WebSocket (ws://localhost:8080/ws)
                               │ JSON text frames (control)
                               │ MessagePack binary frames (push)
                    ┌──────────┴───────────┐
                    │   API Layer (stable)  │
                    │  src/api/ (unchanged) │
                    │  handlers, serializers│
                    │  wire-format, events  │
                    └──────────┬───────────┘
                               │ Internal CL function calls
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────┴────────┐ ┌────┴────┐  ┌────────┴───────┐
    │ Substrate (new)  │ │  Agent  │  │ Orchestration  │
    │ datom, LMDB,     │ │  Layer  │  │  (new)         │
    │ Linda, blobs     │ │(stable) │  │  conductor,    │
    │                  │ │         │  │  workers       │
    └──────────────────┘ └─────────┘  └────────────────┘
```

The Bevy frontend only touches the top boundary. Everything below the API layer can change freely without affecting the frontend.

## Code References

- PR #3: https://github.com/pyrex41/autopoiesis/pull/3
- `src/api/handlers.lisp` — All WebSocket message handlers (the contract the PR depends on)
- `src/api/serializers.lisp` — JSON serialization for wire types
- `src/api/wire-format.lisp` — Hybrid JSON/MessagePack protocol
- `src/api/server.lisp` — Clack/Woo WebSocket server on port 8080
- `src/api/connections.lisp` — Connection management, subscriptions, broadcasting
- `src/api/events.lisp` — Event bridge (integration events → WebSocket push)
- PR `holodeck/src/protocol/types.rs` — Rust-side message types
- PR `holodeck/src/protocol/client.rs` — WebSocket client with reconnection
- PR `holodeck/src/protocol/codec.rs` — JSON/MessagePack codec
- PR `holodeck/src/state/resources.rs` — Bevy resources (state caches)

## Recommendations for Merge

1. **Rebase the monorepo restructuring** against current `main` to pick up new files (substrate, orchestration, conversation). This is mechanical — just ensure the new directories are also moved into `platform/`.

2. **Fix the 4-5 minor serialization mismatches** listed above (easiest on the Rust side with `#[serde(rename)]` and `#[serde(default)]`).

3. **Update CLAUDE.md** in the PR to reflect the current 11-layer architecture (add substrate, orchestration, conversation layers, updated test counts).

4. **The holodeck code itself is clean** and can merge as-is after the restructuring rebase.

## Open Questions

1. **Do we still want the monorepo restructuring?** Moving CL into `platform/` is a significant path change. The Bevy holodeck can live in `holodeck/` without requiring the CL move — it just connects via WebSocket.

2. **Should the CL holodeck (`src/holodeck/`) coexist with the Bevy holodeck?** PR keeps both — the CL version in `platform/src/holodeck/` and the Rust version in `holodeck/`. This seems fine as they serve different purposes (CL is terminal-based 3D simulation, Bevy is GPU-rendered).

3. **The PR sets stream format to JSON on connect** (`client.rs:84`). For production, switching to MessagePack would be more efficient. This is configurable per-connection so it's just a client-side change.
