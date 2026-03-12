import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";
import { agentStore } from "./agents";

// ── Types ────────────────────────────────────────────────────────

export interface EntityActivity {
  tool: string | null;
  idle: boolean;
  cost: number;
  calls: number;
  pendingHuman: number;
}

export interface EntityData {
  id: number;
  kind: string;
  position: [number, number, number];
  scale: [number, number, number];
  rotation: [number, number, number];
  color: [number, number, number, number];
  glow: boolean;
  glowIntensity: number;
  label: string;
  labelOffset: number;
  meshType: string;
  lod: string;
  agentId?: string;
  cognitivePhase?: string;
  activity?: EntityActivity;
  selected: boolean;
  hovered: boolean;
}

export interface ConnectionData {
  id: number;
  kind: string;
  from: [number, number, number];
  to: [number, number, number];
  color: [number, number, number, number];
  energyFlow: number;
}

export interface CameraData {
  position: [number, number, number];
  view: number[];
  projection: number[];
}

export interface HolodeckFrame {
  type: "holodeck_frame";
  dt: number;
  camera: CameraData;
  entities: EntityData[];
  connections: ConnectionData[];
  hud: { visible: boolean; panels: unknown[] };
}

export type ViewMode = "orbit" | "top" | "follow";

// ── Signals ──────────────────────────────────────────────────────

const [entities, setEntities] = createSignal<Map<number, EntityData>>(new Map());
const [connections, setConnections] = createSignal<Map<number, ConnectionData>>(new Map());
const [camera, setCamera] = createSignal<CameraData | null>(null);
const [selectedEntityId, setSelectedEntityId] = createSignal<number | null>(null);
const [viewMode, setViewMode] = createSignal<ViewMode>("orbit");
const [hudVisible, setHudVisible] = createSignal(true);

// FPS tracking
const [fps, setFps] = createSignal(0);
let frameTimestamps: number[] = [];

// ── Derived ──────────────────────────────────────────────────────

const selectedEntity = createMemo(() => {
  const id = selectedEntityId();
  if (id === null) return null;
  return entities().get(id) ?? null;
});

const entityCount = createMemo(() => entities().size);
const connectionCount = createMemo(() => connections().size);

// ── Actions ──────────────────────────────────────────────────────

function selectEntity(id: number | null) {
  setSelectedEntityId(id);
  if (id !== null) {
    wsStore.send({ type: "holodeck_select", entityId: id } as any);
    // Sync: if entity has agentId, select in agent store too
    const entity = entities().get(id);
    if (entity?.agentId) {
      agentStore.selectAgent(entity.agentId);
    }
  }
}

function focusOnAgent(agentId: string) {
  // Find entity with this agentId
  for (const [id, ent] of entities()) {
    if (ent.agentId === agentId) {
      selectEntity(id);
      // Send camera focus command
      sendAction("focus-entity");
      return;
    }
  }
}

function sendInput(key: string) {
  wsStore.send({ type: "holodeck_input", key } as any);
}

function sendAction(action: string) {
  wsStore.send({ type: "holodeck_input", action } as any);
}

function updateFps() {
  const now = performance.now();
  frameTimestamps.push(now);
  // Keep only timestamps from the last second
  const cutoff = now - 1000;
  frameTimestamps = frameTimestamps.filter((t) => t > cutoff);
  setFps(frameTimestamps.length);
}

// ── WS Message Handler ──────────────────────────────────────────

function handleWSMessage(msg: ServerMessage) {
  if (msg.type !== "holodeck_frame") return;

  const frame = (msg.data ?? msg) as unknown as HolodeckFrame;

  updateFps();

  // Update entities map
  const newEntities = new Map<number, EntityData>();
  if (frame.entities) {
    for (const ent of frame.entities) {
      newEntities.set(ent.id, ent);
    }
  }
  setEntities(newEntities);

  // Update connections map
  const newConns = new Map<number, ConnectionData>();
  if (frame.connections) {
    for (const conn of frame.connections) {
      newConns.set(conn.id, conn);
    }
  }
  setConnections(newConns);

  // Update camera
  if (frame.camera) {
    setCamera(frame.camera);
  }

  // Update HUD visibility
  if (frame.hud) {
    setHudVisible(frame.hud.visible);
  }
}

// ── Init ─────────────────────────────────────────────────────────

let initialized = false;

function init() {
  if (initialized) return;
  initialized = true;

  wsStore.onMessage(handleWSMessage);
  wsStore.subscribe("holodeck");
}

function cleanup() {
  wsStore.unsubscribe("holodeck");
  initialized = false;
}

// ── Export ────────────────────────────────────────────────────────

export const holodeckStore = {
  // Data
  entities,
  connections,
  camera,
  selectedEntityId,
  selectedEntity,
  entityCount,
  connectionCount,
  viewMode,
  hudVisible,
  fps,

  // Actions
  init,
  cleanup,
  selectEntity,
  focusOnAgent,
  sendInput,
  sendAction,
  setViewMode,
  setHudVisible,
};
