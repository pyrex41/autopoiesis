use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::sync::{broadcast, mpsc};
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, error, info, warn};

use crate::codec;
use crate::error::ProtocolError;
use crate::types::{ClientMessage, ServerMessage};

/// Calculate reconnect delay with exponential backoff, capped at 30 seconds.
pub fn backoff_delay(attempt: u32) -> Duration {
    let exp = attempt.min(5);
    let secs = 2u64.pow(exp).min(30);
    Duration::from_secs(secs)
}

/// Messages the init sequence sends on connect.
pub fn init_sequence() -> Vec<ClientMessage> {
    vec![
        ClientMessage::SetStreamFormat {
            format: "json".to_string(),
        },
        ClientMessage::Subscribe {
            channel: "agents".to_string(),
        },
        ClientMessage::Subscribe {
            channel: "events".to_string(),
        },
        ClientMessage::SystemInfo,
        ClientMessage::ListAgents,
    ]
}

/// Handle for sending commands to the WebSocket client.
#[derive(Clone)]
pub struct WsHandle {
    outbound: mpsc::Sender<ClientMessage>,
}

impl WsHandle {
    /// Send a client message through the WebSocket connection.
    pub async fn send(&self, msg: ClientMessage) -> Result<(), ProtocolError> {
        self.outbound
            .send(msg)
            .await
            .map_err(|_| ProtocolError::ConnectionClosed)
    }
}

/// Configuration for the WebSocket client.
pub struct WsClientConfig {
    pub url: String,
    pub api_key: Option<String>,
}

/// Start the WebSocket client, returning a handle for sending and a receiver for incoming messages.
///
/// Spawns a background task that manages the connection with automatic reconnection.
pub fn start(
    config: WsClientConfig,
) -> (WsHandle, broadcast::Receiver<ServerMessage>) {
    let (outbound_tx, outbound_rx) = mpsc::channel::<ClientMessage>(256);
    let (inbound_tx, inbound_rx) = broadcast::channel::<ServerMessage>(512);

    let handle = WsHandle {
        outbound: outbound_tx,
    };

    tokio::spawn(connection_loop(config, outbound_rx, inbound_tx));

    (handle, inbound_rx)
}

