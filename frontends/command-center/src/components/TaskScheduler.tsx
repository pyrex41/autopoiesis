import { type Component, createSignal, Show } from "solid-js";
import TaskCalendar from "./TaskCalendar";
import TaskForm from "./TaskForm";
import TaskQueue from "./TaskQueue";
import EventConsole from "./EventConsole";
import { taskStore } from "../stores/tasks";

const TaskScheduler: Component = () => {
  const [activePanel, setActivePanel] = createSignal<"calendar" | "queue" | "form" | "console">("console");
  const [editingTask, setEditingTask] = createSignal<any>(null);
  const [currentWorkspace, setCurrentWorkspace] = createSignal("default-workspace");

  const handleTaskSave = (data: any) => {
    console.log("Saving task:", data);
    // For now, just log. In a full implementation, this would call an API
    setEditingTask(null);
  };

  const handleTaskCancel = () => {
    setEditingTask(null);
  };

  return (
    <div class="task-scheduler">
      <div class="scheduler-header">
        <h2>Task Scheduler</h2>
        <div class="workspace-indicator">
          <span class="workspace-label">Workspace:</span>
          <span class="workspace-name">{currentWorkspace()}</span>
        </div>
        <div class="panel-tabs">
          <button
            class={`tab-btn ${activePanel() === "console" ? "active" : ""}`}
            onClick={() => setActivePanel("console")}
          >
            📢 Console
          </button>
          <button
            class={`tab-btn ${activePanel() === "calendar" ? "active" : ""}`}
            onClick={() => setActivePanel("calendar")}
          >
            📅 Calendar
          </button>
          <button
            class={`tab-btn ${activePanel() === "queue" ? "active" : ""}`}
            onClick={() => setActivePanel("queue")}
          >
            📋 Queue
          </button>
          <button
            class={`tab-btn ${activePanel() === "form" ? "active" : ""}`}
            onClick={() => setActivePanel("form")}
          >
            ✏️ Schedule
          </button>
        </div>
        <button
          class="btn-close"
          onClick={() => taskStore.setShowTaskScheduler(false)}
        >
          ✕
        </button>
      </div>

      <div class="scheduler-content">
        <Show when={activePanel() === "console"}>
          <EventConsole />
        </Show>

        <Show when={activePanel() === "calendar"}>
          <TaskCalendar />
        </Show>

        <Show when={activePanel() === "queue"}>
          <TaskQueue />
        </Show>

        <Show when={activePanel() === "form"}>
          <TaskForm
            task={editingTask()}
            onSave={handleTaskSave}
            onCancel={handleTaskCancel}
          />
        </Show>
      </div>

      <Show when={taskStore.selectedTask()}>
        <div class="task-details-panel">
          <h4>Selected Task</h4>
          <div class="task-details">
            <strong>{taskStore.selectedTask()?.title}</strong>
            <p>{taskStore.selectedTask()?.description}</p>
            <div class="task-meta">
              <span>Status: {taskStore.selectedTask()?.status}</span>
              <span>Priority: {taskStore.selectedTask()?.priority}</span>
              <span>Complexity: {taskStore.selectedTask()?.complexity}</span>
            </div>
            <button
              class="btn-edit"
              onClick={() => {
                setEditingTask(taskStore.selectedTask());
                setActivePanel("form");
              }}
            >
              Edit Task
            </button>
          </div>
        </div>
      </Show>
    </div>
  );
};

export default TaskScheduler;