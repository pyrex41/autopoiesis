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

// ── Color palette (matching hl_project) ───────────────────────────

const COLORS = {
  bg: "#0d1117",
  bgSecondary: "#161b22",
  bgTertiary: "#1c2128",
  border: "#30363d",
  borderLight: "#3d444d",
  text: "#e6edf3",
  textMuted: "#8b949e",
  textDim: "#6e7681",
  accent: "#58a6ff",
  accentDim: "#388bfd",
  green: "#3fb950",
  red: "#f85149",
  yellow: "#d29922",
  purple: "#a371f7",
  orange: "#f0883e",
  cyan: "#56d4dd",
};

const BRANCH_COLORS = [
  COLORS.accent,
  COLORS.purple,
  COLORS.green,
  COLORS.orange,
  COLORS.cyan,
  COLORS.yellow,
  COLORS.red,
  "#d2a8ff", // light purple
  "#79c0ff", // light blue
  "#7ee787", // light green
];

function nodeAccentColor(
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
      if (typeof bname === "string")
        return branchColorMap.get(bname) ?? COLORS.accent;
      return COLORS.accent;
    }
    case "agent": {
      const agent = (
        node.snapshot.metadata as Record<string, unknown> | null
      )?.agent;
      if (typeof agent === "string") {
        let h = 0;
        for (let i = 0; i < agent.length; i++)
          h = (h * 31 + agent.charCodeAt(i)) | 0;
        return `hsl(${Math.abs(h) % 360}, 60%, 60%)`;
      }
      return COLORS.accent;
    }
    case "depth": {
      const t = maxDepth > 0 ? node.depth / maxDepth : 0;
      // Gradient from accent blue -> purple -> cyan
      const hue = 210 + t * 80;
      return `hsl(${hue}, 70%, 60%)`;
    }
    case "time": {
      const ts = node.snapshot.timestamp;
      const allNodes = [...dagStore.layout().nodes.values()];
      const minT = Math.min(...allNodes.map((n) => n.snapshot.timestamp));
      const maxT = Math.max(...allNodes.map((n) => n.snapshot.timestamp));
      const frac = maxT > minT ? (ts - minT) / (maxT - minT) : 0;
      return `hsl(${200 + frac * 120}, 65%, 55%)`;
    }
    case "mono":
      return COLORS.accent;
  }
}

// ── Helpers ────────────────────────────────────────────────────────

