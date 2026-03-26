import { type Component, Show, createSignal, onMount } from "solid-js";
import { taskStore } from "../stores/tasks";
import TaskQueue from "./TaskQueue";
import TaskBoard from "./TaskBoard";

/** Tasks view — wraps existing task components with list/kanban toggle */
const TasksView: Component = () => {
  onMount(() => {
    taskStore.refreshTasks();
  });

  const [viewMode, setViewMode] = createSignal<"list" | "kanban">("list");

  return (
    <div class="tasks-view">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">TASKS</span>
            <span class="sys-indicator-value">{taskStore.taskStats().total}</span>
          </div>
        </div>
        <div class="sys-strip-actions">
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": viewMode() === "list" }}
            onClick={() => setViewMode("list")}
          >
            List
          </button>
          <button
            class="sys-action-btn"
            classList={{ "sys-action-active": viewMode() === "kanban" }}
            onClick={() => setViewMode("kanban")}
          >
            Kanban
          </button>
        </div>
      </div>

      <Show when={viewMode() === "list"}>
        <TaskQueue />
      </Show>

      <Show when={viewMode() === "kanban"}>
        <TaskBoard
          tasks={taskStore.tasks()}
          onStatusChange={(taskId, status) => taskStore.updateTaskStatus(taskId, status)}
        />
      </Show>
    </div>
  );
};

export default TasksView;
