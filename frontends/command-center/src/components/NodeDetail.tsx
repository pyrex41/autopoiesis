import { Show, For, type Component, createMemo } from "solid-js";
import { dagStore } from "../stores/dag";

const NodeDetail: Component = () => {
  const selectedNode = createMemo(() => {
    const sel = dagStore.selection();
    if (!sel.primary) return null;
    return dagStore.layout().nodes.get(sel.primary) ?? null;
  });

  const secondaryNode = createMemo(() => {
    const sel = dagStore.selection();
    if (!sel.secondary) return null;
    return dagStore.layout().nodes.get(sel.secondary) ?? null;
  });

  const ancestors = createMemo(() => dagStore.primaryAncestors());
  const descendants = createMemo(() => dagStore.primaryDescendants());

  function formatTimestamp(ts: number): string {
    return new Date(ts * 1000).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  function formatMeta(meta: unknown): string {
    if (!meta) return "none";
    return JSON.stringify(meta, null, 2);
  }

  return (
    <div class="detail-panel" classList={{ open: dagStore.detailPanelOpen() }}>
      <div class="detail-header">
        <span class="detail-title">Inspector</span>
        <button
          class="btn-icon"
          onClick={() => dagStore.setDetailPanelOpen(!dagStore.detailPanelOpen())}
          title="Toggle panel"
        >
          {dagStore.detailPanelOpen() ? "\u25B6" : "\u25C0"}
        </button>
      </div>

      <Show when={dagStore.detailPanelOpen()}>
        <div class="detail-body">
          <Show
            when={selectedNode()}
            fallback={
              <div class="detail-empty">
                Click a node to inspect it.
                <br />
                <kbd>Shift+click</kbd> second node for diff.
                <br />
                <kbd>Double-click</kbd> to collapse.
              </div>
            }
          >
            {(node) => {
              const n = node();
              const snap = n.snapshot;
              const meta = snap.metadata as Record<string, unknown> | null;
              return (
                <>
                  <section class="detail-section">
                    <h3>Snapshot</h3>
                    <dl>
                      <dt>ID</dt>
                      <dd class="mono">{snap.id}</dd>
                      <dt>Timestamp</dt>
                      <dd>{formatTimestamp(snap.timestamp)}</dd>
                      <dt>Parent</dt>
                      <dd>
                        <Show when={snap.parent} fallback={<em>root</em>}>
                          <button
                            class="link-btn"
                            onClick={() => dagStore.selectNode(snap.parent!)}
                          >
                            {snap.parent!.slice(0, 16)}..
                          </button>
                        </Show>
                      </dd>
                      <dt>Hash</dt>
                      <dd class="mono">{snap.hash ?? "n/a"}</dd>
                      <dt>Depth</dt>
                      <dd>{n.depth}</dd>
                      <dt>Descendants</dt>
                      <dd>{n.childCount}</dd>
                    </dl>
                  </section>

                  <Show when={n.branchNames.length > 0}>
                    <section class="detail-section">
                      <h3>Branch Head</h3>
                      <For each={n.branchNames}>
                        {(name) => <span class="badge">{name}</span>}
                      </For>
                    </section>
                  </Show>

                  <Show when={meta}>
                    <section class="detail-section">
                      <h3>Metadata</h3>
                      <pre class="meta-pre">{formatMeta(meta)}</pre>
                    </section>
                  </Show>

                  <section class="detail-section">
                    <h3>Lineage</h3>
                    <dl>
                      <dt>Ancestors</dt>
                      <dd>{ancestors().size}</dd>
                      <dt>Descendants</dt>
                      <dd>{descendants().size}</dd>
                    </dl>
                  </section>

                  <Show when={secondaryNode()}>
                    {(sec) => (
                      <section class="detail-section diff-section">
                        <h3>
                          Comparison Target
                        </h3>
                        <dl>
                          <dt>ID</dt>
                          <dd class="mono">{sec().snapshot.id}</dd>
                          <dt>Timestamp</dt>
                          <dd>{formatTimestamp(sec().snapshot.timestamp)}</dd>
                        </dl>
                        <button
                          class="btn-primary"
                          onClick={() => dagStore.computeDiff()}
                        >
                          Compute Diff
                        </button>
                      </section>
                    )}
                  </Show>

                  <Show when={dagStore.diffResult()}>
                    <section class="detail-section">
                      <h3>Diff</h3>
                      <pre class="diff-pre">{dagStore.diffResult()}</pre>
                    </section>
                  </Show>

                  <Show when={snap.agentState}>
                    <section class="detail-section">
                      <h3>Agent State</h3>
                      <pre class="meta-pre">{snap.agentState}</pre>
                    </section>
                  </Show>
                </>
              );
            }}
          </Show>
        </div>
      </Show>
    </div>
  );
};

export default NodeDetail;
