import { createSignal, createMemo, batch } from "solid-js";
import type {
  Snapshot,
  Branch,
  LayoutGraph,
  LayoutDirection,
  ColorScheme,
  SelectionState,
} from "../api/types";
import { computeLayout, findAncestors, findDescendants, findPath } from "../graph/layout";
import { generateMockDAG } from "../api/mock";
import * as api from "../api/client";

// ── Raw data signals ──────────────────────────────────────────────

const [snapshots, setSnapshots] = createSignal<Snapshot[]>([]);
const [branches, setBranches] = createSignal<Branch[]>([]);
const [loading, setLoading] = createSignal(false);
const [error, setError] = createSignal<string | null>(null);
const [dataSource, setDataSource] = createSignal<"mock" | "live">("mock");

// ── UI state signals ──────────────────────────────────────────────

const [selection, setSelection] = createSignal<SelectionState>({
  primary: null,
  secondary: null,
  highlighted: new Set(),
});
const [collapsed, setCollapsed] = createSignal<Set<string>>(new Set());
const [direction, setDirection] = createSignal<LayoutDirection>("TB");
const [colorScheme, setColorScheme] = createSignal<ColorScheme>("branch");
const [searchQuery, setSearchQuery] = createSignal("");
const [showCommandPalette, setShowCommandPalette] = createSignal(false);
const [hoveredNode, setHoveredNode] = createSignal<string | null>(null);
const [detailPanelOpen, setDetailPanelOpen] = createSignal(true);
const [diffMode, setDiffMode] = createSignal(false);
const [diffResult, setDiffResult] = createSignal<string | null>(null);

// ── Derived data ──────────────────────────────────────────────────

const layout = createMemo<LayoutGraph>(() => {
  const snaps = snapshots();
  if (snaps.length === 0) {
    return { nodes: new Map(), edges: [], width: 0, height: 0 };
  }
  return computeLayout(snaps, branches(), {
    direction: direction(),
    collapsed: collapsed(),
  });
});

const snapshotById = createMemo(() => {
  const map = new Map<string, Snapshot>();
  for (const s of snapshots()) map.set(s.id, s);
  return map;
});

const searchResults = createMemo(() => {
  const q = searchQuery().toLowerCase().trim();
  if (!q) return null;
  return snapshots().filter((s) => {
    if (s.id.toLowerCase().includes(q)) return true;
    if (s.hash?.toLowerCase().includes(q)) return true;
    const meta = s.metadata;
    if (meta) {
      const str = JSON.stringify(meta).toLowerCase();
      if (str.includes(q)) return true;
    }
    return false;
  });
});

const highlightedPath = createMemo(() => {
  const sel = selection();
  if (!sel.primary || !sel.secondary) return null;
  return findPath(sel.primary, sel.secondary, snapshots());
});

const primaryAncestors = createMemo(() => {
  const sel = selection();
  if (!sel.primary) return new Set<string>();
  return findAncestors(sel.primary, snapshots());
});

const primaryDescendants = createMemo(() => {
  const sel = selection();
  if (!sel.primary) return new Set<string>();
  return findDescendants(sel.primary, snapshots());
});

// ── Actions ───────────────────────────────────────────────────────

async function loadFromAPI() {
  setLoading(true);
  setError(null);
  setDataSource("live");
  try {
    const [snaps, br] = await Promise.all([
      api.listSnapshots(),
      api.listBranches(),
    ]);
    batch(() => {
      setSnapshots(snaps);
      setBranches(br);
    });
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
    // Fall back to mock
    loadMockData();
  } finally {
    setLoading(false);
  }
}

function loadMockData() {
  setDataSource("mock");
  const { snapshots: snaps, branches: br } = generateMockDAG();
  batch(() => {
    setSnapshots(snaps);
    setBranches(br);
    setError(null);
  });
}

function selectNode(id: string | null, secondary = false) {
  setSelection((prev) => {
    if (secondary) {
      return { ...prev, secondary: id, highlighted: prev.highlighted };
    }
    return {
      primary: id,
      secondary: prev.primary !== id ? prev.secondary : null,
      highlighted: prev.highlighted,
    };
  });
}

function toggleCollapse(id: string) {
  setCollapsed((prev) => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    return next;
  });
}

function clearSelection() {
  setSelection({ primary: null, secondary: null, highlighted: new Set() });
}

async function computeDiff() {
  const sel = selection();
  if (!sel.primary || !sel.secondary) return;
  if (dataSource() === "mock") {
    setDiffResult(
      `--- ${sel.primary}\n+++ ${sel.secondary}\n@@ mock diff @@\n` +
        `- (agent-state :id "${sel.primary}" ...)\n` +
        `+ (agent-state :id "${sel.secondary}" ...)`
    );
    return;
  }
  try {
    const result = await api.diffSnapshots(sel.primary, sel.secondary);
    setDiffResult(result.diff);
  } catch (e) {
    setDiffResult(`Error: ${e instanceof Error ? e.message : String(e)}`);
  }
}

// Navigate to the next sibling (same parent, next child)
function navigateToSibling(offset: number) {
  const sel = selection();
  if (!sel.primary) return;
  const snap = snapshotById().get(sel.primary);
  if (!snap?.parent) return;
  const siblings = snapshots().filter((s) => s.parent === snap.parent);
  const idx = siblings.findIndex((s) => s.id === sel.primary);
  const next = siblings[idx + offset];
  if (next) selectNode(next.id);
}

// Navigate to parent
function navigateToParent() {
  const sel = selection();
  if (!sel.primary) return;
  const snap = snapshotById().get(sel.primary);
  if (snap?.parent) selectNode(snap.parent);
}

// Navigate to first child
function navigateToChild() {
  const sel = selection();
  if (!sel.primary) return;
  const child = snapshots().find((s) => s.parent === sel.primary);
  if (child) selectNode(child.id);
}

// ── Export store ──────────────────────────────────────────────────

export const dagStore = {
  // Data
  snapshots,
  branches,
  layout,
  snapshotById,
  loading,
  error,
  dataSource,

  // Selection
  selection,
  hoveredNode,
  setHoveredNode,
  highlightedPath,
  primaryAncestors,
  primaryDescendants,

  // UI state
  collapsed,
  direction,
  setDirection,
  colorScheme,
  setColorScheme,
  searchQuery,
  setSearchQuery,
  searchResults,
  showCommandPalette,
  setShowCommandPalette,
  detailPanelOpen,
  setDetailPanelOpen,
  diffMode,
  setDiffMode,
  diffResult,
  setDiffResult,

  // Actions
  loadFromAPI,
  loadMockData,
  selectNode,
  toggleCollapse,
  clearSelection,
  computeDiff,
  navigateToSibling,
  navigateToParent,
  navigateToChild,
};
