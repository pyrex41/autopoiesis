import { type Component, For, Show, createSignal } from "solid-js";
import { agentStore } from "../stores/agents";
import type { Snapshot, SnapshotDiff } from "../api/types";
import * as api from "../api/client";

const SnapshotTimeline: Component = () => {
  const [loaded, setLoaded] = createSignal(false);
  const [expanded, setExpanded] = createSignal(false);
  const [selectedSnap, setSelectedSnap] = createSignal<string | null>(null);
  const [snapContent, setSnapContent] = createSignal<Snapshot | null>(null);
  const [diffMode, setDiffMode] = createSignal(false);
  const [diffA, setDiffA] = createSignal<string | null>(null);
  const [diffB, setDiffB] = createSignal<string | null>(null);
  const [diffResult, setDiffResult] = createSignal<SnapshotDiff | null>(null);
  const [diffLoading, setDiffLoading] = createSignal(false);
  const [snapshotting, setSnapshotting] = createSignal(false);

  function toggle() {
    const next = !expanded();
    setExpanded(next);
    if (next && !loaded()) {
      const id = agentStore.selectedId();
      if (id) {
        agentStore.loadAgentSnapshots(id);
        setLoaded(true);
      }
    }
  }

  async function takeSnapshot() {
    const id = agentStore.selectedId();
    if (!id) return;
    setSnapshotting(true);
    try {
      await api.takeAgentSnapshot(id);
      agentStore.loadAgentSnapshots(id);
    } catch { /* ignore */ }
    finally { setSnapshotting(false); }
  }

  async function viewSnapshot(snapId: string) {
    if (diffMode()) {
      if (!diffA()) {
        setDiffA(snapId);
      } else if (!diffB()) {
        setDiffB(snapId);
      } else {
        setDiffA(snapId);
        setDiffB(null);
        setDiffResult(null);
      }
      return;
    }
    if (selectedSnap() === snapId) {
      setSelectedSnap(null);
      setSnapContent(null);
      return;
    }
    setSelectedSnap(snapId);
    try {
      const snap = await api.getSnapshot(snapId);
      setSnapContent(snap);
    } catch {
      setSnapContent(null);
    }
  }

  async function compareDiff() {
    const a = diffA(), b = diffB();
    if (!a || !b) return;
    setDiffLoading(true);
    try {
      const result = await api.diffSnapshots(a, b);
      setDiffResult(result);
    } catch {
      setDiffResult(null);
    } finally {
      setDiffLoading(false);
    }
  }

  function toggleDiffMode() {
    const next = !diffMode();
    setDiffMode(next);
    if (!next) {
      setDiffA(null);
      setDiffB(null);
      setDiffResult(null);
    }
  }

  const snapshots = () => agentStore.agentSnapshots();

  return (
    <div class="snapshot-timeline">
      <div class="snapshot-timeline-header">
        <button class="snap-take-btn" disabled={snapshotting()} onClick={takeSnapshot}>
          {snapshotting() ? "..." : "+ Snapshot"}
        </button>
        <button
          class="snap-diff-toggle"
          classList={{ "snap-diff-active": diffMode() }}
          onClick={toggleDiffMode}
        >
          Diff
        </button>
      </div>

      <Show when={agentStore.agentSnapshotsLoading()}>
        <div class="snap-loading">Loading snapshots...</div>
      </Show>

      <Show when={snapshots().length > 0} fallback={
        <div class="snap-empty">No snapshots yet</div>
      }>
        <div class="snap-list">
          <For each={snapshots()}>
            {(snap) => {
              const isSelected = () => selectedSnap() === snap.id;
              const isDiffA = () => diffA() === snap.id;
              const isDiffB = () => diffB() === snap.id;
              return (
                <div
                  class="snap-node"
                  classList={{
                    "snap-node-selected": isSelected(),
                    "snap-node-diff-a": isDiffA(),
                    "snap-node-diff-b": isDiffB(),
                  }}
                  onClick={() => viewSnapshot(snap.id)}
                >
                  <div class="snap-node-dot" />
                  <div class="snap-node-info">
                    <span class="snap-node-hash">{snap.hash?.slice(0, 8) ?? snap.id.slice(0, 8)}</span>
                    <span class="snap-node-time">
                      {new Date(snap.timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })}
                    </span>
                  </div>
                  <Show when={snap.metadata}>
                    <span class="snap-node-meta">
                      {typeof snap.metadata === "object" && snap.metadata !== null
                        ? (snap.metadata as Record<string, unknown>).label as string ?? ""
                        : ""}
                    </span>
                  </Show>
                </div>
              );
            }}
          </For>
        </div>
      </Show>

      <Show when={diffMode() && diffA() && diffB()}>
        <button class="snap-compare-btn" disabled={diffLoading()} onClick={compareDiff}>
          {diffLoading() ? "Comparing..." : "Compare"}
        </button>
      </Show>

      <Show when={diffResult()}>
        {(d) => (
          <pre class="snap-diff-output">{d().diff}</pre>
        )}
      </Show>

      <Show when={!diffMode() && snapContent()}>
        {(snap) => (
          <div class="snap-content">
            <div class="snap-content-header">
              <span>{snap().hash?.slice(0, 12) ?? snap().id.slice(0, 12)}</span>
              <span class="snap-content-time">
                {new Date(snap().timestamp).toLocaleString()}
              </span>
            </div>
            <Show when={snap().metadata}>
              <pre class="snap-content-meta">{JSON.stringify(snap().metadata, null, 2)}</pre>
            </Show>
          </div>
        )}
      </Show>
    </div>
  );
};

export default SnapshotTimeline;
