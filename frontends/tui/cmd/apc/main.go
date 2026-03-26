package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/reuben/autopoiesis/tui/internal/tui"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

func main() {
	wsURL := flag.String("ws-url", "ws://localhost:9080/ws", "WebSocket server URL")
	restURL := flag.String("rest-url", "http://localhost:9080", "REST API base URL")
	flag.Parse()

	// Set up logging to file so it doesn't interfere with TUI
	logFile, err := os.OpenFile("/tmp/apc.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to open log file: %v\n", err)
		os.Exit(1)
	}
	defer logFile.Close()
	log.SetOutput(logFile)

	// Create and start WebSocket client
	wsClient := ws.NewClient(*wsURL)
	wsClient.Start()
	defer wsClient.Stop()

	cfg := tui.Config{
		WSURL:   *wsURL,
		RESTURL: *restURL,
	}

	app := tui.NewApp(cfg, wsClient)
	p := tea.NewProgram(app, tea.WithAltScreen())

	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
