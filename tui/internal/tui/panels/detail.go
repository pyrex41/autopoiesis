package panels

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/tui"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

// Detail displays metadata about the selected agent.
type Detail struct {
	Agent   *ws.AgentData
	Focused bool
	Width   int
	Height  int
}

func NewDetail() Detail {
	return Detail{}
}

func (d Detail) View() string {
	style := tui.StylePanel
	if d.Focused {
		style = tui.StylePanelFocused
	}

	if d.Agent == nil {
		inner := lipgloss.NewStyle().
			Foreground(tui.AgentStateColor("idle")).
			Render("No agent selected")
		return style.Width(d.Width).Height(d.Height).Render(inner)
	}

	a := d.Agent
	stateStyle := lipgloss.NewStyle().Foreground(tui.AgentStateColor(a.State)).Bold(true)

	title := tui.StylePanelTitle.Render(
		fmt.Sprintf("Agent: %s [%s]", a.Name, stateStyle.Render(a.State)),
	)

	caps := "none"
	if len(a.Capabilities) > 0 {
		caps = strings.Join(a.Capabilities, ", ")
	}

	lines := []string{
		title,
		fmt.Sprintf(" ID: %s", a.ID),
		fmt.Sprintf(" Capabilities: %s", caps),
		fmt.Sprintf(" Thoughts: %d", a.ThoughtCount),
	}

	if a.Parent != nil {
		lines = append(lines, fmt.Sprintf(" Parent: %s", *a.Parent))
	}
	if len(a.Children) > 0 {
		lines = append(lines, fmt.Sprintf(" Children: %s", strings.Join(a.Children, ", ")))
	}
	if a.Persistent != nil && *a.Persistent {
		lines = append(lines, " Type: persistent (dual-agent)")
	}

	content := lipgloss.JoinVertical(lipgloss.Left, lines...)
	return style.Width(d.Width).Height(d.Height).Render(content)
}
