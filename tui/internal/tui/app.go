package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

// Panel identifies which panel has focus.
type Panel int

const (
	PanelAgents Panel = iota
	PanelThoughts
	PanelChat
	PanelEvents
	PanelCommand
	panelCount
)

func (p Panel) String() string {
	switch p {
	case PanelAgents:
		return "agents"
	case PanelThoughts:
		return "thoughts"
	case PanelChat:
		return "chat"
	case PanelEvents:
		return "events"
	case PanelCommand:
		return "command"
	default:
		return "unknown"
	}
}

// Config holds TUI configuration.
type Config struct {
	WSURL   string
	RESTURL string
}

// App is the root bubbletea Model.
type App struct {
	config Config
	wsClient *ws.Client
	focus    Panel

	// Panels (imported by app.go directly as types to avoid circular imports)
	// We'll use inline panel state here and render helpers from panels package
	width  int
	height int

	// Connection state
	connected    bool
	connState    string
	version      string
	agentCount   int

	// Agent data
	agents       []ws.AgentData
	selectedIdx  int
	selectedID   string

	// Thoughts
	thoughts     []ws.ThoughtData
	thoughtsVP   viewport.Model
	thoughtsReady bool

	// Chat
	chatMessages []chatMsg
	chatVP       viewport.Model
	chatReady    bool
	chatActive   bool
	chatAgentID  string

	// Events
	events       []ws.EventData
	eventsVP     viewport.Model
	eventsReady  bool

	// Command
	cmdInput   textinput.Model
	cmdHistory []string
	cmdHistIdx int
	cmdFocused bool

	// Error display
	lastError    string
}

type chatMsg struct {
	role string
	text string
}

// NewApp creates the root TUI model.
func NewApp(cfg Config, wsClient *ws.Client) App {
	ti := textinput.New()
	ti.Prompt = "> "
	ti.Placeholder = "type : to enter a command..."
	ti.CharLimit = 256
	return App{
		config:     cfg,
		wsClient:   wsClient,
		connState:  "connecting...",
		cmdInput:   ti,
		cmdHistIdx: -1,
	}
}

// Init returns initial commands.
func (a App) Init() tea.Cmd {
	return tea.Batch(
		listenWS(a.wsClient),
		listenWSState(a.wsClient),
	)
}

// listenWS creates a command that waits for incoming WS messages.
func listenWS(c *ws.Client) tea.Cmd {
	return func() tea.Msg {
		msg, ok := <-c.Incoming
		if !ok {
			return WSDisconnectedMsg{Err: nil}
		}
		return WSDataMsg{Msg: msg}
	}
}

// listenWSState creates a command that waits for WS state changes.
func listenWSState(c *ws.Client) tea.Cmd {
	return func() tea.Msg {
		state, ok := <-c.StateChange
		if !ok {
			return WSDisconnectedMsg{Err: nil}
		}
		switch state {
		case ws.Connected:
			return WSConnectedMsg{}
		case ws.Connecting:
			return WSReconnectingMsg{}
		case ws.Disconnected:
			return WSDisconnectedMsg{}
		}
		return nil
	}
}

