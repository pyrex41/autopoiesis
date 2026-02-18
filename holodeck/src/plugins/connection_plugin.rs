//! Bundles connection systems + resources.

use crate::protocol::client;
use crate::protocol::events::*;
use crate::state::events::*;
use crate::state::resources::*;
use crate::systems::connection;
use bevy::prelude::*;

pub struct ConnectionPlugin {
    pub ws_url: String,
}

impl Default for ConnectionPlugin {
    fn default() -> Self {
        Self {
            ws_url: client::DEFAULT_WS_URL.to_string(),
        }
    }
}

impl Plugin for ConnectionPlugin {
    fn build(&self, app: &mut App) {
        let (inbound_rx, outbound_tx) = client::spawn_ws_thread(&self.ws_url);
        app.insert_resource(WsInbound(inbound_rx))
            .insert_resource(WsOutbound(outbound_tx))
            .init_resource::<ConnectionStatus>()
            .init_resource::<AgentRegistry>()
            .init_resource::<SelectedAgent>()
            .init_resource::<SnapshotTree>()
            .init_resource::<ThoughtCache>()
            .init_resource::<BlockingRequests>()
            .add_event::<BackendConnected>()
            .add_event::<BackendDisconnected>()
            .add_event::<BackendReconnecting>()
            .add_event::<SystemInfoReceived>()
            .add_event::<AgentListReceived>()
            .add_event::<AgentCreatedEvent>()
            .add_event::<AgentStateChangedEvent>()
            .add_event::<ThoughtListReceived>()
            .add_event::<ThoughtReceivedEvent>()
            .add_event::<SnapshotListReceived>()
            .add_event::<SnapshotCreatedEvent>()
            .add_event::<BranchListReceived>()
            .add_event::<BranchCreatedEvent>()
            .add_event::<BranchSwitchedEvent>()
            .add_event::<BlockingRequestListReceived>()
            .add_event::<BlockingRequestEvent>()
            .add_event::<BlockingRespondedEvent>()
            .add_event::<StepCompleteEvent>()
            .add_event::<BackendEvent>()
            .add_event::<SendCreateAgent>()
            .add_event::<SendAgentAction>()
            .add_event::<SendStepAgent>()
            .add_event::<SendInjectThought>()
            .add_event::<SendCreateSnapshot>()
            .add_event::<SendRespondBlocking>()
            .add_event::<SendGetThoughts>()
            .add_event::<SelectAgentEvent>()
            .add_event::<DeselectEvent>()
            .add_event::<SendCommand>()
            .add_systems(Update, connection::drain_ws_channel)
            .add_systems(Update, connection::forward_outbound_messages);
    }
}
