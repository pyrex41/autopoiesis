import { type Component, For, Show } from "solid-js";
import { teamStore, type TeamData } from "../stores/teams";
import EmptyState from "./EmptyState";

const statusDotClass = (status: string) =>
  `team-status-dot team-status-dot-${status}`;

const statusLabelClass = (status: string) =>
  `team-status-label team-status-label-${status}`;

const TeamPanel: Component = () => {
  return (
    <div class="team-panel">
      <div class="team-panel-header">
        <h2 class="team-panel-title">Teams</h2>
        <button
          class="team-panel-create-btn"
          onClick={() => window.dispatchEvent(new CustomEvent("ap:create-team"))}
          title="Create team"
        >
          +
        </button>
      </div>

      <div class="team-panel-list">
        <Show
          when={teamStore.teams().length > 0}
          fallback={<EmptyState icon="mesh" title="No Teams" description="Create a team to coordinate multiple agents." />}
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
      classList={{
        "team-card": true,
        "team-card-selected": props.selected,
      }}
      onClick={props.onClick}
    >
      <div class="team-card-header">
        <div class="team-card-name-row">
          <div class={statusDotClass(props.team.status)} />
          <span class="team-card-name">{props.team.id}</span>
        </div>
        <div class="team-card-meta">
          <Show when={props.team.strategy}>
            <span class="team-strategy-badge">{props.team.strategy}</span>
          </Show>
          <span class={statusLabelClass(props.team.status)}>
            {props.team.status}
          </span>
        </div>
      </div>

      <Show when={props.selected && props.team.members.length > 0}>
        <div class="team-members">
          <For each={props.team.members}>
            {(member, idx) => (
              <div class="team-member-row">
                <span class="team-member-prefix">
                  {member === props.team.leader
                    ? "\u2605 "
                    : idx() === props.team.members.length - 1
                    ? "\u2514 "
                    : "\u251C "}
                </span>
                <span class="team-member-name">
                  {member}
                  <Show when={member === props.team.leader}>
                    <span class="team-leader-tag"> (leader)</span>
                  </Show>
                </span>
              </div>
            )}
          </For>
        </div>
      </Show>

      <Show when={!props.selected && props.team.memberCount > 0}>
        <div class="team-member-count">
          {props.team.memberCount} member{props.team.memberCount !== 1 ? "s" : ""}
        </div>
      </Show>
    </button>
  );
};

export default TeamPanel;
