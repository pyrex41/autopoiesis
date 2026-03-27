import { onMount, onCleanup, type Component } from "solid-js";
import { dagStore } from "../stores/dag";

const W = 200;
const H = 140;

const Minimap: Component = () => {
  let canvasRef!: HTMLCanvasElement;
  let animFrame: number;

  function draw() {
    const ctx = canvasRef.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    canvasRef.width = W * dpr;
    canvasRef.height = H * dpr;
    ctx.scale(dpr, dpr);

    // Gradient background matching observatory theme
    const bg = ctx.createLinearGradient(0, 0, 0, H);
    bg.addColorStop(0, "#0e1525");
    bg.addColorStop(1, "#080c18");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    const graph = dagStore.layout();
    if (graph.nodes.size === 0) return;

    const pad = 12;
    const scaleX = (W - pad * 2) / graph.width;
    const scaleY = (H - pad * 2) / graph.height;
    const scale = Math.min(scaleX, scaleY);
    const ox = pad + (W - pad * 2 - graph.width * scale) / 2;
    const oy = pad + (H - pad * 2 - graph.height * scale) / 2;
    const sel = dagStore.selection();

    // Edges
    ctx.strokeStyle = "rgba(30, 45, 74, 0.5)";
    ctx.lineWidth = 0.5;
    for (const edge of graph.edges) {
      if (edge.points.length < 2) continue;
      ctx.beginPath();
      ctx.moveTo(ox + edge.points[0].x * scale, oy + edge.points[0].y * scale);
      for (let i = 1; i < edge.points.length; i++) {
        ctx.lineTo(ox + edge.points[i].x * scale, oy + edge.points[i].y * scale);
      }
      ctx.stroke();
    }

    // Nodes
    for (const node of graph.nodes.values()) {
      const x = ox + node.x * scale;
      const y = oy + node.y * scale;
      const pri = sel.primary === node.id;
      const sec = sel.secondary === node.id;

      ctx.beginPath();
      ctx.arc(x, y, pri ? 3.5 : sec ? 3 : 1.5, 0, Math.PI * 2);
      ctx.fillStyle = pri ? "#4fc3f7"
        : sec ? "#ffab40"
        : node.isBranchHead ? "#69f0ae"
        : node.isRoot ? "#ffab40"
        : "#4a5a78";
      ctx.fill();

      // Glow for selected
      if (pri) {
        ctx.beginPath();
        ctx.arc(x, y, 7, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(79, 195, 247, 0.15)";
        ctx.fill();
      }
    }
  }

  onMount(() => {
    const loop = () => { draw(); animFrame = requestAnimationFrame(loop); };
    animFrame = requestAnimationFrame(loop);
  });
  onCleanup(() => cancelAnimationFrame(animFrame));

  return (
    <canvas
      ref={canvasRef!}
      class="minimap"
      style={{ width: `${W}px`, height: `${H}px` }}
    />
  );
};

export default Minimap;
