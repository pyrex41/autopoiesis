import { type Component, createSignal, createEffect } from "solid-js";
import type { Task, TaskStatus, TaskPriority } from "../api/types";
import { taskStore } from "../stores/tasks";

interface TaskFormData {
  title: string;
  description: string;
  status: TaskStatus;
  priority: TaskPriority;
  complexity: number;
  dependencies: string[];
}

const TaskForm: Component<{ task?: Task; onSave?: (data: TaskFormData) => void; onCancel?: () => void }> = (props) => {
  const [formData, setFormData] = createSignal<TaskFormData>({
    title: "",
    description: "",
    status: "pending",
    priority: "medium",
    complexity: 1,
    dependencies: [],
  });

  const [plistText, setPlistText] = createSignal("");

  // Initialize form with task data if editing
  createEffect(() => {
    if (props.task) {
      setFormData({
        title: props.task.title,
        description: props.task.description,
        status: props.task.status,
        priority: props.task.priority,
        complexity: props.task.complexity,
        dependencies: props.task.dependencies || [],
      });
      updatePlistText();
    }
  });

  const updatePlistText = () => {
    const data = formData();
    const plist = `(:title "${data.title}"
 :description "${data.description.replace(/"/g, '\\"')}"
 :status :${data.status}
 :priority :${data.priority}
 :complexity ${data.complexity}
 :dependencies (${data.dependencies.map(d => `"${d}"`).join(" ")}))`;
    setPlistText(plist);
  };

  const updateFromPlist = () => {
    try {
      const plist = plistText();
      // Simple plist parser (basic implementation)
      const titleMatch = plist.match(/:title "([^"]*)"/);
      const descMatch = plist.match(/:description "([^"]*)"/);
      const statusMatch = plist.match(/:status :(\w+)/);
      const priorityMatch = plist.match(/:priority :(\w+)/);
      const complexityMatch = plist.match(/:complexity (\d+)/);
      const depsMatch = plist.match(/:dependencies \(([^)]*)\)/);

      setFormData({
        title: titleMatch ? titleMatch[1] : "",
        description: descMatch ? descMatch[1].replace(/\\"/g, '"') : "",
        status: (statusMatch ? statusMatch[1] : "pending") as TaskStatus,
        priority: (priorityMatch ? priorityMatch[1] : "medium") as TaskPriority,
        complexity: complexityMatch ? parseInt(complexityMatch[1]) : 1,
        dependencies: depsMatch ?
          depsMatch[1].split('" "').map(d => d.replace(/"/g, '')).filter(d => d) :
          [],
      });
    } catch (error) {
      console.error("Failed to parse plist:", error);
    }
  };

  const handleSubmit = (e: Event) => {
    e.preventDefault();
    const data = formData();
    if (props.onSave) {
      props.onSave(data);
    }
  };

  const addDependency = (taskId: string) => {
    const deps = [...formData().dependencies];
    if (!deps.includes(taskId)) {
      deps.push(taskId);
      setFormData({ ...formData(), dependencies: deps });
      updatePlistText();
    }
  };

  const removeDependency = (taskId: string) => {
    const deps = formData().dependencies.filter(d => d !== taskId);
    setFormData({ ...formData(), dependencies: deps });
    updatePlistText();
  };

  const availableTasks = () => {
    return taskStore.tasks().filter(task =>
      task.id !== props.task?.id &&
      !formData().dependencies.includes(task.id)
    );
  };

  return (
    <div class="task-form">
      <h3>{props.task ? "Edit Task" : "Create Task"}</h3>

      <div class="form-tabs">
        <button
          class="tab-btn active"
          onClick={() => {/* Switch to form view */}}
        >
          Form
        </button>
        <button
          class="tab-btn"
          onClick={() => {/* Switch to plist view */}}
        >
          Plist
        </button>
      </div>

      <form onSubmit={handleSubmit} class="task-form-content">
        <div class="form-group">
          <label for="title">Title:</label>
          <input
            id="title"
            type="text"
            value={formData().title}
            onInput={(e) => {
              setFormData({ ...formData(), title: e.currentTarget.value });
              updatePlistText();
            }}
            required
          />
        </div>

        <div class="form-group">
          <label for="description">Description:</label>
          <textarea
            id="description"
            value={formData().description}
            onInput={(e) => {
              setFormData({ ...formData(), description: e.currentTarget.value });
              updatePlistText();
            }}
            rows="3"
          />
        </div>

        <div class="form-row">
          <div class="form-group">
            <label for="status">Status:</label>
            <select
              id="status"
              value={formData().status}
              onChange={(e) => {
                setFormData({ ...formData(), status: e.currentTarget.value as TaskStatus });
                updatePlistText();
              }}
            >
              <option value="pending">Pending</option>
              <option value="in-progress">In Progress</option>
              <option value="done">Done</option>
              <option value="blocked">Blocked</option>
            </select>
          </div>

          <div class="form-group">
            <label for="priority">Priority:</label>
            <select
              id="priority"
              value={formData().priority}
              onChange={(e) => {
                setFormData({ ...formData(), priority: e.currentTarget.value as TaskPriority });
                updatePlistText();
              }}
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>
          </div>

          <div class="form-group">
            <label for="complexity">Complexity:</label>
            <input
              id="complexity"
              type="number"
              min="1"
              max="10"
              value={formData().complexity}
              onInput={(e) => {
                setFormData({ ...formData(), complexity: parseInt(e.currentTarget.value) || 1 });
                updatePlistText();
              }}
            />
          </div>
        </div>

        <div class="form-group">
          <label>Dependencies:</label>
          <div class="dependencies-list">
            {formData().dependencies.map(dep => (
              <span class="dependency-tag">
                {dep}
                <button
                  type="button"
                  onClick={() => removeDependency(dep)}
                  class="remove-dep"
                >
                  ×
                </button>
              </span>
            ))}
          </div>
          <select
            onChange={(e) => {
              const taskId = e.currentTarget.value;
              if (taskId) {
                addDependency(taskId);
                e.currentTarget.value = "";
              }
            }}
          >
            <option value="">Add dependency...</option>
            {availableTasks().map(task => (
              <option value={task.id}>{task.title}</option>
            ))}
          </select>
        </div>

        <div class="plist-editor">
          <label for="plist">Plist Representation:</label>
          <textarea
            id="plist"
            value={plistText()}
            onInput={(e) => {
              setPlistText(e.currentTarget.value);
              updateFromPlist();
            }}
            rows="8"
            placeholder="(:title &quot;Task title&quot; :description &quot;Task description&quot; ...)"
          />
        </div>

        <div class="form-actions">
          <button type="submit" class="btn-primary">
            {props.task ? "Update Task" : "Create Task"}
          </button>
          {props.onCancel && (
            <button type="button" onClick={props.onCancel} class="btn-secondary">
              Cancel
            </button>
          )}
        </div>
      </form>
    </div>
  );
};

export default TaskForm;