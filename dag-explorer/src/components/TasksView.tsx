import { type Component, onMount } from "solid-js";
import { taskStore } from "../stores/tasks";
import TaskQueue from "./TaskQueue";
import EventConsole from "./EventConsole";

/** Tasks view — wraps existing task components */
const TasksView: Component = () => {
  onMount(() => {
    taskStore.refreshTasks();
  });

  return (
    <div class="tasks-view">
      <TaskQueue />
    </div>
  );
};

export default TasksView;