async fn connection_loop(
    config: WsClientConfig,
    mut outbound_rx: mpsc::Receiver<ClientMessage>,
    inbound_tx: broadcast::Sender<ServerMessage>,
) {
    let mut attempt: u32 = 0;

    loop {
        let delay = backoff_delay(attempt);
        if attempt > 0 {
            info!(attempt, delay_secs = delay.as_secs(), "Reconnecting after delay");
            tokio::time::sleep(delay).await;
        }

        info!(url = %config.url, "Connecting to WebSocket");

        let ws_stream = match tokio_tungstenite::connect_async(&config.url).await {
            Ok((stream, _response)) => {
                info!("WebSocket connected");
                attempt = 0;
                stream
            }
            Err(e) => {
                error!(error = %e, "WebSocket connection failed");
                attempt = attempt.saturating_add(1);
                continue;
            }
        };

        let (mut ws_sink, mut ws_source) = ws_stream.split();

        // Send init sequence
        let mut init_failed = false;
        for msg in init_sequence() {
            match codec::encode_client_message(&msg) {
                Ok(json) => {
                    if let Err(e) = ws_sink.send(Message::Text(json)).await {
                        error!(error = %e, "Failed to send init message");
                        init_failed = true;
                        break;
                    }
                }
                Err(e) => {
                    error!(error = %e, "Failed to encode init message");
                }
            }
        }

        if init_failed {
            attempt = attempt.saturating_add(1);
            continue;
        }

        // Main select loop: multiplex WS read + outbound drain
        loop {
            tokio::select! {
                // Incoming WS frames
                frame = ws_source.next() => {
                    match frame {
                        Some(Ok(Message::Text(text))) => {
                            match codec::decode_text_frame(&text) {
                                Ok(server_msg) => {
                                    debug!(?server_msg, "Received server message");
                                    // Ignore send errors (no receivers)
                                    let _ = inbound_tx.send(server_msg);
                                }
                                Err(e) => {
                                    warn!(error = %e, "Failed to decode text frame");
                                }
                            }
                        }
                        Some(Ok(Message::Binary(data))) => {
                            match codec::decode_binary_frame(&data) {
                                Ok(server_msg) => {
                                    debug!(?server_msg, "Received binary server message");
                                    let _ = inbound_tx.send(server_msg);
                                }
                                Err(e) => {
                                    warn!(error = %e, "Failed to decode binary frame");
                                }
                            }
                        }
                        Some(Ok(Message::Ping(payload))) => {
                            debug!("Received Ping, sending Pong");
                            if let Err(e) = ws_sink.send(Message::Pong(payload)).await {
                                error!(error = %e, "Failed to send Pong");
                                break;
                            }
                        }
                        Some(Ok(Message::Pong(_))) => {
                            debug!("Received Pong");
                        }
                        Some(Ok(Message::Close(_))) => {
                            info!("Server sent Close frame");
                            break;
                        }
                        Some(Ok(Message::Frame(_))) => {
                            // Raw frame, ignore
                        }
                        Some(Err(e)) => {
                            error!(error = %e, "WebSocket read error");
                            break;
                        }
                        None => {
                            info!("WebSocket stream ended");
                            break;
                        }
                    }
                }
                // Outbound messages from the app
                outbound = outbound_rx.recv() => {
                    match outbound {
                        Some(client_msg) => {
                            match codec::encode_client_message(&client_msg) {
                                Ok(json) => {
                                    if let Err(e) = ws_sink.send(Message::Text(json)).await {
                                        error!(error = %e, "Failed to send outbound message");
                                        break;
                                    }
                                }
                                Err(e) => {
                                    error!(error = %e, "Failed to encode outbound message");
                                }
                            }
                        }
                        None => {
                            // All senders dropped, shut down
                            info!("Outbound channel closed, shutting down WS client");
                            let _ = ws_sink.send(Message::Close(None)).await;
                            return;
                        }
                    }
                }
            }
        }

        // Connection lost, retry
        attempt = attempt.saturating_add(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_backoff_delay_attempt_0() {
        assert_eq!(backoff_delay(0), Duration::from_secs(1));
    }

    #[test]
    fn test_backoff_delay_attempt_1() {
        assert_eq!(backoff_delay(1), Duration::from_secs(2));
    }

    #[test]
    fn test_backoff_delay_attempt_2() {
        assert_eq!(backoff_delay(2), Duration::from_secs(4));
    }

    #[test]
    fn test_backoff_delay_attempt_3() {
        assert_eq!(backoff_delay(3), Duration::from_secs(8));
    }

    #[test]
    fn test_backoff_delay_attempt_4() {
        assert_eq!(backoff_delay(4), Duration::from_secs(16));
    }

    #[test]
    fn test_backoff_delay_attempt_5() {
        assert_eq!(backoff_delay(5), Duration::from_secs(30));
    }

    #[test]
    fn test_backoff_delay_capped_at_30() {
        assert_eq!(backoff_delay(6), Duration::from_secs(30));
        assert_eq!(backoff_delay(10), Duration::from_secs(30));
        assert_eq!(backoff_delay(100), Duration::from_secs(30));
    }

    #[test]
    fn test_init_sequence_messages() {
        let msgs = init_sequence();
        assert_eq!(msgs.len(), 5);

        // Check each message type in order
        match &msgs[0] {
            ClientMessage::SetStreamFormat { format } => assert_eq!(format, "json"),
            _ => panic!("Expected SetStreamFormat"),
        }
        match &msgs[1] {
            ClientMessage::Subscribe { channel } => assert_eq!(channel, "agents"),
            _ => panic!("Expected Subscribe agents"),
        }
        match &msgs[2] {
            ClientMessage::Subscribe { channel } => assert_eq!(channel, "events"),
            _ => panic!("Expected Subscribe events"),
        }
        assert!(matches!(&msgs[3], ClientMessage::SystemInfo));
        assert!(matches!(&msgs[4], ClientMessage::ListAgents));
    }

    #[test]
    fn test_init_sequence_encodes() {
        // Verify all init messages can be encoded to JSON
        for msg in init_sequence() {
            let json = codec::encode_client_message(&msg).unwrap();
            assert!(!json.is_empty());
        }
    }

    #[test]
    fn test_backoff_monotonic_up_to_cap() {
        let mut prev = Duration::ZERO;
        for attempt in 0..=5 {
            let d = backoff_delay(attempt);
            assert!(d > prev || attempt == 0);
            prev = d;
        }
        // After cap, stays the same
        assert_eq!(backoff_delay(5), backoff_delay(6));
    }
}
