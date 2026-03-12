import { type Component, onMount, onCleanup, createSignal } from "solid-js";
import { constellationStore } from "../stores/constellation";
import { agentStore } from "../stores/agents";
import "../styles/constellation.css";

// ── Palette (matches DAGCanvas) ──────────────────────────────────
const C = {
  void: "#04060e",
  deep: "#080c18",
  border: "#1e2d4a",
  text: "#d0daf0",
  textMuted: "#7a8ba8",
  textDim: "#4a5a78",
  signal: "#4fc3f7",
};

interface Star { x: number; y: number; r: number; brightness: number; twinkleRate: number }

function generateStars(count: number): Star[] {
  const stars: Star[] = [];
  for (let i = 0; i < count; i++) {
    stars.push({
      x: Math.random(), y: Math.random(),
      r: 0.3 + Math.random() * 1.2,
      brightness: 0.15 + Math.random() * 0.5,
      twinkleRate: 0.3 + Math.random() * 2,
    });
  }
  return stars;
}

function rgba(hex: string, a: number): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${a})`;
}

const ConstellationView: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;
  let frameCount = 0;
  const stars = generateStars(200);

  const [viewX, setViewX] = createSignal(0);
  const [viewY, setViewY] = createSignal(0);
  const [viewScale, setViewScale] = createSignal(1);
  const [isDragging, setIsDragging] = createSignal(false);
  const [dragStart, setDragStart] = createSignal({ x: 0, y: 0 });

  function s2g(sx: number, sy: number) {
    const r = canvasRef.getBoundingClientRect();
    const cx = r.width / 2 + viewX();
    const cy = r.height / 2 + viewY();
    return { x: (sx - r.left - cx) / viewScale(), y: (sy - r.top - cy) / viewScale() };
  }

  function nodeAt(gx: number, gy: number) {
    for (const n of constellationStore.nodes()) {
      const dx = gx - n.x, dy = gy - n.y;
      if (dx * dx + dy * dy <= n.radius * n.radius * 4) return n;
    }
    return null;
  }

  function draw() {
    frameCount++;
    const ctx = canvasRef.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvasRef.getBoundingClientRect();
    canvasRef.width = rect.width * dpr;
    canvasRef.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const W = rect.width, H = rect.height;
    const t = frameCount / 60;

    // Background
    const bgGrad = ctx.createRadialGradient(W / 2, H / 2, 0, W / 2, H / 2, Math.max(W, H) * 0.7);
    bgGrad.addColorStop(0, C.deep);
    bgGrad.addColorStop(0.6, C.void);
    bgGrad.addColorStop(1, "#020408");
    ctx.fillStyle = bgGrad;
    ctx.fillRect(0, 0, W, H);

    // Starfield
    for (const s of stars) {
      const twinkle = 0.5 + 0.5 * Math.sin(t * s.twinkleRate + s.x * 100);
      ctx.beginPath();
      ctx.arc(s.x * W, s.y * H, s.r, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(180, 210, 255, ${s.brightness * twinkle})`;
      ctx.fill();
    }

    // Graph layer
    ctx.save();
    const cx = W / 2 + viewX();
    const cy = H / 2 + viewY();
    ctx.translate(cx, cy);
    ctx.scale(viewScale(), viewScale());

    // Tick simulation
    constellationStore.tick();

    const nodes = constellationStore.nodes();
    const nodeMap = new Map(nodes.map(n => [n.id, n]));
    const sel = constellationStore.selectedNode();
    const hov = constellationStore.hoveredNode();

    // Draw edges
    for (const edge of constellationStore.edges()) {
      const a = nodeMap.get(edge.source), b = nodeMap.get(edge.target);
      if (!a || !b) continue;
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.strokeStyle = edge.type === "team-member"
        ? rgba(C.signal, 0.15)
        : rgba(C.border, 0.3);
      ctx.lineWidth = 0.8;
      ctx.stroke();
    }

    // Draw nodes
    const F = "'JetBrains Mono', 'SF Mono', 'Fira Code', Consolas, monospace";
    for (const node of nodes) {
      const isSel = sel === node.id;
      const isHov = hov === node.id;

      // Glow
      if (isSel || isHov) {
        ctx.beginPath();
        ctx.arc(node.x, node.y, node.radius * 2.5, 0, Math.PI * 2);
        const pulse = 0.15 + 0.1 * Math.sin(t * 2);
        ctx.fillStyle = rgba(node.color, pulse);
        ctx.fill();
      }

      // Outer glow ring
      ctx.beginPath();
      ctx.arc(node.x, node.y, node.radius * 1.5, 0, Math.PI * 2);
      ctx.fillStyle = rgba(node.color, 0.08 + (isSel ? 0.1 : 0));
      ctx.fill();

      // Core
      ctx.beginPath();
      ctx.arc(node.x, node.y, node.radius, 0, Math.PI * 2);
      ctx.fillStyle = node.color;
      ctx.fill();

      // Inner highlight
      ctx.beginPath();
      ctx.arc(node.x - node.radius * 0.2, node.y - node.radius * 0.2, node.radius * 0.4, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(255,255,255,0.2)";
      ctx.fill();

      // Label for selected/hovered
      if (isSel || isHov) {
        ctx.font = `600 11px ${F}`;
        ctx.fillStyle = C.text;
        ctx.textAlign = "center";
        ctx.fillText(node.label, node.x, node.y - node.radius - 8);
        ctx.textAlign = "left";

        if (isSel && node.state) {
          ctx.font = `9px ${F}`;
          ctx.fillStyle = C.textMuted;
          ctx.textAlign = "center";
          ctx.fillText(node.state, node.x, node.y + node.radius + 14);
          ctx.textAlign = "left";
        }
      }

      // Team nodes get diamond shape overlay
      if (node.type === "team") {
        ctx.save();
        ctx.translate(node.x, node.y);
        ctx.rotate(Math.PI / 4);
        ctx.strokeStyle = rgba(node.color, 0.5);
        ctx.lineWidth = 1;
        const s = node.radius * 0.7;
        ctx.strokeRect(-s, -s, s * 2, s * 2);
        ctx.restore();
      }
    }

    ctx.restore();

    // Vignette
    const vig = ctx.createRadialGradient(W / 2, H / 2, W * 0.25, W / 2, H / 2, W * 0.7);
    vig.addColorStop(0, "rgba(0,0,0,0)");
    vig.addColorStop(1, "rgba(0,0,0,0.35)");
    ctx.fillStyle = vig;
    ctx.fillRect(0, 0, W, H);
  }

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
      const n = nodeAt(g.x, g.y);
      constellationStore.setHoveredNode(n?.id ?? null);
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
          constellationStore.setSelectedNode(n.id);
          if (n.type === "agent") agentStore.selectAgent(n.id);
        } else {
          constellationStore.setSelectedNode(null);
        }
      }
    }
  }

  function onWheel(e: WheelEvent) {
    e.preventDefault();
    const f = e.deltaY < 0 ? 1.1 : 0.9;
    setViewScale(Math.max(0.1, Math.min(5, viewScale() * f)));
  }

  onMount(() => {
    constellationStore.buildGraph();
    const loop = () => { draw(); animFrame = requestAnimationFrame(loop); };
    animFrame = requestAnimationFrame(loop);
    canvasRef.addEventListener("wheel", onWheel, { passive: false });
  });

  onCleanup(() => {
    cancelAnimationFrame(animFrame);
    canvasRef?.removeEventListener("wheel", onWheel);
  });

  return (
    <div class="constellation-view">
      <canvas
        ref={canvasRef!}
        class="constellation-canvas"
        style={{
          width: "100%",
          height: "100%",
          cursor: isDragging() ? "grabbing" : constellationStore.hoveredNode() ? "pointer" : "crosshair",
        }}
        onMouseDown={onMouseDown}
        onMouseMove={onMouseMove}
        onMouseUp={onMouseUp}
      />
    </div>
  );
};

export default ConstellationView;
