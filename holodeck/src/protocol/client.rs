//! WebSocket client running on a dedicated background thread.
//!
//! Communication with the Bevy main loop is entirely through lock-free
//! crossbeam channels — the game loop never blocks on I/O.

use std::thread;
use std::time::Duration;

use crossbeam_channel::{Receiver, Sender, TryRecvError};
use tracing::{error, info, warn};
use tungstenite::{connect, Message};

use crate::protocol::codec;
use crate::protocol::types::{ClientMessage, ServerMessage};

/// Default backend WebSocket URL.
pub const DEFAULT_WS_URL: &str = "ws://localhost:8080/ws";

/// Maximum reconnection backoff in seconds.
const MAX_BACKOFF_SECS: u64 = 30;

/// Status updates sent from the WS thread to Bevy.
#[derive(Debug, Clone)]
pub enum ConnectionEvent {
    Connected,
    Disconnected(String),
    Reconnecting { attempt: u32 },
    Message(ServerMessage),
}

/// Spawn the WebSocket client thread.
///
/// Returns the inbound receiver (server → Bevy) and the outbound sender
/// (Bevy → server). The thread automatically reconnects with exponential
/// backoff on disconnect.
pub fn spawn_ws_thread(
    url: &str,
) -> (Receiver<ConnectionEvent>, Sender<ClientMessage>) {
    let (inbound_tx, inbound_rx) = crossbeam_channel::unbounded::<ConnectionEvent>();
    let (outbound_tx, outbound_rx) = crossbeam_channel::unbounded::<ClientMessage>();
    let url = url.to_owned();

    thread::Builder::new()
        .name("ws-client".into())
        .spawn(move || {
            ws_loop(&url, &inbound_tx, &outbound_rx);
        })
        .expect("failed to spawn WebSocket thread");

    (inbound_rx, outbound_tx)
}

/// Core reconnect loop — runs forever on the background thread.
fn ws_loop(
    url: &str,
    inbound_tx: &Sender<ConnectionEvent>,
    outbound_rx: &Receiver<ClientMessage>,
) {
    let mut attempt: u32 = 0;

    loop {
        attempt += 1;
        let backoff = Duration::from_secs((1u64 << attempt.min(5)).min(MAX_BACKOFF_SECS));

        info!("WebSocket connecting to {url} (attempt {attempt})");
        let _ = inbound_tx.send(ConnectionEvent::Reconnecting { attempt });

        match connect(url) {
            Ok((mut socket, _response)) => {
                info!("WebSocket connected to {url}");
                attempt = 0;
                let _ = inbound_tx.send(ConnectionEvent::Connected);

                // On connect, request JSON stream format for easy debugging
                // and subscribe to key channels.
                let init_msgs = [
                    ClientMessage::SetStreamFormat {
                        format: "json".into(),
                    },
                    ClientMessage::Subscribe {
                        channel: "agents".into(),
                    },
                    ClientMessage::Subscribe {
                        channel: "events".into(),
                    },
                    ClientMessage::SystemInfo,
                    ClientMessage::ListAgents,
                ];

                let mut init_failed = false;
                for msg in &init_msgs {
                    if let Ok(json) = codec::encode_client_message(msg) {
                        if socket.send(Message::Text(json)).is_err() {
                            init_failed = true;
                            break;
                        }
                    }
                }

                if init_failed {
                    warn!("Failed to send init messages, reconnecting");
                    let _ = inbound_tx.send(ConnectionEvent::Disconnected(
                        "init send failed".into(),
                    ));
                    thread::sleep(backoff);
                    continue;
                }

                // Set the socket to non-blocking so we can interleave
                // reading server messages with draining outbound queue.
                if let tungstenite::stream::MaybeTlsStream::Plain(ref s) =
                    socket.get_ref()
                {
                    let _ = s.set_nonblocking(true);
                }

                // Main read/write loop
                'connected: loop {
                    // --- Drain outbound queue (Bevy → server) ---
                    loop {
                        match outbound_rx.try_recv() {
                            Ok(msg) => {
                                if let Ok(json) = codec::encode_client_message(&msg) {
                                    if socket.send(Message::Text(json)).is_err() {
                                        break 'connected;
                                    }
                                }
                            }
                            Err(TryRecvError::Empty) => break,
                            Err(TryRecvError::Disconnected) => {
                                info!("Outbound channel closed, shutting down WS thread");
                                return;
                            }
                        }
                    }

                    // --- Read from server ---
                    match socket.read() {
                        Ok(Message::Text(text)) => {
                            match codec::decode_text_frame(&text) {
                                Ok(msg) => {
                                    let _ =
                                        inbound_tx.send(ConnectionEvent::Message(msg));
                                }
                                Err(e) => {
                                    warn!("Failed to decode text frame: {e}");
                                }
                            }
                        }
                        Ok(Message::Binary(data)) => {
                            match codec::decode_binary_frame(&data) {
                                Ok(msg) => {
                                    let _ =
                                        inbound_tx.send(ConnectionEvent::Message(msg));
                                }
                                Err(e) => {
                                    warn!("Failed to decode binary frame: {e}");
                                }
                            }
                        }
                        Ok(Message::Ping(data)) => {
                            let _ = socket.send(Message::Pong(data));
                        }
                        Ok(Message::Pong(_)) => {}
                        Ok(Message::Close(_)) => {
                            info!("Server sent close frame");
                            break 'connected;
                        }
                        Ok(Message::Frame(_)) => {}
                        Err(tungstenite::Error::Io(ref e))
                            if e.kind() == std::io::ErrorKind::WouldBlock =>
                        {
                            // Non-blocking: no data available right now.
                            // Sleep briefly to avoid busy-spinning.
                            thread::sleep(Duration::from_millis(1));
                        }
                        Err(e) => {
                            warn!("WebSocket read error: {e}");
                            break 'connected;
                        }
                    }
                }

                let _ = inbound_tx.send(ConnectionEvent::Disconnected(
                    "connection lost".into(),
                ));
            }
            Err(e) => {
                error!("WebSocket connection failed: {e}");
                let _ = inbound_tx.send(ConnectionEvent::Disconnected(format!("{e}")));
            }
        }

        info!("Reconnecting in {backoff:?}");
        thread::sleep(backoff);
    }
}
