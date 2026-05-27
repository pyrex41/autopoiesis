/**
 * AETHER store — Week 1 layout-feasibility experiment.
 *
 * Fetches snapshots from the REST API (or falls back to a local placeholder
 * fixture when the API is unavailable), runs a hand-rolled force simulation
 * with edge spring rest-length weighted by a per-edge "diff-magnitude"
 * scalar, and exposes positioned nodes for canvas rendering.
 *
 * Spectral classification: a crude function mapping snapshot/agent fields
 * to an HSL color + size. The whole point of Phase 3 is to find out
 * whether even a crude function produces visually meaningful spread.
 *
 * No external deps. Treats `agent--state` opaquely.
 */
import { createSignal } from "solid-js";
import { listSnapshots } from "../api/client";
import type { Snapshot } from "../api/types";
import placeholder from "../pages/__fixtures__/aether-placeholder.json";

// ── Types ────────────────────────────────────────────────────────────

export interface AetherNode {
  id: string;
  parent: string | null;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  /** Stellar color (full css color string) */
  color: string;
  /** Glow halo color (slightly desaturated/dimmed) */
  haloColor: string;
  /** Cached opaque magnitude — bigger = "more cognitively active" */
  magnitude: number;
  /** ms timestamp the node was added; used by the renderer's birth animation. */
  bornAt: number;
}

export interface AetherEdge {
  source: string;
  target: string;
  /** Higher = more divergence between parent and child = longer rest length */
  diffMagnitude: number;
  /** Cached spring rest length derived from diffMagnitude */
  restLength: number;
}

// ── Opaque magnitude extraction ──────────────────────────────────────
//
// The documented snapshot shape includes `agent--state` as a prin1'd Lisp
// string. We do NOT parse it. Instead we extract a single scalar that
// correlates roughly with cognitive content: the length of the
// serialized string. Until Agent A's fixture confirms the shape, we
// also opportunistically read structured `metadata` fields if present.
//
// The placeholder fixture uses snake-style `agent--state` keys to mirror
// the documented JSON. cl-json typically maps double-dashes to camelCase
// — once the real fixture lands at e2e/fixtures/aether-api-shape.json
// we can swap the field reads.

function stateString(snap: any): string {
  return (
    snap["agent--state"] ??
    snap.agent_state ??
    snap.agentState ??
    ""
  );
}

// Metadata arrives in one of two shapes:
//   - placeholder fixture: a plain JSON object  { version: 0, capabilities: 2, ... }
//   - real API (cl-json):  a flat plist-as-array ["lineage","nimbus-0","mood","linear",...]
// metaMap normalizes both into a Map<string, any>.
function metaMap(snap: Snapshot): Map<string, unknown> {
  const md = snap.metadata as unknown;
  const m = new Map<string, unknown>();
  if (md == null) return m;
  if (Array.isArray(md)) {
    for (let i = 0; i + 1 < md.length; i += 2) {
      const k = md[i];
      if (typeof k === "string") m.set(k, md[i + 1]);
    }
  } else if (typeof md === "object") {
    for (const [k, v] of Object.entries(md as Record<string, unknown>)) m.set(k, v);
  }
  return m;
}

function metaNum(snap: Snapshot, key: string): number {
  const v = metaMap(snap).get(key);
  return typeof v === "number" ? v : 0;
}

function metaStr(snap: Snapshot, key: string): string {
  const v = metaMap(snap).get(key);
  return typeof v === "string" ? v : "";
}

function metaBool(snap: Snapshot, key: string): boolean {
  return metaMap(snap).get(key) === true;
}

// Back-compat alias for any old callsites.
function readMetaNumber(snap: Snapshot, key: string): number {
  return metaNum(snap, key);
}

/** Stable hash of a string -> [0, 1). */
function hash01(s: string): number {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return (h >>> 0) / 0xffffffff;
}

// ── Spectral classification ──────────────────────────────────────────
//
// HSL output. Crude but intentionally non-uniform.
//
//   hot blue-white (200-220° hue, high light) = high recent-diff + low version
//   cool red       (10-30° hue,   mid light)  = high version + many heuristics
//   white-yellow   (50-60° hue,   high light) = high capability count
//
// Each axis is normalized loosely and then blended. We compute three
// "scores" and pick the dominant axis, then mix.
//
// size = log(thoughts + 1) * 4 + 3

export interface Spectral {
  color: string;
  haloColor: string;
  radius: number;
  magnitude: number;
}

