import { type Component, For, Show, createSignal, onMount } from "solid-js";
import { orgStore } from "../stores/org";
import { agentStore } from "../stores/agents";
import type { Department, Goal } from "../api/types";

const OrgChart: Component = () => {
  onMount(() => orgStore.init());

  const [showCreateDept, setShowCreateDept] = createSignal(false);
  const [showCreateGoal, setShowCreateGoal] = createSignal(false);
  const [newDeptName, setNewDeptName] = createSignal("");
  const [newDeptDesc, setNewDeptDesc] = createSignal("");
  const [newDeptParent, setNewDeptParent] = createSignal<number | undefined>(undefined);
  const [newGoalTitle, setNewGoalTitle] = createSignal("");
  const [newGoalDept, setNewGoalDept] = createSignal<number | undefined>(undefined);

  async function handleCreateDept() {
    const name = newDeptName().trim();
    if (!name) return;
    await orgStore.createDepartment(name, newDeptParent(), newDeptDesc().trim() || undefined);
    setNewDeptName("");
    setNewDeptDesc("");
    setNewDeptParent(undefined);
    setShowCreateDept(false);
  }

  async function handleCreateGoal() {
    const title = newGoalTitle().trim();
    if (!title) return;
    await orgStore.createGoal(title, newGoalDept());
    setNewGoalTitle("");
    setNewGoalDept(undefined);
    setShowCreateGoal(false);
  }

  return (
    <div class="dashboard">
      <div class="sys-strip">
        <div class="sys-strip-group">
          <div class="sys-indicator">
            <span class="sys-indicator-label">DEPARTMENTS</span>
            <span class="sys-indicator-value">{orgStore.departments().length}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">GOALS</span>
            <span class="sys-indicator-value">{orgStore.goals().length}</span>
          </div>
          <div class="sys-indicator">
            <span class="sys-indicator-label">AGENTS</span>
            <span class="sys-indicator-value">{agentStore.agents().length}</span>
          </div>
        </div>
        <div class="sys-strip-actions">
          <button class="sys-action-btn" onClick={() => setShowCreateDept(true)}>
            + Department
          </button>
          <button class="sys-action-btn" onClick={() => setShowCreateGoal(true)}>
            + Goal
          </button>
        </div>
      </div>

      {/* Create Department Dialog */}
      <Show when={showCreateDept()}>
        <div class="org-create-overlay" onClick={() => setShowCreateDept(false)}>
          <div class="org-create-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 class="org-dialog-title">Create Department</h3>
            <input
              type="text"
              class="org-dialog-input"
              placeholder="Department name"
              value={newDeptName()}
              onInput={(e) => setNewDeptName(e.currentTarget.value)}
              onKeyDown={(e) => { if (e.key === "Enter") handleCreateDept(); }}
            />
            <input
              type="text"
              class="org-dialog-input"
              placeholder="Description (optional)"
              value={newDeptDesc()}
              onInput={(e) => setNewDeptDesc(e.currentTarget.value)}
            />
            <Show when={orgStore.departments().length > 0}>
              <select
                class="org-dialog-select"
                onChange={(e) => {
                  const v = e.currentTarget.value;
                  setNewDeptParent(v ? parseInt(v) : undefined);
                }}
              >
                <option value="">No parent (root)</option>
                <For each={orgStore.departments()}>
                  {(d) => <option value={d.id}>{d.name}</option>}
                </For>
              </select>
            </Show>
            <div class="org-dialog-actions">
              <button class="btn-secondary" onClick={() => setShowCreateDept(false)}>Cancel</button>
              <button class="sys-action-btn" onClick={handleCreateDept}>Create</button>
            </div>
          </div>
        </div>
      </Show>

      {/* Create Goal Dialog */}
      <Show when={showCreateGoal()}>
        <div class="org-create-overlay" onClick={() => setShowCreateGoal(false)}>
          <div class="org-create-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 class="org-dialog-title">Create Goal</h3>
            <input
              type="text"
              class="org-dialog-input"
              placeholder="Goal title"
              value={newGoalTitle()}
              onInput={(e) => setNewGoalTitle(e.currentTarget.value)}
              onKeyDown={(e) => { if (e.key === "Enter") handleCreateGoal(); }}
            />
            <Show when={orgStore.departments().length > 0}>
              <select
                class="org-dialog-select"
                onChange={(e) => {
                  const v = e.currentTarget.value;
                  setNewGoalDept(v ? parseInt(v) : undefined);
                }}
              >
                <option value="">No department</option>
                <For each={orgStore.departments()}>
                  {(d) => <option value={d.id}>{d.name}</option>}
                </For>
              </select>
            </Show>
            <div class="org-dialog-actions">
              <button class="btn-secondary" onClick={() => setShowCreateGoal(false)}>Cancel</button>
              <button class="sys-action-btn" onClick={handleCreateGoal}>Create</button>
            </div>
          </div>
        </div>
      </Show>

      <div class="dashboard-panels">
        {/* Tree view */}
        <div class="dash-panel org-tree-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <rect x="4.5" y="1" width="5" height="3" rx="1" stroke="currentColor" stroke-width="1.2"/>
                <rect x="0.5" y="9" width="4" height="3" rx="1" stroke="currentColor" stroke-width="1.2"/>
                <rect x="9.5" y="9" width="4" height="3" rx="1" stroke="currentColor" stroke-width="1.2"/>
                <path d="M7 4v2M7 6H2.5V9M7 6h4.5V9" stroke="currentColor" stroke-width="1"/>
              </svg>
              Org Hierarchy
            </h3>
          </div>
          <Show when={orgStore.departments().length > 0} fallback={
            <div class="dash-standby">
              <span class="dash-standby-text">No departments created yet</span>
              <button class="dash-standby-action" onClick={() => setShowCreateDept(true)}>
                Create First Department
              </button>
            </div>
          }>
            <div class="org-tree">
              <For each={orgStore.deptTree().roots}>
                {(dept) => <DeptNode dept={dept} depth={0} />}
              </For>
            </div>
          </Show>
        </div>

        {/* Goals list */}
        <div class="dash-panel">
          <div class="dash-panel-header">
            <h3 class="dash-panel-title">
              <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
                <circle cx="7" cy="7" r="6" stroke="currentColor" stroke-width="1.2"/>
                <circle cx="7" cy="7" r="3" stroke="currentColor" stroke-width="1.2"/>
                <circle cx="7" cy="7" r="1" fill="currentColor"/>
              </svg>
              Goals
            </h3>
            <span class="dash-panel-count">{orgStore.goals().length}</span>
          </div>
          <Show when={orgStore.goals().length > 0} fallback={
            <div class="dash-standby dash-standby-compact">
              <span class="dash-standby-text">No goals defined</span>
            </div>
          }>
            <div class="org-goals-list">
              <For each={orgStore.goals()}>
                {(goal) => <GoalRow goal={goal} />}
              </For>
            </div>
          </Show>
        </div>
      </div>
    </div>
  );
};