// Update handles all messages.
func (a App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		a = a.recalcLayout()

	case tea.KeyMsg:
		// Global keys
		if key.Matches(msg, Keys.Quit) {
			return a, tea.Quit
		}

		// If command input is focused, route there
		if a.cmdFocused {
			return a.updateCommand(msg)
		}

		switch {
		case key.Matches(msg, Keys.Tab):
			a.focus = (a.focus + 1) % panelCount
			if a.focus == PanelCommand {
				a = a.focusCommand()
			}
		case key.Matches(msg, Keys.ShiftTab):
			a.focus = (a.focus - 1 + panelCount) % panelCount
			if a.focus == PanelCommand {
				a = a.focusCommand()
			}
		case key.Matches(msg, Keys.FocusCmd):
			a.focus = PanelCommand
			a = a.focusCommand()
		case key.Matches(msg, Keys.Up):
			a = a.handleUp()
		case key.Matches(msg, Keys.Down):
			a = a.handleDown()
		case key.Matches(msg, Keys.Enter):
			a = a.handleEnter()
		}

	case WSConnectedMsg:
		a.connected = true
		a.connState = "connected"
		// Send initial protocol messages
		a.sendInitialMessages()
		cmds = append(cmds, listenWSState(a.wsClient))

	case WSDisconnectedMsg:
		a.connected = false
		a.connState = "disconnected"
		cmds = append(cmds, listenWSState(a.wsClient))

	case WSReconnectingMsg:
		a.connected = false
		a.connState = "reconnecting..."
		cmds = append(cmds, listenWSState(a.wsClient))

	case WSDataMsg:
		a = a.handleServerMessage(msg.Msg)
		cmds = append(cmds, listenWS(a.wsClient))

	case CommandSubmitMsg:
		a, cmds = a.executeCommand(msg.Command, cmds)
	}

	return a, tea.Batch(cmds...)
}

func (a App) handleUp() App {
	switch a.focus {
	case PanelAgents:
		if a.selectedIdx > 0 {
			a.selectedIdx--
			a = a.onAgentSelected()
		}
	case PanelThoughts:
		if a.thoughtsReady {
			a.thoughtsVP.LineUp(1)
		}
	case PanelChat:
		if a.chatReady {
			a.chatVP.LineUp(1)
		}
	case PanelEvents:
		if a.eventsReady {
			a.eventsVP.LineUp(1)
		}
	}
	return a
}

func (a App) handleDown() App {
	switch a.focus {
	case PanelAgents:
		if a.selectedIdx < len(a.agents)-1 {
			a.selectedIdx++
			a = a.onAgentSelected()
		}
	case PanelThoughts:
		if a.thoughtsReady {
			a.thoughtsVP.LineDown(1)
		}
	case PanelChat:
		if a.chatReady {
			a.chatVP.LineDown(1)
		}
	case PanelEvents:
		if a.eventsReady {
			a.eventsVP.LineDown(1)
		}
	}
	return a
}

func (a App) handleEnter() App {
	if a.focus == PanelAgents && len(a.agents) > 0 {
		a = a.onAgentSelected()
	}
	return a
}

func (a App) focusCommand() App {
	a.cmdFocused = true
	a.cmdInput.Focus()
	return a
}

func (a App) blurCommand() App {
	a.cmdFocused = false
	a.cmdInput.Blur()
	a.cmdInput.SetValue("")
	return a
}

func (a App) onAgentSelected() App {
	if a.selectedIdx >= 0 && a.selectedIdx < len(a.agents) {
		agent := a.agents[a.selectedIdx]
		prevID := a.selectedID
		a.selectedID = agent.ID
		if a.wsClient != nil {
			// Unsubscribe from previous agent's thoughts
			if prevID != "" && prevID != agent.ID {
				a.wsClient.Send(ws.UnsubscribeMsg{
					Type:    "unsubscribe",
					Channel: "thoughts:" + prevID,
				})
			}
			// Request thoughts for the selected agent
			a.wsClient.Send(ws.GetThoughtsMsg{
				Type:    "get_thoughts",
				AgentID: agent.ID,
				Limit:   100,
			})
			// Subscribe to thought updates
			a.wsClient.Send(ws.SubscribeMsg{
				Type:    "subscribe",
				Channel: "thoughts:" + agent.ID,
			})
		}
	}
	return a
}