export function spectralClass(snap: Snapshot, diffMag: number): Spectral {
  // Real-data inputs (from aether-seed): lineage / mood / ticks / depth / root.
  const mood = metaStr(snap, "mood");
  const lineage = metaStr(snap, "lineage");
  const ticks = metaNum(snap, "ticks");
  const depth = metaNum(snap, "depth");
  const isRoot = metaBool(snap, "root");

  // Placeholder-fixture fallback inputs (kept for offline dev).
  const version = metaNum(snap, "version");
  const caps = metaNum(snap, "capabilities");
  const heur = metaNum(snap, "heuristics");
  const thoughts = metaNum(snap, "thoughts");

  // String-length proxy for cognitive content when metadata is sparse.
  const stateLen = stateString(snap).length;
  const lenProxy = Math.log1p(stateLen + ticks * 10) / 8; // ~0..1

  // Three spectral axes — each maps to a base hue (HSL).
  //   explorer/young  → blue-white (210°)
  //   reflector/old   → cool red    (15°)
  //   linear/stable   → white-yellow (50°)
  // Real-data path: mood is the dominant axis.
  // Placeholder path: derive axes from version/caps/heur as before.
  let wExplore: number;
  let wReflect: number;
  let wStable: number;
  if (mood === "explorer") {
    wExplore = 1;
    wReflect = 0;
    wStable = 0.15;
  } else if (mood === "reflector") {
    wExplore = 0;
    wReflect = 1;
    wStable = 0.1;
  } else if (mood === "linear") {
    wExplore = 0;
    wReflect = 0.05;
    wStable = 1;
  } else {
    // No mood field → placeholder/object-metadata path.
    wExplore = Math.min(1, diffMag / 6) * Math.exp(-version / 4);
    wReflect = Math.min(1, version / 6) * Math.min(1, heur / 5);
    wStable = Math.min(1, caps / 8);
  }

  // Tick-driven energy bump on the "hot" axis — accumulated activity glows hotter.
  const energy = Math.min(1, ticks / 8);
  wExplore += energy * 0.25;

  // Constant base so very-uniform snapshots still get *some* hue from each axis.
  wExplore += 0.05;
  wReflect += 0.05;
  wStable += 0.05;

  const axes = [
    { weight: wExplore, hue: 210, light: 0.78, sat: 0.6 },
    { weight: wReflect, hue: 15, light: 0.55, sat: 0.72 },
    { weight: wStable, hue: 50, light: 0.72, sat: 0.6 },
  ];

  // Weighted circular mean for hue.
  let totalW = 0;
  let hx = 0;
  let hy = 0;
  let light = 0;
  let sat = 0;
  for (const a of axes) {
    const rad = (a.hue * Math.PI) / 180;
    hx += Math.cos(rad) * a.weight;
    hy += Math.sin(rad) * a.weight;
    light += a.light * a.weight;
    sat += a.sat * a.weight;
    totalW += a.weight;
  }
  const hue = (Math.atan2(hy, hx) * 180) / Math.PI;
  const normHue = ((hue % 360) + 360) % 360;

  // Lineage gives a small, stable per-cluster hue offset so same-mood
  // lineages drift visually apart without losing the mood's overall color.
  const lineageHueOffset = lineage ? (hash01(lineage) - 0.5) * 30 : 0;

  // Per-id jitter so identical-metadata snapshots don't render identically.
  const jitter = (hash01(snap.id) - 0.5) * 8;
  const finalHue = ((normHue + lineageHueOffset + jitter) % 360 + 360) % 360;

  const L = Math.max(0.35, Math.min(0.9,
    light / totalW + lenProxy * 0.12 + (isRoot ? 0.05 : 0)));
  const S = Math.max(0.3, Math.min(0.95, sat / totalW));

  // Size: prefer ticks (real data) → thoughts (placeholder) → string-length proxy.
  // Root stars get a small bump so they read as the lineage "anchor".
  const sizeBase =
    ticks > 0 ? ticks
    : thoughts > 0 ? thoughts
    : Math.max(1, Math.floor(stateLen / 30));
  const radius = Math.log1p(sizeBase) * 3.5 + (isRoot ? 5 : 3);

  const color = `hsl(${finalHue.toFixed(1)}, ${(S * 100).toFixed(0)}%, ${(L * 100).toFixed(0)}%)`;
  const haloColor = `hsla(${finalHue.toFixed(1)}, ${(S * 100).toFixed(0)}%, ${(L * 100).toFixed(0)}%, 0.25)`;

  return {
    color,
    haloColor,
    radius,
    magnitude: ticks + depth * 0.5 + thoughts + caps + heur + lenProxy * 4,
  };
}

// ── Diff magnitude between parent and child ──────────────────────────
//
// Opaque scalar in [0, +∞). We use:
//   |length(child state) - length(parent state)| / 40
// plus a small contribution from metadata.version delta if present.
//
// Until Agent A's API confirms a precomputed magnitude, this is our
// proxy. If Agent A reports the prin1 string is painful, we can swap
// to a server-precomputed `metadata.diff_magnitude` field once it
// arrives — `readMetaNumber` already covers that path.

