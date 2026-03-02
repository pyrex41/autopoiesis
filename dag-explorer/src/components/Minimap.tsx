import { onMount, onCleanup, createEffect, type Component } from "solid-js";
import { dagStore } from "../stores/dag";

const MINIMAP_W = 200;
const MINIMAP_H = 140;

const Minimap: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;

  function draw() {
    const ctx = canvasRef.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvasRef.width = MINIMAP_W * dpr;
    canvasRef.height = MINIMAP_H * dpr;
    ctx.scale(dpr, dpr);

    ctx.clearRect(0, 0, MINIMAP_W, MINIMAP_H);
    ctx.fillStyle = "rgba(2, 6, 23, 0.85)";
    ctx.fillRect(0, 0, MINIMAP_W, MINIMAP_H);

    const graph = dagStore.layout();
    if (graph.nodes.size === 0) return;

    const pad = 10;
    const scaleX = (MINIMAP_W - pad * 2) / graph.width;
    const scaleY = (MINIMAP_H - pad * 2) / graph.height;
    const scale = Math.min(scaleX, scaleY);

    const offsetX = pad + (MINIMAP_W - pad * 2 - graph.width * scale) / 2;
    const offsetY = pad + (MINIMAP_H - pad * 2 - graph.height * scale) / 2;

    const sel = dagStore.selection();

    // Draw edges
    ctx.strokeStyle = "rgba(100, 116, 139, 0.3)";
    ctx.lineWidth = 0.5;
    for (const edge of graph.edges) {
      if (edge.points.length < 2) continue;
      ctx.beginPath();
      ctx.moveTo(
        offsetX + edge.points[0].x * scale,
        offsetY + edge.points[0].y * scale
      );
      for (let i = 1; i < edge.points.length; i++) {
        ctx.lineTo(
          offsetX + edge.points[i].x * scale,
          offsetY + edge.points[i].y * scale
        );
      }
      ctx.stroke();
    }

    // Draw nodes as dots
    for (const node of graph.nodes.values()) {
      const x = offsetX + node.x * scale;
      const y = offsetY + node.y * scale;
      const isPrimary = sel.primary === node.id;
      const isSecondary = sel.secondary === node.id;

      ctx.beginPath();
      ctx.arc(x, y, isPrimary ? 3 : isSecondary ? 2.5 : 1.5, 0, Math.PI * 2);
      ctx.fillStyle = isPrimary
        ? "#818cf8"
        : isSecondary
          ? "#fbbf24"
          : node.isBranchHead
            ? "#34d399"
            : node.isRoot
              ? "#f97316"
              : "#64748b";
      ctx.fill();
    }

    // Border
    ctx.strokeStyle = "rgba(71, 85, 105, 0.5)";
    ctx.lineWidth = 1;
    ctx.strokeRect(0.5, 0.5, MINIMAP_W - 1, MINIMAP_H - 1);
  }

  onMount(() => {
    const loop = () => {
      draw();
      animFrame = requestAnimationFrame(loop);
    };
    animFrame = requestAnimationFrame(loop);
  });

  onCleanup(() => cancelAnimationFrame(animFrame));

  return (
    <canvas
      ref={canvasRef!}
      class="minimap"
      style={{
        width: `${MINIMAP_W}px`,
        height: `${MINIMAP_H}px`,
      }}
    />
  );
};

export default Minimap;
