//! JSON encode / MessagePack decode / frame detection.
//!
//! The backend sends text frames as JSON and binary frames as MessagePack.
//! The client always sends JSON text frames.

use crate::protocol::types::{ClientMessage, ServerMessage};
use tracing::{debug, warn};

/// Encode a client message to a JSON string for sending over WebSocket.
pub fn encode_client_message(msg: &ClientMessage) -> Result<String, serde_json::Error> {
    serde_json::to_string(msg)
}

/// Decode a text frame (JSON) from the server.
pub fn decode_text_frame(text: &str) -> Result<ServerMessage, DecodeError> {
    serde_json::from_str(text).map_err(|e| {
        debug!("JSON decode error for text: {text:.200}");
        DecodeError::Json(e)
    })
}

/// Decode a binary frame (MessagePack) from the server.
pub fn decode_binary_frame(data: &[u8]) -> Result<ServerMessage, DecodeError> {
    rmp_serde::from_slice(data).map_err(|e| {
        warn!("MessagePack decode error ({} bytes)", data.len());
        DecodeError::MsgPack(e)
    })
}

/// Errors that can occur during message decoding.
#[derive(Debug)]
pub enum DecodeError {
    Json(serde_json::Error),
    MsgPack(rmp_serde::decode::Error),
}

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Json(e) => write!(f, "JSON decode error: {e}"),
            Self::MsgPack(e) => write!(f, "MessagePack decode error: {e}"),
        }
    }
}

impl std::error::Error for DecodeError {}