function diffMagnitude(parent: Snapshot, child: Snapshot): number {
  // Prefer precomputed metadata if the backend ever embeds it on snapshots.
  const pre = metaNum(child, "diff_magnitude");
  if (pre > 0) return pre;

  // Real-data path: derive from metadata deltas (mood/lineage/ticks/depth).
  const dTicks = Math.abs(metaNum(child, "ticks") - metaNum(parent, "ticks"));
  const dDepth = Math.abs(metaNum(child, "depth") - metaNum(parent, "depth"));
  const moodChange = metaStr(child, "mood") !== metaStr(parent, "mood") ? 5 : 0;
  const lineageChange = metaStr(child, "lineage") !== metaStr(parent, "lineage") ? 8 : 0;
  const metaDiff = dTicks + dDepth + moodChange + lineageChange;
  if (metaDiff > 0) return metaDiff;

  // Placeholder fallback: state-string length + version delta + :DIVERGE hint.
  const dLen = Math.abs(stateString(child).length - stateString(parent).length);
  const dVer = Math.abs(metaNum(child, "version") - metaNum(parent, "version"));
  const divergeMatch = stateString(child).match(/:DIVERGE\s+(\d+)/);
  const divergeBoost = divergeMatch ? parseInt(divergeMatch[1]!, 10) : 0;

  return dLen / 40 + dVer * 0.5 + divergeBoost;
}

// ── Force simulation tunables ────────────────────────────────────────
//
// Adapted from stores/constellation.ts pattern. Key change: edge spring
// rest-length is per-edge (driven by diffMagnitude), not constant.

const DAMPING = 0.92;
const REPULSION = 6500;
const SPRING_K = 0.012;
const BASE_REST = 90;
/** rest = BASE_REST + diffMagnitude * REST_PER_DIFF, log-clamped */
const REST_PER_DIFF = 55;
const CENTER_FORCE = 0.0008;
const VELOCITY_CLAMP = 8;

function restLengthFor(diffMag: number): number {
  // Log-scale so a single very large diff doesn't blow the whole layout
  // out. Linear inside the simulation made one outlier swamp everything
  // else when sketched against the placeholder.
  const scaled = Math.log1p(Math.max(0, diffMag)) * REST_PER_DIFF;
  return BASE_REST + scaled;
}

// ── State ────────────────────────────────────────────────────────────

const [nodes, setNodes] = createSignal<AetherNode[]>([]);
const [edges, setEdges] = createSignal<AetherEdge[]>([]);
const [loaded, setLoaded] = createSignal(false);
const [usingFixture, setUsingFixture] = createSignal(false);

// Default view is now tracks (one lane per agent session, time L→R).
// Galactic mode keeps the force-directed constellation alive for
// whole-history navigation; toggle with `g`.
export type ViewMode = "tracks" | "galactic";
const [viewMode, setViewMode] = createSignal<ViewMode>("tracks");

// Selection + hover for the HUD/panel/focus layer.
const [selectedId, setSelectedId] = createSignal<string | null>(null);
const [hoveredId, setHoveredId] = createSignal<string | null>(null);

// Last-birth epoch — page reads this to re-arm physics warmup whenever a
// new live snapshot arrives, so the new star eases into place rather than
// sitting frozen on top of its parent.
const [lastBirthAt, setLastBirthAt] = createSignal(0);

// Retained raw snapshots (for panel display fields not on AetherNode).
let snapshotsById = new Map<string, Snapshot>();
// Adjacency: parent -> children ids
let childrenOf = new Map<string, string[]>();

function getSnapshot(id: string): Snapshot | undefined {
  return snapshotsById.get(id);
}

function ancestorsOf(id: string): Set<string> {
  const out = new Set<string>();
  let cur = snapshotsById.get(id)?.parent ?? null;
  while (cur) {
    if (out.has(cur)) break;
    out.add(cur);
    cur = snapshotsById.get(cur)?.parent ?? null;
  }
  return out;
}

function descendantsOf(id: string): Set<string> {
  const out = new Set<string>();
  const queue = [id];
  while (queue.length > 0) {
    const cur = queue.shift()!;
    const kids = childrenOf.get(cur) ?? [];
    for (const k of kids) {
      if (!out.has(k)) {
        out.add(k);
        queue.push(k);
      }
    }
  }
  return out;
}

/** {selectedId ∪ ancestors ∪ descendants}; empty Set when nothing selected. */
function focusSet(): Set<string> {
  const sid = selectedId();
  if (!sid) return new Set();
  const s = new Set<string>();
  s.add(sid);
  for (const a of ancestorsOf(sid)) s.add(a);
  for (const d of descendantsOf(sid)) s.add(d);
  return s;
}

