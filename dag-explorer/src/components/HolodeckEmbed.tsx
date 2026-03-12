import { type Component, onMount, onCleanup, createSignal } from "solid-js";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { CSS2DRenderer, CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import type { EntityActivity } from "../stores/holodeck";

// ── Types (self-contained, no shared store dependency) ──────────

interface EmbedEntityData {
  id: number;
  position: [number, number, number];
  scale?: [number, number, number];
  rotation?: [number, number, number];
  color: [number, number, number, number];
  glow?: boolean;
  glowIntensity?: number;
  meshType?: string;
  label?: string;
  labelOffset?: number;
  activity?: EntityActivity;
}

interface EmbedConnectionData {
  id: number;
  from: [number, number, number];
  to: [number, number, number];
  color: [number, number, number, number];
}

interface HolodeckFrame {
  type: "holodeck_frame";
  dt: number;
  entities: EmbedEntityData[];
  connections: EmbedConnectionData[];
  camera: { position: [number, number, number]; viewMatrix?: number[]; projectionMatrix?: number[] };
  teams?: unknown[];
  hud?: { visible: boolean };
}

// ── Props ───────────────────────────────────────────────────────

interface HolodeckEmbedProps {
  wsUrl: string;
  width?: string;
  height?: string;
  theme?: "dark" | "light";
  onAgentSelected?: (entityId: number | null) => void;
}

// ── Component ───────────────────────────────────────────────────

const HolodeckEmbed: Component<HolodeckEmbedProps> = (props) => {
  let containerRef: HTMLDivElement | undefined;
  let animFrameId = 0;
  let ws: WebSocket | null = null;

  // Three.js
  let renderer: THREE.WebGLRenderer;
  let css2dRenderer: CSS2DRenderer;
  let scene: THREE.Scene;
  let camera: THREE.PerspectiveCamera;
  let controls: OrbitControls;
  let composer: EffectComposer;
  let raycaster: THREE.Raycaster;
  let mouse: THREE.Vector2;

  const entityGroups = new Map<number, THREE.Group>();
  const entityMeshes = new Map<number, THREE.Mesh>();
  const entityLabels = new Map<number, CSS2DObject>();
  const entityActivityLabels = new Map<number, CSS2DObject>();
  const entityCostBadges = new Map<number, CSS2DObject>();
  const connectionLines = new Map<number, THREE.Line>();
  const geometryCache: Record<string, THREE.BufferGeometry> = {};

  const [selectedId, setSelectedId] = createSignal<number | null>(null);
  const [fps, setFps] = createSignal(0);
  let frameTimestamps: number[] = [];

  // Latest frame data
  let latestEntities: EmbedEntityData[] = [];
  let latestConnections: EmbedConnectionData[] = [];

  function getGeometry(meshType: string): THREE.BufferGeometry {
    if (geometryCache[meshType]) return geometryCache[meshType];
    let geo: THREE.BufferGeometry;
    switch (meshType) {
      case "sphere": geo = new THREE.SphereGeometry(0.5, 32, 32); break;
      case "octahedron": geo = new THREE.OctahedronGeometry(0.5); break;
      case "box": case "cube": geo = new THREE.BoxGeometry(0.8, 0.8, 0.8); break;
      case "cylinder": geo = new THREE.CylinderGeometry(0.3, 0.3, 1, 16); break;
      case "torus": geo = new THREE.TorusGeometry(0.4, 0.15, 16, 32); break;
      default: geo = new THREE.SphereGeometry(0.5, 32, 32);
    }
    geometryCache[meshType] = geo;
    return geo;
  }

  function makeCSSLabel(text: string, css: string): CSS2DObject {
    const div = document.createElement("div");
    div.textContent = text;
    div.style.cssText = css;
    return new CSS2DObject(div);
  }

  function initScene() {
    if (!containerRef) return;
    const w = containerRef.clientWidth;
    const h = containerRef.clientHeight;
    const isDark = (props.theme ?? "dark") === "dark";
    const bgColor = isDark ? 0x0a0a0f : 0xf0f0f5;

    scene = new THREE.Scene();
    scene.background = new THREE.Color(bgColor);
    scene.fog = new THREE.FogExp2(bgColor, 0.02);

    camera = new THREE.PerspectiveCamera(60, w / h, 0.1, 1000);
    camera.position.set(0, 8, 15);
    camera.lookAt(0, 0, 0);

    renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    containerRef.appendChild(renderer.domElement);

    css2dRenderer = new CSS2DRenderer();
    css2dRenderer.setSize(w, h);
    css2dRenderer.domElement.style.position = "absolute";
    css2dRenderer.domElement.style.top = "0";
    css2dRenderer.domElement.style.left = "0";
    css2dRenderer.domElement.style.pointerEvents = "none";
    containerRef.appendChild(css2dRenderer.domElement);

    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;
    controls.minDistance = 2;
    controls.maxDistance = 100;

    scene.add(new THREE.AmbientLight(0x404040, 0.8));
    const dir = new THREE.DirectionalLight(0xffffff, 1.0);
    dir.position.set(10, 20, 10);
    scene.add(dir);
    scene.add(new THREE.PointLight(0x4444ff, 0.5, 50));

    const grid = new THREE.GridHelper(40, 40, isDark ? 0x222244 : 0xccccdd, isDark ? 0x111133 : 0xddddee);
    (grid.material as THREE.Material).transparent = true;
    (grid.material as THREE.Material).opacity = 0.3;
    scene.add(grid);

    composer = new EffectComposer(renderer);
    composer.addPass(new RenderPass(scene, camera));
    composer.addPass(new UnrealBloomPass(new THREE.Vector2(w, h), 0.5, 0.4, 0.85));

    raycaster = new THREE.Raycaster();
    mouse = new THREE.Vector2();
    renderer.domElement.addEventListener("click", onCanvasClick);
  }

  function onCanvasClick(event: MouseEvent) {
    if (!containerRef) return;
    const rect = containerRef.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(mouse, camera);
    const intersects = raycaster.intersectObjects(Array.from(entityMeshes.values()));
    if (intersects.length > 0) {
      for (const [id, mesh] of entityMeshes) {
        if (mesh === intersects[0].object) {
          setSelectedId(id);
          props.onAgentSelected?.(id);
          // Notify parent window (for xwidget integration)
          window.postMessage({ type: "agent-selected", agentId: id }, "*");
          return;
        }
      }
    } else {
      setSelectedId(null);
      props.onAgentSelected?.(null);
      window.postMessage({ type: "agent-selected", agentId: null }, "*");
    }
  }

  function updateEntities(entities: EmbedEntityData[]) {
    const currentIds = new Set<number>();
    for (const ent of entities) {
      currentIds.add(ent.id);
      let group = entityGroups.get(ent.id);
      if (!group) {
        group = new THREE.Group();
        scene.add(group);
        entityGroups.set(ent.id, group);

        const geo = getGeometry(ent.meshType || "sphere");
        const color = new THREE.Color(ent.color[0], ent.color[1], ent.color[2]);
        const mat = new THREE.MeshStandardMaterial({
          color, emissive: color,
          emissiveIntensity: ent.glow ? (ent.glowIntensity || 0.5) : 0,
          metalness: 0.3, roughness: 0.4,
        });
        const mesh = new THREE.Mesh(geo, mat);
        group.add(mesh);
        entityMeshes.set(ent.id, mesh);

        if (ent.label) {
          const label = makeCSSLabel(ent.label,
            "color:#e0e0ff;font-family:'JetBrains Mono',monospace;font-size:11px;padding:2px 6px;background:rgba(10,10,30,0.75);border:1px solid rgba(100,100,255,0.3);border-radius:3px;pointer-events:none;white-space:nowrap;");
          label.position.set(0, ent.labelOffset || 1.2, 0);
          group.add(label);
          entityLabels.set(ent.id, label);
        }
      } else {
        const mesh = entityMeshes.get(ent.id);
        if (mesh) {
          const mat = mesh.material as THREE.MeshStandardMaterial;
          const color = new THREE.Color(ent.color[0], ent.color[1], ent.color[2]);
          mat.color.copy(color);
          mat.emissive.copy(color);
          mat.emissiveIntensity = ent.glow ? (ent.glowIntensity || 0.5) : 0;
          if (ent.activity?.idle) {
            mat.emissiveIntensity *= 0.3;
            const hsl = { h: 0, s: 0, l: 0 };
            mat.color.getHSL(hsl);
            mat.color.setHSL(hsl.h, hsl.s * 0.4, hsl.l * 0.7);
          }
          if (ent.activity?.tool) mat.emissiveIntensity = Math.max(mat.emissiveIntensity, 0.8);
          if (ent.id === selectedId()) mat.emissiveIntensity = Math.max(mat.emissiveIntensity, 1.0);
        }
      }
      group.position.set(ent.position[0], ent.position[1], ent.position[2]);
      if (ent.scale) group.scale.set(ent.scale[0], ent.scale[1], ent.scale[2]);
      if (ent.rotation) group.rotation.set(ent.rotation[0], ent.rotation[1], ent.rotation[2]);

      // Activity labels
      if (ent.activity?.tool) {
        let al = entityActivityLabels.get(ent.id);
        if (!al) {
          al = makeCSSLabel("",
            "color:#80ff80;font-family:'JetBrains Mono',monospace;font-size:9px;padding:1px 4px;background:rgba(0,40,0,0.8);border:1px solid rgba(80,255,80,0.4);border-radius:2px;pointer-events:none;white-space:nowrap;");
          al.position.set(0, -0.8, 0);
          group.add(al);
          entityActivityLabels.set(ent.id, al);
        }
        al.element.textContent = ent.activity.tool;
        al.visible = true;
      } else {
        const al = entityActivityLabels.get(ent.id);
        if (al) al.visible = false;
      }
      if (ent.activity && ent.activity.cost > 0) {
        let cb = entityCostBadges.get(ent.id);
        if (!cb) {
          cb = makeCSSLabel("",
            "color:#ffcc44;font-family:'JetBrains Mono',monospace;font-size:8px;padding:1px 3px;background:rgba(40,30,0,0.8);border:1px solid rgba(255,200,60,0.3);border-radius:2px;pointer-events:none;white-space:nowrap;");
          cb.position.set(1.0, 0.8, 0);
          group.add(cb);
          entityCostBadges.set(ent.id, cb);
        }
        cb.element.textContent = `$${ent.activity.cost.toFixed(3)}`;
        cb.visible = true;
      } else {
        const cb = entityCostBadges.get(ent.id);
        if (cb) cb.visible = false;
      }
    }
    // Remove stale
    for (const [id, group] of entityGroups) {
      if (!currentIds.has(id)) {
        scene.remove(group);
        entityGroups.delete(id);
        entityMeshes.get(id)?.material && ((entityMeshes.get(id)!.material as THREE.Material).dispose());
        entityMeshes.delete(id);
        entityLabels.get(id)?.element.parentElement?.removeChild(entityLabels.get(id)!.element);
        entityLabels.delete(id);
        entityActivityLabels.get(id)?.element.parentElement?.removeChild(entityActivityLabels.get(id)!.element);
        entityActivityLabels.delete(id);
        entityCostBadges.get(id)?.element.parentElement?.removeChild(entityCostBadges.get(id)!.element);
        entityCostBadges.delete(id);
      }
    }
  }

  function updateConnections(connections: EmbedConnectionData[]) {
    const currentIds = new Set<number>();
    for (const conn of connections) {
      currentIds.add(conn.id);
      let line = connectionLines.get(conn.id);
      if (!line) {
        const pts = [new THREE.Vector3(...conn.from), new THREE.Vector3(...conn.to)];
        const geo = new THREE.BufferGeometry().setFromPoints(pts);
        const mat = new THREE.LineBasicMaterial({
          color: new THREE.Color(conn.color[0], conn.color[1], conn.color[2]),
          transparent: true, opacity: conn.color[3] ?? 1, linewidth: 1,
        });
        line = new THREE.Line(geo, mat);
        scene.add(line);
        connectionLines.set(conn.id, line);
      } else {
        const pos = line.geometry.attributes.position as THREE.BufferAttribute;
        pos.setXYZ(0, ...conn.from);
        pos.setXYZ(1, ...conn.to);
        pos.needsUpdate = true;
      }
    }
    for (const [id, line] of connectionLines) {
      if (!currentIds.has(id)) {
        scene.remove(line);
        line.geometry.dispose();
        (line.material as THREE.Material).dispose();
        connectionLines.delete(id);
      }
    }
  }

  function connectWS() {
    ws = new WebSocket(props.wsUrl);
    ws.onopen = () => {
      ws?.send(JSON.stringify({ type: "subscribe", channel: "holodeck" }));
    };
    ws.onmessage = (evt) => {
      try {
        const msg = JSON.parse(evt.data);
        if (msg.type === "holodeck_frame") {
          const frame = msg as HolodeckFrame;
          latestEntities = frame.entities || [];
          latestConnections = frame.connections || [];
          const now = performance.now();
          frameTimestamps.push(now);
          frameTimestamps = frameTimestamps.filter((t) => t > now - 1000);
          setFps(frameTimestamps.length);
        }
      } catch { /* ignore parse errors */ }
    };
    ws.onclose = () => {
      // Reconnect after 2s
      setTimeout(() => { if (containerRef) connectWS(); }, 2000);
    };
  }

  function animate() {
    animFrameId = requestAnimationFrame(animate);
    updateEntities(latestEntities);
    updateConnections(latestConnections);
    controls.update();
    composer.render();
    css2dRenderer.render(scene, camera);
  }

  function handleResize() {
    if (!containerRef) return;
    const w = containerRef.clientWidth;
    const h = containerRef.clientHeight;
    if (w === 0 || h === 0) return;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
    css2dRenderer.setSize(w, h);
    composer.setSize(w, h);
  }

  // Public API for parent window (Emacs xwidget)
  (window as any).holodeckSelectAgent = (entityId: number) => {
    setSelectedId(entityId);
    // Focus camera on entity
    for (const ent of latestEntities) {
      if (ent.id === entityId) {
        controls.target.set(ent.position[0], ent.position[1], ent.position[2]);
        break;
      }
    }
  };

  onMount(() => {
    initScene();
    connectWS();
    animate();

    const resizeObserver = new ResizeObserver(handleResize);
    if (containerRef) resizeObserver.observe(containerRef);

    onCleanup(() => {
      if (animFrameId) cancelAnimationFrame(animFrameId);
      ws?.close();
      resizeObserver.disconnect();
      renderer?.domElement.removeEventListener("click", onCanvasClick);
      renderer?.dispose();
      composer?.dispose();
      css2dRenderer?.domElement.remove();
      for (const [, m] of entityMeshes) (m.material as THREE.Material).dispose();
      for (const key of Object.keys(geometryCache)) geometryCache[key].dispose();
    });
  });

  return (
    <div style={{
      position: "relative",
      width: props.width ?? "100%",
      height: props.height ?? "100%",
      overflow: "hidden",
    }}>
      <div ref={containerRef} style={{ position: "absolute", inset: "0" }} />
      <div style={{
        position: "absolute", bottom: "8px", right: "8px",
        color: "#888", "font-size": "10px", "font-family": "monospace",
        background: "rgba(0,0,0,0.5)", padding: "2px 6px", "border-radius": "3px",
      }}>
        {fps()} FPS
      </div>
    </div>
  );
};

export default HolodeckEmbed;
export type { HolodeckEmbedProps };
