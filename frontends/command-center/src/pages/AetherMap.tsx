/**
 * AETHER map — single full-screen canvas. Phase 3 of the Week-1
 * layout-feasibility experiment.
 *
 * One canvas. Starfield + force-positioned spectrally-colored nodes.
 * Pan with left-drag, zoom with wheel. No labels, no selection, no
 * chrome, no animations beyond the starfield twinkle.
 *
 * Reuse map:
 *   - starfield gen + draw: ConstellationView.tsx:19-95
 *   - pan/zoom math:        DAGCanvas.tsx:235-620
 *   - force sim + colors:   stores/aether.ts
 */
import { type Component, onMount, onCleanup, createSignal } from "solid-js";
import { aetherStore } from "../stores/aether";

// ── Palette (matches design-system.ts) ───────────────────────────────
const C = {
  void: "#04060e",
  deep: "#080c18",
  edge: "#1e2d4a",
};

// ── Starfield (copied directly from ConstellationView.tsx:19-95) ──────

interface Star {
  x: number;
  y: number;
  r: number;
  brightness: number;
  twinkleRate: number;
}

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

const AetherMap: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;
  let frameCount = 0;
  const stars = generateStars(300); // a touch denser than constellation view

  const [viewX, setViewX] = createSignal(0);
  const [viewY, setViewY] = createSignal(0);
  const [viewScale, setViewScale] = createSignal(1);
  const [isDragging, setIsDragging] = createSignal(false);
  const [dragStart, setDragStart] = createSignal({ x: 0, y: 0 });

  // Force simulation cadence — separate from rAF so we can decouple
  // physics from rendering rate without ever animating the nodes.
  // The simulation runs for a finite warmup (~3s @ 60Hz = 180 ticks)
  // then settles. After that we still call tick() but kinetic energy
  // approaches zero so nothing visibly moves — consistent with the
  // "no animations" constraint while letting the layout solve.
  let physicsTicks = 0;
  const PHYSICS_WARMUP_TICKS = 240;

  // ── Pan/zoom (adapted from DAGCanvas.tsx:519-620) ──────────────────

  function onMouseDown(e: MouseEvent) {
    if (e.button !== 0) return;
    setIsDragging(true);
    setDragStart({ x: e.clientX - viewX(), y: e.clientY - viewY() });
  }

  function onMouseMove(e: MouseEvent) {
    if (!isDragging()) return;
    setViewX(e.clientX - dragStart().x);
    setViewY(e.clientY - dragStart().y);
  }

  function onMouseUp() {
    setIsDragging(false);
  }

  function onWheel(e: WheelEvent) {
    e.preventDefault();
    const r = canvasRef.getBoundingClientRect();
    const mx = e.clientX - r.left;
    const my = e.clientY - r.top;
    const f = e.deltaY < 0 ? 1.1 : 0.9;
    const ns = Math.max(0.1, Math.min(6, viewScale() * f));
    const ratio = ns / viewScale();
    setViewX(mx - (mx - viewX()) * ratio);
    setViewY(my - (my - viewY()) * ratio);
    setViewScale(ns);
  }

  // ── Fit-to-view: called once after physics warmup so the layout
  //    actually fills the screen instead of clustering at the origin. ─

  let didInitialFit = false;
  function fitToView() {
    const ns = aetherStore.nodes();
    if (ns.length === 0) return;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const n of ns) {
      if (n.x < minX) minX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.x > maxX) maxX = n.x;
      if (n.y > maxY) maxY = n.y;
    }
    const w = Math.max(1, maxX - minX);
    const h = Math.max(1, maxY - minY);
    const r = canvasRef.getBoundingClientRect();
    const pad = 100;
    const s = Math.min((r.width - pad * 2) / w, (r.height - pad * 2) / h, 1.2);
    setViewScale(s);
    // Center the bounding box.
    const cx = (minX + maxX) / 2;
    const cy = (minY + maxY) / 2;
    setViewX(r.width / 2 - cx * s);
    setViewY(r.height / 2 - cy * s);
  }

  // ── Draw ──────────────────────────────────────────────────────────

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

    // Background — radial gradient, slightly deeper than ConstellationView.
    const bg = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, Math.max(W, H) * 0.8);
    bg.addColorStop(0, C.deep);
    bg.addColorStop(0.6, C.void);
    bg.addColorStop(1, "#020308");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    // Starfield — twinkle is the ONLY animation allowed in this page.
    for (const s of stars) {
      const tw = 0.5 + 0.5 * Math.sin(t * s.twinkleRate + s.x * 100);
      ctx.beginPath();
      ctx.arc(s.x * W, s.y * H, s.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(180, 210, 255, ${(s.brightness * tw).toFixed(3)})`;
      ctx.fill();
    }

    // Run physics inside the rAF until warmup ticks consumed. After that
    // the system has effectively settled — keep ticking (cheap; helps
    // when new data lands) but it won't visibly move.
    if (physicsTicks < PHYSICS_WARMUP_TICKS) {
      // Multi-step per frame during warmup so the layout converges fast
      // and the user doesn't watch it solve.
      for (let i = 0; i < 4; i++) aetherStore.tick();
      physicsTicks += 4;
      if (physicsTicks >= PHYSICS_WARMUP_TICKS && !didInitialFit && aetherStore.nodes().length > 0) {
        fitToView();
        didInitialFit = true;
      }
    } else {
      aetherStore.tick(); // gentle continued solve; ~0 motion
    }

    // ── Graph layer ─────────────────────────────────────────────────
    ctx.save();
    ctx.translate(viewX(), viewY());
    ctx.scale(viewScale(), viewScale());

    const nodes = aetherStore.nodes();
    const edges = aetherStore.edges();
    const nodeMap = new Map(nodes.map((n) => [n.id, n]));

    // Edges first, so nodes draw over.
    ctx.lineWidth = 0.6 / viewScale();
    for (const e of edges) {
      const a = nodeMap.get(e.source);
      const b = nodeMap.get(e.target);
      if (!a || !b) continue;
      // Stroke alpha decays with diff magnitude — high divergence edges
      // are dimmer (they're more "proper motion vector" than tight
      // structural ligament).
      const alpha = Math.max(0.08, 0.35 - e.diffMagnitude * 0.04);
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.strokeStyle = `rgba(80, 110, 160, ${alpha.toFixed(3)})`;
      ctx.stroke();
    }

    // Nodes — halo first, core on top.
    for (const n of nodes) {
      // Halo (no blur — additive alpha disk).
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.radius * 2.4, 0, Math.PI * 2);
      ctx.fillStyle = n.haloColor;
      ctx.fill();
    }
    for (const n of nodes) {
      // Core.
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.radius, 0, Math.PI * 2);
      ctx.fillStyle = n.color;
      ctx.fill();
      // Subtle outline so brighter stars don't blow out.
      ctx.strokeStyle = "rgba(255,255,255,0.15)";
      ctx.lineWidth = 0.4 / viewScale();
      ctx.stroke();
    }

    ctx.restore();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  onMount(() => {
    aetherStore.load();
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

  return (
    <canvas
      ref={canvasRef!}
      style={{
        width: "100vw",
        height: "100vh",
        display: "block",
        cursor: isDragging() ? "grabbing" : "grab",
        "touch-action": "none",
        background: C.void,
      }}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={onMouseUp}
    />
  );
};

export default AetherMap;
