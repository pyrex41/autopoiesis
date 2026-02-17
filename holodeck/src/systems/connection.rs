//! System: drain crossbeam channel, emit Bevy events, update connection status.

use bevy::prelude::*;
use bevy::ecs::system::SystemParam;

use crate::protocol::client::ConnectionEvent;
use crate::protocol::events::*;
use crate::protocol::types::*;
use crate::state::resources::*;

#[derive(SystemParam)]
pub struct BackendEventWriters<'w> {
    pub ev_sysinfo: EventWriter<'w, SystemInfoReceived>,
    pub ev_agent_list: EventWriter<'w, AgentListReceived>,
    pub ev_agent_created: EventWriter<'w, AgentCreatedEvent>,
    pub ev_agent_state: EventWriter<'w, AgentStateChangedEvent>,
    pub ev_thought_list: EventWriter<'w, ThoughtListReceived>,
    pub ev_thought: EventWriter<'w, ThoughtReceivedEvent>,
    pub ev_snapshot_list: EventWriter<'w, SnapshotListReceived>,
    pub ev_snapshot_created: EventWriter<'w, SnapshotCreatedEvent>,
    pub ev_branch_list: EventWriter<'w, BranchListReceived>,
    pub ev_branch_created: EventWriter<'w, BranchCreatedEvent>,
    pub ev_branch_switched: EventWriter<'w, BranchSwitchedEvent>,
    pub ev_blocking_list: EventWriter<'w, BlockingRequestListReceived>,
    pub ev_blocking: EventWriter<'w, BlockingRequestEvent>,
    pub ev_blocking_responded: EventWriter<'w, BlockingRespondedEvent>,
    pub ev_backend: EventWriter<'w, BackendEvent>,
}

