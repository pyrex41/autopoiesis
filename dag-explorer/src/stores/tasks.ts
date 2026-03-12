import { createSignal, createResource, createEffect } from "solid-js";
import type { Task, TaskStatus } from "../api/types";
import * as api from "../api/client";

// ── Raw data signals ──────────────────────────────────────────────

const [tasks, setTasks] = createSignal<Task[]>([]);
const [loading, setLoading] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);
const [refreshTrigger, setRefreshTrigger] = createSignal(0);

// ── UI state signals ──────────────────────────────────────────────

const [selectedTaskId, setSelectedTaskId] = createSignal<string | null>(null);
const [taskFilter, setTaskFilter] = createSignal<TaskStatus | "all">("all");
const [showTaskScheduler, setShowTaskScheduler] = createSignal(false);

// ── Data fetching ─────────────────────────────────────────────────

const fetchTasks = async () => {
  setLoading(true);
  try {
    const fetchedTasks = await api.listTasks();
    setTasks(fetchedTasks);
    setError(null);
    return fetchedTasks;
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : "Failed to load tasks";
    setError(errorMsg);
    throw err;
  } finally {
    setLoading(false);
  }
};

const [taskListResource] = createResource(refreshTrigger, fetchTasks);

// ── Computed values ───────────────────────────────────────────────

const filteredTasks = () => {
  const allTasks = tasks();
  const filter = taskFilter();
  if (filter === "all") return allTasks;
  return allTasks.filter(task => task.status === filter);
};

const selectedTask = () => {
  const id = selectedTaskId();
  if (!id) return null;
  return tasks().find(task => task.id === id) || null;
};

const taskStats = () => {
  const allTasks = tasks();
  const stats = {
    total: allTasks.length,
    pending: 0,
    "in-progress": 0,
    done: 0,
    blocked: 0,
    cancelled: 0,
  };

  allTasks.forEach(task => {
    stats[task.status] = (stats[task.status] || 0) + 1;
  });

  return stats;
};

// ── Actions ───────────────────────────────────────────────────────

const refreshTasks = () => {
  setRefreshTrigger(prev => prev + 1);
};

const updateTaskStatus = async (taskId: string, status: TaskStatus) => {
  try {
    await api.updateTaskStatus(taskId, { status });
    // Refresh the task list
    refreshTasks();
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : "Failed to update task status";
    setError(errorMsg);
    throw err;
  }
};

const selectTask = (taskId: string | null) => {
  setSelectedTaskId(taskId);
};

// ── Exports ───────────────────────────────────────────────────────

export const taskStore = {
  // Data
  tasks,
  loading,
  error,
  filteredTasks,
  selectedTask,
  taskStats,

  // UI state
  selectedTaskId,
  taskFilter,
  showTaskScheduler,

  // Actions
  refreshTasks,
  updateTaskStatus,
  selectTask,
  setTaskFilter,
  setShowTaskScheduler,
};