import { createSignal } from "solid-js";
import type { AuditEntry } from "../api/types";
import * as api from "../api/client";

const [entries, setEntries] = createSignal<AuditEntry[]>([]);
const [loading, setLoading] = createSignal(false);
const [hasMore, setHasMore] = createSignal(true);

const PAGE_SIZE = 50;

async function loadEntries(opts?: { agent?: string; type?: string; append?: boolean }) {
  setLoading(true);
  try {
    const data = await api.getAuditLog({
      agent: opts?.agent,
      type: opts?.type,
      limit: PAGE_SIZE,
    });
    if (opts?.append) {
      setEntries((prev) => [...prev, ...data]);
    } else {
      setEntries(data);
    }
    setHasMore(data.length >= PAGE_SIZE);
  } catch { /* non-critical */ }
  setLoading(false);
}

function init() {
  loadEntries();
}

export const auditStore = {
  entries,
  loading,
  hasMore,
  init,
  loadEntries,
};
