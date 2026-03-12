import { type Component, onMount, onCleanup, createEffect } from "solid-js";
import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { CSS2DRenderer, CSS2DObject } from "three/examples/jsm/renderers/CSS2DRenderer.js";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { holodeckStore, type EntityData, type ConnectionData } from "../stores/holodeck";
import HolodeckHUD from "./HolodeckHUD";

const HolodeckView: Component = () => {
  let containerRef: HTMLDivElement | undefined;
  let animFrameId: number = 0;

  // Three.js objects
  let renderer: THREE.WebGLRenderer;
  let css2dRenderer: CSS2DRenderer;
  let scene: THREE.Scene;
  let camera: THREE.PerspectiveCamera;
  let controls: OrbitControls;
  let composer: EffectComposer;
  let raycaster: THREE.Raycaster;
  let mouse: THREE.Vector2;

  // Entity tracking
  const entityGroups = new Map<number, THREE.Group>();
  const entityMeshes = new Map<number, THREE.Mesh>();
  const entityLabels = new Map<number, CSS2DObject>();
  const connectionLines = new Map<number, THREE.Line>();

  // Geometry/material caches
  const geometryCache: Record<string, THREE.BufferGeometry> = {};
  const materialCache = new Map<string, THREE.MeshStandardMaterial>();

  function getGeometry(meshType: string): THREE.BufferGeometry {
    if (geometryCache[meshType]) return geometryCache[meshType];
    let geo: THREE.BufferGeometry;
    switch (meshType) {
      case "sphere":
        geo = new THREE.SphereGeometry(0.5, 32, 32);
        break;
      case "octahedron":
        geo = new THREE.OctahedronGeometry(0.5);
        break;
      case "box":
      case "cube":
        geo = new THREE.BoxGeometry(0.8, 0.8, 0.8);
        break;
      case "cylinder":
        geo = new THREE.CylinderGeometry(0.3, 0.3, 1, 16);
        break;
      case "torus":
        geo = new THREE.TorusGeometry(0.4, 0.15, 16, 32);
        break;
      default:
        geo = new THREE.SphereGeometry(0.5, 32, 32);
    }
    geometryCache[meshType] = geo;
    return geo;
  }

  function getMaterial(colorKey: string, color: THREE.Color, emissiveIntensity: number): THREE.MeshStandardMaterial {
    const key = `${colorKey}-${emissiveIntensity.toFixed(2)}`;
    let mat = materialCache.get(key);
    if (!mat) {
      mat = new THREE.MeshStandardMaterial({
        color,
        emissive: color,
        emissiveIntensity,
        metalness: 0.3,
        roughness: 0.4,
      });
      materialCache.set(key, mat);
    }
    return mat;
  }

  function createLabel(text: string): CSS2DObject {
    const div = document.createElement("div");
    div.className = "holodeck-label";
    div.textContent = text;
    div.style.cssText = `
      color: #e0e0ff;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      padding: 2px 6px;
      background: rgba(10, 10, 30, 0.75);
      border: 1px solid rgba(100, 100, 255, 0.3);
      border-radius: 3px;
      pointer-events: none;
      white-space: nowrap;
    `;
    return new CSS2DObject(div);
  }

  function initScene() {
    if (!containerRef) return;

    const width = containerRef.clientWidth;
    const height = containerRef.clientHeight;

    // Scene
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0a0a0f);
    scene.fog = new THREE.FogExp2(0x0a0a0f, 0.02);

    // Camera
    camera = new THREE.PerspectiveCamera(60, width / height, 0.1, 1000);
    camera.position.set(0, 8, 15);
    camera.lookAt(0, 0, 0);

    // WebGL Renderer
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.2;
    containerRef.appendChild(renderer.domElement);

    // CSS2D Renderer (labels)
    css2dRenderer = new CSS2DRenderer();
    css2dRenderer.setSize(width, height);
    css2dRenderer.domElement.style.position = "absolute";
    css2dRenderer.domElement.style.top = "0";
    css2dRenderer.domElement.style.left = "0";
    css2dRenderer.domElement.style.pointerEvents = "none";
    containerRef.appendChild(css2dRenderer.domElement);

    // Controls
    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;
    controls.minDistance = 2;
    controls.maxDistance = 100;
    controls.maxPolarAngle = Math.PI * 0.85;

    // Lighting
    const ambient = new THREE.AmbientLight(0x404040, 0.8);
    scene.add(ambient);

    const directional = new THREE.DirectionalLight(0xffffff, 1.0);
    directional.position.set(10, 20, 10);
    scene.add(directional);

    const pointLight = new THREE.PointLight(0x4444ff, 0.5, 50);
    pointLight.position.set(0, 10, 0);
    scene.add(pointLight);

    // Grid helper
    const grid = new THREE.GridHelper(40, 40, 0x222244, 0x111133);
    (grid.material as THREE.Material).transparent = true;
    (grid.material as THREE.Material).opacity = 0.3;
    scene.add(grid);

    // Post-processing
    composer = new EffectComposer(renderer);
    const renderPass = new RenderPass(scene, camera);
    composer.addPass(renderPass);

    const bloomPass = new UnrealBloomPass(
      new THREE.Vector2(width, height),
      0.5,   // strength
      0.4,   // radius
      0.85   // threshold
    );
    composer.addPass(bloomPass);

    // Raycaster
    raycaster = new THREE.Raycaster();
    mouse = new THREE.Vector2();

    // Click handler for selection
    renderer.domElement.addEventListener("click", onCanvasClick);
  }

  function onCanvasClick(event: MouseEvent) {
    if (!containerRef) return;
    const rect = containerRef.getBoundingClientRect();
    mouse.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    mouse.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(mouse, camera);
    const meshArray = Array.from(entityMeshes.values());
    const intersects = raycaster.intersectObjects(meshArray);

    if (intersects.length > 0) {
      const hit = intersects[0].object;
      // Find entity ID from mesh
      for (const [id, mesh] of entityMeshes) {
        if (mesh === hit) {
          holodeckStore.selectEntity(id);
          return;
        }
      }
    } else {
      holodeckStore.selectEntity(null);
    }
  }

  function updateEntities(entitiesMap: Map<number, EntityData>) {
    // Track which IDs are present this frame
    const currentIds = new Set<number>();

    for (const [id, ent] of entitiesMap) {
      currentIds.add(id);
      let group = entityGroups.get(id);

      if (!group) {
        // Create new entity
        group = new THREE.Group();
        scene.add(group);
        entityGroups.set(id, group);

        const geo = getGeometry(ent.meshType || "sphere");
        const color = new THREE.Color(ent.color[0], ent.color[1], ent.color[2]);
        const intensity = ent.glow ? (ent.glowIntensity || 0.5) : 0;
        const colorKey = `${ent.color[0].toFixed(2)}-${ent.color[1].toFixed(2)}-${ent.color[2].toFixed(2)}`;
        const mat = getMaterial(colorKey, color, intensity);

        const mesh = new THREE.Mesh(geo, mat.clone());
        group.add(mesh);
        entityMeshes.set(id, mesh);

        // Label
        if (ent.label) {
          const label = createLabel(ent.label);
          label.position.set(0, ent.labelOffset || 1.2, 0);
          group.add(label);
          entityLabels.set(id, label);
        }
      } else {
        // Update existing entity material
        const mesh = entityMeshes.get(id);
        if (mesh) {
          const mat = mesh.material as THREE.MeshStandardMaterial;
          const color = new THREE.Color(ent.color[0], ent.color[1], ent.color[2]);
          mat.color.copy(color);
          mat.emissive.copy(color);
          mat.emissiveIntensity = ent.glow ? (ent.glowIntensity || 0.5) : 0;

          // Selection highlight
          if (ent.id === holodeckStore.selectedEntityId()) {
            mat.emissiveIntensity = Math.max(mat.emissiveIntensity, 1.0);
          }
        }
      }

      // Update transform
      group.position.set(ent.position[0], ent.position[1], ent.position[2]);
      if (ent.scale) {
        group.scale.set(ent.scale[0], ent.scale[1], ent.scale[2]);
      }
      if (ent.rotation) {
        group.rotation.set(ent.rotation[0], ent.rotation[1], ent.rotation[2]);
      }
    }

    // Remove entities no longer in frame
    for (const [id, group] of entityGroups) {
      if (!currentIds.has(id)) {
        scene.remove(group);
        entityGroups.delete(id);

        const mesh = entityMeshes.get(id);
        if (mesh) {
          (mesh.material as THREE.Material).dispose();
          entityMeshes.delete(id);
        }

        const label = entityLabels.get(id);
        if (label) {
          const div = label.element;
          div.parentElement?.removeChild(div);
          entityLabels.delete(id);
        }
      }
    }
  }

  function updateConnections(connectionsMap: Map<number, ConnectionData>) {
    const currentIds = new Set<number>();

    for (const [id, conn] of connectionsMap) {
      currentIds.add(id);
      let line = connectionLines.get(id);

      if (!line) {
        const points = [
          new THREE.Vector3(conn.from[0], conn.from[1], conn.from[2]),
          new THREE.Vector3(conn.to[0], conn.to[1], conn.to[2]),
        ];
        const geo = new THREE.BufferGeometry().setFromPoints(points);
        const color = new THREE.Color(conn.color[0], conn.color[1], conn.color[2]);
        const mat = new THREE.LineBasicMaterial({
          color,
          transparent: true,
          opacity: conn.color[3] ?? 1.0,
          linewidth: 1,
        });
        line = new THREE.Line(geo, mat);
        scene.add(line);
        connectionLines.set(id, line);
      } else {
        // Update existing line positions
        const positions = line.geometry.attributes.position as THREE.BufferAttribute;
        positions.setXYZ(0, conn.from[0], conn.from[1], conn.from[2]);
        positions.setXYZ(1, conn.to[0], conn.to[1], conn.to[2]);
        positions.needsUpdate = true;

        const mat = line.material as THREE.LineBasicMaterial;
        mat.color.setRGB(conn.color[0], conn.color[1], conn.color[2]);
        mat.opacity = conn.color[3] ?? 1.0;
      }
    }

    // Remove old connections
    for (const [id, line] of connectionLines) {
      if (!currentIds.has(id)) {
        scene.remove(line);
        line.geometry.dispose();
        (line.material as THREE.Material).dispose();
        connectionLines.delete(id);
      }
    }
  }

  function animate() {
    animFrameId = requestAnimationFrame(animate);

    // Update entities/connections from store signals
    updateEntities(holodeckStore.entities());
    updateConnections(holodeckStore.connections());

    controls.update();
    composer.render();
    css2dRenderer.render(scene, camera);
  }

  function handleResize() {
    if (!containerRef) return;
    const width = containerRef.clientWidth;
    const height = containerRef.clientHeight;
    if (width === 0 || height === 0) return;

    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
    css2dRenderer.setSize(width, height);
    composer.setSize(width, height);
  }

  function disposeAll() {
    // Cancel animation
    if (animFrameId) cancelAnimationFrame(animFrameId);

    // Remove click handler
    if (renderer) {
      renderer.domElement.removeEventListener("click", onCanvasClick);
    }

    // Dispose entity resources
    for (const [, mesh] of entityMeshes) {
      (mesh.material as THREE.Material).dispose();
    }
    entityMeshes.clear();
    entityGroups.clear();

    for (const [, label] of entityLabels) {
      label.element.parentElement?.removeChild(label.element);
    }
    entityLabels.clear();

    // Dispose connections
    for (const [, line] of connectionLines) {
      line.geometry.dispose();
      (line.material as THREE.Material).dispose();
    }
    connectionLines.clear();

    // Dispose cached geometries
    for (const key of Object.keys(geometryCache)) {
      geometryCache[key].dispose();
      delete geometryCache[key];
    }

    // Dispose cached materials
    for (const [, mat] of materialCache) {
      mat.dispose();
    }
    materialCache.clear();

    // Dispose renderer/composer
    if (composer) composer.dispose();
    if (renderer) {
      renderer.dispose();
      renderer.domElement.remove();
    }
    if (css2dRenderer) {
      css2dRenderer.domElement.remove();
    }

    // Dispose scene
    if (scene) {
      scene.traverse((obj) => {
        if ((obj as any).geometry) (obj as any).geometry.dispose();
        if ((obj as any).material) {
          const mat = (obj as any).material;
          if (Array.isArray(mat)) mat.forEach((m: THREE.Material) => m.dispose());
          else mat.dispose();
        }
      });
    }
  }

  onMount(() => {
    holodeckStore.init();
    initScene();
    animate();

    const resizeObserver = new ResizeObserver(handleResize);
    if (containerRef) resizeObserver.observe(containerRef);

    onCleanup(() => {
      resizeObserver.disconnect();
      disposeAll();
    });
  });

  return (
    <div class="holodeck-view" style={{ position: "relative", width: "100%", height: "100%" }}>
      <div
        ref={containerRef}
        class="holodeck-canvas-container"
        style={{ position: "absolute", inset: "0", overflow: "hidden" }}
      />
      <HolodeckHUD />
    </div>
  );
};

export default HolodeckView;
