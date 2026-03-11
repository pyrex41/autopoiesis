import { type Component, onMount, createSignal, Show } from "solid-js";
import { dagStore } from "./stores/dag";
import { taskStore } from "./stores/tasks";
import DAGCanvas from "./components/DAGCanvas";
import ThreeScene from "./components/ThreeScene";
import NodeDetail from "./components/NodeDetail";
import Toolbar from "./components/Toolbar";
import Minimap from "./components/Minimap";
import BranchList from "./components/BranchList";
import CommandPalette from "./components/CommandPalette";
import KeyboardHandler from "./components/KeyboardHandler";
import TaskScheduler from "./components/TaskScheduler";
import ChatPane from "./components/ChatPane";

const App: Component = () => {
  const [ready, setReady] = createSignal(false);

  onMount(() => {
    dagStore.loadMockData();
    // Orchestrated reveal: stagger the UI elements in
    requestAnimationFrame(() => setReady(true));
  });

  return (
    <div class="app-layout" classList={{ "app-ready": ready() }}>
      <KeyboardHandler />
      <Toolbar />
      <div class="app-main">
        <div class="canvas-container">
          <Show when={dagStore.viewMode() === "2d"}>
            <DAGCanvas />
            <Show when={ready()}>
              <BranchList />
              <Minimap />
              <div class="kbd-hints">
                <kbd>h</kbd>parent <kbd>l</kbd>child <kbd>j</kbd>/<kbd>k</kbd>sibling
                <br />
                <kbd>f</kbd>fit <kbd>i</kbd>panel <kbd>d</kbd>diff <kbd>/</kbd>search
                <br />
                <kbd>Space</kbd>collapse <kbd>Ctrl+K</kbd>commands
              </div>
            </Show>
          </Show>
          <Show when={dagStore.viewMode() === "3d"}>
            <ThreeScene />
          </Show>
        </div>
        <NodeDetail />
      </div>
      <CommandPalette />
      <ChatPane />
      <Show when={taskStore.showTaskScheduler()}>
        <TaskScheduler />
      </Show>
    </div>
  );
};

export default App;