func (a App) updateCommand(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		cmd := a.cmdInput.Value()
		if cmd != "" {
			a.cmdHistory = append(a.cmdHistory, cmd)
			a.cmdHistIdx = len(a.cmdHistory)
			a.cmdInput.SetValue("")
			var cmds []tea.Cmd
			a, cmds = a.executeCommand(cmd, nil)
			return a, tea.Batch(cmds...)
		}
	case "esc":
		a.focus = PanelAgents
		a = a.blurCommand()
	case "up":
		if len(a.cmdHistory) > 0 && a.cmdHistIdx > 0 {
			a.cmdHistIdx--
			a.cmdInput.SetValue(a.cmdHistory[a.cmdHistIdx])
			a.cmdInput.CursorEnd()
		}
	case "down":
		if a.cmdHistIdx < len(a.cmdHistory)-1 {
			a.cmdHistIdx++
			a.cmdInput.SetValue(a.cmdHistory[a.cmdHistIdx])
			a.cmdInput.CursorEnd()
		} else {
			a.cmdHistIdx = len(a.cmdHistory)
			a.cmdInput.SetValue("")
		}
	default:
		// Delegate to textinput for all other keys (typing, ctrl+a/e, paste, etc.)
		var cmd tea.Cmd
		a.cmdInput, cmd = a.cmdInput.Update(msg)
		return a, cmd
	}
	return a, nil
}

func (a App) executeCommand(input string, cmds []tea.Cmd) (App, []tea.Cmd) {
	parts := strings.Fields(input)
	if len(parts) == 0 {
		return a, cmds
	}

	cmd := parts[0]
	args := parts[1:]

	switch cmd {
	case "create":
		if len(args) >= 2 && args[0] == "agent" {
			name := args[1]
			var caps []string
			if len(args) > 2 {
				caps = args[2:]
			}
			a.send(ws.CreateAgentMsg{
				Type:         "create_agent",
				Name:         name,
				Capabilities: caps,
			})
		} else {
			a.lastError = "usage: create agent <name> [capabilities...]"
		}

	case "step":
		if a.selectedID != "" {
			a.send(ws.StepAgentMsg{
				Type:    "step_agent",
				AgentID: a.selectedID,
			})
		} else {
			a.lastError = "no agent selected"
		}

	case "start":
		if a.selectedID != "" {
			a.send(ws.AgentActionMsg{
				Type:    "agent_action",
				AgentID: a.selectedID,
				Action:  "start",
			})
		}

	case "stop":
		if a.selectedID != "" {
			a.send(ws.AgentActionMsg{
				Type:    "agent_action",
				AgentID: a.selectedID,
				Action:  "stop",
			})
		}

	case "pause":
		if a.selectedID != "" {
			a.send(ws.AgentActionMsg{
				Type:    "agent_action",
				AgentID: a.selectedID,
				Action:  "pause",
			})
		}

	case "resume":
		if a.selectedID != "" {
			a.send(ws.AgentActionMsg{
				Type:    "agent_action",
				AgentID: a.selectedID,
				Action:  "resume",
			})
		}

	case "chat":
		if a.selectedID == "" {
			a.lastError = "no agent selected"
		} else if len(args) == 0 {
			a.lastError = "usage: chat <message>"
		} else {
			text := strings.Join(args, " ")
			if !a.chatActive {
				a.send(ws.StartChatMsg{
					Type:    "start_chat",
					AgentID: a.selectedID,
				})
				a.chatActive = true
				a.chatAgentID = a.selectedID
			}
			a.send(ws.ChatPromptMsg{
				Type:    "chat_prompt",
				AgentID: a.selectedID,
				Text:    text,
			})
			a.chatMessages = append(a.chatMessages, chatMsg{role: "you", text: text})
			a = a.renderChat()
		}

	case "endchat":
		if a.chatActive {
			a.send(ws.StopChatMsg{
				Type:    "stop_chat",
				AgentID: a.chatAgentID,
			})
			a.chatActive = false
			a.chatMessages = append(a.chatMessages, chatMsg{role: "system", text: "chat ended"})
			a = a.renderChat()
		}

	case "info":
		a.send(ws.SystemInfoMsg{Type: "system_info"})

	case "inject":
		if a.selectedID == "" {
			a.lastError = "no agent selected"
		} else if len(args) == 0 {
			a.lastError = "usage: inject <content>"
		} else {
			a.send(ws.InjectThoughtMsg{
				Type:    "inject_thought",
				AgentID: a.selectedID,
				Content: strings.Join(args, " "),
			})
		}

	case "help":
		a.lastError = "commands: create agent <name>, step, start, stop, pause, resume, chat <msg>, endchat, inject <text>, info, help"

	default:
		a.lastError = fmt.Sprintf("unknown command: %s (type 'help' for commands)", cmd)
	}

	return a, cmds
}

