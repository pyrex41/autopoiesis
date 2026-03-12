import { type Component, Show } from "solid-js";
import { dagStore } from "../stores/dag";
import { taskStore } from "../stores/tasks";
import { fitToView } from "../graph/globals";
import type { ColorScheme, LayoutDirection } from "../api/types";

const Toolbar: Component = () => {
  return (
    <div class="toolbar">
      <div class="toolbar-group">
        <span class="toolbar-brand">AP DAG Explorer</span>
        <div class="toolbar-sep" />

        <button
          class="btn-toolbar"
          classList={{ active: dagStore.dataSource() === "mock" }}
          onClick={() => dagStore.loadMockData()}
          title="Load mock data"
        >
          Mock
        </button>
        <button
          class="btn-toolbar"
          classList={{ active: dagStore.dataSource() === "live" }}
          onClick={() => dagStore.loadFromAPI()}
          title="Connect to live API"
        >
          Live
        </button>
        <div class="toolbar-sep" />

        <Show when={dagStore.loading()}>
          <span class="toolbar-status">Loading...</span>
        </Show>
        <Show when={dagStore.error()}>
          <span class="toolbar-error" title={dagStore.error()!}>
            {dagStore.error()!.slice(0, 40)}
          </span>
        </Show>
      </div>

      <div class="toolbar-group">
        <label class="toolbar-label">
          Layout:
          <select
            value={dagStore.direction()}
            onChange={(e) =>
              dagStore.setDirection(e.currentTarget.value as LayoutDirection)
            }
          >
            <option value="TB">Top-Down</option>
            <option value="LR">Left-Right</option>
          </select>
        </label>

        <label class="toolbar-label">
          Color:
          <select
            value={dagStore.colorScheme()}
            onChange={(e) =>
              dagStore.setColorScheme(e.currentTarget.value as ColorScheme)
            }
          >
            <option value="branch">Branch</option>
            <option value="agent">Agent</option>
            <option value="depth">Depth</option>
            <option value="time">Time</option>
            <option value="mono">Mono</option>
          </select>
        </label>

        <div class="toolbar-sep" />

        <button
          class="btn-toolbar"
          classList={{ active: dagStore.diffMode() }}
          onClick={() => dagStore.setDiffMode(!dagStore.diffMode())}
          title="Toggle diff mode (click two nodes to compare)"
        >
          Diff
        </button>

        <button
          class="btn-toolbar"
          onClick={() => dagStore.setDetailPanelOpen(!dagStore.detailPanelOpen())}
          title="Toggle inspector panel [i]"
        >
          {dagStore.detailPanelOpen() ? "Hide" : "Show"} Inspector
        </button>

        <button
          class="btn-toolbar"
          onClick={() => fitToView()}
          title="Fit graph to view [f]"
        >
          Fit
        </button>

        <button
          class="btn-toolbar"
          classList={{ active: dagStore.viewMode() === "3d" }}
          onClick={() => dagStore.setViewMode(dagStore.viewMode() === "2d" ? "3d" : "2d")}
          title="Toggle 2D/3D view"
        >
          {dagStore.viewMode() === "2d" ? "2D" : "3D"}
        </button>

        <div class="toolbar-sep" />

        <div class="toolbar-stats">
          {dagStore.snapshots().length} nodes &middot;{" "}
          {dagStore.branches().length} branches
        </div>
      </div>

      <div class="toolbar-group">
        <input
          type="text"
          class="search-input"
          placeholder="Search nodes... [/]"
          value={dagStore.searchQuery()}
          onInput={(e) => dagStore.setSearchQuery(e.currentTarget.value)}
        />
        <Show when={dagStore.searchResults()}>
          <span class="search-count">
            {dagStore.searchResults()!.length} hits
          </span>
        </Show>

        <button
          class="btn-toolbar"
          classList={{ active: taskStore.showTaskScheduler() }}
          onClick={() => taskStore.setShowTaskScheduler(!taskStore.showTaskScheduler())}
          title="Task scheduler"
        >
          📋 Tasks
        </button>

        <button
          class="btn-toolbar"
          onClick={() => dagStore.setShowCommandPalette(true)}
          title="Command palette [Ctrl+K]"
        >
          Cmd
        </button>
      </div>
    </div>
  );
};

export default Toolbar;
