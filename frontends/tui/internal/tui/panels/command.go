package panels

import (
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/reuben/autopoiesis/tui/internal/tui"
)

// Command provides a command input with history.
type Command struct {
	input   textinput.Model
	history []string
	histIdx int
	Focused bool
	Width   int
}

func NewCommand() Command {
	ti := textinput.New()
	ti.Placeholder = "type : to enter a command..."
	ti.Prompt = "> "
	ti.CharLimit = 256
	return Command{
		input:   ti,
		histIdx: -1,
	}
}

func (c Command) Focus() Command {
	c.input.Focus()
	c.Focused = true
	return c
}

func (c Command) Blur() Command {
	c.input.Blur()
	c.Focused = false
	return c
}

func (c Command) SetWidth(w int) Command {
	c.Width = w
	c.input.Width = w - 6 // borders + padding + prompt
	return c
}

func (c Command) Update(msg tea.Msg) (Command, tea.Cmd) {
	var cmd tea.Cmd
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "enter":
			val := c.input.Value()
			if val != "" {
				c.history = append(c.history, val)
				c.histIdx = len(c.history)
				c.input.SetValue("")
				return c, func() tea.Msg {
					return tui.CommandSubmitMsg{Command: val}
				}
			}
		case "up":
			if len(c.history) > 0 && c.histIdx > 0 {
				c.histIdx--
				c.input.SetValue(c.history[c.histIdx])
				c.input.CursorEnd()
			}
			return c, nil
		case "down":
			if c.histIdx < len(c.history)-1 {
				c.histIdx++
				c.input.SetValue(c.history[c.histIdx])
				c.input.CursorEnd()
			} else {
				c.histIdx = len(c.history)
				c.input.SetValue("")
			}
			return c, nil
		}
	}
	c.input, cmd = c.input.Update(msg)
	return c, cmd
}

func (c Command) View() string {
	style := tui.StyleCommandInput
	if c.Focused {
		style = tui.StyleCommandInputFocused
	}
	return style.Width(c.Width).Render(c.input.View())
}