func (a App) send(msg any) {
	if a.wsClient != nil {
		a.wsClient.Send(msg)
	}
}

func (a App) sendInitialMessages() {
	if a.wsClient == nil {
		return
	}
	a.wsClient.Send(ws.SetStreamFormatMsg{Type: "set_stream_format", Format: "json"})
	a.wsClient.Send(ws.SubscribeMsg{Type: "subscribe", Channel: "agents"})
	a.wsClient.Send(ws.SubscribeMsg{Type: "subscribe", Channel: "events"})
	a.wsClient.Send(ws.SystemInfoMsg{Type: "system_info"})
	a.wsClient.Send(ws.ListAgentsMsg{Type: "list_agents"})
}

func (a App) handleServerMessage(msg ws.ServerMessage) App {
	a.lastError = ""

	switch msg.Type {
	case "connected":
		var resp ws.ConnectedResponse
		msg.As(&resp)
		a.version = resp.Version

	case "system_info":
		var resp ws.SystemInfoResponse
		msg.As(&resp)
		a.version = resp.Version
		a.agentCount = resp.AgentCount

	case "agents":
		var resp ws.AgentsResponse
		msg.As(&resp)
		a.agents = resp.Agents
		a.agentCount = len(resp.Agents)
		if a.selectedIdx >= len(a.agents) {
			a.selectedIdx = max(0, len(a.agents)-1)
		}
		// Auto-select first agent
		if len(a.agents) > 0 && a.selectedID == "" {
			a = a.onAgentSelected()
		}

	case "agent_created":
		var resp ws.AgentCreatedResponse
		msg.As(&resp)
		a.agents = append(a.agents, resp.Agent)
		a.agentCount = len(a.agents)

	case "agent_state_changed":
		var resp ws.AgentStateChangedResponse
		msg.As(&resp)
		for i := range a.agents {
			if a.agents[i].ID == resp.AgentID {
				a.agents[i].State = resp.State
				break
			}
		}

	case "thoughts":
		var resp ws.ThoughtsResponse
		msg.As(&resp)
		if resp.AgentID == a.selectedID {
			a.thoughts = resp.Thoughts
			a = a.renderThoughts()
		}

	case "thought_added":
		var resp ws.ThoughtAddedResponse
		msg.As(&resp)
		if resp.AgentID == a.selectedID {
			a.thoughts = append(a.thoughts, resp.Thought)
			a = a.renderThoughts()
		}

	case "step_complete":
		// Refresh thoughts after step
		if a.selectedID != "" {
			a.send(ws.GetThoughtsMsg{
				Type:    "get_thoughts",
				AgentID: a.selectedID,
				Limit:   100,
			})
		}

	case "event":
		var resp ws.EventPush
		msg.As(&resp)
		a.events = append(a.events, resp.Event)
		if len(a.events) > 200 {
			a.events = a.events[len(a.events)-200:]
		}
		a = a.renderEvents()

	case "events":
		var resp ws.EventsResponse
		msg.As(&resp)
		a.events = resp.Events
		a = a.renderEvents()

	case "chat_started":
		var resp ws.ChatStartedResponse
		msg.As(&resp)
		a.chatActive = true
		a.chatAgentID = resp.AgentID
		a.chatMessages = append(a.chatMessages, chatMsg{role: "system", text: "chat started"})
		a = a.renderChat()

	case "chat_response":
		var resp ws.ChatResponse
		msg.As(&resp)
		a.chatMessages = append(a.chatMessages, chatMsg{role: "agent", text: resp.Text})
		a = a.renderChat()

	case "chat_stopped":
		a.chatActive = false
		a.chatMessages = append(a.chatMessages, chatMsg{role: "system", text: "chat stopped"})
		a = a.renderChat()

	case "error":
		var resp ws.ErrorResponse
		msg.As(&resp)
		a.lastError = fmt.Sprintf("[%s] %s", resp.Code, resp.Message)
	}

	return a
}

