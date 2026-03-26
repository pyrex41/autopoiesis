package panels

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/tui"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

// Thoughts displays a scrollable stream of agent thoughts.
type Thoughts struct {
	thoughts []ws.ThoughtData
	viewport viewport.Model
	Focused  bool
	Width    int
	Height   int
	ready    bool
}

func NewThoughts() Thoughts {
	return Thoughts{}
}

func (t Thoughts) SetSize(w, h int) Thoughts {
	t.Width = w
	t.Height = h
	contentW := w - 4 // borders + padding
	contentH := h - 4 // borders + title
	if contentW < 1 {
		contentW = 1
	}
	if contentH < 1 {
		contentH = 1
	}
	if !t.ready {
		t.viewport = viewport.New(contentW, contentH)
		t.ready = true
	} else {
		t.viewport.Width = contentW
		t.viewport.Height = contentH
	}
	t.renderContent()
	return t
}

func (t Thoughts) SetThoughts(thoughts []ws.ThoughtData) Thoughts {
	t.thoughts = thoughts
	t.renderContent()
	t.viewport.GotoBottom()
	return t
}

func (t Thoughts) AddThought(thought ws.ThoughtData) Thoughts {
	t.thoughts = append(t.thoughts, thought)
	t.renderContent()
	t.viewport.GotoBottom()
	return t
}

func (t Thoughts) Clear() Thoughts {
	t.thoughts = nil
	t.renderContent()
	return t
}

func (t *Thoughts) renderContent() {
	if !t.ready {
		return
	}
	var lines []string
	for _, th := range t.thoughts {
		badge := tui.ThoughtBadge(th.Type)
		content := truncate(th.Content, t.viewport.Width-12)
		line := fmt.Sprintf(" %s %s", badge, content)
		lines = append(lines, line)
	}
	if len(lines) == 0 {
		lines = append(lines, lipgloss.NewStyle().Foreground(tui.AgentStateColor("idle")).Render(" No thoughts yet"))
	}
	t.viewport.SetContent(strings.Join(lines, "\n"))
}

func (t Thoughts) Viewport() viewport.Model {
	return t.viewport
}

func (t Thoughts) SetViewport(vp viewport.Model) Thoughts {
	t.viewport = vp
	return t
}

func (t Thoughts) View() string {
	style := tui.StylePanel
	if t.Focused {
		style = tui.StylePanelFocused
	}

	title := tui.StylePanelTitle.Render("Thoughts")
	var content string
	if t.ready {
		content = t.viewport.View()
	}
	inner := lipgloss.JoinVertical(lipgloss.Left, title, content)
	return style.Width(t.Width).Height(t.Height).Render(inner)
}

func truncate(s string, maxLen int) string {
	if maxLen <= 0 {
		return ""
	}
	// Remove newlines for single-line display
	s = strings.ReplaceAll(s, "\n", " ")
	if len(s) > maxLen {
		return s[:maxLen-1] + "…"
	}
	return s
}