pub fn drain_ws_channel(
    ws_inbound: Res<WsInbound>,
    mut connection_status: ResMut<ConnectionStatus>,
    mut agent_registry: ResMut<AgentRegistry>,
    mut thought_cache: ResMut<ThoughtCache>,
    mut blocking_reqs: ResMut<BlockingRequests>,
    mut snapshot_tree: ResMut<SnapshotTree>,
    mut ev_connected: EventWriter<BackendConnected>,
    mut ev_disconnected: EventWriter<BackendDisconnected>,
    mut ev_reconnecting: EventWriter<BackendReconnecting>,
    mut writers: BackendEventWriters,
) {
    for event in ws_inbound.0.try_iter() {
        match event {
            ConnectionEvent::Connected => {
                connection_status.state = ConnectionState::Connected;
                ev_connected.send(BackendConnected);
            }
            ConnectionEvent::Disconnected(reason) => {
                connection_status.state = ConnectionState::Disconnected;
                ev_disconnected.send(BackendDisconnected { reason });
            }
            ConnectionEvent::Reconnecting { attempt } => {
                connection_status.state = ConnectionState::Reconnecting { attempt };
                ev_reconnecting.send(BackendReconnecting { attempt });
            }
            ConnectionEvent::Message(msg) => {
                dispatch_server_message(msg, &mut connection_status, &mut agent_registry,
                    &mut thought_cache, &mut blocking_reqs, &mut snapshot_tree, &mut writers);
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn dispatch_server_message(
    msg: ServerMessage, cs: &mut ConnectionStatus, ar: &mut AgentRegistry,
    tc: &mut ThoughtCache, br: &mut BlockingRequests, st: &mut SnapshotTree,
    w: &mut BackendEventWriters,
) {
    match msg {
        ServerMessage::Pong | ServerMessage::Subscribed { .. } | ServerMessage::Unsubscribed { .. } | ServerMessage::StreamFormatSet => {}
        ServerMessage::SystemInfo(info) => {
            cs.server_version = info.version.clone();
            cs.agent_count = info.agent_count;
            cs.connection_count = info.connection_count;
            w.ev_sysinfo.send(SystemInfoReceived(info));
        }
        ServerMessage::Agents { agents } => {
            for a in &agents { ar.upsert(a.clone()); }
            cs.agent_count = agents.len() as u32;
            w.ev_agent_list.send(AgentListReceived { agents });
        }
        ServerMessage::Agent { agent } => {
            ar.upsert(agent.clone());
            w.ev_agent_list.send(AgentListReceived { agents: vec![agent] });
        }
        ServerMessage::AgentCreated { agent } => {
            ar.upsert(agent.clone());
            cs.agent_count = ar.agents.len() as u32;
            w.ev_agent_created.send(AgentCreatedEvent { agent });
        }
        ServerMessage::AgentStateChanged { agent_id, state } => {
            ar.update_state(agent_id, state.clone());
            w.ev_agent_state.send(AgentStateChangedEvent { agent_id, state });
        }
        ServerMessage::StepComplete { .. } => {}
        ServerMessage::Thoughts { thoughts, total } => {
            tc.thoughts = thoughts.clone();
            w.ev_thought_list.send(ThoughtListReceived { thoughts, total });
        }
        ServerMessage::ThoughtAdded { agent_id, thought } => {
            if tc.agent_id == Some(agent_id) { tc.thoughts.push(thought.clone()); }
            w.ev_thought.send(ThoughtReceivedEvent { agent_id, thought });
        }
        ServerMessage::Snapshots { snapshots } => {
            for s in &snapshots { st.upsert(s.clone()); }
            w.ev_snapshot_list.send(SnapshotListReceived { snapshots });
        }
        ServerMessage::Snapshot { snapshot, .. } => {
            st.upsert(snapshot.clone());
            w.ev_snapshot_list.send(SnapshotListReceived { snapshots: vec![snapshot] });
        }
        ServerMessage::SnapshotCreated { snapshot } => {
            st.upsert(snapshot.clone());
            w.ev_snapshot_created.send(SnapshotCreatedEvent { snapshot });
        }
        ServerMessage::Branches { branches, current } => {
            st.current_branch = current.clone();
            w.ev_branch_list.send(BranchListReceived { branches, current });
        }
        ServerMessage::BranchCreated { branch } => {
            w.ev_branch_created.send(BranchCreatedEvent { name: branch.name });
        }
        ServerMessage::BranchSwitched { branch } => {
            st.current_branch = Some(branch.name.clone());
            w.ev_branch_switched.send(BranchSwitchedEvent { name: branch.name });
        }
        ServerMessage::BlockingRequests { requests } => {
            br.requests = requests.clone();
            w.ev_blocking_list.send(BlockingRequestListReceived { requests });
        }
        ServerMessage::BlockingRequest { request } => {
            br.requests.push(request.clone());
            w.ev_blocking.send(BlockingRequestEvent { request });
        }
        ServerMessage::BlockingResponded { blocking_request_id } => {
            br.requests.retain(|r| r.id != blocking_request_id);
            w.ev_blocking_responded.send(BlockingRespondedEvent { request_id: blocking_request_id });
        }
        ServerMessage::Events { events } => {
            for e in events { w.ev_backend.send(BackendEvent { event: e }); }
        }
        ServerMessage::Event { event } => { w.ev_backend.send(BackendEvent { event }); }
        ServerMessage::Unknown => {}
    }
}

pub fn forward_outbound_messages(
    ws_outbound: Res<WsOutbound>,
    mut ev_create_agent: EventReader<crate::state::events::SendCreateAgent>,
    mut ev_agent_action: EventReader<crate::state::events::SendAgentAction>,
    mut ev_step_agent: EventReader<crate::state::events::SendStepAgent>,
    mut ev_inject: EventReader<crate::state::events::SendInjectThought>,
    mut ev_snapshot: EventReader<crate::state::events::SendCreateSnapshot>,
    mut ev_respond: EventReader<crate::state::events::SendRespondBlocking>,
    mut ev_get_thoughts: EventReader<crate::state::events::SendGetThoughts>,
) {
    for ev in ev_create_agent.read() {
        let _ = ws_outbound.0.send(ClientMessage::CreateAgent { name: ev.name.clone(), capabilities: ev.capabilities.clone() });
    }
    for ev in ev_agent_action.read() {
        let _ = ws_outbound.0.send(ClientMessage::AgentAction { agent_id: ev.agent_id, action: ev.action.clone() });
    }
    for ev in ev_step_agent.read() {
        let _ = ws_outbound.0.send(ClientMessage::StepAgent { agent_id: ev.agent_id, environment: None });
    }
    for ev in ev_inject.read() {
        let _ = ws_outbound.0.send(ClientMessage::InjectThought { agent_id: ev.agent_id, content: ev.content.clone(), thought_type: ev.thought_type.clone() });
    }
    for ev in ev_snapshot.read() {
        let _ = ws_outbound.0.send(ClientMessage::CreateSnapshot { agent_id: ev.agent_id, label: ev.label.clone() });
    }
    for ev in ev_respond.read() {
        let _ = ws_outbound.0.send(ClientMessage::RespondBlocking { blocking_request_id: ev.request_id.clone(), response: ev.response.clone() });
    }
    for ev in ev_get_thoughts.read() {
        let _ = ws_outbound.0.send(ClientMessage::GetThoughts { agent_id: ev.agent_id, limit: Some(ev.limit) });
    }
}
