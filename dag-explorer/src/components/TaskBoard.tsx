import { type Component, For, Show, createSignal, createMemo } from "solid-js";
import type { Task, TaskStatus } from "../api/types";

interface TaskBoardProps {
  tasks: Task[];
  onStatusChange?: (taskId: string, newStatus: TaskStatus) => void;
}

const COLUMNS: { status: TaskStatus; label: string; color: string }[] = [
  { status: "pending", label: "Pending", color: "var(--text-dim)" },
  { status: "in-progress", label: "In Progress", color: "var(--emerge)" },
  { status: "blocked", label: "Blocked", color: "var(--danger)" },
  { status: "done", label: "Done", color: "var(--signal)" },
];

const TaskBoard: Component<TaskBoardProps> = (props) => {
  const [draggedTask, setDraggedTask] = createSignal<string | null>(null);
  const [dragOverCol, setDragOverCol] = createSignal<TaskStatus | null>(null);

  const tasksByStatus = createMemo(() => {
    const map: Record<string, Task[]> = {};
    for (const col of COLUMNS) {
      map[col.status] = [];
    }
    for (const t of props.tasks) {
      const col = map[t.status];
      if (col) col.push(t);
      else (map["pending"] ??= []).push(t);
    }
    return map;
  });

  function handleDragStart(e: DragEvent, taskId: string) {
    setDraggedTask(taskId);
    if (e.dataTransfer) {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", taskId);
    }
  }

  function handleDragOver(e: DragEvent, status: TaskStatus) {
    e.preventDefault();
    setDragOverCol(status);
  }

  function handleDrop(e: DragEvent, status: TaskStatus) {
    e.preventDefault();
    const taskId = draggedTask();
    if (taskId && props.onStatusChange) {
      props.onStatusChange(taskId, status);
    }
    setDraggedTask(null);
    setDragOverCol(null);
  }

  function handleDragEnd() {
    setDraggedTask(null);
    setDragOverCol(null);
  }

  const priorityColor = (p: string) => {
    switch (p) {
      case "high": return "var(--danger)";
      case "medium": return "var(--warm)";
      default: return "var(--text-dim)";
    }
  };

  return (
    <div class="kanban-board">
      <For each={COLUMNS}>
        {(col) => (
          <div
            class="kanban-column"
            classList={{ "kanban-column-dragover": dragOverCol() === col.status }}
            onDragOver={(e) => handleDragOver(e, col.status)}
            onDragLeave={() => setDragOverCol(null)}
            onDrop={(e) => handleDrop(e, col.status)}
          >
            <div class="kanban-column-header">
              <div class="kanban-column-indicator" style={{ background: col.color }} />
              <span class="kanban-column-title">{col.label}</span>
              <span class="kanban-column-count">{(tasksByStatus()[col.status] ?? []).length}</span>
            </div>
            <div class="kanban-column-body">
              <For each={tasksByStatus()[col.status] ?? []}>
                {(task) => (
                  <div
                    class="kanban-card"
                    classList={{ "kanban-card-dragging": draggedTask() === task.id }}
                    draggable={true}
                    onDragStart={(e) => handleDragStart(e, task.id)}
                    onDragEnd={handleDragEnd}
                  >
                    <div class="kanban-card-title">{task.title}</div>
                    <Show when={task.description}>
                      <div class="kanban-card-desc">{task.description.slice(0, 80)}</div>
                    </Show>
                    <div class="kanban-card-meta">
                      <span class="kanban-card-priority" style={{ color: priorityColor(task.priority) }}>
                        {task.priority.toUpperCase()}
                      </span>
                      <Show when={task.complexity > 0}>
                        <span class="kanban-card-complexity">C{task.complexity}</span>
                      </Show>
                      <Show when={task.dependencies.length > 0}>
                        <span class="kanban-card-deps">{task.dependencies.length} dep{task.dependencies.length !== 1 ? "s" : ""}</span>
                      </Show>
                    </div>
                  </div>
                )}
              </For>
            </div>
          </div>
        )}
      </For>
    </div>
  );
};

export default TaskBoard;
