import { type Component, Show, onMount } from "solid-js";
import { dagStore } from "../stores/dag";
import DAGCanvas from "./DAGCanvas";
import NodeDetail from "./NodeDetail";
import Minimap from "./Minimap";
import BranchList from "./BranchList";
import Toolbar from "./Toolbar";

/** DAG Explorer view — wraps existing DAG components */
const DAGView: Component = () => {
  onMount(() => {
    // Load data if not already loaded
    if (dagStore.snapshots().length === 0) {
      dagStore.loadMockData();
    }
  });

  return (
    <div class="dag-view">
      <Toolbar />
      <div class="dag-view-body">
        <div class="dag-canvas-wrap">
          <DAGCanvas />
          <BranchList />
          <Minimap />
          <div class="kbd-hints">
            <kbd>h</kbd>parent <kbd>l</kbd>child <kbd>j</kbd>/<kbd>k</kbd>sibling
            <br />
            <kbd>f</kbd>fit <kbd>i</kbd>panel <kbd>d</kbd>diff <kbd>Space</kbd>collapse
          </div>
        </div>
        <Show when={dagStore.detailPanelOpen()}>
          <NodeDetail />
        </Show>
      </div>
    </div>
  );
};

export default DAGView;
