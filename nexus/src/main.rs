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

    #[command(subcommand)]
    command: Option<SubCommand>,
}

#[derive(clap::Subcommand, Debug)]
enum SubCommand {
    /// Download models for voice features (Moonshine STT, Piper TTS)
    Setup {
        /// List available models without downloading
        #[arg(long)]
        list: bool,
    },
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

    // Handle subcommands before starting TUI
    if let Some(SubCommand::Setup { list }) = cli.command {
        println!("Nexus Setup -- Voice Model Manager");
        println!();
        println!("Required models:");
        println!("  Moonshine v2 (STT): moonshine-small-streaming-en (~120MB)");
        println!("              Search: ~/Library/Application Support/com.pais.handy/models/");
        println!("                      ~/.nexus/models/moonshine-small-streaming-en/");
        println!("  Piper TTS:          en_US-lessac-medium (~60MB)");
        println!("              Search: ~/.nexus/models/piper/");
        println!("  Silero VAD v4:      silero_vad_v4.onnx (~2MB)");
        println!("              Search: ~/.nexus/models/silero_vad_v4.onnx");
        println!();
        println!("Download instructions:");
        println!("  STT: Download from https://github.com/usefulsensors/moonshine/releases");
        println!("       or if you have Handy.app installed, models are already available.");
        println!("  TTS: Download from https://github.com/rhasspy/piper/releases");
        println!("  VAD: Download from https://github.com/snakers4/silero-vad/releases");
        if !list {
            println!();
            println!("(Use --list to just show model info without any downloads)");
        }
        return Ok(());
    }

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
