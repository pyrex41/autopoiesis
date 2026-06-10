/**
 * SB product-loop store (Slice 3b-ii). Backs the Board view: the kanban board,
 * the deliberation gate (decisions + dissent), and the "why did we decide X"
 * provenance panel. Reads from /api/sb/*. Refreshes after each action and on a
 * light poll (matching the runs.ts polling idiom; SB SSE uses named events the
 * shared subscribeEvents helper doesn't surface).
 */
import { createSignal } from "solid-js";
import {
  getSbBoard, listSbDecisions, getSbWhy,
  claimNext, resolveSbDecision, addSbInput, createSbDecision, seedSb, moveTicket,
  type SbBoard, type SbDecision, type SbWhyRow,
} from "../api/client";

const [board, setBoard] = createSignal<SbBoard | null>(null);
const [decisions, setDecisions] = createSignal<SbDecision[]>([]);
const [why, setWhy] = createSignal<SbWhyRow[]>([]);
const [error, setError] = createSignal<string | null>(null);
const [busy, setBusy] = createSignal(false);

async function refresh(): Promise<void> {
  try {
    const [b, d, w] = await Promise.all([getSbBoard(), listSbDecisions(), getSbWhy()]);
    setBoard(b);
    setDecisions(d);
    setWhy(w);
    setError(null);
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
  }
}

async function withRefresh(fn: () => Promise<unknown>): Promise<void> {
  setBusy(true);
  try {
    await fn();
    await refresh();
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
  } finally {
    setBusy(false);
  }
}

export const sbStore = {
  board,
  decisions,
  why,
  error,
  busy,
  refresh,
  seed: () => withRefresh(() => seedSb()),
  claim: (from: string, to: string) => withRefresh(() => claimNext(from, to)),
  move: (id: string, to: string) => withRefresh(() => moveTicket(id, to)),
  addInput: (id: string, user: string, text: string) => withRefresh(() => addSbInput(id, user, text)),
  resolve: (id: string, lead: string, resolution: string) => withRefresh(() => resolveSbDecision(id, lead, resolution)),
  createDecision: (name: string, question: string, ticket?: string) =>
    withRefresh(() => createSbDecision(name, question, ticket)),
};