// ── Build from snapshot list ─────────────────────────────────────────

function buildGraph(snapshots: Snapshot[]) {
  const byId = new Map<string, Snapshot>();
  for (const s of snapshots) byId.set(s.id, s);
  snapshotsById = byId;

  const builtEdges: AetherEdge[] = [];
  const builtChildren = new Map<string, string[]>();
  for (const s of snapshots) {
    if (!s.parent) continue;
    const parent = byId.get(s.parent);
    if (!parent) continue;
    const mag = diffMagnitude(parent, s);
    builtEdges.push({
      source: s.parent,
      target: s.id,
      diffMagnitude: mag,
      restLength: restLengthFor(mag),
    });
    const arr = builtChildren.get(s.parent) ?? [];
    arr.push(s.id);
    builtChildren.set(s.parent, arr);
  }
  childrenOf = builtChildren;

  // Per-node accumulated incoming edge magnitude — used as "recent diff"
  // input to spectralClass (the diff that produced this node).
  const incomingDiff = new Map<string, number>();
  for (const e of builtEdges) {
    incomingDiff.set(e.target, (incomingDiff.get(e.target) ?? 0) + e.diffMagnitude);
  }

  // Initial positions: seeded scatter using id hash, NOT a circle.
  // Circle initial conditions are the #1 way to end up with a force
  // layout that looks like... a circle.
  const initialBornAt = Date.now() - 10000; // pre-existing nodes are "born long ago"
  const builtNodes: AetherNode[] = snapshots.map((s) => {
    const h1 = hash01(s.id + "::x");
    const h2 = hash01(s.id + "::y");
    const spread = 350;
    const spec = spectralClass(s, incomingDiff.get(s.id) ?? 0);
    return {
      id: s.id,
      parent: s.parent ?? null,
      x: (h1 - 0.5) * spread * 2,
      y: (h2 - 0.5) * spread * 2,
      vx: 0,
      vy: 0,
      radius: spec.radius,
      color: spec.color,
      haloColor: spec.haloColor,
      magnitude: spec.magnitude,
      bornAt: initialBornAt,
    };
  });

  setNodes(builtNodes);
  setEdges(builtEdges);
}

// ── Tick: one step of the simulation ─────────────────────────────────

function tick() {
  setNodes((prev) => {
    if (prev.length === 0) return prev;
    const next = prev.map((n) => ({ ...n }));
    const map = new Map(next.map((n) => [n.id, n]));

    // Repulsion — all pairs. O(n²); fine for n < ~300.
    for (let i = 0; i < next.length; i++) {
      for (let j = i + 1; j < next.length; j++) {
        const a = next[i]!;
        const b = next[j]!;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const d2 = dx * dx + dy * dy + 0.01;
        const dist = Math.sqrt(d2);
        const force = REPULSION / d2;
        const fx = (dx / dist) * force;
        const fy = (dy / dist) * force;
        a.vx -= fx; a.vy -= fy;
        b.vx += fx; b.vy += fy;
      }
    }

    // Spring attraction — per-edge rest length.
    for (const edge of edges()) {
      const a = map.get(edge.source);
      const b = map.get(edge.target);
      if (!a || !b) continue;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const dist = Math.sqrt(dx * dx + dy * dy) || 1;
      const force = SPRING_K * (dist - edge.restLength);
      const fx = (dx / dist) * force;
      const fy = (dy / dist) * force;
      a.vx += fx; a.vy += fy;
      b.vx -= fx; b.vy -= fy;
    }

    // Weak centering pull toward origin.
    for (const n of next) {
      n.vx -= n.x * CENTER_FORCE;
      n.vy -= n.y * CENTER_FORCE;
    }

    // Integrate with damping + velocity clamp.
    for (const n of next) {
      n.vx *= DAMPING;
      n.vy *= DAMPING;
      if (n.vx > VELOCITY_CLAMP) n.vx = VELOCITY_CLAMP;
      if (n.vx < -VELOCITY_CLAMP) n.vx = -VELOCITY_CLAMP;
      if (n.vy > VELOCITY_CLAMP) n.vy = VELOCITY_CLAMP;
      if (n.vy < -VELOCITY_CLAMP) n.vy = -VELOCITY_CLAMP;
      n.x += n.vx;
      n.y += n.vy;
    }

    return next;
  });
}

// ── Live append (new snapshot arriving via WS) ───────────────────────
//
// When the backend pushes an aether_snapshot frame we want the new star
// to appear on the map immediately — not on a polling boundary, not after
// a full re-layout. liveAppend mutates the existing graph in place: adds
// the snapshot to byId, adds an edge to its parent if known, builds an
// AetherNode positioned just next to the parent (so the force sim eases
// it into place from a natural starting point), and stamps `bornAt` so
// the renderer can draw the birth animation.

