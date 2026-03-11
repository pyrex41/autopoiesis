package tui

import (
	"encoding/json"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/reuben/autopoiesis/tui/internal/ws"
)

func makeTestApp() App {
	// Create app without a real WS client (we'll test message handling directly)
	return App{
		config:    Config{WSURL: "ws://test:9080/ws"},
		connState: "disconnected",
	}
}

func makeServerMsg(data string) ws.ServerMessage {
	msg, _ := ws.ParseServerMessage([]byte(data))
	return msg
}

func TestHandleServerMessage_Connected(t *testing.T) {
	app := makeTestApp()
	msg := makeServerMsg(`{"type":"connected","connectionId":"c1","version":"0.3.0"}`)
	app = app.handleServerMessage(msg)

	if app.version != "0.3.0" {
		t.Errorf("version = %q, want 0.3.0", app.version)
	}
}

func TestHandleServerMessage_SystemInfo(t *testing.T) {
	app := makeTestApp()
	msg := makeServerMsg(`{"type":"system_info","version":"0.1.0","health":"ok","agentCount":5,"connectionCount":1}`)
	app = app.handleServerMessage(msg)

	if app.version != "0.1.0" {
		t.Errorf("version = %q", app.version)
	}
	if app.agentCount != 5 {
		t.Errorf("agentCount = %d, want 5", app.agentCount)
	}
}

func TestHandleServerMessage_Agents(t *testing.T) {
	app := makeTestApp()
	msg := makeServerMsg(`{"type":"agents","agents":[{"id":"a1","name":"alice","state":"running","capabilities":[],"parent":null,"children":[],"thoughtCount":3},{"id":"a2","name":"bob","state":"idle","capabilities":["think"],"parent":null,"children":[],"thoughtCount":0}]}`)
	app = app.handleServerMessage(msg)

	if len(app.agents) != 2 {
		t.Fatalf("len(agents) = %d, want 2", len(app.agents))
	}
	if app.agents[0].Name != "alice" {
		t.Errorf("agents[0].Name = %q", app.agents[0].Name)
	}
	if app.agents[1].Name != "bob" {
		t.Errorf("agents[1].Name = %q", app.agents[1].Name)
	}
	if app.agentCount != 2 {
		t.Errorf("agentCount = %d", app.agentCount)
	}
}

func TestHandleServerMessage_AgentCreated(t *testing.T) {
	app := makeTestApp()
	app.agents = []ws.AgentData{{ID: "a1", Name: "existing", State: "idle"}}

	msg := makeServerMsg(`{"type":"agent_created","agent":{"id":"a2","name":"new","state":"initialized","capabilities":["act"],"parent":null,"children":[],"thoughtCount":0}}`)
	app = app.handleServerMessage(msg)

	if len(app.agents) != 2 {
		t.Fatalf("len(agents) = %d, want 2", len(app.agents))
	}
	if app.agents[1].Name != "new" {
		t.Errorf("agents[1].Name = %q", app.agents[1].Name)
	}
}

func TestHandleServerMessage_AgentStateChanged(t *testing.T) {
	app := makeTestApp()
	app.agents = []ws.AgentData{
		{ID: "a1", Name: "test", State: "idle"},
	}

	msg := makeServerMsg(`{"type":"agent_state_changed","agentId":"a1","state":"running"}`)
	app = app.handleServerMessage(msg)

	if app.agents[0].State != "running" {
		t.Errorf("agents[0].State = %q, want running", app.agents[0].State)
	}
}

func TestHandleServerMessage_Thoughts(t *testing.T) {
	app := makeTestApp()
	app.selectedID = "a1"
	app.width = 80
	app.height = 24
	app = app.recalcLayout()

	msg := makeServerMsg(`{"type":"thoughts","agentId":"a1","thoughts":[{"id":"t1","timestamp":"now","type":"observation","confidence":0.8,"content":"saw something","provenance":null}],"total":1}`)
	app = app.handleServerMessage(msg)

	if len(app.thoughts) != 1 {
		t.Fatalf("len(thoughts) = %d, want 1", len(app.thoughts))
	}
	if app.thoughts[0].Content != "saw something" {
		t.Errorf("thoughts[0].Content = %q", app.thoughts[0].Content)
	}
}

func TestHandleServerMessage_ThoughtAdded(t *testing.T) {
	app := makeTestApp()
	app.selectedID = "a1"
	app.width = 80
	app.height = 24
	app = app.recalcLayout()
	app.thoughts = []ws.ThoughtData{{ID: "t1", Type: "observation", Content: "first"}}

	msg := makeServerMsg(`{"type":"thought_added","agentId":"a1","thought":{"id":"t2","timestamp":"now","type":"action","confidence":1.0,"content":"did something","provenance":null}}`)
	app = app.handleServerMessage(msg)

	if len(app.thoughts) != 2 {
		t.Fatalf("len(thoughts) = %d, want 2", len(app.thoughts))
	}
}

