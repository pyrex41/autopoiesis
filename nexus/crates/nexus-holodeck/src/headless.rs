use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::thread::JoinHandle;
use tokio::sync::{mpsc, watch};

use bevy::{
    app::{App, ScheduleRunnerPlugin},
    asset::Assets,
    color::Color,
    math::Vec3,
    pbr::StandardMaterial,
    prelude::*,
    render::{
        camera::RenderTarget,
        render_resource::{
            Extent3d, TextureDimension, TextureFormat, TextureUsages,
        },
    },
    utils::Duration,
};

/// Events that can be sent from the TUI to the Bevy thread.
#[derive(Clone, Debug)]
pub enum HolodeckEvent {
    MouseClick { x: f32, y: f32, button: u8 },
    KeyPress { key: String },
    Resize { width: u32, height: u32 },
    Shutdown,
}

/// Handle for controlling the headless holodeck from the TUI thread.
///
/// The holodeck runs Bevy in a dedicated std::thread (not tokio), rendering
/// to an offscreen image and streaming frames via a watch channel.
pub struct HeadlessHolodeck {
    /// Receive the latest RGBA frame data (latest-frame semantics).
    pub frame_rx: watch::Receiver<Vec<u8>>,
    /// Send input events to the Bevy thread.
    pub event_tx: mpsc::UnboundedSender<HolodeckEvent>,
    /// Frame dimensions.
    pub width: u32,
    pub height: u32,
    /// Thread join handle.
    thread_handle: Option<JoinHandle<()>>,
    /// Shared shutdown flag.
    shutdown: Arc<AtomicBool>,
}

impl HeadlessHolodeck {
    /// Start the headless holodeck renderer in a dedicated thread.
    ///
    /// The Bevy app runs at ~30fps with a minimal scene (grid + colored cubes).
    /// Frame data is sent as raw RGBA bytes via the watch channel.
    pub fn start(width: u32, height: u32) -> Self {
        let (frame_tx, frame_rx) = watch::channel(Vec::new());
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let shutdown = Arc::new(AtomicBool::new(false));
        let shutdown_clone = shutdown.clone();

        let thread_handle = std::thread::Builder::new()
            .name("holodeck-bevy".to_string())
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    run_bevy_app(width, height, frame_tx, event_rx, shutdown_clone);
                }));

                if let Err(e) = result {
                    tracing::error!("Holodeck Bevy thread panicked: {:?}", e);
                }
            })
            .expect("Failed to spawn holodeck thread");

        Self {
            frame_rx,
            event_tx,
            width,
            height,
            thread_handle: Some(thread_handle),
            shutdown,
        }
    }

    /// Stop the holodeck renderer and wait for the thread to finish.
    pub fn stop(&mut self) {
        self.shutdown.store(true, Ordering::SeqCst);
        let _ = self.event_tx.send(HolodeckEvent::Shutdown);
        if let Some(handle) = self.thread_handle.take() {
            let _ = handle.join();
        }
    }

    /// Check if the Bevy thread is still running.
    pub fn is_running(&self) -> bool {
        !self.shutdown.load(Ordering::SeqCst)
            && self
                .thread_handle
                .as_ref()
                .map(|h| !h.is_finished())
                .unwrap_or(false)
    }

    /// Send an input event to the Bevy thread.
    pub fn send_event(&self, event: HolodeckEvent) {
        let _ = self.event_tx.send(event);
    }
}

impl Drop for HeadlessHolodeck {
    fn drop(&mut self) {
        self.stop();
    }
}

// === Bevy App Setup ===

/// Resource holding the frame sender and event receiver for the Bevy app.
#[derive(Resource)]
struct HolodeckChannels {
    frame_tx: watch::Sender<Vec<u8>>,
    event_rx: Arc<Mutex<mpsc::UnboundedReceiver<HolodeckEvent>>>,
    shutdown: Arc<AtomicBool>,
}

/// Resource holding the render target image handle and dimensions.
#[derive(Resource)]
struct RenderTargetImage {
    handle: Handle<Image>,
    #[allow(dead_code)]
    width: u32,
    #[allow(dead_code)]
    height: u32,
}

/// Marker component for the holodeck camera.
#[derive(Component)]
struct HolodeckCamera;

/// Marker for agent cube entities.
#[derive(Component)]
struct AgentCube {
    #[allow(dead_code)]
    index: usize,
}

/// Marker for the grid plane.
#[derive(Component)]
struct GridPlane;

