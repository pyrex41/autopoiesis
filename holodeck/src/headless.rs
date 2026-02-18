//! Headless rendering setup for the Autopoiesis Holodeck.
//!
//! Provides a Bevy App configured for headless rendering without a window.
//! Renders to an image target that can be captured and processed.

use bevy::prelude::*;
use bevy::render::camera::RenderTarget;
use bevy::render::RenderPlugin;
use crossbeam_channel::{bounded, Receiver};
use std::sync::Arc;
use tokio::sync::{mpsc, watch};

use crate::protocol::events::BackendEvent;
use crate::protocol::types::ServerMessage;

/// Plugin for headless rendering setup.
pub struct HeadlessPlugin;

impl Plugin for HeadlessPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup_headless_camera)
            .add_systems(Update, copy_frame_to_buffer);
    }
}

/// Plugin that bridges Nexus WebSocket events to Bevy events.
pub struct NexusBridgePlugin {
    pub event_rx: Receiver<ServerMessage>,
}

impl Plugin for NexusBridgePlugin {
    fn build(&self, app: &mut App) {
        let event_rx = self.event_rx.clone();
        app.add_event::<BackendEvent>()
            .add_systems(Update, move |mut backend_events: EventWriter<BackendEvent>| {
                // Drain all available events from the channel
                while let Ok(msg) = event_rx.try_recv() {
                    match msg {
                        ServerMessage::Event { event } => {
                            backend_events.send(BackendEvent { event });
                        }
                        _ => {} // Ignore other message types for now
                    }
                }
            });
    }
}

/// Sets up a camera that renders to an image target for headless rendering.
fn setup_headless_camera(mut commands: Commands, mut images: ResMut<Assets<Image>>) {
    // Create a new image to render to
    let image = Image::new_fill(
        bevy::render::render_resource::Extent3d {
            width: 1920,
            height: 1080,
            depth_or_array_layers: 1,
        },
        bevy::render::render_resource::TextureDimension::D2,
        &[0, 0, 0, 255],
        bevy::render::render_resource::TextureFormat::Rgba8UnormSrgb,
        default(),
    );
    let image_handle = images.add(image);

    // Spawn a camera that renders to the image
    commands.spawn((
        Camera3d::default(),
        Camera {
            target: RenderTarget::Image(image_handle.clone()),
            hdr: true,
            ..default()
        },
        Transform::from_translation(Vec3::new(0.0, 15.0, 25.0)).looking_at(Vec3::ZERO, Vec3::Y),
    ));

    // Store the image handle as a resource for later access
    commands.insert_resource(HeadlessRenderTarget(image_handle));
}

/// Copies the rendered frame to the shared buffer each frame.
fn copy_frame_to_buffer(
    images: Res<Assets<Image>>,
    render_target: Res<HeadlessRenderTarget>,
    headless_resource: Option<Res<HeadlessHolodeckResource>>,
) {
    if let Some(headless_res) = headless_resource {
        if let Some(image) = images.get(&render_target.0) {
            // Copy the RGBA data to the shared buffer
            let rgba_data = image.data.clone();
            // Send the frame data (ignore if channel is full)
            let _ = headless_res.0.frame_tx.send(rgba_data);
        }
    }
}

/// Resource containing the render target image handle.
#[derive(Resource)]
pub struct HeadlessRenderTarget(pub Handle<Image>);

/// Resource containing the headless holodeck instance.
#[derive(Resource)]
pub struct HeadlessHolodeckResource(pub Arc<HeadlessHolodeck>);

/// Headless Holodeck struct for external integration.
pub struct HeadlessHolodeck {
    /// Receiver for frame data (RGBA bytes)
    pub frame_rx: watch::Receiver<Vec<u8>>,
    /// Sender for WebSocket events to feed into Bevy
    pub event_tx: mpsc::Sender<ServerMessage>,
    /// Frame width
    pub width: u32,
    /// Frame height
    pub height: u32,
    /// Internal frame sender
    frame_tx: watch::Sender<Vec<u8>>,
    /// Internal event receiver
    event_rx: Receiver<ServerMessage>,
}

impl HeadlessHolodeck {
    /// Creates a new HeadlessHolodeck instance.
    pub fn new(width: u32, height: u32) -> Self {
        let (frame_tx, frame_rx) = watch::channel(Vec::new());
        let (event_tx, event_rx) = mpsc::channel(256);
        let (event_tx_sync, event_rx_sync) = bounded(256);

        // Bridge async event channel to sync channel
        tokio::spawn(async move {
            let mut event_rx_async = event_rx;
            while let Some(msg) = event_rx_async.recv().await {
                let _ = event_tx_sync.send(msg);
            }
        });

        Self {
            frame_rx,
            event_tx,
            width,
            height,
            frame_tx,
            event_rx: event_rx_sync,
        }
    }

    /// Returns the NexusBridgePlugin configured for this instance.
    pub fn bridge_plugin(&self) -> NexusBridgePlugin {
        NexusBridgePlugin {
            event_rx: self.event_rx.clone(),
        }
    }
}

/// Creates and returns a headless Bevy App for rendering.
///
/// The app includes MinimalPlugins and RenderPlugin, plus the HeadlessPlugin
/// for camera setup. This allows rendering scenes without a display window.
pub fn create_headless_app() -> App {
    let mut app = App::new();

    app.add_plugins(MinimalPlugins)
        .add_plugins(RenderPlugin::default())
        .add_plugins(HeadlessPlugin);

    app
}
