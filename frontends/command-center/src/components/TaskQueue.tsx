import { type Component, createMemo, For } from "solid-js";
import type { Task, TaskStatus } from "../api/types";
import { taskStore } from "../stores/tasks";

const TaskQueue: Component = () => {
  const queueTasks = createMemo(() => {
    const tasks = taskStore.tasks();
    const grouped: Record<TaskStatus, Task[]> = {
      pending: [],
      "in-progress": [],
      done: [],
      blocked: [],
      cancelled: [],
    };

    tasks.forEach(task => {
      if (grouped[task.status]) {
        grouped[task.status].push(task);
      }
    });

    return grouped;
  });

  const claimTask = async (taskId: string) => {
    try {
      await taskStore.updateTaskStatus(taskId, "in-progress");
    } catch (error) {
      console.error("Failed to claim task:", error);
    }
  };

  const getStatusIcon = (status: TaskStatus) => {
    switch (status) {
      case "pending": return "⏳";
      case "in-progress": return "🔄";
      case "done": return "✅";
      case "blocked": return "🚫";
      case "cancelled": return "❌";
      default: return "❓";
    }
  };

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case "high": return "text-red-600";
      case "medium": return "text-yellow-600";
      case "low": return "text-green-600";
      default: return "text-gray-600";
    }
  };

  return (
    <div class="task-queue">
      <div class="queue-header">
        <h3>Task Queue Monitor</h3>
        <div class="queue-stats">
          <span>Total: {taskStore.taskStats().total}</span>
          <span class="stat-pending">Pending: {taskStore.taskStats().pending}</span>
          <span class="stat-in-progress">In Progress: {taskStore.taskStats()["in-progress"]}</span>
          <span class="stat-done">Done: {taskStore.taskStats().done}</span>
          <span class="stat-blocked">Blocked: {taskStore.taskStats().blocked}</span>
        </div>
      </div>

      <div class="queue-columns">
        <For each={Object.entries(queueTasks()) as [TaskStatus, Task[]][]}>
          {([status, tasks]) => (
            <div class={`queue-column status-${status.replace("-", "")}`}>
              <div class="column-header">
                <h4>
                  {getStatusIcon(status)} {status.replace("-", " ").toUpperCase()}
                  <span class="task-count">({tasks.length})</span>
                </h4>
              </div>

              <div class="task-list">
                <For each={tasks}>
                  {(task) => (
                    <div
                      class={`task-card ${task.id === taskStore.selectedTaskId() ? 'selected' : ''}`}
                      onClick={() => taskStore.selectTask(task.id)}
                    >
                      <div class="task-header">
                        <span class="task-id">{task.id}</span>
                        <span class={`task-priority ${getPriorityColor(task.priority)}`}>
                          {task.priority.toUpperCase()}
                        </span>
                      </div>

                      <div class="task-title">{task.title}</div>

                      <div class="task-meta">
                        <span class="complexity">Complexity: {task.complexity}</span>
                        <span class="agent-type">{task.agent_type}</span>
                      </div>

                      <div class="task-actions">
                        {status === "pending" && (
                          <button
                            class="btn-claim"
                            onClick={(e) => {
                              e.stopPropagation();
                              claimTask(task.id);
                            }}
                          >
                            Claim
                          </button>
                        )}

                        {status === "in-progress" && (
                          <button
                            class="btn-complete"
                            onClick={(e) => {
                              e.stopPropagation();
                              taskStore.updateTaskStatus(task.id, "done");
                            }}
                          >
                            Complete
                          </button>
                        )}

                        {status !== "done" && status !== "cancelled" && (
                          <button
                            class="btn-block"
                            onClick={(e) => {
                              e.stopPropagation();
                              taskStore.updateTaskStatus(task.id, "blocked");
                            }}
                          >
                            Block
                          </button>
                        )}
                      </div>

                      {task.dependencies && task.dependencies.length > 0 && (
                        <div class="task-deps">
                          <small>Deps: {task.dependencies.join(", ")}</small>
                        </div>
                      )}
                    </div>
                  )}
                </For>

                {tasks.length === 0 && (
                  <div class="empty-column">
                    No tasks in {status.replace("-", " ")}
                  </div>
                )}
              </div>
            </div>
          )}
        </For>
      </div>
    </div>
  );
};

export default TaskQueue;