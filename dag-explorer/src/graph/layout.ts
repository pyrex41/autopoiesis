import dagre from "dagre";
import type {
  Snapshot,
  Branch,
  LayoutNode,
  LayoutEdge,
  LayoutGraph,
  LayoutDirection,
} from "../api/types";

const NODE_W = 180;
const NODE_H = 56;

/**
 * Compute a dagre layout for the snapshot DAG.
 *
 * Nodes are placed in a hierarchical Sugiyama-style layout with
 * edge routing through intermediate points. Branch heads and
 * root nodes are annotated for the renderer.
 */
export function computeLayout(
  snapshots: Snapshot[],
  branches: Branch[],
  opts?: {
    direction?: LayoutDirection;
    collapsed?: Set<string>;
    ranksep?: number;
    nodesep?: number;
  }
): LayoutGraph {
  const dir = opts?.direction ?? "TB";
  const collapsed = opts?.collapsed ?? new Set<string>();

  const g = new dagre.graphlib.Graph();
  g.setGraph({
    rankdir: dir,
    ranksep: opts?.ranksep ?? 70,
    nodesep: opts?.nodesep ?? 30,
    marginx: 40,
    marginy: 40,
  });
  g.setDefaultEdgeLabel(() => ({}));

  // Index: id -> snapshot, parent -> children
  const byId = new Map<string, Snapshot>();
  const childrenOf = new Map<string, string[]>();
  for (const s of snapshots) {
    byId.set(s.id, s);
    if (s.parent) {
      const list = childrenOf.get(s.parent) ?? [];
      list.push(s.id);
      childrenOf.set(s.parent, list);
    }
  }

  // Build set of branch heads
  const branchHeads = new Map<string, string[]>(); // snapId -> branch names
  for (const b of branches) {
    if (b.head) {
      const names = branchHeads.get(b.head) ?? [];
      names.push(b.name);
      branchHeads.set(b.head, names);
    }
  }

  // Determine visible nodes (respect collapsed subtrees)
  const hidden = new Set<string>();
  function hideDescendants(id: string) {
    for (const c of childrenOf.get(id) ?? []) {
      hidden.add(c);
      hideDescendants(c);
    }
  }
  for (const cid of collapsed) {
    hideDescendants(cid);
  }

  // Compute depths
  const depthOf = new Map<string, number>();
  function getDepth(id: string): number {
    const cached = depthOf.get(id);
    if (cached !== undefined) return cached;
    const snap = byId.get(id);
    if (!snap || !snap.parent) {
      depthOf.set(id, 0);
      return 0;
    }
    const d = getDepth(snap.parent) + 1;
    depthOf.set(id, d);
    return d;
  }

  // Count descendants
  function descendantCount(id: string): number {
    const ch = childrenOf.get(id) ?? [];
    let count = ch.length;
    for (const c of ch) count += descendantCount(c);
    return count;
  }

  // Add visible nodes
  for (const s of snapshots) {
    if (hidden.has(s.id)) continue;
    g.setNode(s.id, { width: NODE_W, height: NODE_H });
  }

  // Add edges
  for (const s of snapshots) {
    if (hidden.has(s.id)) continue;
    if (s.parent && !hidden.has(s.parent) && byId.has(s.parent)) {
      g.setEdge(s.parent, s.id);
    }
  }

  dagre.layout(g);

  const nodes = new Map<string, LayoutNode>();
  for (const nid of g.nodes()) {
    const n = g.node(nid);
    if (!n) continue;
    const snap = byId.get(nid)!;
    nodes.set(nid, {
      id: nid,
      x: n.x,
      y: n.y,
      width: n.width,
      height: n.height,
      snapshot: snap,
      depth: getDepth(nid),
      childCount: descendantCount(nid),
      branchNames: branchHeads.get(nid) ?? [],
      isRoot: snap.parent === null,
      isBranchHead: branchHeads.has(nid),
      collapsed: collapsed.has(nid),
    });
  }

  const edges: LayoutEdge[] = [];
  for (const e of g.edges()) {
    const edge = g.edge(e);
    if (!edge) continue;
    edges.push({
      source: e.v,
      target: e.w,
      points: edge.points ?? [
        { x: nodes.get(e.v)!.x, y: nodes.get(e.v)!.y },
        { x: nodes.get(e.w)!.x, y: nodes.get(e.w)!.y },
      ],
    });
  }

  const graphMeta = g.graph();
  return {
    nodes,
    edges,
    width: (graphMeta?.width ?? 800) + 80,
    height: (graphMeta?.height ?? 600) + 80,
  };
}

/**
 * Find all ancestor IDs of a given node.
 */
export function findAncestors(
  id: string,
  snapshots: Snapshot[]
): Set<string> {
  const byId = new Map(snapshots.map((s) => [s.id, s]));
  const result = new Set<string>();
  let current = byId.get(id);
  while (current?.parent) {
    result.add(current.parent);
    current = byId.get(current.parent);
  }
  return result;
}

/**
 * Find all descendant IDs of a given node.
 */
export function findDescendants(
  id: string,
  snapshots: Snapshot[]
): Set<string> {
  const childrenOf = new Map<string, string[]>();
  for (const s of snapshots) {
    if (s.parent) {
      const list = childrenOf.get(s.parent) ?? [];
      list.push(s.id);
      childrenOf.set(s.parent, list);
    }
  }
  const result = new Set<string>();
  const queue = [id];
  while (queue.length > 0) {
    const cur = queue.pop()!;
    for (const c of childrenOf.get(cur) ?? []) {
      result.add(c);
      queue.push(c);
    }
  }
  return result;
}

/**
 * Find path between two nodes through the DAG.
 */
export function findPath(
  fromId: string,
  toId: string,
  snapshots: Snapshot[]
): string[] | null {
  const byId = new Map(snapshots.map((s) => [s.id, s]));

  // Build ancestor chain for both
  function ancestorChain(id: string): string[] {
    const chain: string[] = [];
    let cur = byId.get(id);
    while (cur) {
      chain.push(cur.id);
      cur = cur.parent ? byId.get(cur.parent) : undefined;
    }
    return chain;
  }

  const chainA = ancestorChain(fromId);
  const chainB = ancestorChain(toId);
  const setA = new Set(chainA);

  // Find common ancestor
  let commonIdx = -1;
  for (let i = 0; i < chainB.length; i++) {
    if (setA.has(chainB[i])) {
      commonIdx = i;
      break;
    }
  }
  if (commonIdx === -1) return null;

  const commonId = chainB[commonIdx];
  const idxInA = chainA.indexOf(commonId);

  // Path: fromId -> ... -> common -> ... -> toId
  const pathDown = chainA.slice(0, idxInA + 1);
  const pathUp = chainB.slice(0, commonIdx).reverse();
  return [...pathDown, ...pathUp];
}