/// Resource storing frame dimensions for the setup system.
#[derive(Resource)]
struct FrameDimensions {
    width: u32,
    height: u32,
}

/// Run the Bevy app in headless mode. This blocks the calling thread.
fn run_bevy_app(
    width: u32,
    height: u32,
    frame_tx: watch::Sender<Vec<u8>>,
    event_rx: mpsc::UnboundedReceiver<HolodeckEvent>,
    shutdown: Arc<AtomicBool>,
) {
    let mut app = App::new();

    // DefaultPlugins with window disabled for headless rendering
    app.add_plugins(
        DefaultPlugins
            .set(WindowPlugin {
                primary_window: None,
                exit_condition: bevy::window::ExitCondition::DontExit,
                close_when_requested: false,
            }),
    );

    // Schedule runner for headless loop at 30fps
    app.add_plugins(ScheduleRunnerPlugin::run_loop(Duration::from_secs_f64(
        1.0 / 30.0,
    )));

    // Insert resources
    app.insert_resource(HolodeckChannels {
        frame_tx,
        event_rx: Arc::new(Mutex::new(event_rx)),
        shutdown,
    });
    app.insert_resource(FrameDimensions { width, height });

    // Setup systems
    app.add_systems(Startup, setup_scene);
    app.add_systems(Update, (process_events, extract_and_send_frame, check_shutdown));

    app.run();
}

/// Setup the offscreen render target, camera, and initial scene.
fn setup_scene(
    mut commands: Commands,
    mut images: ResMut<Assets<Image>>,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    dimensions: Res<FrameDimensions>,
) {
    let width = dimensions.width;
    let height = dimensions.height;

    // Create the render target image
    let size = Extent3d {
        width,
        height,
        depth_or_array_layers: 1,
    };

    let mut render_image = Image::new_fill(
        size,
        TextureDimension::D2,
        &[0, 0, 0, 255],
        TextureFormat::Rgba8UnormSrgb,
        default(),
    );
    render_image.texture_descriptor.usage =
        TextureUsages::TEXTURE_BINDING
        | TextureUsages::COPY_SRC
        | TextureUsages::RENDER_ATTACHMENT;

    let image_handle = images.add(render_image);

    // Store the render target handle
    commands.insert_resource(RenderTargetImage {
        handle: image_handle.clone(),
        width,
        height,
    });

    // Camera targeting the offscreen image (Bevy 0.15 API: use Camera3d component)
    commands.spawn((
        Camera3d::default(),
        Camera {
            target: RenderTarget::Image(image_handle),
            ..default()
        },
        Transform::from_xyz(5.0, 5.0, 5.0).looking_at(Vec3::ZERO, Vec3::Y),
        HolodeckCamera,
    ));

    // Grid plane (Bevy 0.15: use Mesh3d + MeshMaterial3d)
    commands.spawn((
        Mesh3d(meshes.add(Plane3d::default().mesh().size(10.0, 10.0))),
        MeshMaterial3d(materials.add(StandardMaterial {
            base_color: Color::srgb(0.15, 0.15, 0.2),
            ..default()
        })),
        GridPlane,
    ));

    // Agent cubes - colored to represent different agents
    let agent_colors = [
        Color::srgb(0.0, 0.8, 1.0),  // Cyan
        Color::srgb(1.0, 0.3, 0.3),  // Red
        Color::srgb(0.3, 1.0, 0.3),  // Green
        Color::srgb(1.0, 0.8, 0.0),  // Yellow
    ];

    let cube_mesh = meshes.add(Cuboid::new(0.8, 0.8, 0.8));

    for (i, color) in agent_colors.iter().enumerate() {
        let x = (i as f32 - 1.5) * 2.0;
        commands.spawn((
            Mesh3d(cube_mesh.clone()),
            MeshMaterial3d(materials.add(StandardMaterial {
                base_color: *color,
                ..default()
            })),
            Transform::from_xyz(x, 0.4, 0.0),
            AgentCube { index: i },
        ));
    }

    // Directional light (Bevy 0.15: use DirectionalLight component directly)
    commands.spawn((
        DirectionalLight {
            illuminance: 10000.0,
            shadows_enabled: false,
            ..default()
        },
        Transform::from_rotation(Quat::from_euler(
            EulerRot::XYZ,
            -std::f32::consts::FRAC_PI_4,
            std::f32::consts::FRAC_PI_4,
            0.0,
        )),
    ));

    // Ambient light
    commands.insert_resource(AmbientLight {
        color: Color::WHITE,
        brightness: 200.0,
    });
}

