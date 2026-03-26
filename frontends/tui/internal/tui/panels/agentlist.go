package panels

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/tui"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

// AgentList displays a navigable list of agents.
type AgentList struct {
	Agents   []ws.AgentData
	Selected int
	Focused  bool
	Width    int
	Height   int
}

func NewAgentList() AgentList {
	return AgentList{}
}

func (a AgentList) SelectedAgent() *ws.AgentData {
	if len(a.Agents) == 0 || a.Selected < 0 || a.Selected >= len(a.Agents) {
		return nil
	}
	return &a.Agents[a.Selected]
}

func (a AgentList) MoveUp() AgentList {
	if a.Selected > 0 {
		a.Selected--
	}
	return a
}

func (a AgentList) MoveDown() AgentList {
	if a.Selected < len(a.Agents)-1 {
		a.Selected++
	}
	return a
}

func (a AgentList) SetAgents(agents []ws.AgentData) AgentList {
	a.Agents = agents
	if a.Selected >= len(agents) {
		a.Selected = max(0, len(agents)-1)
	}
	return a
}

func (a AgentList) UpdateAgent(id string, state string) AgentList {
	for i := range a.Agents {
		if a.Agents[i].ID == id {
			a.Agents[i].State = state
			break
		}
	}
	return a
}

func (a AgentList) AddAgent(agent ws.AgentData) AgentList {
	a.Agents = append(a.Agents, agent)
	return a
}

func (a AgentList) View() string {
	style := tui.StylePanel
	if a.Focused {
		style = tui.StylePanelFocused
	}

	title := tui.StylePanelTitle.Render("Agents")

	contentHeight := a.Height - 4 // borders + title
	if contentHeight < 1 {
		contentHeight = 1
	}

	var lines []string
	for i, agent := range a.Agents {
		bullet := tui.AgentStateBullet(agent.State)
		name := agent.Name
		if name == "" {
			name = agent.ID[:8]
		}

		var line string
		if i == a.Selected {
			line = fmt.Sprintf(" %s %s", bullet, tui.StyleAgentSelected.Render("> "+name))
		} else {
			line = fmt.Sprintf(" %s %s", bullet, tui.StyleAgentNormal.Render("  "+name))
		}
		lines = append(lines, line)

		if len(lines) >= contentHeight {
			break
		}
	}

	// Pad remaining lines
	for len(lines) < contentHeight {
		lines = append(lines, "")
	}

	content := lipgloss.JoinVertical(lipgloss.Left, lines...)
	inner := lipgloss.JoinVertical(lipgloss.Left, title, content)

	return style.Width(a.Width).Height(a.Height).Render(inner)
}
