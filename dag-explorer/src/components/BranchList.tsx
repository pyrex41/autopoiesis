import { type Component, For, createMemo } from "solid-js";
import { dagStore } from "../stores/dag";
import { centerOnNode } from "../graph/globals";

const BranchList: Component = () => {
  const sortedBranches = createMemo(() =>
    [...dagStore.branches()].sort((a, b) => b.created - a.created)
  );

  function jumpToHead(headId: string | null) {
    if (!headId) return;
    dagStore.selectNode(headId);
    centerOnNode(headId);
  }

  return (
    <div class="branch-list">
      <h3 class="branch-list-title">Branches</h3>
      <For each={sortedBranches()}>
        {(branch) => (
          <button
            class="branch-item"
            classList={{
              active:
                dagStore.selection().primary !== null &&
                branch.head === dagStore.selection().primary,
            }}
            onClick={() => jumpToHead(branch.head)}
            title={`Head: ${branch.head ?? "none"}`}
          >
            <span class="branch-name">{branch.name}</span>
            <span class="branch-head-id">
              {branch.head ? branch.head.slice(0, 8) : "empty"}
            </span>
          </button>
        )}
      </For>
    </div>
  );
};

export default BranchList;