function liveAppend(snap: Snapshot) {
  // Idempotent: ignore duplicates (server may resend on reconnect).
  if (snapshotsById.has(snap.id)) return;
  snapshotsById.set(snap.id, snap);

  // Update edges + adjacency.
  const newEdges = edges().slice();
  if (snap.parent) {
    const parentSnap = snapshotsById.get(snap.parent);
    if (parentSnap) {
      const mag = diffMagnitude(parentSnap, snap);
      newEdges.push({
        source: snap.parent,
        target: snap.id,
        diffMagnitude: mag,
        restLength: restLengthFor(mag),
      });
      const arr = childrenOf.get(snap.parent) ?? [];
      arr.push(snap.id);
      childrenOf.set(snap.parent, arr);
    }
  }
  setEdges(newEdges);

  // Build the new node. Position: snap to parent's coords + small jitter,
  // so it visually "births from" the parent rather than teleporting in
  // from a random point and being yanked by the spring.
  const incoming = newEdges
    .filter((e) => e.target === snap.id)
    .reduce((acc, e) => acc + e.diffMagnitude, 0);
  const spec = spectralClass(snap, incoming);
  const parentNode = snap.parent
    ? nodes().find((n) => n.id === snap.parent)
    : null;
  const jitter = 35;
  const baseX = parentNode ? parentNode.x : (hash01(snap.id + "::x") - 0.5) * 700;
  const baseY = parentNode ? parentNode.y : (hash01(snap.id + "::y") - 0.5) * 700;
  const node: AetherNode = {
    id: snap.id,
    parent: snap.parent ?? null,
    x: baseX + (hash01(snap.id + "::jx") - 0.5) * jitter,
    y: baseY + (hash01(snap.id + "::jy") - 0.5) * jitter,
    vx: 0,
    vy: 0,
    radius: spec.radius,
    color: spec.color,
    haloColor: spec.haloColor,
    magnitude: spec.magnitude,
    bornAt: Date.now(),
  };
  setNodes([...nodes(), node]);
  setLastBirthAt(Date.now());
}

// ── WebSocket subscription for live snapshots ────────────────────────

let liveWs: WebSocket | null = null;
let liveReconnectTimer: ReturnType<typeof setTimeout> | null = null;
const [liveConnected, setLiveConnected] = createSignal(false);

function aetherWsUrl(): string {
  // Vite dev: page on :3000, /ws proxied to ws://localhost:${AP_WS_PORT}
  // Production: assume same-origin /ws upgrade.
  const proto = window.location.protocol === "https:" ? "wss" : "ws";
  return `${proto}://${window.location.host}/ws`;
}

function connectLiveWs() {
  if (liveWs && (liveWs.readyState === WebSocket.OPEN || liveWs.readyState === WebSocket.CONNECTING)) {
    return;
  }
  try {
    liveWs = new WebSocket(aetherWsUrl());
  } catch {
    scheduleLiveReconnect();
    return;
  }
  liveWs.onopen = () => {
    setLiveConnected(true);
    liveWs?.send(JSON.stringify({ type: "set_stream_format", format: "json" }));
    liveWs?.send(JSON.stringify({ type: "subscribe", channel: "aether:snapshots" }));
  };
  liveWs.onmessage = (ev) => {
    if (typeof ev.data !== "string") return;
    try {
      const m = JSON.parse(ev.data);
      if (m.type === "aether_snapshot" && m.snapshot) {
        liveAppend(m.snapshot as Snapshot);
      }
    } catch {
      // ignore malformed
    }
  };
  liveWs.onclose = () => {
    setLiveConnected(false);
    liveWs = null;
    scheduleLiveReconnect();
  };
  liveWs.onerror = () => {
    // close handler will run too
  };
}

function scheduleLiveReconnect() {
  if (liveReconnectTimer) return;
  liveReconnectTimer = setTimeout(() => {
    liveReconnectTimer = null;
    connectLiveWs();
  }, 2000);
}

// ── Spawn (POST to /api/aether/spawn) ────────────────────────────────

export interface SpawnResult {
  session_id: string;
  initial_snapshot_id: string;
  lineage: string;
  model: string;
}

async function spawnAgent(opts: { prompt: string; parent?: string | null; model?: string; cwd?: string }): Promise<SpawnResult> {
  const body: Record<string, unknown> = { prompt: opts.prompt };
  if (opts.parent) body.parent = opts.parent;
  if (opts.model) body.model = opts.model;
  if (opts.cwd) body.cwd = opts.cwd;
  const res = await fetch("/api/aether/spawn", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`spawn failed: ${res.status} ${text}`);
  }
  return (await res.json()) as SpawnResult;
}

// ── Filesystem capture: files-at-snapshot + checkout ─────────────────