func TestHandleServerMessage_ThoughtsWrongAgent(t *testing.T) {
	app := makeTestApp()
	app.selectedID = "a1"

	msg := makeServerMsg(`{"type":"thoughts","agentId":"a2","thoughts":[{"id":"t1","timestamp":"now","type":"observation","confidence":0.8,"content":"not mine","provenance":null}],"total":1}`)
	app = app.handleServerMessage(msg)

	if len(app.thoughts) != 0 {
		t.Errorf("should not store thoughts for unselected agent")
	}
}

func TestHandleServerMessage_Error(t *testing.T) {
	app := makeTestApp()
	msg := makeServerMsg(`{"type":"error","code":"bad_request","message":"missing field"}`)
	app = app.handleServerMessage(msg)

	if app.lastError == "" {
		t.Error("lastError should be set")
	}
	if app.lastError != "[bad_request] missing field" {
		t.Errorf("lastError = %q", app.lastError)
	}
}

func TestHandleServerMessage_ChatResponse(t *testing.T) {
	app := makeTestApp()
	app.width = 80
	app.height = 24
	app = app.recalcLayout()

	msg := makeServerMsg(`{"type":"chat_response","agentId":"a1","text":"hello human","sessionId":"a1"}`)
	app = app.handleServerMessage(msg)

	if len(app.chatMessages) != 1 {
		t.Fatalf("len(chatMessages) = %d, want 1", len(app.chatMessages))
	}
	if app.chatMessages[0].role != "agent" {
		t.Errorf("role = %q, want agent", app.chatMessages[0].role)
	}
	if app.chatMessages[0].text != "hello human" {
		t.Errorf("text = %q", app.chatMessages[0].text)
	}
}

func TestHandleServerMessage_EventPush(t *testing.T) {
	app := makeTestApp()
	app.width = 80
	app.height = 24
	app = app.recalcLayout()

	msg := makeServerMsg(`{"type":"event","event":{"id":"e1","type":"agent-created","source":"system","agentId":"a1","data":{},"timestamp":"now"}}`)
	app = app.handleServerMessage(msg)

	if len(app.events) != 1 {
		t.Fatalf("len(events) = %d, want 1", len(app.events))
	}
}

func TestHandleServerMessage_EventsOverflow(t *testing.T) {
	app := makeTestApp()
	app.width = 80
	app.height = 24
	app = app.recalcLayout()

	// Fill 200 events
	for i := range 201 {
		app.events = append(app.events, ws.EventData{ID: string(rune(i))})
	}

	msg := makeServerMsg(`{"type":"event","event":{"id":"overflow","type":"test","source":"s","agentId":null,"data":{},"timestamp":"now"}}`)
	app = app.handleServerMessage(msg)

	if len(app.events) > 200 {
		t.Errorf("events should be capped at 200, got %d", len(app.events))
	}
}

func TestExecuteCommand_Help(t *testing.T) {
	app := makeTestApp()
	app, _ = app.executeCommand("help", nil)
	if app.lastError == "" {
		t.Error("help should set lastError with command list")
	}
}

func TestExecuteCommand_Unknown(t *testing.T) {
	app := makeTestApp()
	app, _ = app.executeCommand("foobar", nil)
	if app.lastError == "" {
		t.Error("unknown command should set error")
	}
}

func TestExecuteCommand_CreateNoArgs(t *testing.T) {
	app := makeTestApp()
	app, _ = app.executeCommand("create", nil)
	if app.lastError == "" {
		t.Error("create without args should set error")
	}
}

func TestExecuteCommand_StepNoAgent(t *testing.T) {
	app := makeTestApp()
	app, _ = app.executeCommand("step", nil)
	if app.lastError == "" {
		t.Error("step without selected agent should set error")
	}
}

func TestExecuteCommand_ChatNoAgent(t *testing.T) {
	app := makeTestApp()
	app, _ = app.executeCommand("chat hello", nil)
	if app.lastError == "" {
		t.Error("chat without selected agent should set error")
	}
}

func TestExecuteCommand_InjectNoAgent(t *testing.T) {
	app := makeTestApp()
	app, _ = app.executeCommand("inject test", nil)
	if app.lastError == "" {
		t.Error("inject without selected agent should set error")
	}
}

func TestPanelCycling(t *testing.T) {
	app := makeTestApp()
	if app.focus != PanelAgents {
		t.Errorf("initial focus = %v, want PanelAgents", app.focus)
	}

	// Tab forward through non-command panels
	expected := []Panel{PanelThoughts, PanelChat, PanelEvents, PanelCommand}
	for _, want := range expected {
		result, _ := app.Update(tea.KeyMsg{Type: tea.KeyTab})
		app = result.(App)
		if app.focus != want {
			t.Errorf("after tab: focus = %v, want %v", app.focus, want)
		}
	}

	// When in command panel, esc returns to agents
	result, _ := app.Update(tea.KeyMsg{Type: tea.KeyEscape})
	app = result.(App)
	if app.focus != PanelAgents {
		t.Errorf("after esc from command: focus = %v, want PanelAgents", app.focus)
	}
}

func TestPanelString(t *testing.T) {
	panels := []struct {
		p    Panel
		want string
	}{
		{PanelAgents, "agents"},
		{PanelThoughts, "thoughts"},
		{PanelChat, "chat"},
		{PanelEvents, "events"},
		{PanelCommand, "command"},
	}
	for _, tt := range panels {
		if got := tt.p.String(); got != tt.want {
			t.Errorf("Panel(%d).String() = %q, want %q", tt.p, got, tt.want)
		}
	}
}

