import { createSignal, createMemo } from "solid-js";
import { wsStore, type ServerMessage } from "./ws";

// ── Types ────────────────────────────────────────────────────────

export interface TeamData {
  id: string;
  status: string; // "created" | "active" | "paused" | "completed" | "failed"
  task: string | null;
  leader: string | null;
  members: string[];
  memberCount: number;
  workspaceId: string | null;
  strategy: string | null;
  config: any;
  createdAt: string;
}

// ── Signals ──────────────────────────────────────────────────────

const [teams, setTeams] = createSignal<TeamData[]>([]);
const [selectedTeamId, setSelectedTeamId] = createSignal<string | null>(null);

// ── Derived ──────────────────────────────────────────────────────

const selectedTeam = createMemo(() => {
  const id = selectedTeamId();
  if (!id) return null;
  return teams().find((t) => t.id === id) ?? null;
});

const teamsByStatus = createMemo(() => {
  const map: Record<string, TeamData[]> = {};
  for (const t of teams()) {
    (map[t.status] ??= []).push(t);
  }
  return map;
});

const activeTeams = createMemo(() => {
  return teams().filter((t) => t.status === "active");
});

// ── Helpers ──────────────────────────────────────────────────────

function parseTeamData(raw: any): TeamData {
  return {
    id: raw.id ?? "",
    status: raw.status ?? "created",
    task: raw.task ?? null,
    leader: raw.leader ?? null,
    members: Array.isArray(raw.members) ? raw.members : [],
    memberCount: raw.memberCount ?? raw.member_count ?? 0,
    workspaceId: raw.workspaceId ?? raw.workspace_id ?? null,
    strategy: raw.strategy ?? null,
    config: raw.config ?? null,
    createdAt: raw.createdAt ?? raw.created_at ?? "",
  };
}

// ── Actions ──────────────────────────────────────────────────────

function loadTeams() {
  wsStore.send({ type: "list_teams" } as any);
}

function createTeam(
  name: string,
  strategy: string,
  members?: string[],
  leader?: string,
  task?: string,
) {
  const msg: any = { type: "create_team", name, strategy };
  if (members && members.length > 0) msg.members = members;
  if (leader) msg.leader = leader;
  if (task) msg.task = task;
  wsStore.send(msg);
}

function startTeam(teamId: string) {
  wsStore.send({ type: "start_team", teamId } as any);
}

function disbandTeam(teamId: string) {
  wsStore.send({ type: "disband_team", teamId } as any);
}

function addMember(teamId: string, agentName: string) {
  wsStore.send({ type: "add_team_member", teamId, agentName } as any);
}

function removeMember(teamId: string, agentName: string) {
  wsStore.send({ type: "remove_team_member", teamId, agentName } as any);
}

function selectTeam(id: string | null) {
  const prev = selectedTeamId();
  if (prev) wsStore.unsubscribe(`team:${prev}`);
  setSelectedTeamId(id);
  if (id) wsStore.subscribe(`team:${id}`);
}

// ── WS Handling ──────────────────────────────────────────────────

function handleWSMessage(msg: ServerMessage) {
  switch (msg.type) {
    case "teams": {
      // List response
      const list = msg.teams;
      if (Array.isArray(list)) {
        setTeams(list.map(parseTeamData));
      }
      break;
    }

    case "team_created": {
      const team = msg.team as any;
      if (team) {
        setTeams((prev) => [...prev, parseTeamData(team)]);
      }
      break;
    }

    case "team_started": {
      const teamId = msg.teamId as string;
      if (teamId) {
        setTeams((prev) =>
          prev.map((t) => (t.id === teamId ? { ...t, status: "active" } : t))
        );
      }
      break;
    }

    case "team_disbanded": {
      const teamId = msg.teamId as string;
      if (teamId) {
        setTeams((prev) => prev.filter((t) => t.id !== teamId));
        if (selectedTeamId() === teamId) {
          setSelectedTeamId(null);
        }
      }
      break;
    }

    case "team_member_added": {
      const teamId = msg.teamId as string;
      const agentName = msg.agentName as string;
      if (teamId && agentName) {
        setTeams((prev) =>
          prev.map((t) =>
            t.id === teamId
              ? { ...t, members: [...t.members, agentName], memberCount: t.memberCount + 1 }
              : t
          )
        );
      }
      break;
    }

    case "team_member_removed": {
      const teamId = msg.teamId as string;
      const agentName = msg.agentName as string;
      if (teamId && agentName) {
        setTeams((prev) =>
          prev.map((t) =>
            t.id === teamId
              ? {
                  ...t,
                  members: t.members.filter((m) => m !== agentName),
                  memberCount: Math.max(0, t.memberCount - 1),
                }
              : t
          )
        );
      }
      break;
    }

    case "team_detail": {
      const team = msg.team as any;
      if (team) {
        const parsed = parseTeamData(team);
        setTeams((prev) => {
          const idx = prev.findIndex((t) => t.id === parsed.id);
          if (idx >= 0) {
            const next = [...prev];
            next[idx] = parsed;
            return next;
          }
          return [...prev, parsed];
        });
      }
      break;
    }

    case "team_state_changed": {
      const teamId = msg.teamId as string;
      const status = msg.status as string;
      if (teamId && status) {
        setTeams((prev) =>
          prev.map((t) => (t.id === teamId ? { ...t, status } : t))
        );
      }
      break;
    }
  }
}

function init() {
  wsStore.onMessage(handleWSMessage);
  wsStore.subscribe("teams");
  loadTeams();
}

// ── Export ────────────────────────────────────────────────────────

export const teamStore = {
  // Data
  teams,
  selectedTeamId,
  selectedTeam,
  teamsByStatus,
  activeTeams,

  // Actions
  init,
  loadTeams,
  createTeam,
  startTeam,
  disbandTeam,
  addMember,
  removeMember,
  selectTeam,
};
