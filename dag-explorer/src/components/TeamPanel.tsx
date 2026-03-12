import { type Component, For, Show, createSignal } from "solid-js";
import { teamStore, type TeamData } from "../stores/teams";

const statusColors: Record<string, string> = {
  active: "var(--emerge)",
  created: "var(--signal)",
  paused: "var(--warm)",
  completed: "var(--text-dim)",
  failed: "var(--danger)",
};

const TeamPanel: Component = () => {
  return (
    <div style={panelStyle}>
      <div style={headerStyle}>
        <h2 style={titleStyle}>Teams</h2>
        <button
          style={createBtnStyle}
          onClick={() => window.dispatchEvent(new CustomEvent("ap:create-team"))}
          title="Create team"
        >
          +
        </button>
      </div>

      <div style={listStyle}>
        <Show
          when={teamStore.teams().length > 0}
          fallback={<div style={emptyStyle}>No teams yet</div>}
        >
          <For each={teamStore.teams()}>
            {(team) => (
              <TeamCard
                team={team}
                selected={teamStore.selectedTeamId() === team.id}
                onClick={() => teamStore.selectTeam(
                  teamStore.selectedTeamId() === team.id ? null : team.id
                )}
              />
            )}
          </For>
        </Show>
      </div>
    </div>
  );
};

const TeamCard: Component<{
  team: TeamData;
  selected: boolean;
  onClick: () => void;
}> = (props) => {
  return (
    <button
      style={{
        ...cardStyle,
        ...(props.selected ? cardSelectedStyle : {}),
      }}
      onClick={props.onClick}
    >
      <div style={cardHeaderStyle}>
        <div style={cardNameRowStyle}>
          <div
            style={{
              ...dotStyle,
              background: statusColors[props.team.status] ?? "var(--text-dim)",
            }}
          />
          <span style={cardNameStyle}>{props.team.id}</span>
        </div>
        <div style={cardMetaStyle}>
          <Show when={props.team.strategy}>
            <span style={strategyBadgeStyle}>{props.team.strategy}</span>
          </Show>
          <span
            style={{
              ...statusLabelStyle,
              color: statusColors[props.team.status] ?? "var(--text-dim)",
            }}
          >
            {props.team.status}
          </span>
        </div>
      </div>

      <Show when={props.selected && props.team.members.length > 0}>
        <div style={membersStyle}>
          <For each={props.team.members}>
            {(member, idx) => (
              <div style={memberRowStyle}>
                <span style={memberPrefixStyle}>
                  {member === props.team.leader
                    ? "\u2605 "
                    : idx() === props.team.members.length - 1
                    ? "\u2514 "
                    : "\u251C "}
                </span>
                <span style={memberNameStyle}>
                  {member}
                  <Show when={member === props.team.leader}>
                    <span style={leaderTagStyle}> (leader)</span>
                  </Show>
                </span>
              </div>
            )}
          </For>
        </div>
      </Show>

      <Show when={!props.selected && props.team.memberCount > 0}>
        <div style={memberCountStyle}>
          {props.team.memberCount} member{props.team.memberCount !== 1 ? "s" : ""}
        </div>
      </Show>
    </button>
  );
};

// ── Styles ───────────────────────────────────────────────────────

const panelStyle: Record<string, string> = {
  "border-top": "1px solid var(--border)",
  padding: "8px 0",
  "flex-shrink": "0",
};

const headerStyle: Record<string, string> = {
  display: "flex",
  "align-items": "center",
  "justify-content": "space-between",
  padding: "0 12px 6px",
};

const titleStyle: Record<string, string> = {
  "font-family": "var(--font-display)",
  "font-size": "11px",
  "font-weight": "600",
  color: "var(--text-muted)",
  "text-transform": "uppercase",
  "letter-spacing": "0.8px",
};

const createBtnStyle: Record<string, string> = {
  width: "22px",
  height: "22px",
  display: "flex",
  "align-items": "center",
  "justify-content": "center",
  background: "var(--surface)",
  border: "1px solid var(--border)",
  "border-radius": "var(--radius)",
  color: "var(--signal)",
  "font-size": "14px",
  cursor: "pointer",
  transition: "all var(--transition)",
};

const listStyle: Record<string, string> = {
  "max-height": "200px",
  "overflow-y": "auto",
  padding: "0 8px",
};

const emptyStyle: Record<string, string> = {
  padding: "12px",
  "text-align": "center",
  color: "var(--text-dim)",
  "font-size": "11px",
};

const cardStyle: Record<string, string> = {
  display: "block",
  width: "100%",
  "text-align": "left",
  padding: "8px 10px",
  background: "transparent",
  border: "1px solid transparent",
  "border-radius": "var(--radius)",
  cursor: "pointer",
  "font-family": "var(--font-mono)",
  "font-size": "11px",
  color: "var(--text)",
  transition: "all var(--transition)",
  "margin-bottom": "2px",
};

const cardSelectedStyle: Record<string, string> = {
  background: "rgba(79, 195, 247, 0.06)",
  "border-color": "rgba(79, 195, 247, 0.2)",
};

const cardHeaderStyle: Record<string, string> = {
  display: "flex",
  "align-items": "center",
  "justify-content": "space-between",
  gap: "6px",
};

const cardNameRowStyle: Record<string, string> = {
  display: "flex",
  "align-items": "center",
  gap: "6px",
  "min-width": "0",
};

const dotStyle: Record<string, string> = {
  width: "6px",
  height: "6px",
  "border-radius": "50%",
  "flex-shrink": "0",
};

const cardNameStyle: Record<string, string> = {
  "font-weight": "600",
  overflow: "hidden",
  "text-overflow": "ellipsis",
  "white-space": "nowrap",
};

const cardMetaStyle: Record<string, string> = {
  display: "flex",
  "align-items": "center",
  gap: "6px",
  "flex-shrink": "0",
};

const strategyBadgeStyle: Record<string, string> = {
  "font-size": "9px",
  color: "var(--purple)",
  background: "rgba(179, 136, 255, 0.1)",
  padding: "1px 5px",
  "border-radius": "2px",
  "white-space": "nowrap",
};

const statusLabelStyle: Record<string, string> = {
  "font-size": "10px",
};

const membersStyle: Record<string, string> = {
  "margin-top": "6px",
  "padding-left": "12px",
};

const memberRowStyle: Record<string, string> = {
  display: "flex",
  "align-items": "center",
  "line-height": "1.6",
};

const memberPrefixStyle: Record<string, string> = {
  color: "var(--text-dim)",
  "font-size": "11px",
  "white-space": "pre",
};

const memberNameStyle: Record<string, string> = {
  color: "var(--text-muted)",
  "font-size": "11px",
};

const leaderTagStyle: Record<string, string> = {
  color: "var(--warm)",
  "font-size": "9px",
};

const memberCountStyle: Record<string, string> = {
  "margin-top": "3px",
  "font-size": "10px",
  color: "var(--text-dim)",
};

export default TeamPanel;
