package tui

import "github.com/charmbracelet/lipgloss"

var (
	// Colors
	colorPrimary   = lipgloss.Color("#7C3AED") // violet
	colorSecondary = lipgloss.Color("#06B6D4") // cyan
	colorSuccess   = lipgloss.Color("#22C55E") // green
	colorWarning   = lipgloss.Color("#F59E0B") // amber
	colorError     = lipgloss.Color("#EF4444") // red
	colorMuted     = lipgloss.Color("#6B7280") // gray
	colorText      = lipgloss.Color("#E5E7EB") // light gray
	colorBg        = lipgloss.Color("#1F2937") // dark gray
	colorBorder    = lipgloss.Color("#374151") // medium gray

	// Agent state colors
	colorRunning     = colorSuccess
	colorPaused      = colorWarning
	colorStopped     = colorError
	colorInitialized = colorSecondary
	colorIdle        = colorMuted

	// Thought type colors
	colorObservation = lipgloss.Color("#60A5FA") // blue
	colorDecision    = lipgloss.Color("#F472B6") // pink
	colorAction      = lipgloss.Color("#34D399") // emerald
	colorReflection  = lipgloss.Color("#A78BFA") // purple

	// Styles
	StyleStatusBar = lipgloss.NewStyle().
			Background(lipgloss.Color("#111827")).
			Foreground(colorText).
			Padding(0, 1)

	StyleStatusConnected = lipgloss.NewStyle().
				Foreground(colorSuccess).
				Bold(true)

	StyleStatusDisconnected = lipgloss.NewStyle().
				Foreground(colorError).
				Bold(true)

	StylePanel = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colorBorder)

	StylePanelFocused = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(colorPrimary)

	StylePanelTitle = lipgloss.NewStyle().
			Foreground(colorPrimary).
			Bold(true).
			Padding(0, 1)

	StyleAgentSelected = lipgloss.NewStyle().
				Foreground(colorText).
				Bold(true)

	StyleAgentNormal = lipgloss.NewStyle().
			Foreground(colorMuted)

	StyleCommandInput = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(colorBorder).
				Padding(0, 1)

	StyleCommandInputFocused = lipgloss.NewStyle().
					Border(lipgloss.RoundedBorder()).
					BorderForeground(colorPrimary).
					Padding(0, 1)

	StyleChatYou = lipgloss.NewStyle().
			Foreground(colorSecondary).
			Bold(true)

	StyleChatAgent = lipgloss.NewStyle().
			Foreground(colorSuccess).
			Bold(true)

	StyleChatSystem = lipgloss.NewStyle().
			Foreground(colorMuted).
			Italic(true)

	StyleError = lipgloss.NewStyle().
			Foreground(colorError)
)

// AgentStateColor returns the color for an agent state string.
func AgentStateColor(state string) lipgloss.Color {
	switch state {
	case "running":
		return colorRunning
	case "paused":
		return colorPaused
	case "stopped":
		return colorStopped
	case "initialized":
		return colorInitialized
	default:
		return colorIdle
	}
}

// AgentStateBullet returns a colored bullet for an agent state.
func AgentStateBullet(state string) string {
	c := AgentStateColor(state)
	return lipgloss.NewStyle().Foreground(c).Render("●")
}

// ThoughtBadge returns a styled badge for a thought type.
func ThoughtBadge(thoughtType string) string {
	var icon string
	var c lipgloss.Color
	switch thoughtType {
	case "observation":
		icon, c = "◉ obs", colorObservation
	case "decision":
		icon, c = "◆ dec", colorDecision
	case "action":
		icon, c = "▶ act", colorAction
	case "reflection":
		icon, c = "◈ ref", colorReflection
	default:
		icon, c = "? ???", colorMuted
	}
	return lipgloss.NewStyle().Foreground(c).Render("["+icon+"]")
}