func (a App) recalcLayout() App {
	rightW := a.width - sidebarWidth - 3
	if rightW < 10 {
		rightW = 10
	}

	// Compute content heights for the 3 right-column panels (used by both layout and viewports)
	detailContent, thoughtsContent, bottomContent := a.rightPanelContentHeights()

	// Viewport content area = panel content height minus title line (1)
	vpW := rightW - 4 // account for border (2) + small padding
	if vpW < 1 {
		vpW = 1
	}
	thVPH := thoughtsContent - 1 // subtract title line
	if thVPH < 1 {
		thVPH = 1
	}
	botVPH := bottomContent - 1
	if botVPH < 1 {
		botVPH = 1
	}
	_ = detailContent // used only in View()

	if !a.thoughtsReady {
		a.thoughtsVP = viewport.New(vpW, thVPH)
		a.thoughtsReady = true
	} else {
		a.thoughtsVP.Width = vpW
		a.thoughtsVP.Height = thVPH
	}

	if !a.chatReady {
		a.chatVP = viewport.New(vpW, botVPH)
		a.chatReady = true
	} else {
		a.chatVP.Width = vpW
		a.chatVP.Height = botVPH
	}

	if !a.eventsReady {
		a.eventsVP = viewport.New(vpW, botVPH)
		a.eventsReady = true
	} else {
		a.eventsVP.Width = vpW
		a.eventsVP.Height = botVPH
	}

	a = a.renderThoughts()
	a = a.renderChat()
	a = a.renderEvents()

	return a
}

const sidebarWidth = 20

// mainAreaHeight returns the total pixel height available for the main area
// (sidebar + right column), accounting for status bar and command bar.
//
// Layout budget:
//   status bar:  1 line
//   main area:   this value
//   command bar:  3 lines (1 content + 2 border)
func (a App) mainAreaHeight() int {
	h := a.height - 4 // 1 status + 3 cmd
	if h < 6 {
		h = 6
	}
	return h
}

// rightPanelContentHeights returns the content heights (inside border) for
// the 3 stacked right-column panels: detail, thoughts, bottom (chat/events).
// The 3 panels' rendered heights (content + 2 border each = +6 total) must
// equal mainAreaHeight so that the right column matches the sidebar.
func (a App) rightPanelContentHeights() (detail, thoughts, bottom int) {
	totalH := a.mainAreaHeight()
	// 3 panels × 2 border lines = 6 lines consumed by borders
	contentBudget := totalH - 6
	if contentBudget < 6 {
		contentBudget = 6
	}

	detail = 4
	remaining := contentBudget - detail
	if remaining < 2 {
		remaining = 2
		detail = contentBudget - remaining
	}
	thoughts = remaining / 2
	bottom = remaining - thoughts
	return
}

func (a App) renderThoughts() App {
	if !a.thoughtsReady {
		return a
	}
	var lines []string
	for _, th := range a.thoughts {
		badge := ThoughtBadge(th.Type)
		content := th.Content
		content = strings.ReplaceAll(content, "\n", " ")
		maxW := a.thoughtsVP.Width - 12
		if maxW > 0 && len(content) > maxW {
			content = content[:maxW-1] + "…"
		}
		lines = append(lines, fmt.Sprintf(" %s %s", badge, content))
	}
	if len(lines) == 0 {
		lines = append(lines, " No thoughts yet")
	}
	a.thoughtsVP.SetContent(strings.Join(lines, "\n"))
	a.thoughtsVP.GotoBottom()
	return a
}