/// Process input events from the TUI and animate the camera.
fn process_events(
    channels: Res<HolodeckChannels>,
    mut camera_query: Query<&mut Transform, With<HolodeckCamera>>,
    time: Res<Time>,
) {
    // Slowly rotate camera for visual interest
    if let Ok(mut transform) = camera_query.get_single_mut() {
        let angle = time.elapsed_secs() * 0.2;
        let radius = 7.0;
        transform.translation = Vec3::new(
            angle.cos() * radius,
            5.0,
            angle.sin() * radius,
        );
        transform.look_at(Vec3::ZERO, Vec3::Y);
    }

    // Drain events
    if let Ok(mut rx) = channels.event_rx.lock() {
        while let Ok(event) = rx.try_recv() {
            match event {
                HolodeckEvent::Shutdown => {
                    channels.shutdown.store(true, Ordering::SeqCst);
                }
                HolodeckEvent::Resize { .. } => {
                    // TODO: resize render target
                }
                HolodeckEvent::MouseClick { .. } | HolodeckEvent::KeyPress { .. } => {
                    // TODO: forward input to scene
                }
            }
        }
    }
}

/// Extract the rendered frame from the image asset and send it via watch channel.
fn extract_and_send_frame(
    channels: Res<HolodeckChannels>,
    images: Res<Assets<Image>>,
    render_target: Option<Res<RenderTargetImage>>,
) {
    let Some(target) = render_target else { return };

    if let Some(image) = images.get(&target.handle) {
        let data = image.data.clone();
        if !data.is_empty() {
            let _ = channels.frame_tx.send(data);
        }
    }
}

/// Check if we should shut down the Bevy app.
fn check_shutdown(channels: Res<HolodeckChannels>, mut exit: EventWriter<AppExit>) {
    if channels.shutdown.load(Ordering::SeqCst) {
        exit.send(AppExit::Success);
    }
}

// === Test helper ===

/// Create channel infrastructure without spawning a Bevy thread.
///
/// Useful for testing TUI integration without GPU access.
/// Returns (frame_tx, frame_rx, event_tx, event_rx) - keep event_rx alive to allow sends.
pub fn create_test_holodeck(width: u32, height: u32) -> (watch::Sender<Vec<u8>>, watch::Receiver<Vec<u8>>, mpsc::UnboundedSender<HolodeckEvent>, mpsc::UnboundedReceiver<HolodeckEvent>) {
    let (frame_tx, frame_rx) = watch::channel(Vec::new());
    let (event_tx, event_rx) = mpsc::unbounded_channel();
    let _ = (width, height); // dimensions are for documentation
    (frame_tx, frame_rx, event_tx, event_rx)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_holodeck_event_variants() {
        let _click = HolodeckEvent::MouseClick {
            x: 10.0,
            y: 20.0,
            button: 1,
        };
        let _key = HolodeckEvent::KeyPress {
            key: "ArrowUp".to_string(),
        };
        let _resize = HolodeckEvent::Resize {
            width: 800,
            height: 600,
        };
        let _shutdown = HolodeckEvent::Shutdown;
    }

    #[test]
    fn test_create_test_holodeck() {
        let (frame_tx, frame_rx, event_tx, _event_rx) = create_test_holodeck(320, 240);

        // Send a test frame
        let test_data = vec![128u8; 320 * 240 * 4];
        frame_tx.send(test_data.clone()).unwrap();

        // Receive it
        let received = frame_rx.borrow().clone();
        assert_eq!(received.len(), 320 * 240 * 4);

        // Send an event
        event_tx
            .send(HolodeckEvent::KeyPress {
                key: "Space".to_string(),
            })
            .unwrap();
    }

    #[test]
    fn test_test_holodeck_frame_streaming() {
        let (frame_tx, mut frame_rx, _event_tx, _event_rx) = create_test_holodeck(64, 64);

        // Initially empty
        assert!(frame_rx.borrow().is_empty());

        // Send frame 1
        let frame1 = vec![100u8; 64 * 64 * 4];
        frame_tx.send(frame1.clone()).unwrap();
        assert!(frame_rx.has_changed().unwrap());
        let received = frame_rx.borrow_and_update().clone();
        assert_eq!(received, frame1);

        // Send frame 2 — latest-frame semantics
        let frame2 = vec![200u8; 64 * 64 * 4];
        frame_tx.send(frame2.clone()).unwrap();
        assert!(frame_rx.has_changed().unwrap());
        let received = frame_rx.borrow_and_update().clone();
        assert_eq!(received, frame2);
    }
}
