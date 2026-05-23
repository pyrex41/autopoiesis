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

function readMetaNumber(snap: Snapshot, key: string): number {
  const md = snap.metadata as Record<string, unknown> | null;
  if (md && typeof md[key] === "number") return md[key] as number;
  return 0;
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
  const meta = (snap.metadata ?? {}) as Record<string, unknown>;

  // Pull whatever we can. Default to 0; the placeholder + Agent A fixture
  // will populate these. If neither populates them, the string-length
  // proxies below carry the variance.
  const version = readMetaNumber(snap, "version");
  const caps = readMetaNumber(snap, "capabilities");
  const heur = readMetaNumber(snap, "heuristics");
  const thoughts = readMetaNumber(snap, "thoughts");

  // String-length proxy for cognitive content when metadata is sparse.
  const stateLen = stateString(snap).length;
  const lenProxy = Math.log1p(stateLen) / 8; // ~0..1

  // Three spectral axes, each in [0, 1].
  // Young + exploring: high diff, low version.
  const youngExplore = Math.min(1, diffMag / 6) * Math.exp(-version / 4);
  // Old reflective: high version + many heuristics.
  const oldReflect = Math.min(1, version / 6) * Math.min(1, heur / 5);
  // Capability-rich: high cap count.
  const capRich = Math.min(1, caps / 8);

  // Pick dominant axis + secondary blend.
  // Each axis maps to a base hue:
  //   blue-white  → 210°
  //   red         → 15°
  //   yellow      → 50°
  // We compute a weighted circular mean (treating hues as 2D unit vectors).
  const axes = [
    { weight: youngExplore + 0.05, hue: 210, light: 0.75, sat: 0.55 },
    { weight: oldReflect + 0.05, hue: 15, light: 0.55, sat: 0.7 },
    { weight: capRich + 0.05, hue: 50, light: 0.7, sat: 0.6 },
  ];
  // Add a small constant so we never divide by zero and so very-uniform
  // snapshots still get *some* color from each axis.

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
  const L = Math.max(0.35, Math.min(0.85, light / totalW + (lenProxy - 0.5) * 0.1));
  const S = Math.max(0.3, Math.min(0.9, sat / totalW));

  // Size: log(thoughts + 1) with a string-length fallback.
  const sizeBase = thoughts > 0 ? thoughts : Math.max(1, Math.floor(stateLen / 30));
  const radius = Math.log1p(sizeBase) * 3.5 + 3;

  // Slight variation per-id so colors don't clump for identical metadata.
  const jitter = (hash01(snap.id) - 0.5) * 8;
  const finalHue = ((normHue + jitter) % 360 + 360) % 360;

  const color = `hsl(${finalHue.toFixed(1)}, ${(S * 100).toFixed(0)}%, ${(L * 100).toFixed(0)}%)`;
  const haloColor = `hsla(${finalHue.toFixed(1)}, ${(S * 100).toFixed(0)}%, ${(L * 100).toFixed(0)}%, 0.25)`;

  return {
    color,
    haloColor,
    radius,
    magnitude: thoughts + caps + heur + lenProxy * 4,
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
  // Prefer precomputed metadata if the backend ever adds it.
  const pre = readMetaNumber(child, "diff_magnitude");
  if (pre > 0) return pre;

  const dLen = Math.abs(stateString(child).length - stateString(parent).length);
  const dVer = Math.abs(
    readMetaNumber(child, "version") - readMetaNumber(parent, "version"),
  );
  // Optional explicit "DIVERGE" hint baked into the placeholder fixture's
  // state strings; treated as a soft signal, not parsed.
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

// ── Build from snapshot list ─────────────────────────────────────────

function buildGraph(snapshots: Snapshot[]) {
  const byId = new Map<string, Snapshot>();
  for (const s of snapshots) byId.set(s.id, s);

  const builtEdges: AetherEdge[] = [];
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
  }

  // Per-node accumulated incoming edge magnitude — used as "recent diff"
  // input to spectralClass (the diff that produced this node).
  const incomingDiff = new Map<string, number>();
  for (const e of builtEdges) {
    incomingDiff.set(e.target, (incomingDiff.get(e.target) ?? 0) + e.diffMagnitude);
  }

  // Initial positions: seeded scatter using id hash, NOT a circle.
  // Circle initial conditions are the #1 way to end up with a force
  // layout that looks like... a circle.
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

// ── Loading ──────────────────────────────────────────────────────────

async function loadFromApiOrFixture() {
  try {
    const snaps = await listSnapshots();
    if (snaps.length > 0) {
      buildGraph(snaps);
      setUsingFixture(false);
      setLoaded(true);
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

export const aetherStore = {
  nodes,
  edges,
  loaded,
  usingFixture,
  load: loadFromApiOrFixture,
  tick,
  /** Forces a fixture-only load — used by the dev page for offline work. */
  loadFixture: () => {
    buildGraph(placeholder as unknown as Snapshot[]);
    setUsingFixture(true);
    setLoaded(true);
  },
};