func (a App) renderChat() App {
	if !a.chatReady {
		return a
	}
	var lines []string
	for _, m := range a.chatMessages {
		var prefix string
		switch m.role {
		case "you":
			prefix = StyleChatYou.Render("you: ")
		case "agent":
			prefix = StyleChatAgent.Render("agent: ")
		default:
			prefix = StyleChatSystem.Render("system: ")
		}
		lines = append(lines, " "+prefix+m.text)
	}
	if len(lines) == 0 {
		lines = append(lines, " No chat messages")
	}
	a.chatVP.SetContent(strings.Join(lines, "\n"))
	a.chatVP.GotoBottom()
	return a
}

func (a App) renderEvents() App {
	if !a.eventsReady {
		return a
	}
	var lines []string
	for _, ev := range a.events {
		line := fmt.Sprintf(" %s %s", ev.Type, ev.Source)
		lines = append(lines, line)
	}
	if len(lines) == 0 {
		lines = append(lines, " No events")
	}
	a.eventsVP.SetContent(strings.Join(lines, "\n"))
	a.eventsVP.GotoBottom()
	return a
}

// View renders the full TUI.
func (a App) View() string {
	if a.width == 0 {
		return "Initializing..."
	}

	// Status bar (1 line)
	statusBar := a.viewStatusBar()

	// Main area: sidebar | right panels
	mainH := a.mainAreaHeight()
	sidebar := a.viewSidebar(mainH)

	rightW := a.width - sidebarWidth - 3
	if rightW < 10 {
		rightW = 10
	}

	// Right column: 3 panels whose rendered heights (content + 2 border each) sum to mainH
	detailContent, thoughtsContent, bottomContent := a.rightPanelContentHeights()

	detail := a.viewDetail(rightW, detailContent)
	thoughts := a.viewThoughts(rightW, thoughtsContent)
	chatOrEvents := a.viewChatOrEvents(rightW, bottomContent)

	rightCol := lipgloss.JoinVertical(lipgloss.Left, detail, thoughts, chatOrEvents)

	mainArea := lipgloss.JoinHorizontal(lipgloss.Top, sidebar, rightCol)

	// Command bar (3 lines: 1 content + 2 border)
	cmdBar := a.viewCommand()

	// Show error inline in the status bar rather than adding a line
	if a.lastError != "" {
		statusBar = StyleStatusBar.Width(a.width).Render(
			StyleError.Render(" "+a.lastError),
		)
	}

	return lipgloss.JoinVertical(lipgloss.Left, statusBar, mainArea, cmdBar)
}

func (a App) viewStatusBar() string {
	var connIndicator string
	if a.connected {
		connIndicator = StyleStatusConnected.Render("● connected")
	} else {
		connIndicator = StyleStatusDisconnected.Render("○ " + a.connState)
	}

	agents := fmt.Sprintf("%d agents", a.agentCount)
	ver := "autopoiesis"
	if a.version != "" {
		ver = "autopoiesis " + a.version
	}

	left := connIndicator + "  " + agents
	right := ver
	gap := a.width - lipgloss.Width(left) - lipgloss.Width(right) - 2
	if gap < 1 {
		gap = 1
	}

	return StyleStatusBar.Width(a.width).Render(left + strings.Repeat(" ", gap) + right)
}

