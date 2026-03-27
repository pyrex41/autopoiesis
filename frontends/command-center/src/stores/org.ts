import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";
import type { Department, Goal } from "../api/types";
import * as api from "../api/client";

const [departments, setDepartments] = createSignal<Department[]>([]);
const [goals, setGoals] = createSignal<Goal[]>([]);
const [selectedDeptId, setSelectedDeptId] = createSignal<number | null>(null);

const selectedDept = createMemo(() => {
  const id = selectedDeptId();
  if (id === null) return null;
  return departments().find((d) => d.id === id) ?? null;
});

const deptTree = createMemo(() => {
  const roots: Department[] = [];
  const byParent = new Map<number, Department[]>();
  for (const d of departments()) {
    if (d.parent === null) {
      roots.push(d);
    } else {
      const list = byParent.get(d.parent) ?? [];
      list.push(d);
      byParent.set(d.parent, list);
    }
  }
  return { roots, byParent };
});

const goalsByDept = createMemo(() => {
  const map = new Map<number, Goal[]>();
  for (const g of goals()) {
    if (g.department !== null) {
      const list = map.get(g.department) ?? [];
      list.push(g);
      map.set(g.department, list);
    }
  }
  return map;
});

async function loadDepartments() {
  try {
    const data = await api.listDepartments();
    setDepartments(Array.isArray(data) ? data : []);
  } catch { /* non-critical */ }
}

async function loadGoals() {
  try {
    const data = await api.listGoals();
    setGoals(Array.isArray(data) ? data : []);
  } catch { /* non-critical */ }
}

async function createDepartment(name: string, parent?: number, description?: string) {
  try {
    const dept = await api.createDepartment({ name, parent, description });
    setDepartments((prev) => [...prev, dept]);
    return dept;
  } catch { return null; }
}

async function createGoal(title: string, department?: number, agent?: string) {
  try {
    const goal = await api.createGoal({ title, department, agent });
    setGoals((prev) => [...prev, goal]);
    return goal;
  } catch { return null; }
}

async function updateGoal(id: number, data: Partial<Goal>) {
  try {
    const updated = await api.updateGoal(id, data);
    setGoals((prev) => prev.map((g) => (g.id === id ? updated : g)));
  } catch { /* ignore */ }
}

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "departments": {
      const list = (msg as any).departments;
      if (Array.isArray(list)) setDepartments(list);
      break;
    }
    case "department_created": {
      const dept = (msg as any).department;
      if (dept) setDepartments((prev) => [...prev, dept]);
      break;
    }
    case "department_updated": {
      const dept = (msg as any).department as Department;
      if (dept) setDepartments((prev) => prev.map((d) => d.id === dept.id ? dept : d));
      break;
    }
    case "goals": {
      const list = (msg as any).goals;
      if (Array.isArray(list)) setGoals(list);
      break;
    }
    case "goal_created": {
      const goal = (msg as any).goal;
      if (goal) setGoals((prev) => [...prev, goal]);
      break;
    }
    case "goal_updated": {
      const goal = (msg as any).goal as Goal;
      if (goal) setGoals((prev) => prev.map((g) => g.id === goal.id ? goal : g));
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.subscribe("departments");
  loadDepartments();
  loadGoals();
}

export const orgStore = {
  departments,
  goals,
  selectedDeptId,
  selectedDept,
  deptTree,
  goalsByDept,
  init,
  loadDepartments,
  loadGoals,
  createDepartment,
  createGoal,
  updateGoal,
  setSelectedDeptId,
};
