package panels

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/tui"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

// Events displays a scrollable event log.
type Events struct {
	events   []ws.EventData
	viewport viewport.Model
	Focused  bool
	Width    int
	Height   int
	ready    bool
}

func NewEvents() Events {
	return Events{}
}

func (e Events) SetSize(w, h int) Events {
	e.Width = w
	e.Height = h
	contentW := w - 4
	contentH := h - 4
	if contentW < 1 {
		contentW = 1
	}
	if contentH < 1 {
		contentH = 1
	}
	if !e.ready {
		e.viewport = viewport.New(contentW, contentH)
		e.ready = true
	} else {
		e.viewport.Width = contentW
		e.viewport.Height = contentH
	}
	e.renderContent()
	return e
}

func (e Events) AddEvent(event ws.EventData) Events {
	e.events = append(e.events, event)
	// Keep last 200 events
	if len(e.events) > 200 {
		e.events = e.events[len(e.events)-200:]
	}
	e.renderContent()
	e.viewport.GotoBottom()
	return e
}

func (e Events) SetEvents(events []ws.EventData) Events {
	e.events = events
	e.renderContent()
	e.viewport.GotoBottom()
	return e
}

func (e *Events) renderContent() {
	if !e.ready {
		return
	}
	var lines []string
	for _, ev := range e.events {
		typeStyle := lipgloss.NewStyle().Foreground(tui.AgentStateColor("initialized"))
		source := ev.Source
		if source == "" {
			source = "system"
		}
		line := fmt.Sprintf(" %s %s %s",
			typeStyle.Render(ev.Type),
			lipgloss.NewStyle().Foreground(tui.AgentStateColor("idle")).Render(source),
			summarizeEventData(ev.Data),
		)
		lines = append(lines, line)
	}
	if len(lines) == 0 {
		lines = append(lines, lipgloss.NewStyle().Foreground(tui.AgentStateColor("idle")).Render(" No events"))
	}
	e.viewport.SetContent(strings.Join(lines, "\n"))
}

func (e Events) Viewport() viewport.Model {
	return e.viewport
}

func (e Events) SetViewport(vp viewport.Model) Events {
	e.viewport = vp
	return e
}

func (e Events) View() string {
	style := tui.StylePanel
	if e.Focused {
		style = tui.StylePanelFocused
	}

	title := tui.StylePanelTitle.Render("Events")
	var content string
	if e.ready {
		content = e.viewport.View()
	}
	inner := lipgloss.JoinVertical(lipgloss.Left, title, content)
	return style.Width(e.Width).Height(e.Height).Render(inner)
}

func summarizeEventData(data map[string]string) string {
	if len(data) == 0 {
		return ""
	}
	var parts []string
	for k, v := range data {
		if len(v) > 40 {
			v = v[:37] + "..."
		}
		parts = append(parts, k+"="+v)
	}
	return strings.Join(parts, " ")
}
