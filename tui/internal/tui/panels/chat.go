package panels

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/tui"
)

// ChatMessage represents a single chat message.
type ChatMessage struct {
	Role string // "you", "agent", "system"
	Text string
}

// Chat displays a scrollable chat conversation.
type Chat struct {
	messages []ChatMessage
	viewport viewport.Model
	AgentID  string
	Active   bool
	Focused  bool
	Width    int
	Height   int
	ready    bool
}

func NewChat() Chat {
	return Chat{}
}

func (c Chat) SetSize(w, h int) Chat {
	c.Width = w
	c.Height = h
	contentW := w - 4
	contentH := h - 4
	if contentW < 1 {
		contentW = 1
	}
	if contentH < 1 {
		contentH = 1
	}
	if !c.ready {
		c.viewport = viewport.New(contentW, contentH)
		c.ready = true
	} else {
		c.viewport.Width = contentW
		c.viewport.Height = contentH
	}
	c.renderContent()
	return c
}

func (c Chat) AddMessage(role, text string) Chat {
	c.messages = append(c.messages, ChatMessage{Role: role, Text: text})
	c.renderContent()
	c.viewport.GotoBottom()
	return c
}

func (c Chat) Clear() Chat {
	c.messages = nil
	c.AgentID = ""
	c.Active = false
	c.renderContent()
	return c
}

func (c *Chat) renderContent() {
	if !c.ready {
		return
	}
	var lines []string
	for _, msg := range c.messages {
		var prefix string
		switch msg.Role {
		case "you":
			prefix = tui.StyleChatYou.Render("you: ")
		case "agent":
			prefix = tui.StyleChatAgent.Render("agent: ")
		case "system":
			prefix = tui.StyleChatSystem.Render("system: ")
		default:
			prefix = msg.Role + ": "
		}
		lines = append(lines, " "+prefix+msg.Text)
	}
	if len(lines) == 0 {
		lines = append(lines, lipgloss.NewStyle().Foreground(tui.AgentStateColor("idle")).Render(" No chat messages"))
	}
	c.viewport.SetContent(strings.Join(lines, "\n"))
}

func (c Chat) Viewport() viewport.Model {
	return c.viewport
}

func (c Chat) SetViewport(vp viewport.Model) Chat {
	c.viewport = vp
	return c
}

func (c Chat) View() string {
	style := tui.StylePanel
	if c.Focused {
		style = tui.StylePanelFocused
	}

	titleText := "Chat"
	if c.Active && c.AgentID != "" {
		short := c.AgentID
		if len(short) > 8 {
			short = short[:8]
		}
		titleText = fmt.Sprintf("Chat [%s]", short)
	}
	title := tui.StylePanelTitle.Render(titleText)

	var content string
	if c.ready {
		content = c.viewport.View()
	}
	inner := lipgloss.JoinVertical(lipgloss.Left, title, content)
	return style.Width(c.Width).Height(c.Height).Render(inner)
}
