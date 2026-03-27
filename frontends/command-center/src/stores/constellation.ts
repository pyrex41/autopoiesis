import { createSignal, createMemo } from "solid-js";
import { agentStore } from "./agents";
import { teamStore } from "./teams";

// ── Types ────────────────────────────────────────────────────────

export interface GraphNode {
  id: string;
  label: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  color: string;
  type: "agent" | "team";
  state?: string;
  capCount: number;
}

export interface GraphEdge {
  source: string;
  target: string;
  type: "parent" | "team-member";
}

// ── State colors by agent status ─────────────────────────────────

const STATE_COLORS: Record<string, string> = {
  running: "#69f0ae",
  idle: "#4fc3f7",
  paused: "#ffab40",
  stopped: "#ff5252",
  created: "#b388ff",
  active: "#69f0ae",
  completed: "#4fc3f7",
  failed: "#ff5252",
};

function stateColor(state?: string): string {
  return STATE_COLORS[state ?? ""] ?? "#4fc3f7";
}

// ── Force simulation ─────────────────────────────────────────────

const [nodes, setNodes] = createSignal<GraphNode[]>([]);
const [edges, setEdges] = createSignal<GraphEdge[]>([]);
const [selectedNode, setSelectedNode] = createSignal<string | null>(null);
const [hoveredNode, setHoveredNode] = createSignal<string | null>(null);

function buildGraph() {
  const agents = agentStore.agents();
  const teams = teamStore.teams();

  const newNodes: GraphNode[] = [];
  const newEdges: GraphEdge[] = [];
  const count = agents.length + teams.length;
  const angleStep = (2 * Math.PI) / Math.max(count, 1);
  const radius = Math.max(150, count * 20);

  // Agent nodes
  agents.forEach((a, i) => {
    const angle = i * angleStep;
    newNodes.push({
      id: a.id,
      label: a.name ?? a.id,
      x: Math.cos(angle) * radius,
      y: Math.sin(angle) * radius,
      vx: 0,
      vy: 0,
      radius: 8 + (a.capabilities?.length ?? 0) * 2,
      color: stateColor(a.state),
      type: "agent",
      state: a.state,
      capCount: a.capabilities?.length ?? 0,
    });

    // Parent edges
    if (a.parent) {
      newEdges.push({ source: a.parent, target: a.id, type: "parent" });
    }
  });

  // Team nodes
  teams.forEach((t, i) => {
    const angle = (agents.length + i) * angleStep;
    newNodes.push({
      id: `team-${t.id}`,
      label: t.id,
      x: Math.cos(angle) * radius * 0.6,
      y: Math.sin(angle) * radius * 0.6,
      vx: 0,
      vy: 0,
      radius: 12 + t.memberCount * 2,
      color: stateColor(t.status),
      type: "team",
      state: t.status,
      capCount: t.memberCount,
    });

    // Team membership edges
    for (const memberId of t.members) {
      newEdges.push({ source: `team-${t.id}`, target: memberId, type: "team-member" });
    }
  });

  setNodes(newNodes);
  setEdges(newEdges);
}

const DAMPING = 0.95;
const REPULSION = 5000;
const SPRING_K = 0.005;
const SPRING_REST = 100;
const CENTER_FORCE = 0.001;

function tick() {
  setNodes((prev) => {
    const next = prev.map((n) => ({ ...n }));
    const nodeMap = new Map(next.map((n) => [n.id, n]));

    // Repulsion between all pairs
    for (let i = 0; i < next.length; i++) {
      for (let j = i + 1; j < next.length; j++) {
        const a = next[i], b = next[j];
        const dx = b.x - a.x, dy = b.y - a.y;
        const dist = Math.sqrt(dx * dx + dy * dy) || 1;
        const force = REPULSION / (dist * dist);
        const fx = (dx / dist) * force;
        const fy = (dy / dist) * force;
        a.vx -= fx; a.vy -= fy;
        b.vx += fx; b.vy += fy;
      }
    }

    // Spring attraction along edges
    for (const edge of edges()) {
      const a = nodeMap.get(edge.source);
      const b = nodeMap.get(edge.target);
      if (!a || !b) continue;
      const dx = b.x - a.x, dy = b.y - a.y;
      const dist = Math.sqrt(dx * dx + dy * dy) || 1;
      const force = SPRING_K * (dist - SPRING_REST);
      const fx = (dx / dist) * force;
      const fy = (dy / dist) * force;
      a.vx += fx; a.vy += fy;
      b.vx -= fx; b.vy -= fy;
    }

    // Centering force
    for (const n of next) {
      n.vx -= n.x * CENTER_FORCE;
      n.vy -= n.y * CENTER_FORCE;
    }

    // Apply velocity with damping
    for (const n of next) {
      n.vx *= DAMPING;
      n.vy *= DAMPING;
      n.x += n.vx;
      n.y += n.vy;
    }

    return next;
  });
}

export const constellationStore = {
  nodes,
  edges,
  selectedNode,
  setSelectedNode,
  hoveredNode,
  setHoveredNode,
  buildGraph,
  tick,
};