export interface FilesAtSnapshot {
  snapshot_id: string;
  tree_root: string;
  cwd: string;
  count: number;
  files: Array<{ path: string; size: number; hash: string }>;
}

export interface CheckoutResult {
  snapshot_id: string;
  target: string;
  entries_written: number;
}

async function fetchFilesAt(snapshotId: string): Promise<FilesAtSnapshot> {
  const res = await fetch(`/api/aether/snapshots/${snapshotId}/files`);
  if (!res.ok) throw new Error(`files fetch failed: ${res.status}`);
  return (await res.json()) as FilesAtSnapshot;
}

async function checkoutSnapshot(snapshotId: string, target?: string): Promise<CheckoutResult> {
  const body: Record<string, unknown> = {};
  if (target) body.target = target;
  const res = await fetch(`/api/aether/snapshots/${snapshotId}/checkout`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`checkout failed: ${res.status} ${text}`);
  }
  return (await res.json()) as CheckoutResult;
}

// ── Per-line blame (aether-blame) ────────────────────────────────────

export interface BlameLine {
  line: number;
  text: string;
  origin_snapshot: string;
  origin_event_type: string;
  origin_timestamp: number;
  origin_lineage: string;
}

export interface BlameResult {
  snapshot_id: string;
  path: string;
  line_count: number;
  blames: BlameLine[];
}

async function fetchBlame(snapshotId: string, path: string): Promise<BlameResult> {
  const res = await fetch(
    `/api/aether/blame/${snapshotId}/${encodeURIComponent(path)}`,
  );
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`blame fetch failed: ${res.status} ${text}`);
  }
  return (await res.json()) as BlameResult;
}

// ── Batch spawn + snapshot compare (sibling-fork comparison) ─────────

/** Result of POST /api/aether/spawn-batch — parallel arrays across variants. */
export interface BatchSpawnResult {
  session_ids: string[];
  initial_snapshot_ids: string[];
  cwds: string[];
  lineages: string[];
  parent: string;
  count: number;
}

async function spawnBatch(opts: {
  prompt: string;
  variants: string[];
  parent?: string | null;
  cwdPrefix?: string;
  model?: string;
}): Promise<BatchSpawnResult> {
  const body: Record<string, unknown> = {
    prompt: opts.prompt,
    variants: opts.variants,
  };
  if (opts.parent) body.parent = opts.parent;
  if (opts.cwdPrefix) body.cwd_prefix = opts.cwdPrefix;
  if (opts.model) body.model = opts.model;
  const res = await fetch("/api/aether/spawn-batch", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`spawn-batch failed: ${res.status} ${text}`);
  }
  return (await res.json()) as BatchSpawnResult;
}

/** Compare payload from GET /api/aether/snapshots/:a/compare/:b. */
export interface CompareMetaSummary {
  lineage: string;
  mood: string;
  event_type: string;
  session: string;
  ticks: number;
  depth: number;
  cwd: string;
  files: number;
  text: string;
}
export interface CognitionEditSummary {
  type: "replace" | "insert" | "delete";
  path: string;
  summary: string;
}
export interface FsAdded {
  path: string;
  type: string;
  size: number;
  hash: string;
}
export interface FsChanged {
  path: string;
  size_a: number;
  size_b: number;
  hash_a: string;
  hash_b: string;
}
export interface CompareResult {
  a: { id: string; metadata: CompareMetaSummary };
  b: { id: string; metadata: CompareMetaSummary };
  common_ancestor: string;
  cognition_diff: {
    edit_count: number;
    truncated: boolean | null;
    edits: CognitionEditSummary[];
  };
  filesystem_diff: {
    added: FsAdded[];
    removed: FsAdded[];
    changed: FsChanged[];
    count_a: number;
    count_b: number;
  };
}

async function compareSnapshots(a: string, b: string): Promise<CompareResult> {
  const res = await fetch(
    `/api/aether/snapshots/${encodeURIComponent(a)}/compare/${encodeURIComponent(b)}`,
  );
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`compare failed: ${res.status} ${text}`);
  }
  return (await res.json()) as CompareResult;
}

// ── Session timelines (the tracks view's data model) ─────────────────
//
// Tracks treat each agent run as a horizontal lane. Consecutive
// `text_delta` events collapse into a single "thinking" bar — you don't
// care about token boundaries, you care about the agent's *decisions*.
// `tool_start` + immediately-following `tool_result` collapse into one
// "tool" block carrying the tool name + ok/failed outcome. Everything
// else (prompt, session, complete, error) is its own block.
//
// Only snapshots that carry a `:session` metadata field participate —
// the seed/synthetic snapshots from `aether-seed` are intentionally
// excluded from tracks view (they live in galactic mode).

export type ChunkKind = "prompt" | "thinking" | "tool" | "complete" | "error" | "session";

