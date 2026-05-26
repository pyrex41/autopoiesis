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
import { type Component, onMount, onCleanup, createSignal, createEffect, Show, For } from "solid-js";
import { aetherStore } from "../stores/aether";

// ── Palette (matches design-system.ts) ───────────────────────────────
const C = {
  void: "#04060e",
  deep: "#080c18",
  edge: "#1e2d4a",
};

// Hit-test radius multiplier — slightly bigger than visual to be forgiving.
const HIT_RADIUS_MULT = 1.6;
// Pixel drift on mousedown→mouseup below which we treat as a click, not drag.
const CLICK_DRIFT_PX = 4;

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
  // Cursor screen-pixel position, used to anchor the hover HUD.
  const [mousePos, setMousePos] = createSignal({ x: 0, y: 0 });
  // Where the press started — used to distinguish click from drag on mouseup.
  let mouseDownAt: { x: number; y: number } | null = null;

  // Force simulation cadence — separate from rAF so we can decouple
  // physics from rendering rate without ever animating the nodes.
  // The simulation runs for a finite warmup (~3s @ 60Hz = 180 ticks)
  // then settles. After that we still call tick() but kinetic energy
  // approaches zero so nothing visibly moves — consistent with the
  // "no animations" constraint while letting the layout solve.
  let physicsTicks = 0;
  const PHYSICS_WARMUP_TICKS = 240;
  /** Re-armed each time a live snapshot arrives — gives the layout
      a fresh burst of multi-step physics to ease the new star in. */
  const REBIRTH_BOOST_TICKS = 120;

  // Prompt-bar state.
  const [prompt, setPrompt] = createSignal("");
  const [promptBusy, setPromptBusy] = createSignal(false);
  const [promptError, setPromptError] = createSignal<string | null>(null);
  const [promptOpen, setPromptOpen] = createSignal(false);
  let promptInputRef!: HTMLInputElement;

  // Files-at-snapshot fetched on selection (cached by id).
  const [filesAtSelected, setFilesAtSelected] = createSignal<import("../stores/aether").FilesAtSnapshot | null>(null);
  const [filesLoading, setFilesLoading] = createSignal(false);

  // Checkout toast (auto-dismisses).
  const [toast, setToast] = createSignal<{ kind: "ok" | "err"; text: string } | null>(null);
  function flashToast(kind: "ok" | "err", text: string) {
    setToast({ kind, text });
    setTimeout(() => setToast(null), 3500);
  }

  // Sibling-fork comparison (shift-click a second star while one is selected).
  const [compareWith, setCompareWith] = createSignal<string | null>(null);
  const [compareData, setCompareData] = createSignal<import("../stores/aether").CompareResult | null>(null);
  const [compareLoading, setCompareLoading] = createSignal(false);
  const [compareError, setCompareError] = createSignal<string | null>(null);
  function closeCompare() {
    setCompareWith(null);
    setCompareData(null);
    setCompareError(null);
  }

  // ── Pan/zoom (adapted from DAGCanvas.tsx:519-620) ──────────────────
  // mousedown→mousemove with drift ≥ CLICK_DRIFT_PX = drag
  // mousedown→mouseup with drift < CLICK_DRIFT_PX  = click (hit-test → select)
  // mousemove without buttons = hover (hit-test → set hover id)

  function hitTest(clientX: number, clientY: number): string | null {
    const r = canvasRef.getBoundingClientRect();
    const wx = (clientX - r.left - viewX()) / viewScale();
    const wy = (clientY - r.top - viewY()) / viewScale();
    let best: { id: string; d: number } | null = null;
    for (const n of aetherStore.nodes()) {
      const dx = n.x - wx;
      const dy = n.y - wy;
      const d = Math.hypot(dx, dy);
      const r2 = n.radius * HIT_RADIUS_MULT;
      if (d <= r2 && (!best || d < best.d)) best = { id: n.id, d };
    }
    return best?.id ?? null;
  }

  function onMouseDown(e: MouseEvent) {
    if (e.button !== 0) return;
    setIsDragging(true);
    setDragStart({ x: e.clientX - viewX(), y: e.clientY - viewY() });
    mouseDownAt = { x: e.clientX, y: e.clientY };
  }

  function onMouseMove(e: MouseEvent) {
    setMousePos({ x: e.clientX, y: e.clientY });
    if (isDragging()) {
      setViewX(e.clientX - dragStart().x);
      setViewY(e.clientY - dragStart().y);
      return;
    }
    // Hover hit-test only when not dragging.
    aetherStore.hover(hitTest(e.clientX, e.clientY));
  }

  function onMouseUp(e?: MouseEvent) {
    setIsDragging(false);
    if (e && mouseDownAt) {
      const drift = Math.hypot(e.clientX - mouseDownAt.x, e.clientY - mouseDownAt.y);
      if (drift < CLICK_DRIFT_PX) {
        const hit = hitTest(e.clientX, e.clientY);
        // Shift-click: if a star is already selected and this is a different
        // star, open the comparison modal instead of switching selection.
        if (e.shiftKey && hit && aetherStore.selectedId() && hit !== aetherStore.selectedId()) {
          setCompareWith(hit);
        } else {
          aetherStore.select(hit); // null = deselect when clicking empty space
        }
      }
    }
    mouseDownAt = null;
  }

  function onMouseLeave() {
    setIsDragging(false);
    aetherStore.hover(null);
    mouseDownAt = null;
  }

  function onKeyDown(e: KeyboardEvent) {
    // Ignore key shortcuts when the user is typing into the prompt input.
    const activeIsInput = document.activeElement?.tagName === "INPUT";

    // "/" focuses the prompt bar; Esc closes it OR clears selection.
    if (e.key === "/" && !promptOpen() && !activeIsInput) {
      e.preventDefault();
      setPromptOpen(true);
      queueMicrotask(() => promptInputRef?.focus());
      return;
    }
    if (e.key === "Escape") {
      if (compareWith()) {
        closeCompare();
        return;
      }
      if (promptOpen()) {
        setPromptOpen(false);
        setPrompt("");
        setPromptError(null);
        return;
      }
      aetherStore.select(null);
    }
    // "c" — checkout the selected star's FS state to its captured cwd.
    if ((e.key === "c" || e.key === "C") && !activeIsInput) {
      const id = aetherStore.selectedId();
      if (!id) return;
      e.preventDefault();
      checkoutSelected();
    }
  }

  async function checkoutSelected() {
    const id = aetherStore.selectedId();
    if (!id) return;
    try {
      const res = await aetherStore.checkout(id);
      flashToast("ok", `checked out ${res.entries_written} file${res.entries_written === 1 ? "" : "s"} → ${res.target}`);
    } catch (err) {
      flashToast("err", err instanceof Error ? err.message : String(err));
    }
  }

  async function submitPrompt() {
    const text = prompt().trim();
    if (!text || promptBusy()) return;
    setPromptBusy(true);
    setPromptError(null);
    try {
      const parent = aetherStore.selectedId();
      // Pipe-separated input → batch spawn one variant per chunk after the first.
      //   "build a parser | use regex | use a peg grammar | hand-rolled"
      // becomes base="build a parser" + variants=["use regex","use a peg grammar","hand-rolled"]
      const parts = text.split("|").map((s) => s.trim()).filter(Boolean);
      if (parts.length > 1) {
        const base = parts[0]!;
        const variants = parts.slice(1);
        // Per-batch cwd prefix: stable enough for an interactive session,
        // unique enough to keep parallel forks from stomping each other.
        const ts = Date.now().toString(36);
        const cwdPrefix = `/tmp/aether-batch-${ts}/`;
        const res = await aetherStore.spawnBatch({
          prompt: base,
          variants,
          parent: parent ?? null,
          cwdPrefix,
        });
        flashToast("ok", `spawned ${res.count} variants → ${cwdPrefix}`);
      } else {
        await aetherStore.spawn({ prompt: text, parent: parent ?? null });
      }
      setPrompt("");
      setPromptOpen(false);
    } catch (err) {
      setPromptError(err instanceof Error ? err.message : String(err));
    } finally {
      setPromptBusy(false);
    }
  }

  /** Pan + zoom the camera so the given node is centered. */
  function focusOnNode(id: string) {
    const n = aetherStore.nodes().find((x) => x.id === id);
    if (!n) return;
    const r = canvasRef.getBoundingClientRect();
    setViewX(r.width / 2 - n.x * viewScale());
    setViewY(r.height / 2 - n.y * viewScale());
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

    // Focus mode: when a star is selected, fade everything outside the
    // {selected ∪ ancestors ∪ descendants} set. This is the "transform"
    // gesture — clicking a star turns the picture into a lineage story.
    const sel = aetherStore.selectedId();
    const hov = aetherStore.hoveredId();
    const focus = sel ? aetherStore.focusSet() : null;
    const dim = (id: string) => (focus && !focus.has(id) ? 0.18 : 1);

    // Edges first, so nodes draw over.
    ctx.lineWidth = 0.6 / viewScale();
    for (const e of edges) {
      const a = nodeMap.get(e.source);
      const b = nodeMap.get(e.target);
      if (!a || !b) continue;
      // Stroke alpha decays with diff magnitude — high divergence edges
      // are dimmer (they're more "proper motion vector" than tight
      // structural ligament).
      const baseAlpha = Math.max(0.08, 0.35 - e.diffMagnitude * 0.04);
      const inFocus = focus ? focus.has(e.source) && focus.has(e.target) : true;
      const alpha = baseAlpha * (inFocus ? 1 : 0.2);
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      // Lineage path through the selection gets a slight color shift.
      ctx.strokeStyle = inFocus && focus
        ? `rgba(160, 200, 255, ${alpha.toFixed(3)})`
        : `rgba(80, 110, 160, ${alpha.toFixed(3)})`;
      ctx.stroke();
    }

    // Birth animation: any node within BIRTH_MS of its bornAt gets an
    // additional bright halo + plasma line back to its parent that
    // both fade as the star "settles". Pure render layer — no extra
    // physics, no extra data on the node.
    const BIRTH_MS = 2500;
    const now = Date.now();

    // Plasma bridges from parent → newborn (drawn behind nodes).
    for (const n of nodes) {
      const age = now - n.bornAt;
      if (age >= BIRTH_MS || !n.parent) continue;
      const parent = nodeMap.get(n.parent);
      if (!parent) continue;
      const t = 1 - age / BIRTH_MS; // 1 -> 0 over BIRTH_MS
      const alpha = 0.55 * t;
      ctx.beginPath();
      ctx.moveTo(parent.x, parent.y);
      ctx.lineTo(n.x, n.y);
      ctx.strokeStyle = `rgba(180, 230, 255, ${alpha.toFixed(3)})`;
      ctx.lineWidth = (1.4 + 2 * t) / viewScale();
      ctx.stroke();
    }

    // Nodes — halo first, core on top.
    for (const n of nodes) {
      ctx.globalAlpha = dim(n.id);
      const age = now - n.bornAt;
      const birthGlow = age < BIRTH_MS ? 1 - age / BIRTH_MS : 0;
      // Extra outer halo while being born.
      if (birthGlow > 0) {
        ctx.beginPath();
        ctx.arc(n.x, n.y, n.radius * (3.2 + 2 * birthGlow), 0, Math.PI * 2);
        ctx.fillStyle = n.haloColor.replace(/[\d.]+\)$/, `${(0.35 * birthGlow).toFixed(3)})`);
        ctx.fill();
      }
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.radius * 2.4, 0, Math.PI * 2);
      ctx.fillStyle = n.haloColor;
      ctx.fill();
    }
    for (const n of nodes) {
      ctx.globalAlpha = dim(n.id);
      const age = now - n.bornAt;
      const birthBoost = age < BIRTH_MS ? 1 + 0.6 * (1 - age / BIRTH_MS) : 1;
      ctx.beginPath();
      ctx.arc(n.x, n.y, n.radius * birthBoost, 0, Math.PI * 2);
      ctx.fillStyle = n.color;
      ctx.fill();
      // Subtle outline so brighter stars don't blow out.
      ctx.strokeStyle = "rgba(255,255,255,0.15)";
      ctx.lineWidth = 0.4 / viewScale();
      ctx.stroke();
    }
    ctx.globalAlpha = 1;

    // Hover ring — thin, just visible enough to confirm a hit.
    if (hov && hov !== sel) {
      const h = nodeMap.get(hov);
      if (h) {
        ctx.beginPath();
        ctx.arc(h.x, h.y, h.radius * 1.9, 0, Math.PI * 2);
        ctx.strokeStyle = "rgba(220, 235, 255, 0.55)";
        ctx.lineWidth = 1.4 / viewScale();
        ctx.stroke();
      }
    }

    // Selection ring — brighter, double stroke for a "telescope lock" feel.
    if (sel) {
      const s = nodeMap.get(sel);
      if (s) {
        ctx.beginPath();
        ctx.arc(s.x, s.y, s.radius * 2.2, 0, Math.PI * 2);
        ctx.strokeStyle = "rgba(255,255,255,0.85)";
        ctx.lineWidth = 1.4 / viewScale();
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(s.x, s.y, s.radius * 3.4, 0, Math.PI * 2);
        ctx.strokeStyle = "rgba(180, 210, 255, 0.35)";
        ctx.lineWidth = 0.9 / viewScale();
        ctx.stroke();
      }
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
    window.addEventListener("keydown", onKeyDown);

    // Re-arm a burst of multi-step physics each time a new star arrives
    // via WS, so it settles into its place over ~2s of warmup rather than
    // sitting frozen on top of its parent.
    createEffect(() => {
      const ts = aetherStore.lastBirthAt();
      if (ts > 0) {
        physicsTicks = Math.min(physicsTicks, PHYSICS_WARMUP_TICKS - REBIRTH_BOOST_TICKS);
      }
    });

    // When a star is selected, fetch its files listing (so the panel can
    // show "what existed at this point in time"). Cleared on deselect.
    // Clear the cached data BEFORE fetching so a quick re-select doesn't
    // leak the prior star's files into the new star's panel.
    createEffect(() => {
      const id = aetherStore.selectedId();
      setFilesAtSelected(null);
      if (!id) return;
      setFilesLoading(true);
      aetherStore.fetchFilesAt(id)
        .then((data) => {
          // Make sure the user hasn't re-selected before this resolved.
          if (aetherStore.selectedId() === id) setFilesAtSelected(data);
        })
        .catch(() => {})
        .finally(() => {
          if (aetherStore.selectedId() === id) setFilesLoading(false);
        });
    });

    // Compare modal: when (selectedId, compareWith) both set, fetch the diff.
    // Cleared on close. Re-fires if either id changes.
    createEffect(() => {
      const a = aetherStore.selectedId();
      const b = compareWith();
      setCompareData(null);
      setCompareError(null);
      if (!a || !b) return;
      setCompareLoading(true);
      aetherStore.compareSnapshots(a, b)
        .then((data) => {
          if (aetherStore.selectedId() === a && compareWith() === b) {
            setCompareData(data);
          }
        })
        .catch((err) => {
          setCompareError(err instanceof Error ? err.message : String(err));
        })
        .finally(() => {
          if (aetherStore.selectedId() === a && compareWith() === b) {
            setCompareLoading(false);
          }
        });
    });
  });

  onCleanup(() => {
    cancelAnimationFrame(animFrame);
    canvasRef?.removeEventListener("wheel", onWheel);
    window.removeEventListener("keydown", onKeyDown);
  });

  // ── Overlay renderers ───────────────────────────────────────────────

  function shortId(id: string): string {
    return id.length > 8 ? id.slice(0, 8) : id;
  }
  function shortHash(h: string | undefined): string {
    if (!h) return "—";
    return h.length > 10 ? h.slice(0, 10) + "…" : h;
  }
  function tsLocal(ts: number | undefined): string {
    if (!ts) return "—";
    const d = new Date(ts * 1000);
    return d.toISOString().replace("T", " ").replace(/\.\d+Z$/, "Z");
  }

  function hudFor(id: string) {
    const m = aetherStore.meta(id);
    const snap = aetherStore.getSnapshot(id);
    return (
      <div class="aether-hud-card">
        <div class="aether-hud-id">{shortId(id)}</div>
        <div class="aether-hud-row">
          <span class="k">lineage</span>
          <span class="v">{m.lineage || "—"}</span>
        </div>
        <div class="aether-hud-row">
          <span class="k">mood</span>
          <span class={`v mood-${m.mood || "none"}`}>{m.mood || "—"}</span>
        </div>
        <div class="aether-hud-row">
          <span class="k">ticks</span>
          <span class="v">{m.ticks}</span>
        </div>
        <div class="aether-hud-row">
          <span class="k">depth</span>
          <span class="v">{m.depth}{m.isRoot ? " (root)" : ""}</span>
        </div>
        <div class="aether-hud-row">
          <span class="k">parent</span>
          <span class="v">{snap?.parent ? shortId(snap.parent) : "—"}</span>
        </div>
      </div>
    );
  }

  function detailPanelFor(id: string) {
    const snap = aetherStore.getSnapshot(id);
    const m = aetherStore.meta(id);
    const kids = aetherStore.childrenOf(id);
    const ancestorCount = aetherStore.ancestorsOf(id).size;
    const descendantCount = aetherStore.descendantsOf(id).size;
    return (
      <div class="aether-panel">
        <div class="aether-panel-head">
          <div class="aether-panel-title">SNAPSHOT</div>
          <button
            class="aether-panel-close"
            onClick={() => aetherStore.select(null)}
            title="Close (Esc)"
          >
            ✕
          </button>
        </div>
        <div class="aether-panel-id" title={id}>{id}</div>

        <div class="aether-section">
          <div class="aether-section-title">classification</div>
          <div class="aether-row"><span class="k">lineage</span><span class={`v lin-${m.lineage}`}>{m.lineage || "—"}</span></div>
          <div class="aether-row"><span class="k">mood</span><span class={`v mood-${m.mood || "none"}`}>{m.mood || "—"}</span></div>
          <div class="aether-row"><span class="k">ticks</span><span class="v">{m.ticks}</span></div>
          <div class="aether-row"><span class="k">depth</span><span class="v">{m.depth}{m.isRoot ? " (root)" : ""}</span></div>
        </div>

        <div class="aether-section">
          <div class="aether-section-title">topology</div>
          <div class="aether-row">
            <span class="k">parent</span>
            <span class="v">
              {snap?.parent ? (
                <a
                  class="aether-link"
                  onClick={() => { aetherStore.select(snap.parent!); focusOnNode(snap.parent!); }}
                  title={snap.parent}
                >
                  {shortId(snap.parent)}
                </a>
              ) : "— (root)"}
            </span>
          </div>
          <div class="aether-row"><span class="k">ancestors</span><span class="v">{ancestorCount}</span></div>
          <div class="aether-row"><span class="k">descendants</span><span class="v">{descendantCount}</span></div>
          <Show when={kids.length > 0}>
            <div class="aether-children-label">children ({kids.length})</div>
            <div class="aether-children">
              <For each={kids}>{(cid) => (
                <a
                  class="aether-link aether-child"
                  onClick={() => { aetherStore.select(cid); focusOnNode(cid); }}
                  title={cid}
                >
                  {shortId(cid)}
                </a>
              )}</For>
            </div>
          </Show>
        </div>

        <div class="aether-section">
          <div class="aether-section-title">provenance</div>
          <div class="aether-row"><span class="k">timestamp</span><span class="v mono-small">{tsLocal(snap?.timestamp)}</span></div>
          <div class="aether-row"><span class="k">hash</span><span class="v mono-small" title={snap?.hash}>{shortHash(snap?.hash)}</span></div>
        </div>

        <div class="aether-section">
          <div class="aether-section-title">filesystem</div>
          <Show
            when={filesAtSelected()}
            fallback={
              <div class="aether-files-empty">
                {filesLoading() ? "loading…" : "no FS capture"}
              </div>
            }
          >
            {(data) => (
              <>
                <div class="aether-row">
                  <span class="k">cwd</span>
                  <span class="v mono-small" title={data().cwd}>
                    {data().cwd || "—"}
                  </span>
                </div>
                <div class="aether-row">
                  <span class="k">files</span>
                  <span class="v">{data().count}</span>
                </div>
                <Show when={(data().files ?? []).length > 0}>
                  <div class="aether-files-list">
                    <For each={(data().files ?? []).slice(0, 12)}>
                      {(f) => (
                        <div class="aether-file-row" title={`${f.path} (${f.size}B)`}>
                          <span class="aether-file-path">{f.path}</span>
                          <span class="aether-file-size">{formatBytes(f.size)}</span>
                        </div>
                      )}
                    </For>
                    <Show when={(data().files ?? []).length > 12}>
                      <div class="aether-files-more">+{(data().files ?? []).length - 12} more</div>
                    </Show>
                  </div>
                </Show>
                <Show when={data().count > 0 || data().cwd}>
                  <button
                    class="aether-checkout-btn"
                    onClick={checkoutSelected}
                    title="Restore this filesystem state to the captured cwd (key: c)"
                  >
                    checkout to {data().cwd || "captured cwd"}
                  </button>
                </Show>
              </>
            )}
          </Show>
        </div>

        <div class="aether-panel-foot">
          <kbd>Esc</kbd> close · <kbd>c</kbd> checkout · click another star to switch
        </div>
      </div>
    );
  }

  function formatBytes(n: number): string {
    if (n < 1024) return `${n}B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)}K`;
    return `${(n / 1024 / 1024).toFixed(1)}M`;
  }

  function compareModal() {
    const a = aetherStore.selectedId();
    const b = compareWith();
    if (!a || !b) return null;
    const data = compareData();
    return (
      <div class="aether-compare-modal-backdrop" onClick={closeCompare}>
        <div class="aether-compare-modal" onClick={(e) => e.stopPropagation()}>
          <div class="aether-compare-head">
            <div class="aether-compare-title">
              <span class="aether-compare-id a-side">{shortId(a)}</span>
              <span class="aether-compare-vs">vs</span>
              <span class="aether-compare-id b-side">{shortId(b)}</span>
            </div>
            <button
              class="aether-compare-close"
              onClick={closeCompare}
              title="Close (Esc)"
            >
              ✕
            </button>
          </div>
          <Show when={compareLoading()}>
            <div class="aether-compare-empty">loading diff…</div>
          </Show>
          <Show when={compareError()}>
            <div class="aether-compare-err">{compareError()}</div>
          </Show>
          <Show when={data}>
            {(d) => (
              <>
                <div class="aether-compare-section">
                  <div class="aether-compare-section-title">classification</div>
                  <div class="aether-compare-row">
                    <span class="k">lineage</span>
                    <span class="v a-side">{d().a.metadata.lineage || "—"}</span>
                    <span class="v b-side">{d().b.metadata.lineage || "—"}</span>
                  </div>
                  <div class="aether-compare-row">
                    <span class="k">mood</span>
                    <span class={`v a-side mood-${d().a.metadata.mood || "none"}`}>{d().a.metadata.mood || "—"}</span>
                    <span class={`v b-side mood-${d().b.metadata.mood || "none"}`}>{d().b.metadata.mood || "—"}</span>
                  </div>
                  <div class="aether-compare-row">
                    <span class="k">ticks</span>
                    <span class="v a-side">{d().a.metadata.ticks}</span>
                    <span class="v b-side">{d().b.metadata.ticks}</span>
                  </div>
                  <div class="aether-compare-row">
                    <span class="k">depth</span>
                    <span class="v a-side">{d().a.metadata.depth}</span>
                    <span class="v b-side">{d().b.metadata.depth}</span>
                  </div>
                  <div class="aether-compare-row">
                    <span class="k">cwd</span>
                    <span class="v a-side mono-small" title={d().a.metadata.cwd}>{d().a.metadata.cwd || "—"}</span>
                    <span class="v b-side mono-small" title={d().b.metadata.cwd}>{d().b.metadata.cwd || "—"}</span>
                  </div>
                  <Show when={d().common_ancestor}>
                    <div class="aether-compare-row">
                      <span class="k">ancestor</span>
                      <span class="v mono-small" title={d().common_ancestor}>
                        {shortId(d().common_ancestor)}
                      </span>
                    </div>
                  </Show>
                </div>

                <div class="aether-compare-section">
                  <div class="aether-compare-section-title">
                    cognition diff
                    <span class="aether-compare-count">
                      {d().cognition_diff.edit_count}
                      {d().cognition_diff.truncated ? " (truncated)" : ""}
                    </span>
                  </div>
                  <Show
                    when={d().cognition_diff.edits.length > 0}
                    fallback={<div class="aether-compare-empty">no cognitive divergence</div>}
                  >
                    <div class="aether-compare-edits">
                      <For each={d().cognition_diff.edits}>
                        {(ed) => (
                          <div class={`aether-compare-edit edit-${ed.type}`}>
                            <span class="aether-compare-edit-type">{ed.type}</span>
                            <span class="aether-compare-edit-path">{ed.path}</span>
                            <span class="aether-compare-edit-summary">{ed.summary}</span>
                          </div>
                        )}
                      </For>
                    </div>
                  </Show>
                </div>

                <div class="aether-compare-section">
                  <div class="aether-compare-section-title">
                    filesystem diff
                    <span class="aether-compare-count">
                      +{d().filesystem_diff.added.length}
                      {" "}/ −{d().filesystem_diff.removed.length}
                      {" "}/ ~{d().filesystem_diff.changed.length}
                    </span>
                  </div>
                  <Show when={d().filesystem_diff.added.length > 0}>
                    <div class="aether-compare-fs-group added">
                      <For each={d().filesystem_diff.added}>
                        {(f) => (
                          <div class="aether-compare-fs-row">
                            <span class="op">+</span>
                            <span class="path">{f.path}</span>
                            <span class="size">{formatBytes(f.size)}</span>
                          </div>
                        )}
                      </For>
                    </div>
                  </Show>
                  <Show when={d().filesystem_diff.removed.length > 0}>
                    <div class="aether-compare-fs-group removed">
                      <For each={d().filesystem_diff.removed}>
                        {(f) => (
                          <div class="aether-compare-fs-row">
                            <span class="op">−</span>
                            <span class="path">{f.path}</span>
                            <span class="size">{formatBytes(f.size)}</span>
                          </div>
                        )}
                      </For>
                    </div>
                  </Show>
                  <Show when={d().filesystem_diff.changed.length > 0}>
                    <div class="aether-compare-fs-group changed">
                      <For each={d().filesystem_diff.changed}>
                        {(f) => (
                          <div class="aether-compare-fs-row">
                            <span class="op">~</span>
                            <span class="path">{f.path}</span>
                            <span class="size">
                              {formatBytes(f.size_a)} → {formatBytes(f.size_b)}
                            </span>
                          </div>
                        )}
                      </For>
                    </div>
                  </Show>
                  <Show
                    when={d().filesystem_diff.added.length === 0
                      && d().filesystem_diff.removed.length === 0
                      && d().filesystem_diff.changed.length === 0}
                  >
                    <div class="aether-compare-empty">no filesystem divergence</div>
                  </Show>
                </div>

                <div class="aether-compare-foot">
                  <kbd>Esc</kbd> close
                </div>
              </>
            )}
          </Show>
        </div>
      </div>
    );
  }

  function statusBar() {
    const total = aetherStore.nodes().length;
    const sel = aetherStore.selectedId();
    return (
      <div class="aether-status">
        <span class="dim">aether</span>
        <span class="sep">·</span>
        <span>{total} stars</span>
        <Show when={sel}>
          <span class="sep">·</span>
          <span>focus {shortId(sel!)}</span>
          <span class="sep">·</span>
          <span class="dim">{aetherStore.focusSet().size} in lineage</span>
        </Show>
        <Show when={aetherStore.usingFixture()}>
          <span class="sep">·</span>
          <span class="warn">fixture mode</span>
        </Show>
        <Show when={!aetherStore.usingFixture()}>
          <span class="sep">·</span>
          <span class={aetherStore.liveConnected() ? "live-on" : "live-off"}>
            {aetherStore.liveConnected() ? "● live" : "○ offline"}
          </span>
        </Show>
        <span class="sep">·</span>
        <span class="dim">press / to prompt</span>
      </div>
    );
  }

  function promptBar() {
    const parent = aetherStore.selectedId();
    return (
      <div class={`aether-prompt ${promptOpen() ? "open" : ""}`}>
        <Show when={promptOpen()}>
          <div class="aether-prompt-head">
            <span class="aether-prompt-label">
              {parent ? `fork from ${shortId(parent)}` : "spawn new agent"}
            </span>
            <button
              class="aether-prompt-close"
              onClick={() => { setPromptOpen(false); setPrompt(""); setPromptError(null); }}
              title="Close (Esc)"
            >
              ✕
            </button>
          </div>
          <input
            ref={promptInputRef!}
            class="aether-prompt-input"
            value={prompt()}
            placeholder="what should the agent do?"
            disabled={promptBusy()}
            onInput={(e) => setPrompt(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") { e.preventDefault(); submitPrompt(); }
              if (e.key === "Escape") {
                e.preventDefault();
                setPromptOpen(false);
                setPrompt("");
                setPromptError(null);
              }
            }}
          />
          <div class="aether-prompt-foot">
            <Show when={promptError()} fallback={
              <span class="aether-prompt-hint">
                {promptBusy()
                  ? "spawning…"
                  : "Enter to send · Esc to cancel · use | for parallel variants"}
              </span>
            }>
              <span class="aether-prompt-err">{promptError()}</span>
            </Show>
          </div>
        </Show>
      </div>
    );
  }

  return (
    <div class="aether-root">
      <canvas
        ref={canvasRef!}
        class="aether-canvas"
        style={{ cursor: isDragging() ? "grabbing" : aetherStore.hoveredId() ? "pointer" : "grab" }}
        onMouseDown={onMouseDown}
        onMouseMove={onMouseMove}
        onMouseUp={onMouseUp}
        onMouseLeave={onMouseLeave}
      />
      <Show when={aetherStore.hoveredId() && aetherStore.hoveredId() !== aetherStore.selectedId()}>
        <div
          class="aether-hud"
          style={{
            left: `${Math.min(mousePos().x + 16, window.innerWidth - 220)}px`,
            top: `${Math.min(mousePos().y + 16, window.innerHeight - 160)}px`,
          }}
        >
          {hudFor(aetherStore.hoveredId()!)}
        </div>
      </Show>
      <Show when={aetherStore.selectedId()}>
        {detailPanelFor(aetherStore.selectedId()!)}
      </Show>
      {promptBar()}
      {statusBar()}
      <Show when={toast()}>
        <div class={`aether-toast aether-toast-${toast()!.kind}`}>
          {toast()!.text}
        </div>
      </Show>
    </div>
  );
};

export default AetherMap;
