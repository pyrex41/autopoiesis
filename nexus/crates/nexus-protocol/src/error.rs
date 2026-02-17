use thiserror::Error;

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("JSON encode error: {0}")]
    JsonEncode(serde_json::Error),
    #[error("JSON decode error: {0}")]
    JsonDecode(serde_json::Error),
    #[error("MessagePack decode error: {0}")]
    MsgPackDecode(rmp_serde::decode::Error),
    #[error("WebSocket error: {0}")]
    WebSocket(#[from] Box<tokio_tungstenite::tungstenite::Error>),
    #[error("Connection closed")]
    ConnectionClosed,
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
}
