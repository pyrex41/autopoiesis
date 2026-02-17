use clap::Parser;
use tracing_subscriber::{fmt, EnvFilter};

use nexus_protocol::ws::{self, WsClientConfig};
use nexus_tui::app::App;

mod config;

#[derive(Parser, Debug)]
#[command(name = "nexus", version, about = "Terminal cockpit for the Autopoiesis agent platform")]
struct Cli {
    /// WebSocket URL for the Autopoiesis backend
    #[arg(long)]
    ws_url: Option<String>,

    /// REST API URL for the Autopoiesis backend
    #[arg(long)]
    rest_url: Option<String>,

    /// API key for authentication
    #[arg(long, env = "NEXUS_API_KEY")]
    api_key: Option<String>,

    /// Disable WebSocket connection (offline/demo mode)
    #[arg(long)]
    offline: bool,

    /// Path to config file (default: nexus.toml in cwd or ~/.nexus/)
    #[arg(long)]
    config: Option<std::path::PathBuf>,
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

    // Load config file (search default paths if no --config given), then apply CLI overrides
    let mut config = match cli.config {
        Some(path) => config::NexusConfig::load_from(Some(path)),
        None => config::NexusConfig::load(),
    };
    config.apply_cli_overrides(cli.ws_url, cli.rest_url, cli.api_key);
    tracing::debug!(theme = %config.tui.theme, layout = %config.tui.layout, "Config loaded");

    // Load command history (append each command immediately for crash safety)
    let history_store = config::HistoryStore::new();
    let history = history_store.load();

    let mut app = App::new().with_history(history);

    if !cli.offline {
        let ws_config = WsClientConfig {
            url: config.connection.ws_url.clone(),
            api_key: config.connection.api_key.clone(),
        };
        let (handle, rx) = ws::start(ws_config);
        app = app.with_ws(handle, rx);
        tracing::info!(url = %config.connection.ws_url, "WebSocket client started");
    } else {
        tracing::info!("Running in offline mode (no WebSocket connection)");
    }

    let result = app.run().await;

    // Save command history on exit
    history_store.save_all(&app.state.command_history);

    result
}
