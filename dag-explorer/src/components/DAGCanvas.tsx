import {
  onMount,
  onCleanup,
  createEffect,
  createSignal,
  type Component,
} from "solid-js";
import { dagStore } from "../stores/dag";
import type { LayoutNode, LayoutEdge, ColorScheme } from "../api/types";
import "../graph/globals";

// ── Palette ───────────────────────────────────────────────────────
// Deep observatory blues + vivid signal colors.
// Background is NOT flat - it's a radial gradient from deep navy center
// to near-black edges, like looking through a viewport into space.

const C = {
  void: "#04060e",       // deepest black
  deep: "#080c18",       // canvas base
  mid: "#0e1525",        // node bg
  surface: "#141d30",    // elevated surfaces
  raised: "#1a2640",     // hover / active
  border: "#1e2d4a",     // subtle borders
  borderHi: "#2a3f66",   // highlighted borders
  text: "#d0daf0",       // primary text
  textMuted: "#7a8ba8",  // secondary text
  textDim: "#4a5a78",    // tertiary text
  signal: "#4fc3f7",     // primary accent (vivid cyan-blue)
  signalDim: "#2196f3",  // deeper accent
  signalGlow: "#29b6f6", // glow color
  warm: "#ffab40",       // secondary accent (amber)
  warmDim: "#ff9100",    // deeper warm
  emerge: "#69f0ae",     // success / root
  danger: "#ff5252",     // error
  purple: "#b388ff",     // branch accent
  magenta: "#f06292",    // alternate accent
  ghost: "#1a2744",      // faint structural
};

const BRANCH_PALETTE = [
  C.signal,
  C.purple,
  C.emerge,
  C.warm,
  "#80deea",  // cyan
  C.magenta,
  "#fff176",  // lemon
  "#ce93d8",  // lavender
  "#4dd0e1",  // teal
  "#aed581",  // lime
];

function nodeAccent(
  node: LayoutNode,
  scheme: ColorScheme,
  bcm: Map<string, string>,
  maxD: number
): string {
  switch (scheme) {
    case "branch": {
      const b = node.branchNames[0] ??
        (node.snapshot.metadata as Record<string, unknown> | null)?.branch;
      return typeof b === "string" ? (bcm.get(b) ?? C.signal) : C.signal;
    }
    case "agent": {
      const a = (node.snapshot.metadata as Record<string, unknown> | null)?.agent;
      if (typeof a === "string") {
        let h = 0;
        for (let i = 0; i < a.length; i++) h = (h * 31 + a.charCodeAt(i)) | 0;
        return `hsl(${Math.abs(h) % 360}, 70%, 65%)`;
      }
      return C.signal;
    }
    case "depth":
      return `hsl(${190 + (maxD > 0 ? (node.depth / maxD) * 100 : 0)}, 80%, 60%)`;
    case "time": {
      const nodes = [...dagStore.layout().nodes.values()];
      const mn = Math.min(...nodes.map(n => n.snapshot.timestamp));
      const mx = Math.max(...nodes.map(n => n.snapshot.timestamp));
      const f = mx > mn ? (node.snapshot.timestamp - mn) / (mx - mn) : 0;
      return `hsl(${180 + f * 140}, 75%, 55%)`;
    }
    case "mono":
      return C.signal;
  }
}

