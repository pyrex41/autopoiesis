//! egui: toast notifications for events.

use std::time::Instant;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use crate::protocol::events::*;

#[derive(Debug, Clone)]
pub struct Toast {
    pub message: String,
    pub color: egui::Color32,
    pub created: Instant,
    pub duration_secs: f32,
}

impl Toast {
    pub fn new(message: String, color: egui::Color32) -> Self {
        Self { message, color, created: Instant::now(), duration_secs: 5.0 }
    }
    pub fn is_expired(&self) -> bool {
        self.created.elapsed().as_secs_f32() > self.duration_secs
    }
    pub fn alpha(&self) -> f32 {
        let elapsed = self.created.elapsed().as_secs_f32();
        let fade_start = self.duration_secs - 1.0;
        if elapsed > fade_start { 1.0 - (elapsed - fade_start) } else { 1.0 }
    }
}

#[derive(Resource, Default)]
pub struct ToastQueue { pub toasts: Vec<Toast> }

pub fn collect_notifications(
    mut queue: ResMut<ToastQueue>,
    mut ev_connected: EventReader<BackendConnected>,
    mut ev_disconnected: EventReader<BackendDisconnected>,
    mut ev_agent_created: EventReader<AgentCreatedEvent>,
    mut ev_agent_state: EventReader<AgentStateChangedEvent>,
    mut ev_snapshot_created: EventReader<SnapshotCreatedEvent>,
    mut ev_blocking: EventReader<BlockingRequestEvent>,
) {
    for _ev in ev_connected.read() {
        queue.toasts.push(Toast::new("Connected to backend".into(), egui::Color32::from_rgb(0, 255, 136)));
    }
    for ev in ev_disconnected.read() {
        queue.toasts.push(Toast::new(format!("Disconnected: {}", ev.reason), egui::Color32::from_rgb(255, 51, 68)));
    }
    for ev in ev_agent_created.read() {
        queue.toasts.push(Toast::new(format!("Agent created: {}", ev.agent.name), egui::Color32::from_rgb(0, 200, 255)));
    }
    for ev in ev_agent_state.read() {
        queue.toasts.push(Toast::new(format!("Agent {:?} -> {:?}", ev.agent_id, ev.state), egui::Color32::from_rgb(255, 170, 0)));
    }
    for ev in ev_snapshot_created.read() {
        queue.toasts.push(Toast::new(
            format!("Snapshot created: {}", ev.snapshot.metadata.as_deref().unwrap_or(&ev.snapshot.id)),
            egui::Color32::from_rgb(255, 215, 0),
        ));
    }
    for ev in ev_blocking.read() {
        queue.toasts.push(Toast::new(format!("Blocking request: {}", ev.request.prompt), egui::Color32::from_rgb(255, 100, 50)));
    }
}

pub fn render_notifications(mut contexts: EguiContexts, mut queue: ResMut<ToastQueue>) {
    queue.toasts.retain(|t| !t.is_expired());
    if queue.toasts.is_empty() { return; }
    egui::Area::new(egui::Id::new("notifications"))
        .anchor(egui::Align2::RIGHT_TOP, egui::vec2(-10.0, 30.0))
        .show(contexts.ctx_mut(), |ui| {
            ui.set_max_width(300.0);
            let mut to_remove = Vec::new();
            for (idx, toast) in queue.toasts.iter().enumerate() {
                let alpha = (toast.alpha() * 255.0) as u8;
                let bg = egui::Color32::from_rgba_premultiplied(20, 20, 40, alpha.min(200));
                let text_color = egui::Color32::from_rgba_unmultiplied(toast.color.r(), toast.color.g(), toast.color.b(), alpha);
                let frame = egui::Frame::default()
                    .fill(bg)
                    .inner_margin(8.0)
                    .outer_margin(egui::Margin::symmetric(0, 2))
                    .corner_radius(4.0);
                let response = frame.show(ui, |ui| {
                    ui.label(egui::RichText::new(&toast.message).color(text_color).size(12.0));
                });
                if response.response.clicked() { to_remove.push(idx); }
            }
            for idx in to_remove.into_iter().rev() { queue.toasts.remove(idx); }
        });
}