export interface TimelineEvent {
  kind: ChunkKind;
  snapshotIds: string[];     // 1 for most, N for collapsed thinking
  primaryId: string;          // the snapshot this block represents on click
  startTime: number;          // unix seconds (first snapshot)
  endTime: number;            // unix seconds (last snapshot in chunk)
  label: string;              // short text shown in/on the block
  toolName?: string;          // e.g. "write", "bash", "read"
  success?: boolean;          // for tool/complete/error
  mood: string;               // "linear" | "explorer" | "reflector"
}

export interface SessionTimeline {
  sessionId: string;
  lineage: string;
  startedAt: number;          // unix seconds (oldest event)
  lastActivityAt: number;     // unix seconds (newest event)
  status: "running" | "complete" | "error";
  events: TimelineEvent[];
  /** The parent snapshot (if forked from another session's star), used to
      draw the fork connector in the track view. */
  forkedFromId: string | null;
}

function eventMoodForKind(kind: ChunkKind): string {
  switch (kind) {
    case "prompt":   return "linear";
    case "session":  return "explorer";
    case "thinking": return "linear";
    case "tool":     return "explorer";
    case "complete": return "reflector";
    case "error":    return "reflector";
  }
}

function deriveSessionTimelines(allSnaps: Snapshot[]): SessionTimeline[] {
  // 1. Bucket snapshots by :session metadata. Skip those without one.
  const bySession = new Map<string, Snapshot[]>();
  for (const s of allSnaps) {
    const sid = metaStr(s, "session");
    if (!sid) continue;
    const arr = bySession.get(sid) ?? [];
    arr.push(s);
    bySession.set(sid, arr);
  }

  const out: SessionTimeline[] = [];
  for (const [sid, snaps] of bySession) {
    // 2. Sort by timestamp ascending.
    snaps.sort((a, b) => a.timestamp - b.timestamp);

    // 3. Identify the fork-origin: parent of the FIRST snapshot in the
    //    session. If that parent's session differs, this is a fork.
    const firstSnap = snaps[0]!;
    let forkedFromId: string | null = null;
    if (firstSnap.parent) {
      const parentSnap = snapshotsById.get(firstSnap.parent);
      if (parentSnap && metaStr(parentSnap, "session") !== sid) {
        forkedFromId = firstSnap.parent;
      }
    }

    // 4. Chunk events.
    const events: TimelineEvent[] = [];
    for (const s of snaps) {
      // cl-json camelCases keyword keys ("event-type" → "eventType"); fall back
      // through both for safety so this still works if the convention changes.
      const evType = metaStr(s, "eventType") || metaStr(s, "event-type");
      const text = metaStr(s, "text");

      // text_delta → fold into the previous "thinking" chunk if any.
      if (evType === "text_delta") {
        const last = events[events.length - 1];
        if (last && last.kind === "thinking") {
          last.snapshotIds.push(s.id);
          last.endTime = s.timestamp;
          // Keep the first ~80 chars of accumulated text as label.
          if (last.label.length < 80) {
            last.label = (last.label + " " + text).slice(0, 80).trim();
          }
          continue;
        }
        events.push({
          kind: "thinking",
          snapshotIds: [s.id],
          primaryId: s.id,
          startTime: s.timestamp,
          endTime: s.timestamp,
          label: text.slice(0, 80),
          mood: eventMoodForKind("thinking"),
        });
        continue;
      }

      // tool_start → start a pending "tool" chunk
      if (evType === "tool_start") {
        // Parse "name(summary)" out of the captured text.
        const m = text.match(/^([\w_-]+)\((.*)\)$/s);
        const toolName = m ? m[1]! : "tool";
        const summary = m ? m[2]! : text;
        events.push({
          kind: "tool",
          snapshotIds: [s.id],
          primaryId: s.id,
          startTime: s.timestamp,
          endTime: s.timestamp,
          label: toolName + "(" + (summary.length > 30 ? summary.slice(0, 30) + "…" : summary) + ")",
          toolName,
          mood: eventMoodForKind("tool"),
        });
        continue;
      }

      // tool_result → close the preceding pending tool chunk (or stand alone).
      if (evType === "tool_result") {
        const last = events[events.length - 1];
        const m = text.match(/^([\w_-]+)\s*→\s*(ok|failed)$/);
        const success = m ? m[2] === "ok" : true;
        if (last && last.kind === "tool" && last.success === undefined) {
          last.snapshotIds.push(s.id);
          last.endTime = s.timestamp;
          last.success = success;
          // tool_result's primary snapshot is the result (where FS state is captured).
          last.primaryId = s.id;
          continue;
        }
        events.push({
          kind: "tool",
          snapshotIds: [s.id],
          primaryId: s.id,
          startTime: s.timestamp,
          endTime: s.timestamp,
          label: text,
          toolName: m ? m[1] : "tool",
          success,
          mood: success ? eventMoodForKind("tool") : eventMoodForKind("error"),
        });
        continue;
      }

      // prompt / session / complete / error → standalone chunk.
      const kind: ChunkKind =
        evType === "prompt"   ? "prompt"   :
        evType === "session"  ? "session"  :
        evType === "complete" ? "complete" :
        evType === "error"    ? "error"    :
        "thinking";
      events.push({
        kind,
        snapshotIds: [s.id],
        primaryId: s.id,
        startTime: s.timestamp,
        endTime: s.timestamp,
        label: kind === "prompt" ? text.slice(0, 80) :
               kind === "complete" ? (text || "completed") :
               kind === "error" ? (text || "error") :
               text.slice(0, 30),
        success: kind === "complete" ? true : kind === "error" ? false : undefined,
        mood: eventMoodForKind(kind),
      });
    }

    // 5. Status from terminal event.
    let status: SessionTimeline["status"] = "running";
    const terminal = events[events.length - 1];
    if (terminal?.kind === "complete") status = "complete";
    else if (terminal?.kind === "error") status = "error";

    out.push({
      sessionId: sid,
      lineage: metaStr(firstSnap, "lineage"),
      startedAt: snaps[0]!.timestamp,
      lastActivityAt: snaps[snaps.length - 1]!.timestamp,
      status,
      events,
      forkedFromId,
    });
  }

  // 6. Newest started session first (top of screen = most-recent work).
  out.sort((a, b) => b.startedAt - a.startedAt);
  return out;
}