function rgba(hex: string, a: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${a})`;
}

function rr(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

// ── Starfield ─────────────────────────────────────────────────────
// Pre-computed static stars for the background. Gives depth like
// looking through a space station viewport.

interface Star { x: number; y: number; r: number; brightness: number; twinkleRate: number }

function generateStars(count: number): Star[] {
  const stars: Star[] = [];
  for (let i = 0; i < count; i++) {
    stars.push({
      x: Math.random(),
      y: Math.random(),
      r: 0.3 + Math.random() * 1.2,
      brightness: 0.15 + Math.random() * 0.5,
      twinkleRate: 0.3 + Math.random() * 2,
    });
  }
  return stars;
}

// ── Edge particles ────────────────────────────────────────────────
// Small luminous dots that flow along edges, representing data/thought
// flowing through the DAG. Only on lineage/path edges.

interface Particle { progress: number; speed: number; size: number }

function spawnParticles(count: number): Particle[] {
  const p: Particle[] = [];
  for (let i = 0; i < count; i++) {
    p.push({
      progress: Math.random(),
      speed: 0.003 + Math.random() * 0.008,
      size: 1 + Math.random() * 1.5,
    });
  }
  return p;
}

function lerpEdge(edge: LayoutEdge, t: number): { x: number; y: number } {
  const pts = edge.points;
  if (pts.length < 2) return pts[0];
  const totalLen = pts.reduce((sum, p, i) => {
    if (i === 0) return 0;
    const dx = p.x - pts[i - 1].x;
    const dy = p.y - pts[i - 1].y;
    return sum + Math.sqrt(dx * dx + dy * dy);
  }, 0);
  let target = t * totalLen;
  for (let i = 1; i < pts.length; i++) {
    const dx = pts[i].x - pts[i - 1].x;
    const dy = pts[i].y - pts[i - 1].y;
    const segLen = Math.sqrt(dx * dx + dy * dy);
    if (target <= segLen || i === pts.length - 1) {
      const f = segLen > 0 ? target / segLen : 0;
      return {
        x: pts[i - 1].x + dx * f,
        y: pts[i - 1].y + dy * f,
      };
    }
    target -= segLen;
  }
  return pts[pts.length - 1];
}

// ── Component ─────────────────────────────────────────────────────

const DAGCanvas: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;
  let frameCount = 0;
  const stars = generateStars(120);
  const edgeParticles = spawnParticles(40);

  const [viewX, setViewX] = createSignal(0);
  const [viewY, setViewY] = createSignal(0);
  const [viewScale, setViewScale] = createSignal(1);
  const [isDragging, setIsDragging] = createSignal(false);
  const [dragStart, setDragStart] = createSignal({ x: 0, y: 0 });

  const bcm = () => {
    const map = new Map<string, string>();
    dagStore.branches().forEach((b, i) => map.set(b.name, BRANCH_PALETTE[i % BRANCH_PALETTE.length]));
    return map;
  };

  const maxD = () => {
    let m = 0;
    for (const n of dagStore.layout().nodes.values()) if (n.depth > m) m = n.depth;
    return m;
  };

  function s2g(sx: number, sy: number) {
    const r = canvasRef.getBoundingClientRect();
    return { x: (sx - r.left - viewX()) / viewScale(), y: (sy - r.top - viewY()) / viewScale() };
  }

  function nodeAt(gx: number, gy: number): LayoutNode | null {
    for (const n of dagStore.layout().nodes.values()) {
      if (gx >= n.x - n.width / 2 && gx <= n.x + n.width / 2 &&
          gy >= n.y - n.height / 2 && gy <= n.y + n.height / 2) return n;
    }
    return null;
  }

  // ── DRAW ─────────────────────────────────────────────────────

  function draw() {
    frameCount++;
    const ctx = canvasRef.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvasRef.getBoundingClientRect();
    canvasRef.width = rect.width * dpr;
    canvasRef.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const W = rect.width;
    const H = rect.height;
    const t = frameCount / 60;

    // ── Background: radial gradient (viewport into space) ─────
    const bgGrad = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, Math.max(W, H) * 0.7);
    bgGrad.addColorStop(0, C.deep);
    bgGrad.addColorStop(0.6, C.void);
    bgGrad.addColorStop(1, "#020408");
    ctx.fillStyle = bgGrad;
    ctx.fillRect(0, 0, W, H);

    // ── Starfield ─────────────────────────────────────────────
    for (const s of stars) {
      const twinkle = 0.5 + 0.5 * Math.sin(t * s.twinkleRate + s.x * 100);
      const alpha = s.brightness * twinkle;
      ctx.beginPath();
      ctx.arc(s.x * W, s.y * H, s.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(180, 210, 255, ${alpha})`;
      ctx.fill();
    }

    // ── Graph layer ───────────────────────────────────────────
    ctx.save();
    ctx.translate(viewX(), viewY());
    ctx.scale(viewScale(), viewScale());

    const graph = dagStore.layout();
    const sel = dagStore.selection();
    const hov = dagStore.hoveredNode();
    const path = dagStore.highlightedPath();
    const pathSet = path ? new Set(path) : null;
    const anc = dagStore.primaryAncestors();
    const desc = dagStore.primaryDescendants();
    const scheme = dagStore.colorScheme();
    const bmap = bcm();
    const md = maxD();
    const search = dagStore.searchResults();
    const sids = search ? new Set(search.map(s => s.id)) : null;

    // ── Radar pulse from selected node ────────────────────────
    if (sel.primary) {
      const sn = graph.nodes.get(sel.primary);
      if (sn) {
        const pulseR = ((t * 40) % 200);
        const pulseAlpha = Math.max(0, 0.15 - pulseR / 1600);
        ctx.beginPath();
        ctx.arc(sn.x, sn.y, pulseR, 0, Math.PI * 2);
        ctx.strokeStyle = rgba(C.signal, pulseAlpha);
        ctx.lineWidth = 1.5;
        ctx.stroke();
        // Second ring, offset
        const pulseR2 = ((t * 40 + 80) % 200);
        const pulseAlpha2 = Math.max(0, 0.1 - pulseR2 / 2000);
        ctx.beginPath();
        ctx.arc(sn.x, sn.y, pulseR2, 0, Math.PI * 2);
        ctx.strokeStyle = rgba(C.signal, pulseAlpha2);
        ctx.stroke();
      }
    }

    // ── Edges ─────────────────────────────────────────────────
    const activeEdges: LayoutEdge[] = [];

    for (const edge of graph.edges) {
      const onPath = pathSet?.has(edge.source) && pathSet?.has(edge.target);
      const lineage = sel.primary && (
        (edge.source === sel.primary && desc.has(edge.target)) ||
        (edge.target === sel.primary && anc.has(edge.source)) ||
        (anc.has(edge.source) && anc.has(edge.target)) ||
        (desc.has(edge.source) && desc.has(edge.target))
      );

      if (onPath || lineage) activeEdges.push(edge);

      ctx.beginPath();
      if (onPath) {
        ctx.strokeStyle = C.warm;
        ctx.lineWidth = 2;
        ctx.setLineDash([6, 4]);
        ctx.lineDashOffset = -t * 16;
      } else if (lineage) {
        ctx.strokeStyle = rgba(C.signal, 0.45);
        ctx.lineWidth = 1.5;
        ctx.setLineDash([]);
      } else {
        ctx.strokeStyle = rgba(C.border, 0.4);
        ctx.lineWidth = 0.8;
        ctx.setLineDash([]);
      }

      const pts = edge.points;
      if (pts.length >= 2) {
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length - 1; i++) {
          const cur = pts[i], nxt = pts[i + 1];
          ctx.quadraticCurveTo(cur.x, cur.y, (cur.x + nxt.x) / 2, (cur.y + nxt.y) / 2);
        }
        ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y);
      }
      ctx.stroke();
      ctx.setLineDash([]);

      // Arrow
      if (pts.length >= 2) {
        const p1 = pts[pts.length - 2], p2 = pts[pts.length - 1];
        const ang = Math.atan2(p2.y - p1.y, p2.x - p1.x);
        ctx.save();
        ctx.translate(p2.x, p2.y);
        ctx.rotate(ang);
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(-7, -3);
        ctx.lineTo(-7, 3);
        ctx.closePath();
        ctx.fillStyle = ctx.strokeStyle;
        ctx.fill();
        ctx.restore();
      }
    }

    // ── Edge particles (flow of data) ─────────────────────────
    if (activeEdges.length > 0) {
      for (const p of edgeParticles) {
        p.progress = (p.progress + p.speed) % 1;
        const edge = activeEdges[Math.floor(p.progress * 1000) % activeEdges.length];
        const pos = lerpEdge(edge, p.progress);
        ctx.beginPath();
        ctx.arc(pos.x, pos.y, p.size, 0, Math.PI * 2);
        const alpha = 0.4 + 0.4 * Math.sin(p.progress * Math.PI);
        ctx.fillStyle = rgba(C.signal, alpha);
        ctx.fill();
        // Glow
        ctx.beginPath();
        ctx.arc(pos.x, pos.y, p.size * 3, 0, Math.PI * 2);
        ctx.fillStyle = rgba(C.signal, alpha * 0.15);
        ctx.fill();
      }
    }

    // ── Nodes ─────────────────────────────────────────────────

    for (const node of graph.nodes.values()) {
      const isPri = sel.primary === node.id;
      const isSec = sel.secondary === node.id;
      const isHov = hov === node.id;
      const isPath = pathSet?.has(node.id) ?? false;
      const isAnc = anc.has(node.id);
      const isDsc = desc.has(node.id);
      const isSrch = sids?.has(node.id) ?? false;
      const dim = sids !== null && !isSrch && !isPri && !isSec;

      const x = node.x - node.width / 2;
      const y = node.y - node.height / 2;
      const accent = nodeAccent(node, scheme, bmap, md);
      const R = 6;

      ctx.save();
      ctx.globalAlpha = dim ? 0.12 : 1;

      // Glow halo for selected
      if ((isPri || isSec) && !dim) {
        const gc = isPri ? C.signal : C.warm;
        const pulse = 12 + 6 * Math.sin(t * 2.5);
        ctx.shadowColor = gc;
        ctx.shadowBlur = pulse;
      }

      // Body fill
      rr(ctx, x, y, node.width, node.height, R);
      ctx.fillStyle = isPri ? C.raised
        : isSec ? C.raised
        : isHov ? C.surface
        : C.mid;
      ctx.fill();

      ctx.shadowBlur = 0;
      ctx.shadowColor = "transparent";

      // Border
      rr(ctx, x, y, node.width, node.height, R);
      ctx.strokeStyle = isPri ? C.signal
        : isSec ? C.warm
        : isPath ? rgba(C.warm, 0.7)
        : isHov ? C.borderHi
        : isAnc || isDsc ? rgba(C.signal, 0.3)
        : isSrch ? C.emerge
        : C.border;
      ctx.lineWidth = isPri || isSec ? 2 : 1;
      if (isPath && !isPri && !isSec) {
        ctx.setLineDash([3, 2]);
        ctx.lineDashOffset = -t * 8;
      }
      ctx.stroke();
      ctx.setLineDash([]);

      // Left accent strip
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(x, y + R);
      ctx.arcTo(x, y, x + R, y, R);
      ctx.lineTo(x + 3.5, y);
      ctx.lineTo(x + 3.5, y + node.height);
      ctx.lineTo(x + R, y + node.height);
      ctx.arcTo(x, y + node.height, x, y + node.height - R, R);
      ctx.closePath();
      ctx.fillStyle = accent;
      ctx.fill();
      ctx.restore();

      // ── Node text ─────────────────────────────────────────
      const F = "'JetBrains Mono', 'SF Mono', 'Fira Code', Consolas, monospace";

      // ID
      ctx.fillStyle = C.text;
      ctx.font = `600 11px ${F}`;
      ctx.fillText(
        node.id.length > 14 ? node.id.slice(0, 14) + "\u2026" : node.id,
        x + 11, y + 17
      );

      // Metadata
      const meta = node.snapshot.metadata as Record<string, unknown> | null;
      const label = (typeof meta?.label === "string" ? meta.label : "") ||
                    (typeof meta?.agent === "string" ? meta.agent : "");
      if (label) {
        ctx.font = `11px ${F}`;
        ctx.fillStyle = C.textMuted;
        ctx.fillText(label.length > 22 ? label.slice(0, 22) + "\u2026" : label, x + 11, y + 32);
      }

      // Branch badge
      if (node.isBranchHead) {
        const bn = node.branchNames[0] ?? "";
        const sh = bn.length > 12 ? "\u2026" + bn.slice(-10) : bn;
        ctx.font = `600 9px ${F}`;
        const tw = ctx.measureText(sh).width;
        const bx = x + node.width - tw - 12;
        const by = y + node.height - 11;
        rr(ctx, bx - 4, by - 9, tw + 8, 13, 3);
        ctx.fillStyle = rgba(accent.startsWith("#") ? accent : C.signal, 0.18);
        ctx.fill();
        ctx.fillStyle = accent;
        ctx.fillText(sh, bx, by);
      }

      // Collapse indicator
      if (node.collapsed) {
        ctx.fillStyle = C.warm;
        ctx.font = `600 10px ${F}`;
        ctx.fillText(`+${node.childCount}`, x + node.width - 34, y + 17);
      }

      // Root: glowing dot
      if (node.isRoot) {
        const dx = x + 11, dy = y + node.height - 10;
        const gp = 0.6 + 0.4 * Math.sin(t * 1.5);
        ctx.beginPath();
        ctx.arc(dx, dy, 3, 0, Math.PI * 2);
        ctx.fillStyle = C.emerge;
        ctx.fill();
        ctx.beginPath();
        ctx.arc(dx, dy, 6, 0, Math.PI * 2);
        ctx.fillStyle = rgba(C.emerge, 0.12 * gp);
        ctx.fill();
        ctx.font = `8px ${F}`;
        ctx.fillStyle = C.textDim;
        ctx.fillText("GENESIS", dx + 8, dy + 3);
      }

      // Depth
      ctx.fillStyle = C.textDim;
      ctx.font = `8px ${F}`;
      ctx.fillText(`\u2022${node.depth}`, x + node.width - 20, y + 15);

      ctx.restore();
    }

    ctx.restore();

    // ── Screen-space vignette ─────────────────────────────────
    const vig = ctx.createRadialGradient(W / 2, H / 2, W * 0.25, W / 2, H / 2, W * 0.7);
    vig.addColorStop(0, "rgba(0,0,0,0)");
    vig.addColorStop(1, "rgba(0,0,0,0.35)");
    ctx.fillStyle = vig;
    ctx.fillRect(0, 0, W, H);

    // ── Subtle scan line overlay ──────────────────────────────
    ctx.fillStyle = "rgba(255,255,255,0.008)";
    for (let sy = 0; sy < H; sy += 3) {
      ctx.fillRect(0, sy, W, 1);
    }
  }

  // ── Event handlers (mouse and touch) ────────────────────────

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
      const g = s2g(e.clientX, e.clientY);
      dagStore.setHoveredNode(nodeAt(g.x, g.y)?.id ?? null);
    }
  }

  function onMouseUp(e: MouseEvent) {
    if (isDragging()) {
      setIsDragging(false);
      const dx = e.clientX - dragStart().x - viewX();
      const dy = e.clientY - dragStart().y - viewY();
      if (Math.abs(dx) < 3 && Math.abs(dy) < 3) {
        const g = s2g(e.clientX, e.clientY);
        const n = nodeAt(g.x, g.y);
        if (n) {
          (e.shiftKey || dagStore.diffMode()) ? dagStore.selectNode(n.id, true) : dagStore.selectNode(n.id);
        } else dagStore.clearSelection();
      }
    }
  }

  // ── Touch event handlers for mobile ──────────────────────────

  // Double tap detection
  let lastTapTime = 0;
  let lastTapPosition = { x: 0, y: 0 };

  function onTouchStart(e: TouchEvent) {
    e.preventDefault(); // Prevent scrolling and other default behaviors
    if (e.touches.length === 1) {
      const touch = e.touches[0];
      setIsDragging(true);
      setDragStart({ x: touch.clientX - viewX(), y: touch.clientY - viewY() });
    }
  }

  function onTouchMove(e: TouchEvent) {
    e.preventDefault();
    if (isDragging() && e.touches.length === 1) {
      const touch = e.touches[0];
      setViewX(touch.clientX - dragStart().x);
      setViewY(touch.clientY - dragStart().y);
    }
  }

  function onTouchEnd(e: TouchEvent) {
    e.preventDefault();
    if (isDragging()) {
      setIsDragging(false);
      if (e.changedTouches.length === 1) {
        const touch = e.changedTouches[0];
        const dx = touch.clientX - dragStart().x - viewX();
        const dy = touch.clientY - dragStart().y - viewY();

        // Check for double tap
        const currentTime = Date.now();
        const timeDiff = currentTime - lastTapTime;
        const posDiff = Math.sqrt(
          Math.pow(touch.clientX - lastTapPosition.x, 2) +
          Math.pow(touch.clientY - lastTapPosition.y, 2)
        );

        if (timeDiff < 300 && posDiff < 30) { // Double tap within 300ms and 30px
          const g = s2g(touch.clientX, touch.clientY);
          const n = nodeAt(g.x, g.y);
          if (n) dagStore.toggleCollapse(n.id);
        } else if (Math.abs(dx) < 10 && Math.abs(dy) < 10) { // Single tap (larger threshold for touch)
          const g = s2g(touch.clientX, touch.clientY);
          const n = nodeAt(g.x, g.y);
          if (n) {
            dagStore.selectNode(n.id); // Single tap selects
          } else dagStore.clearSelection();
        }

        lastTapTime = currentTime;
        lastTapPosition = { x: touch.clientX, y: touch.clientY };
      }
    }
  }

  function onWheel(e: WheelEvent) {
    e.preventDefault();
    const r = canvasRef.getBoundingClientRect();
    const mx = e.clientX - r.left, my = e.clientY - r.top;
    const f = e.deltaY < 0 ? 1.1 : 0.9;
    const ns = Math.max(0.05, Math.min(5, viewScale() * f));
    const ratio = ns / viewScale();
    setViewX(mx - (mx - viewX()) * ratio);
    setViewY(my - (my - viewY()) * ratio);
    setViewScale(ns);
  }

  function onDblClick(e: MouseEvent) {
    const g = s2g(e.clientX, e.clientY);
    const n = nodeAt(g.x, g.y);
    if (n) dagStore.toggleCollapse(n.id);
  }

  function fitToView() {
    const graph = dagStore.layout();
    if (graph.nodes.size === 0) return;
    const r = canvasRef.getBoundingClientRect();
    const pad = 80;
    const s = Math.min((r.width - pad * 2) / graph.width, (r.height - pad * 2) / graph.height, 1.5);
    setViewScale(s);
    setViewX((r.width - graph.width * s) / 2);
    setViewY((r.height - graph.height * s) / 2);
  }

  function centerOnNode(id: string) {
    const n = dagStore.layout().nodes.get(id);
    if (!n) return;
    const r = canvasRef.getBoundingClientRect();
    setViewX(r.width / 2 - n.x * viewScale());
    setViewY(r.height / 2 - n.y * viewScale());
  }

  onMount(() => {
    const loop = () => { draw(); animFrame = requestAnimationFrame(loop); };
    animFrame = requestAnimationFrame(loop);
    canvasRef.addEventListener("wheel", onWheel, { passive: false });
  });

  onCleanup(() => {
    cancelAnimationFrame(animFrame);
    canvasRef?.removeEventListener("wheel", onWheel);
  });

  createEffect(() => { if (dagStore.layout().nodes.size > 0) fitToView(); });
  createEffect(() => { const s = dagStore.selection(); if (s.primary) centerOnNode(s.primary); });

  window.__dagFitToView = fitToView;
  window.__dagCenterOnNode = centerOnNode;

  return (
    <canvas
      ref={canvasRef!}
      style={{
        width: "100%",
        height: "100%",
        cursor: isDragging() ? "grabbing" : dagStore.hoveredNode() ? "pointer" : "crosshair",
        "touch-action": "none", // Prevent default touch behaviors
      }}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onDblClick={onDblClick}
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
    />
  );
};

export default DAGCanvas;
