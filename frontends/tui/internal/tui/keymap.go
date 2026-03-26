package tui

import "github.com/charmbracelet/bubbles/key"

// KeyMap defines all key bindings for the TUI.
type KeyMap struct {
	Quit       key.Binding
	Tab        key.Binding
	ShiftTab   key.Binding
	Up         key.Binding
	Down       key.Binding
	Enter      key.Binding
	Escape     key.Binding
	FocusCmd   key.Binding
	Help       key.Binding
}

var Keys = KeyMap{
	Quit: key.NewBinding(
		key.WithKeys("ctrl+c"),
		key.WithHelp("ctrl+c", "quit"),
	),
	Tab: key.NewBinding(
		key.WithKeys("tab"),
		key.WithHelp("tab", "next panel"),
	),
	ShiftTab: key.NewBinding(
		key.WithKeys("shift+tab"),
		key.WithHelp("shift+tab", "prev panel"),
	),
	Up: key.NewBinding(
		key.WithKeys("up", "k"),
		key.WithHelp("↑/k", "up"),
	),
	Down: key.NewBinding(
		key.WithKeys("down", "j"),
		key.WithHelp("↓/j", "down"),
	),
	Enter: key.NewBinding(
		key.WithKeys("enter"),
		key.WithHelp("enter", "select/submit"),
	),
	Escape: key.NewBinding(
		key.WithKeys("esc"),
		key.WithHelp("esc", "back"),
	),
	FocusCmd: key.NewBinding(
		key.WithKeys(":"),
		key.WithHelp(":", "command"),
	),
	Help: key.NewBinding(
		key.WithKeys("?"),
		key.WithHelp("?", "help"),
	),
}