// Reactive timelines derived from nodes — solid will re-evaluate on every
// node/edge change, which is what we want when live snapshots land.
function sessionTimelines(): SessionTimeline[] {
  // Use snapshotsById (the cache) directly — it's the source of truth
  // for full snapshot metadata. nodes() only carries display state.
  return deriveSessionTimelines(Array.from(snapshotsById.values()));
}

// ── Loading ──────────────────────────────────────────────────────────

async function loadFromApiOrFixture() {
  try {
    const snaps = await listSnapshots();
    if (snaps.length > 0) {
      buildGraph(snaps);
      setUsingFixture(false);
      setLoaded(true);
      // Live WS only useful against the real API (not the offline fixture).
      connectLiveWs();
      return;
    }
    // Empty store → fall through to fixture so the page is still useful.
  } catch (err) {
    // Network/API failure → fixture.
    console.warn("[aether] API unavailable, using placeholder fixture:", err);
  }
  buildGraph(placeholder as unknown as Snapshot[]);
  setUsingFixture(true);
  setLoaded(true);
}

// ── Public store ─────────────────────────────────────────────────────

// Tiny debug hook so tests / rodney can drive selection without
// hunting for star positions on the canvas. Harmless in prod.
if (typeof window !== "undefined") {
  (window as unknown as Record<string, unknown>).__aether = {
    select: (id: string | null) => setSelectedId(id),
    selected: () => selectedId(),
    nodeIds: () => nodes().map((n) => n.id),
  };
}

export const aetherStore = {
  nodes,
  edges,
  loaded,
  usingFixture,
  liveConnected,
  lastBirthAt,
  // View mode
  viewMode,
  setViewMode,
  toggleViewMode: () =>
    setViewMode((m) => (m === "tracks" ? "galactic" : "tracks")),
  // Tracks data
  sessionTimelines,
  load: loadFromApiOrFixture,
  tick,
  spawn: spawnAgent,
  spawnBatch,
  compareSnapshots,
  fetchFilesAt,
  checkout: checkoutSnapshot,
  fetchBlame,
  // Selection / hover / focus layer.
  selectedId,
  hoveredId,
  select: (id: string | null) => setSelectedId(id),
  hover: (id: string | null) => setHoveredId(id),
  getSnapshot,
  childrenOf: (id: string) => childrenOf.get(id) ?? [],
  ancestorsOf,
  descendantsOf,
  focusSet,
  // Metadata accessors so the page doesn't need to duplicate plist parsing.
  meta: (id: string) => {
    const s = snapshotsById.get(id);
    if (!s) return { mood: "", lineage: "", ticks: 0, depth: 0, isRoot: false };
    return {
      mood: metaStr(s, "mood"),
      lineage: metaStr(s, "lineage"),
      ticks: metaNum(s, "ticks"),
      depth: metaNum(s, "depth"),
      isRoot: metaBool(s, "root"),
    };
  },
  /** Forces a fixture-only load — used by the dev page for offline work. */
  loadFixture: () => {
    buildGraph(placeholder as unknown as Snapshot[]);
    setUsingFixture(true);
    setLoaded(true);
  },
};