const DeptNode: Component<{ dept: Department; depth: number }> = (props) => {
  const [expanded, setExpanded] = createSignal(true);
  const children = () => orgStore.deptTree().byParent.get(props.dept.id) ?? [];
  const goals = () => orgStore.goalsByDept().get(props.dept.id) ?? [];
  const hasChildren = () => children().length > 0;

  return (
    <div class="org-dept-node" style={{ "padding-left": `${props.depth * 20}px` }}>
      <button
        class="org-dept-header"
        classList={{
          "org-dept-selected": orgStore.selectedDeptId() === props.dept.id,
        }}
        onClick={() => {
          orgStore.setSelectedDeptId(
            orgStore.selectedDeptId() === props.dept.id ? null : props.dept.id
          );
        }}
      >
        <Show when={hasChildren()}>
          <span
            class="org-dept-toggle"
            onClick={(e) => { e.stopPropagation(); setExpanded(!expanded()); }}
          >
            {expanded() ? "\u25BE" : "\u25B8"}
          </span>
        </Show>
        <span class="org-dept-name">{props.dept.name}</span>
        <Show when={goals().length > 0}>
          <span class="org-dept-goal-count">{goals().length} goal{goals().length !== 1 ? "s" : ""}</span>
        </Show>
        <Show when={props.dept.budgetLimit}>
          <span class="org-dept-budget">${props.dept.budgetLimit?.toLocaleString()}</span>
        </Show>
      </button>
      <Show when={expanded()}>
        <Show when={goals().length > 0}>
          <div class="org-dept-goals" style={{ "padding-left": `${(props.depth + 1) * 20 + 12}px` }}>
            <For each={goals()}>
              {(g) => (
                <div class="org-goal-chip">
                  <span class="org-goal-status-dot" classList={{
                    "status-active": g.status === "active",
                    "status-completed": g.status === "completed",
                    "status-paused": g.status === "paused",
                  }} />
                  {g.title}
                </div>
              )}
            </For>
          </div>
        </Show>
        <For each={children()}>
          {(child) => <DeptNode dept={child} depth={props.depth + 1} />}
        </For>
      </Show>
    </div>
  );
};

const GoalRow: Component<{ goal: Goal }> = (props) => {
  const deptName = () => {
    if (props.goal.department === null) return null;
    return orgStore.departments().find((d) => d.id === props.goal.department)?.name ?? null;
  };

  const statusColor = () => {
    switch (props.goal.status) {
      case "active": return "var(--emerge)";
      case "completed": return "var(--signal)";
      case "paused": return "var(--warm)";
      case "blocked": return "var(--danger)";
      default: return "var(--text-dim)";
    }
  };

  return (
    <div class="org-goal-row">
      <div class="org-goal-status-pip" style={{ background: statusColor() }} />
      <span class="org-goal-title">{props.goal.title}</span>
      <Show when={deptName()}>
        <span class="org-goal-dept">{deptName()}</span>
      </Show>
      <Show when={props.goal.agent}>
        <span class="org-goal-agent">{props.goal.agent}</span>
      </Show>
      <span class="org-goal-status-label" style={{ color: statusColor() }}>
        {props.goal.status.toUpperCase()}
      </span>
    </div>
  );
};

export default OrgChart;
