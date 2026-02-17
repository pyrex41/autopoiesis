use clap::Parser;
use tracing_subscriber::{fmt, EnvFilter};

use nexus_protocol::ws::{self, WsClientConfig};
use nexus_tui::app::App;

#[derive(Parser, Debug)]
#[command(name = "nexus", version, about = "Terminal cockpit for the Autopoiesis agent platform")]
struct Cli {
    /// WebSocket URL for the Autopoiesis backend
    #[arg(long, default_value = "ws://localhost:8080/ws")]
    ws_url: String,

    /// REST API URL for the Autopoiesis backend
    #[arg(long, default_value = "http://localhost:8080")]
    rest_url: String,

    /// API key for authentication
    #[arg(long, env = "NEXUS_API_KEY")]
    api_key: Option<String>,

    /// Disable WebSocket connection (offline/demo mode)
    #[arg(long)]
    offline: bool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("nexus=info,nexus_protocol=info")),
        )
        .with_target(false)
        .init();

    tracing::info!("Nexus starting...");

    let mut app = App::new();

    if !cli.offline {
        let config = WsClientConfig {
            url: cli.ws_url.clone(),
            api_key: cli.api_key.clone(),
        };
        let (handle, rx) = ws::start(config);
        app = app.with_ws(handle, rx);
        tracing::info!(url = %cli.ws_url, "WebSocket client started");
    } else {
        tracing::info!("Running in offline mode (no WebSocket connection)");
    }

    app.run().await
}
