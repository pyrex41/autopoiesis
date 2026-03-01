import {
  onMount,
  onCleanup,
  createEffect,
  createSignal,
  type Component,
} from "solid-js";
import { dagStore } from "../stores/dag";
import type { LayoutNode, ColorScheme } from "../api/types";
import "../graph/globals";

// ── Color palettes ────────────────────────────────────────────────

const BRANCH_COLORS = [
  "#6366f1", // indigo
  "#f59e0b", // amber
  "#10b981", // emerald
  "#ef4444", // red
  "#8b5cf6", // violet
  "#ec4899", // pink
  "#14b8a6", // teal
  "#f97316", // orange
  "#3b82f6", // blue
  "#84cc16", // lime
];

const DEPTH_GRADIENT = (d: number, maxDepth: number) => {
  const t = maxDepth > 0 ? d / maxDepth : 0;
  const r = Math.round(99 + t * 100);
  const g = Math.round(102 + (1 - t) * 100);
  const b = Math.round(241 - t * 100);
  return `rgb(${r},${g},${b})`;
};

function nodeColor(
  node: LayoutNode,
  scheme: ColorScheme,
  branchColorMap: Map<string, string>,
  maxDepth: number
): string {
  switch (scheme) {
    case "branch": {
      const bname =
        node.branchNames[0] ??
        (node.snapshot.metadata as Record<string, unknown> | null)?.branch;
      if (typeof bname === "string") return branchColorMap.get(bname) ?? "#6366f1";
      return "#6366f1";
    }
    case "agent": {
      const agent = (node.snapshot.metadata as Record<string, unknown> | null)?.agent;
      if (typeof agent === "string") {
        let h = 0;
        for (let i = 0; i < agent.length; i++) h = (h * 31 + agent.charCodeAt(i)) | 0;
        return `hsl(${Math.abs(h) % 360}, 65%, 55%)`;
      }
      return "#6366f1";
    }
    case "depth":
      return DEPTH_GRADIENT(node.depth, maxDepth);
    case "time": {
      const t = node.snapshot.timestamp;
      const allNodes = [...dagStore.layout().nodes.values()];
      const minT = Math.min(...allNodes.map((n) => n.snapshot.timestamp));
      const maxT = Math.max(...allNodes.map((n) => n.snapshot.timestamp));
      const frac = maxT > minT ? (t - minT) / (maxT - minT) : 0;
      return `hsl(${210 + frac * 150}, 70%, 50%)`;
    }
    case "mono":
      return "#6366f1";
  }
}

// ── Canvas renderer component ─────────────────────────────────────

