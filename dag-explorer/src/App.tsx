import { type Component, onMount } from "solid-js";
import { dagStore } from "./stores/dag";
import DAGCanvas from "./components/DAGCanvas";
import NodeDetail from "./components/NodeDetail";
import Toolbar from "./components/Toolbar";
import Minimap from "./components/Minimap";
import BranchList from "./components/BranchList";
import CommandPalette from "./components/CommandPalette";
import KeyboardHandler from "./components/KeyboardHandler";

const App: Component = () => {
  onMount(() => {
    // Start with mock data so the explorer works standalone
    dagStore.loadMockData();
  });

  return (
    <div class="app-layout">
      <KeyboardHandler />
      <Toolbar />
      <div class="app-main">
        <div class="canvas-container">
          <DAGCanvas />
          <BranchList />
          <Minimap />
          <div class="kbd-hints">
            <kbd>h</kbd>parent <kbd>l</kbd>child <kbd>j</kbd>/<kbd>k</kbd>sibling
            <br />
            <kbd>f</kbd>fit <kbd>i</kbd>inspector <kbd>d</kbd>diff
            <br />
            <kbd>/</kbd>search <kbd>Ctrl+K</kbd>commands <kbd>Space</kbd>collapse
          </div>
        </div>
        <NodeDetail />
      </div>
      <CommandPalette />
    </div>
  );
};

export default App;