function hexToRgba(hex: string, alpha: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

function roundRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// ── Canvas renderer ───────────────────────────────────────────────

const DAGCanvas: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;
  let frameCount = 0;

  const [viewX, setViewX] = createSignal(0);
  const [viewY, setViewY] = createSignal(0);
  const [viewScale, setViewScale] = createSignal(1);
  const [isDragging, setIsDragging] = createSignal(false);
  const [dragStart, setDragStart] = createSignal({ x: 0, y: 0 });

  const branchColorMap = () => {
    const map = new Map<string, string>();
    dagStore.branches().forEach((b, i) => {
      map.set(b.name, BRANCH_COLORS[i % BRANCH_COLORS.length]);
    });
    return map;
  };

  const maxDepth = () => {
    let max = 0;
    for (const n of dagStore.layout().nodes.values()) {
      if (n.depth > max) max = n.depth;
    }
    return max;
  };

  function screenToGraph(sx: number, sy: number): { x: number; y: number } {
    const rect = canvasRef.getBoundingClientRect();
    return {
      x: (sx - rect.left - viewX()) / viewScale(),
      y: (sy - rect.top - viewY()) / viewScale(),
    };
  }

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
    frameCount++;
    const canvas = canvasRef;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    // Background
    ctx.fillStyle = COLORS.bg;
    ctx.fillRect(0, 0, rect.width, rect.height);

    // Subtle grid pattern
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
    const t = frameCount / 60; // animation time in seconds

    // ── Draw edges ────────────────────────────────────────────

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

      if (isOnPath) {
        ctx.strokeStyle = COLORS.yellow;
        ctx.lineWidth = 2.5;
        // Animated dashed line for path
        ctx.setLineDash([8, 4]);
        ctx.lineDashOffset = -t * 12;
      } else if (isLineage) {
        ctx.strokeStyle = hexToRgba(COLORS.accent, 0.5);
        ctx.lineWidth = 1.5;
        ctx.setLineDash([]);
      } else {
        ctx.strokeStyle = hexToRgba(COLORS.border, 0.6);
        ctx.lineWidth = 1;
        ctx.setLineDash([]);
      }

      if (edge.points.length >= 2) {
        ctx.moveTo(edge.points[0].x, edge.points[0].y);
        if (edge.points.length === 2) {
          ctx.lineTo(edge.points[1].x, edge.points[1].y);
        } else {
          for (let i = 1; i < edge.points.length - 1; i++) {
            const curr = edge.points[i];
            const next = edge.points[i + 1];
            ctx.quadraticCurveTo(
              curr.x,
              curr.y,
              (curr.x + next.x) / 2,
              (curr.y + next.y) / 2
            );
          }
          const last = edge.points[edge.points.length - 1];
          ctx.lineTo(last.x, last.y);
        }
      }
      ctx.stroke();
      ctx.setLineDash([]);

      // Arrow head (small, minimal)
      if (edge.points.length >= 2) {
        const p1 = edge.points[edge.points.length - 2];
        const p2 = edge.points[edge.points.length - 1];
        const angle = Math.atan2(p2.y - p1.y, p2.x - p1.x);
        const sz = 4;
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

    // ── Draw nodes ────────────────────────────────────────────

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
      const color = nodeAccentColor(node, scheme, bcm, md);
      const R = 8; // border-radius matching hl_project

      ctx.save();
      ctx.globalAlpha = isDimmed ? 0.15 : 1;

      // Glow for selected/path nodes
      if ((isPrimary || isSecondary || isOnPath) && !isDimmed) {
        const glowColor = isPrimary
          ? COLORS.accent
          : isSecondary
            ? COLORS.yellow
            : COLORS.yellow;
        const pulse = 0.3 + 0.15 * Math.sin(t * 2);
        ctx.shadowColor = glowColor;
        ctx.shadowBlur = 16 + pulse * 8;
      }

      // Node body
      roundRect(ctx, x, y, node.width, node.height, R);
      ctx.fillStyle = isPrimary
        ? COLORS.bgTertiary
        : isSecondary
          ? COLORS.bgTertiary
          : isHovered
            ? COLORS.bgTertiary
            : COLORS.bgSecondary;
      ctx.fill();

      // Clear shadow for border
      ctx.shadowBlur = 0;
      ctx.shadowColor = "transparent";

      // Border
      roundRect(ctx, x, y, node.width, node.height, R);
      ctx.strokeStyle = isPrimary
        ? COLORS.accent
        : isSecondary
          ? COLORS.yellow
          : isOnPath
            ? COLORS.yellow
            : isHovered
              ? COLORS.borderLight
              : isAncestor || isDescendant
                ? hexToRgba(COLORS.accent, 0.4)
                : isSearchHit
                  ? COLORS.green
                  : COLORS.border;
      ctx.lineWidth = isPrimary || isSecondary ? 2 : 1;
      if (isOnPath && !isPrimary && !isSecondary) {
        ctx.setLineDash([4, 2]);
        ctx.lineDashOffset = -t * 6;
      }
      ctx.stroke();
      ctx.setLineDash([]);

      // Left accent bar (like hl_project's left border styling)
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(x, y + R);
      ctx.arcTo(x, y, x + R, y, R);
      ctx.lineTo(x + 4, y);
      ctx.lineTo(x + 4, y + node.height);
      ctx.lineTo(x + R, y + node.height);
      ctx.arcTo(x, y + node.height, x, y + node.height - R, R);
      ctx.closePath();
      ctx.fillStyle = color;
      ctx.fill();
      ctx.restore();

      // ── Text ──────────────────────────────────────────────

      const FONT = "'SF Mono', 'Fira Code', Consolas, monospace";

      // ID
      ctx.fillStyle = COLORS.text;
      ctx.font = `600 11px ${FONT}`;
      const idShort =
        node.id.length > 14 ? node.id.slice(0, 14) + ".." : node.id;
      ctx.fillText(idShort, x + 12, y + 17);

      // Metadata label
      const meta = node.snapshot.metadata as Record<string, unknown> | null;
      const label =
        (typeof meta?.label === "string" ? meta.label : "") ||
        (typeof meta?.agent === "string" ? meta.agent : "");
      if (label) {
        ctx.font = `11px ${FONT}`;
        ctx.fillStyle = COLORS.textMuted;
        const truncLabel =
          label.length > 22 ? label.slice(0, 22) + ".." : label;
        ctx.fillText(truncLabel, x + 12, y + 32);
      }

      // Branch head badge
      if (node.isBranchHead) {
        const bname = node.branchNames[0] ?? "";
        const short = bname.length > 14 ? ".." + bname.slice(-12) : bname;
        ctx.font = `600 9px ${FONT}`;
        const tw = ctx.measureText(short).width;
        const bx = x + node.width - tw - 14;
        const by = y + node.height - 12;

        // Badge background
        roundRect(ctx, bx - 4, by - 9, tw + 8, 13, 3);
        ctx.fillStyle = hexToRgba(
          color.startsWith("#") ? color : COLORS.accent,
          0.15
        );
        ctx.fill();

        // Badge text
        ctx.fillStyle = color;
        ctx.fillText(short, bx, by);
      }

      // Collapse indicator
      if (node.collapsed) {
        ctx.fillStyle = COLORS.yellow;
        ctx.font = `600 10px ${FONT}`;
        ctx.fillText(`+${node.childCount}`, x + node.width - 32, y + 17);
      }

      // Root indicator (status dot style)
      if (node.isRoot) {
        const dotX = x + 12;
        const dotY = y + node.height - 10;
        ctx.beginPath();
        ctx.arc(dotX, dotY, 3, 0, Math.PI * 2);
        ctx.fillStyle = COLORS.green;
        ctx.fill();
        ctx.font = `9px ${FONT}`;
        ctx.fillStyle = COLORS.textDim;
        ctx.fillText("root", dotX + 8, dotY + 3);
      }

      // Depth indicator
      ctx.fillStyle = COLORS.textDim;
      ctx.font = `9px ${FONT}`;
      ctx.fillText(`d${node.depth}`, x + node.width - 24, y + 17);

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
    if (node) dagStore.toggleCollapse(node.id);
  }

  function fitToView() {
    const graph = dagStore.layout();
    if (graph.nodes.size === 0) return;
    const rect = canvasRef.getBoundingClientRect();
    const pad = 60;
    const scaleX = (rect.width - pad * 2) / graph.width;
    const scaleY = (rect.height - pad * 2) / graph.height;
    const scale = Math.min(scaleX, scaleY, 1.5);
    setViewScale(scale);
    setViewX((rect.width - graph.width * scale) / 2);
    setViewY((rect.height - graph.height * scale) / 2);
  }

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

  createEffect(() => {
    const graph = dagStore.layout();
    if (graph.nodes.size > 0) fitToView();
  });

  createEffect(() => {
    const sel = dagStore.selection();
    if (sel.primary) centerOnNode(sel.primary);
  });

  window.__dagFitToView = fitToView;
  window.__dagCenterOnNode = centerOnNode;

  return (
    <canvas
      ref={canvasRef!}
      style={{
        width: "100%",
        height: "100%",
        cursor: isDragging()
          ? "grabbing"
          : dagStore.hoveredNode()
            ? "pointer"
            : "grab",
      }}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onDblClick={onDblClick}
    />
  );
};

export default DAGCanvas;
