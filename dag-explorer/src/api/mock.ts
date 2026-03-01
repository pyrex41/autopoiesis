import type { Snapshot, Branch } from "./types";

let idCounter = 0;
function uid(): string {
  return `snap-${String(++idCounter).padStart(4, "0")}`;
}

function hashOf(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = ((h << 5) - h + s.charCodeAt(i)) | 0;
  return Math.abs(h).toString(16).padStart(8, "0");
}

/**
 * Generate a realistic DAG of snapshot histories.
 *
 * Produces a main trunk with several branches forking off,
 * some branches forking further (sub-branches), and varying
 * depths. Metadata includes agent names, labels, and tags
 * so the explorer has rich data to display.
 */
export function generateMockDAG(opts?: {
  trunkLength?: number;
  branchCount?: number;
  maxBranchDepth?: number;
}): { snapshots: Snapshot[]; branches: Branch[] } {
  const trunkLen = opts?.trunkLength ?? 30;
  const branchCount = opts?.branchCount ?? 6;
  const maxBranchDepth = opts?.maxBranchDepth ?? 12;

  const snapshots: Snapshot[] = [];
  const branches: Branch[] = [];

  const agents = [
    "architect",
    "debugger",
    "researcher",
    "optimizer",
    "guardian",
    "explorer",
  ];
  const labels = [
    "initial observation",
    "reasoning step",
    "decision point",
    "action taken",
    "reflection",
    "hypothesis formed",
    "experiment started",
    "result analyzed",
    "strategy revised",
    "capability acquired",
    "anomaly detected",
    "recovery initiated",
  ];
  const tags = [
    "cognitive-cycle",
    "learning",
    "self-modification",
    "tool-use",
    "collaboration",
    "error-recovery",
  ];

  const baseTime = Date.now() / 1000 - 3600; // 1 hour ago

  // Build trunk
  const trunk: Snapshot[] = [];
  for (let i = 0; i < trunkLen; i++) {
    const id = uid();
    const snap: Snapshot = {
      id,
      timestamp: baseTime + i * 45,
      parent: i > 0 ? trunk[i - 1].id : null,
      hash: hashOf(id),
      metadata: {
        agent: agents[0],
        label: labels[i % labels.length],
        tags: [tags[i % tags.length]],
        thoughtCount: 10 + i * 3,
      },
    };
    trunk.push(snap);
    snapshots.push(snap);
  }

  branches.push({
    name: "main",
    head: trunk[trunk.length - 1].id,
    created: baseTime,
  });

  // Fork branches off the trunk at various points
  for (let b = 0; b < branchCount; b++) {
    const forkIdx = Math.floor(
      ((b + 1) / (branchCount + 1)) * (trunkLen - 2)
    ) + 1;
    const forkPoint = trunk[forkIdx];
    const depth = 3 + Math.floor(Math.random() * (maxBranchDepth - 3));
    const agentIdx = (b + 1) % agents.length;
    const branchName = `${agents[agentIdx]}/experiment-${b + 1}`;

    const branchSnaps: Snapshot[] = [];
    for (let j = 0; j < depth; j++) {
      const id = uid();
      const snap: Snapshot = {
        id,
        timestamp: forkPoint.timestamp + (j + 1) * 30 + b * 5,
        parent: j === 0 ? forkPoint.id : branchSnaps[j - 1].id,
        hash: hashOf(id),
        metadata: {
          agent: agents[agentIdx],
          branch: branchName,
          label: labels[(b + j) % labels.length],
          tags: [tags[(b + j) % tags.length]],
          thoughtCount: 5 + j * 2,
        },
      };
      branchSnaps.push(snap);
      snapshots.push(snap);
    }

    branches.push({
      name: branchName,
      head: branchSnaps[branchSnaps.length - 1].id,
      created: forkPoint.timestamp,
    });

    // Sub-branch off this branch (1 in 3 chance, at midpoint)
    if (b % 3 === 0 && branchSnaps.length > 4) {
      const subForkIdx = Math.floor(branchSnaps.length / 2);
      const subFork = branchSnaps[subForkIdx];
      const subDepth = 2 + Math.floor(Math.random() * 5);
      const subName = `${branchName}/fork`;

      let prevId = subFork.id;
      let lastId = prevId;
      for (let k = 0; k < subDepth; k++) {
        const id = uid();
        const snap: Snapshot = {
          id,
          timestamp: subFork.timestamp + (k + 1) * 25,
          parent: prevId,
          hash: hashOf(id),
          metadata: {
            agent: agents[(agentIdx + 1) % agents.length],
            branch: subName,
            label: labels[(b + k + 3) % labels.length],
            tags: ["sub-experiment"],
            thoughtCount: 3 + k,
          },
        };
        snapshots.push(snap);
        prevId = id;
        lastId = id;
      }

      branches.push({
        name: subName,
        head: lastId,
        created: subFork.timestamp,
      });
    }
  }

  return { snapshots, branches };
}
