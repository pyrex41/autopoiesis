package panels

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/tui"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

// StatusBar shows connection state, agent count, and version.
type StatusBar struct {
	Connected  bool
	AgentCount int
	Version    string
	ConnState  string
	Width      int
}

func NewStatusBar() StatusBar {
	return StatusBar{
		ConnState: "disconnected",
	}
}

func (s StatusBar) View() string {
	var connIndicator string
	if s.Connected {
		connIndicator = tui.StyleStatusConnected.Render("● connected")
	} else {
		connIndicator = tui.StyleStatusDisconnected.Render("○ " + s.ConnState)
	}

	agents := fmt.Sprintf("%d agents", s.AgentCount)
	version := s.Version
	if version == "" {
		version = "autopoiesis"
	} else {
		version = "autopoiesis " + version
	}

	left := connIndicator + "  " + agents
	right := version

	gap := s.Width - lipgloss.Width(left) - lipgloss.Width(right) - 2
	if gap < 1 {
		gap = 1
	}
	padding := fmt.Sprintf("%*s", gap, "")

	return tui.StyleStatusBar.Width(s.Width).Render(left + padding + right)
}

func (s StatusBar) HandleWSState(state ws.ConnState) StatusBar {
	switch state {
	case ws.Connected:
		s.Connected = true
		s.ConnState = "connected"
	case ws.Connecting:
		s.Connected = false
		s.ConnState = "connecting..."
	case ws.Disconnected:
		s.Connected = false
		s.ConnState = "disconnected"
	}
	return s
}
