package tui

import "github.com/reuben/autopoiesis/tui/internal/ws"

// WebSocket lifecycle messages

type WSConnectedMsg struct {
	ConnectionID string
	Version      string
}

type WSDisconnectedMsg struct {
	Err error
}

type WSReconnectingMsg struct {
	Attempt int
}

// WSDataMsg wraps a parsed server message for the TUI update loop.
type WSDataMsg struct {
	Msg ws.ServerMessage
}

// WSErrorMsg indicates a protocol-level error from the server.
type WSErrorMsg struct {
	Code    string
	Message string
}

// Internal command messages

type FocusChangedMsg struct {
	Panel Panel
}

type AgentSelectedMsg struct {
	AgentID string
}

type CommandSubmitMsg struct {
	Command string
}

type WindowSizeMsg struct {
	Width  int
	Height int
}