func TestFocusCommand(t *testing.T) {
	app := makeTestApp()
	result, _ := app.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{':'}})
	app = result.(App)
	if app.focus != PanelCommand {
		t.Errorf("':' should focus command panel, got %v", app.focus)
	}
	if !app.cmdFocused {
		t.Error("cmdFocused should be true")
	}
}

func TestWindowSize(t *testing.T) {
	app := makeTestApp()
	result, _ := app.Update(tea.WindowSizeMsg{Width: 120, Height: 40})
	app = result.(App)
	if app.width != 120 || app.height != 40 {
		t.Errorf("size = %dx%d, want 120x40", app.width, app.height)
	}
}

func TestView_NoSize(t *testing.T) {
	app := makeTestApp()
	v := app.View()
	if v != "Initializing..." {
		t.Errorf("View with no size = %q, want Initializing...", v)
	}
}

func TestView_WithSize(t *testing.T) {
	app := makeTestApp()
	app.width = 80
	app.height = 24
	app = app.recalcLayout()
	v := app.View()
	if len(v) == 0 {
		t.Error("View should produce output")
	}
}

func TestAgentNavigation(t *testing.T) {
	app := makeTestApp()
	app.agents = []ws.AgentData{
		{ID: "a1", Name: "first"},
		{ID: "a2", Name: "second"},
		{ID: "a3", Name: "third"},
	}
	app.focus = PanelAgents

	// Move down
	app = app.handleDown()
	if app.selectedIdx != 1 {
		t.Errorf("selectedIdx = %d, want 1", app.selectedIdx)
	}

	app = app.handleDown()
	if app.selectedIdx != 2 {
		t.Errorf("selectedIdx = %d, want 2", app.selectedIdx)
	}

	// Can't go past end
	app = app.handleDown()
	if app.selectedIdx != 2 {
		t.Errorf("selectedIdx = %d, want 2 (clamped)", app.selectedIdx)
	}

	// Move up
	app = app.handleUp()
	if app.selectedIdx != 1 {
		t.Errorf("selectedIdx = %d, want 1", app.selectedIdx)
	}

	// Up to top
	app = app.handleUp()
	if app.selectedIdx != 0 {
		t.Errorf("selectedIdx = %d, want 0", app.selectedIdx)
	}

	// Can't go past start
	app = app.handleUp()
	if app.selectedIdx != 0 {
		t.Errorf("selectedIdx = %d, want 0 (clamped)", app.selectedIdx)
	}
}

func TestSelectedIdxClampOnAgentList(t *testing.T) {
	app := makeTestApp()
	app.selectedIdx = 5

	msg := makeServerMsg(`{"type":"agents","agents":[{"id":"a1","name":"only","state":"idle","capabilities":[],"parent":null,"children":[],"thoughtCount":0}]}`)
	app = app.handleServerMessage(msg)

	if app.selectedIdx != 0 {
		t.Errorf("selectedIdx should clamp to 0, got %d", app.selectedIdx)
	}
}

// Verify JSON round-trip of all client message types
func TestAllClientMessagesRoundTrip(t *testing.T) {
	messages := []any{
		ws.PingMsg{Type: "ping"},
		ws.SystemInfoMsg{Type: "system_info"},
		ws.SetStreamFormatMsg{Type: "set_stream_format", Format: "json"},
		ws.SubscribeMsg{Type: "subscribe", Channel: "agents"},
		ws.UnsubscribeMsg{Type: "unsubscribe", Channel: "events"},
		ws.ListAgentsMsg{Type: "list_agents"},
		ws.GetAgentMsg{Type: "get_agent", AgentID: "a1"},
		ws.CreateAgentMsg{Type: "create_agent", Name: "test"},
		ws.AgentActionMsg{Type: "agent_action", AgentID: "a1", Action: "start"},
		ws.StepAgentMsg{Type: "step_agent", AgentID: "a1"},
		ws.GetThoughtsMsg{Type: "get_thoughts", AgentID: "a1", Limit: 50},
		ws.InjectThoughtMsg{Type: "inject_thought", AgentID: "a1", Content: "hi", ThoughtType: "observation"},
		ws.GetEventsMsg{Type: "get_events", Limit: 20},
		ws.StartChatMsg{Type: "start_chat", AgentID: "a1"},
		ws.ChatPromptMsg{Type: "chat_prompt", AgentID: "a1", Text: "hello"},
		ws.StopChatMsg{Type: "stop_chat", AgentID: "a1"},
	}

	for _, msg := range messages {
		data, err := json.Marshal(msg)
		if err != nil {
			t.Errorf("Marshal %T: %v", msg, err)
			continue
		}
		var env ws.Envelope
		if err := json.Unmarshal(data, &env); err != nil {
			t.Errorf("Unmarshal envelope %T: %v", msg, err)
			continue
		}
		if env.Type == "" {
			t.Errorf("%T: type field is empty", msg)
		}
	}
}