func (a App) viewSidebar(totalH int) string {
	style := StylePanel
	if a.focus == PanelAgents {
		style = StylePanelFocused
	}

	title := StylePanelTitle.Render("Agents")
	// totalH includes border (2 lines), so content area = totalH - 2
	// Subtract 1 more for title line
	contentH := totalH - 3
	if contentH < 1 {
		contentH = 1
	}

	var lines []string
	for i, agent := range a.agents {
		bullet := AgentStateBullet(agent.State)
		name := agent.Name
		if name == "" && len(agent.ID) >= 8 {
			name = agent.ID[:8]
		}
		if i == a.selectedIdx {
			lines = append(lines, fmt.Sprintf(" %s %s", bullet, StyleAgentSelected.Render("> "+name)))
		} else {
			lines = append(lines, fmt.Sprintf(" %s %s", bullet, StyleAgentNormal.Render("  "+name)))
		}
		if len(lines) >= contentH {
			break
		}
	}
	for len(lines) < contentH {
		lines = append(lines, "")
	}

	content := lipgloss.JoinVertical(lipgloss.Left, append([]string{title}, lines...)...)
	// Height is content height inside border; border adds 2 more for total = totalH
	return style.Width(sidebarWidth).Height(totalH - 2).Render(content)
}

func (a App) viewDetail(w, contentH int) string {
	style := StylePanel

	if len(a.agents) == 0 || a.selectedIdx >= len(a.agents) {
		return style.Width(w).Height(contentH).Render(" No agent selected")
	}

	agent := a.agents[a.selectedIdx]
	stateStyle := lipgloss.NewStyle().Foreground(AgentStateColor(agent.State)).Bold(true)
	title := StylePanelTitle.Render(
		fmt.Sprintf("Agent: %s [%s]", agent.Name, stateStyle.Render(agent.State)),
	)

	caps := "none"
	if len(agent.Capabilities) > 0 {
		caps = strings.Join(agent.Capabilities, ", ")
	}

	lines := []string{
		title,
		fmt.Sprintf(" ID: %s", agent.ID),
		fmt.Sprintf(" Capabilities: %s", caps),
		fmt.Sprintf(" Thoughts: %d", agent.ThoughtCount),
	}
	if agent.Parent != nil {
		lines = append(lines, fmt.Sprintf(" Parent: %s", *agent.Parent))
	}

	content := lipgloss.JoinVertical(lipgloss.Left, lines...)
	return style.Width(w).Height(contentH).Render(content)
}

func (a App) viewThoughts(w, contentH int) string {
	style := StylePanel
	if a.focus == PanelThoughts {
		style = StylePanelFocused
	}

	title := StylePanelTitle.Render("Thoughts")
	var vpView string
	if a.thoughtsReady {
		vpView = a.thoughtsVP.View()
	}
	inner := lipgloss.JoinVertical(lipgloss.Left, title, vpView)
	return style.Width(w).Height(contentH).Render(inner)
}

func (a App) viewChatOrEvents(w, contentH int) string {
	if a.chatActive || len(a.chatMessages) > 0 {
		return a.viewChat(w, contentH)
	}
	return a.viewEvents(w, contentH)
}

func (a App) viewChat(w, contentH int) string {
	style := StylePanel
	if a.focus == PanelChat {
		style = StylePanelFocused
	}

	titleText := "Chat"
	if a.chatActive && a.chatAgentID != "" {
		short := a.chatAgentID
		if len(short) > 8 {
			short = short[:8]
		}
		titleText = fmt.Sprintf("Chat [%s]", short)
	}
	title := StylePanelTitle.Render(titleText)
	var vpView string
	if a.chatReady {
		vpView = a.chatVP.View()
	}
	inner := lipgloss.JoinVertical(lipgloss.Left, title, vpView)
	return style.Width(w).Height(contentH).Render(inner)
}

func (a App) viewEvents(w, contentH int) string {
	style := StylePanel
	if a.focus == PanelEvents {
		style = StylePanelFocused
	}

	title := StylePanelTitle.Render("Events")
	var vpView string
	if a.eventsReady {
		vpView = a.eventsVP.View()
	}
	inner := lipgloss.JoinVertical(lipgloss.Left, title, vpView)
	return style.Width(w).Height(contentH).Render(inner)
}

func (a App) viewCommand() string {
	style := StyleCommandInput
	if a.cmdFocused {
		style = StyleCommandInputFocused
	}
	return style.Width(a.width).Render(a.cmdInput.View())
}