const DAGCanvas: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;

  const [viewX, setViewX] = createSignal(0);
  const [viewY, setViewY] = createSignal(0);
  const [viewScale, setViewScale] = createSignal(1);
  const [isDragging, setIsDragging] = createSignal(false);
  const [dragStart, setDragStart] = createSignal({ x: 0, y: 0 });

  // Build branch color map
  const branchColorMap = () => {
    const map = new Map<string, string>();
    dagStore.branches().forEach((b, i) => {
      map.set(b.name, BRANCH_COLORS[i % BRANCH_COLORS.length]);
    });
    return map;
  };

  // Max depth for gradient
  const maxDepth = () => {
    let max = 0;
    for (const n of dagStore.layout().nodes.values()) {
      if (n.depth > max) max = n.depth;
    }
    return max;
  };

  // Convert screen coordinates to graph coordinates
  function screenToGraph(sx: number, sy: number): { x: number; y: number } {
    const rect = canvasRef.getBoundingClientRect();
    return {
      x: (sx - rect.left - viewX()) / viewScale(),
      y: (sy - rect.top - viewY()) / viewScale(),
    };
  }

  // Find node at graph coordinates
  function nodeAtPoint(gx: number, gy: number): LayoutNode | null {
    for (const node of dagStore.layout().nodes.values()) {
      const hw = node.width / 2;
      const hh = node.height / 2;
      if (
        gx >= node.x - hw &&
        gx <= node.x + hw &&
        gy >= node.y - hh &&
        gy <= node.y + hh
      ) {
        return node;
      }
    }
    return null;
  }

  // ── Drawing ───────────────────────────────────────────────────

  function draw() {
    const canvas = canvasRef;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, rect.width, rect.height);
    ctx.save();
    ctx.translate(viewX(), viewY());
    ctx.scale(viewScale(), viewScale());

    const graph = dagStore.layout();
    const sel = dagStore.selection();
    const hovered = dagStore.hoveredNode();
    const path = dagStore.highlightedPath();
    const pathSet = path ? new Set(path) : null;
    const ancestors = dagStore.primaryAncestors();
    const descendants = dagStore.primaryDescendants();
    const scheme = dagStore.colorScheme();
    const bcm = branchColorMap();
    const md = maxDepth();
    const search = dagStore.searchResults();
    const searchIds = search ? new Set(search.map((s) => s.id)) : null;

    // Draw edges
    for (const edge of graph.edges) {
      const isOnPath =
        pathSet && pathSet.has(edge.source) && pathSet.has(edge.target);
      const isLineage =
        sel.primary &&
        ((edge.source === sel.primary && descendants.has(edge.target)) ||
          (edge.target === sel.primary && ancestors.has(edge.source)) ||
          (ancestors.has(edge.source) && ancestors.has(edge.target)) ||
          (descendants.has(edge.source) && descendants.has(edge.target)));

      ctx.beginPath();
      ctx.strokeStyle = isOnPath
        ? "#f59e0b"
        : isLineage
          ? "rgba(99, 102, 241, 0.6)"
          : "rgba(148, 163, 184, 0.35)";
      ctx.lineWidth = isOnPath ? 3 : isLineage ? 2 : 1;

      if (edge.points.length >= 2) {
        ctx.moveTo(edge.points[0].x, edge.points[0].y);
        if (edge.points.length === 2) {
          ctx.lineTo(edge.points[1].x, edge.points[1].y);
        } else {
          // Smooth curve through intermediate points
          for (let i = 1; i < edge.points.length - 1; i++) {
            const curr = edge.points[i];
            const next = edge.points[i + 1];
            const cpx = (curr.x + next.x) / 2;
            const cpy = (curr.y + next.y) / 2;
            ctx.quadraticCurveTo(curr.x, curr.y, cpx, cpy);
          }
          const last = edge.points[edge.points.length - 1];
          ctx.lineTo(last.x, last.y);
        }
      }
      ctx.stroke();

      // Arrow head
      if (edge.points.length >= 2) {
        const p1 = edge.points[edge.points.length - 2];
        const p2 = edge.points[edge.points.length - 1];
        const angle = Math.atan2(p2.y - p1.y, p2.x - p1.x);
        const sz = 6;
        ctx.save();
        ctx.translate(p2.x, p2.y);
        ctx.rotate(angle);
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(-sz * 2, -sz);
        ctx.lineTo(-sz * 2, sz);
        ctx.closePath();
        ctx.fillStyle = ctx.strokeStyle;
        ctx.fill();
        ctx.restore();
      }
    }

    // Draw nodes
    for (const node of graph.nodes.values()) {
      const isPrimary = sel.primary === node.id;
      const isSecondary = sel.secondary === node.id;
      const isHovered = hovered === node.id;
      const isOnPath = pathSet?.has(node.id) ?? false;
      const isAncestor = ancestors.has(node.id);
      const isDescendant = descendants.has(node.id);
      const isSearchHit = searchIds?.has(node.id) ?? false;
      const isDimmed =
        searchIds !== null && !isSearchHit && !isPrimary && !isSecondary;

      const x = node.x - node.width / 2;
      const y = node.y - node.height / 2;
      const color = nodeColor(node, scheme, bcm, md);

      // Node background
      ctx.save();
      ctx.globalAlpha = isDimmed ? 0.2 : 1;

      // Shadow for selected nodes
      if (isPrimary || isSecondary) {
        ctx.shadowColor = isPrimary ? "#6366f1" : "#f59e0b";
        ctx.shadowBlur = 12;
      }

      ctx.beginPath();
      const r = 6;
      ctx.moveTo(x + r, y);
      ctx.arcTo(x + node.width, y, x + node.width, y + node.height, r);
      ctx.arcTo(x + node.width, y + node.height, x, y + node.height, r);
      ctx.arcTo(x, y + node.height, x, y, r);
      ctx.arcTo(x, y, x + node.width, y, r);
      ctx.closePath();

      // Fill
      ctx.fillStyle = isPrimary
        ? "#1e1b4b"
        : isSecondary
          ? "#451a03"
          : isHovered
            ? "#1e293b"
            : "#0f172a";
      ctx.fill();

      // Border
      ctx.shadowBlur = 0;
      ctx.strokeStyle = isPrimary
        ? "#818cf8"
        : isSecondary
          ? "#fbbf24"
          : isOnPath
            ? "#f59e0b"
            : isHovered
              ? "#94a3b8"
              : isAncestor || isDescendant
                ? "rgba(99, 102, 241, 0.5)"
                : isSearchHit
                  ? "#34d399"
                  : "rgba(71, 85, 105, 0.6)";
      ctx.lineWidth = isPrimary || isSecondary ? 2 : 1;
      ctx.stroke();

      // Color accent bar on left edge
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.arcTo(x, y, x, y + node.height, r);
      ctx.arcTo(x, y + node.height, x + r, y + node.height, 0);
      ctx.lineTo(x + 4, y + node.height);
      ctx.lineTo(x + 4, y);
      ctx.closePath();
      ctx.fill();

      // Text
      ctx.fillStyle = "#e2e8f0";
      ctx.font = "bold 11px ui-monospace, monospace";
      const idShort = node.id.length > 14 ? node.id.slice(0, 14) + ".." : node.id;
      ctx.fillText(idShort, x + 10, y + 16);

      // Metadata line
      const meta = node.snapshot.metadata as Record<string, unknown> | null;
      ctx.font = "10px ui-monospace, monospace";
      ctx.fillStyle = "#94a3b8";
      const label =
        (typeof meta?.label === "string" ? meta.label : "") ||
        (typeof meta?.agent === "string" ? meta.agent : "");
      if (label) {
        const truncLabel = label.length > 22 ? label.slice(0, 22) + ".." : label;
        ctx.fillText(truncLabel, x + 10, y + 30);
      }

      // Branch head badge
      if (node.isBranchHead) {
        const bname = node.branchNames[0] ?? "";
        const short = bname.length > 16 ? ".." + bname.slice(-14) : bname;
        ctx.fillStyle = color;
        ctx.font = "bold 9px ui-monospace, monospace";
        const tw = ctx.measureText(short).width;
        const bx = x + node.width - tw - 12;
        const by = y + node.height - 10;
        ctx.beginPath();
        ctx.roundRect(bx - 3, by - 8, tw + 6, 12, 3);
        ctx.globalAlpha = isDimmed ? 0.1 : 0.2;
        ctx.fill();
        ctx.globalAlpha = isDimmed ? 0.2 : 1;
        ctx.fillText(short, bx, by);
      }

      // Collapse indicator
      if (node.collapsed) {
        ctx.fillStyle = "#fbbf24";
        ctx.font = "bold 12px sans-serif";
        ctx.fillText(`+${node.childCount}`, x + node.width - 30, y + 16);
      }

      // Root indicator
      if (node.isRoot) {
        ctx.fillStyle = "#34d399";
        ctx.font = "9px ui-monospace, monospace";
        ctx.fillText("ROOT", x + 10, y + node.height - 6);
      }

      // Depth badge
      ctx.fillStyle = "#64748b";
      ctx.font = "9px ui-monospace, monospace";
      ctx.fillText(`d${node.depth}`, x + node.width - 24, y + 16);

      ctx.restore();
    }

    ctx.restore();
  }

  // ── Event handlers ────────────────────────────────────────────

  function onMouseDown(e: MouseEvent) {
    if (e.button === 0) {
      setIsDragging(true);
      setDragStart({ x: e.clientX - viewX(), y: e.clientY - viewY() });
    }
  }

  function onMouseMove(e: MouseEvent) {
    if (isDragging()) {
      setViewX(e.clientX - dragStart().x);
      setViewY(e.clientY - dragStart().y);
    } else {
      const { x, y } = screenToGraph(e.clientX, e.clientY);
      const node = nodeAtPoint(x, y);
      dagStore.setHoveredNode(node?.id ?? null);
    }
  }

  function onMouseUp(e: MouseEvent) {
    if (isDragging()) {
      setIsDragging(false);
      // If very short drag, treat as click
      const dx = e.clientX - dragStart().x - viewX();
      const dy = e.clientY - dragStart().y - viewY();
      if (Math.abs(dx) < 3 && Math.abs(dy) < 3) {
        const { x, y } = screenToGraph(e.clientX, e.clientY);
        const node = nodeAtPoint(x, y);
        if (node) {
          if (e.shiftKey || dagStore.diffMode()) {
            dagStore.selectNode(node.id, true);
          } else {
            dagStore.selectNode(node.id);
          }
        } else {
          dagStore.clearSelection();
        }
      }
    }
  }

  function onWheel(e: WheelEvent) {
    e.preventDefault();
    const rect = canvasRef.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const my = e.clientY - rect.top;

    const factor = e.deltaY < 0 ? 1.1 : 0.9;
    const newScale = Math.max(0.05, Math.min(5, viewScale() * factor));
    const ratio = newScale / viewScale();

    setViewX(mx - (mx - viewX()) * ratio);
    setViewY(my - (my - viewY()) * ratio);
    setViewScale(newScale);
  }

  function onDblClick(e: MouseEvent) {
    const { x, y } = screenToGraph(e.clientX, e.clientY);
    const node = nodeAtPoint(x, y);
    if (node) {
      dagStore.toggleCollapse(node.id);
    }
  }

  // Fit the graph into view
  function fitToView() {
    const graph = dagStore.layout();
    if (graph.nodes.size === 0) return;
    const rect = canvasRef.getBoundingClientRect();
    const padX = 60;
    const padY = 60;
    const scaleX = (rect.width - padX * 2) / graph.width;
    const scaleY = (rect.height - padY * 2) / graph.height;
    const scale = Math.min(scaleX, scaleY, 1.5);
    setViewScale(scale);
    setViewX((rect.width - graph.width * scale) / 2);
    setViewY((rect.height - graph.height * scale) / 2);
  }

  // Center on a specific node
  function centerOnNode(nodeId: string) {
    const node = dagStore.layout().nodes.get(nodeId);
    if (!node) return;
    const rect = canvasRef.getBoundingClientRect();
    const scale = viewScale();
    setViewX(rect.width / 2 - node.x * scale);
    setViewY(rect.height / 2 - node.y * scale);
  }

  // ── Lifecycle ─────────────────────────────────────────────────

  onMount(() => {
    const loop = () => {
      draw();
      animFrame = requestAnimationFrame(loop);
    };
    animFrame = requestAnimationFrame(loop);

    canvasRef.addEventListener("wheel", onWheel, { passive: false });
  });

  onCleanup(() => {
    cancelAnimationFrame(animFrame);
    canvasRef?.removeEventListener("wheel", onWheel);
  });

  // Auto-fit when layout changes
  createEffect(() => {
    const graph = dagStore.layout();
    if (graph.nodes.size > 0) {
      fitToView();
    }
  });

  // Center on selected node
  createEffect(() => {
    const sel = dagStore.selection();
    if (sel.primary) {
      centerOnNode(sel.primary);
    }
  });

  // Expose fit/center for keyboard shortcuts via typed global
  window.__dagFitToView = fitToView;
  window.__dagCenterOnNode = centerOnNode;

  return (
    <canvas
      ref={canvasRef!}
      style={{
        width: "100%",
        height: "100%",
        cursor: isDragging() ? "grabbing" : dagStore.hoveredNode() ? "pointer" : "grab",
        "background-color": "#020617",
      }}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onDblClick={onDblClick}
    />
  );
};

export default DAGCanvas;
