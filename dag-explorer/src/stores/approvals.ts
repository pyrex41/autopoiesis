import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";
import type { Approval } from "../api/types";
import * as api from "../api/client";

const [approvals, setApprovals] = createSignal<Approval[]>([]);

const pendingCount = createMemo(() =>
  approvals().filter((a) => a.status === "pending").length
);

async function loadApprovals() {
  try {
    const data = await api.listApprovals();
    setApprovals(Array.isArray(data) ? data : []);
  } catch { /* non-critical */ }
}

async function approve(id: string, response?: string) {
  try {
    await api.approveRequest(id, response);
    setApprovals((prev) => prev.filter((a) => a.id !== id));
  } catch { /* ignore */ }
}

async function reject(id: string, reason?: string) {
  try {
    await api.rejectRequest(id, reason);
    setApprovals((prev) => prev.filter((a) => a.id !== id));
  } catch { /* ignore */ }
}

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "blocking_requests": {
      const list = (msg as any).requests;
      if (Array.isArray(list)) setApprovals(list);
      break;
    }
    case "blocking_request": {
      const req = (msg as any).request;
      if (req) {
        setApprovals((prev) => {
          const idx = prev.findIndex((a) => a.id === req.id);
          if (idx >= 0) {
            const next = [...prev];
            next[idx] = req;
            return next;
          }
          return [...prev, req];
        });
      }
      break;
    }
    case "blocking_responded": {
      const id = (msg as any).blockingRequestId as string;
      if (id) setApprovals((prev) => prev.filter((a) => a.id !== id));
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  loadApprovals();
}

export const approvalsStore = {
  approvals,
  pendingCount,
  init,
  loadApprovals,
  approve,
  reject,
};
