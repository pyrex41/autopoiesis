package ws

import (
	"encoding/json"
	"testing"
)

func TestParseServerMessage(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantType string
		wantReqID string
	}{
		{
			name:     "connected message",
			input:    `{"type":"connected","connectionId":"abc-123","version":"0.1.0"}`,
			wantType: "connected",
		},
		{
			name:     "agents response",
			input:    `{"type":"agents","agents":[],"requestId":"req-1"}`,
			wantType: "agents",
			wantReqID: "req-1",
		},
		{
			name:     "error response",
			input:    `{"type":"error","code":"not_found","message":"agent not found"}`,
			wantType: "error",
		},
		{
			name:     "pong",
			input:    `{"type":"pong"}`,
			wantType: "pong",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			msg, err := ParseServerMessage([]byte(tt.input))
			if err != nil {
				t.Fatalf("ParseServerMessage() error = %v", err)
			}
			if msg.Type != tt.wantType {
				t.Errorf("Type = %q, want %q", msg.Type, tt.wantType)
			}
			if msg.RequestID != tt.wantReqID {
				t.Errorf("RequestID = %q, want %q", msg.RequestID, tt.wantReqID)
			}
		})
	}
}

func TestParseServerMessageAs(t *testing.T) {
	t.Run("connected response", func(t *testing.T) {
		input := `{"type":"connected","connectionId":"uuid-1","version":"0.2.0"}`
		msg, err := ParseServerMessage([]byte(input))
		if err != nil {
			t.Fatal(err)
		}
		var resp ConnectedResponse
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		if resp.ConnectionID != "uuid-1" {
			t.Errorf("ConnectionID = %q, want %q", resp.ConnectionID, "uuid-1")
		}
		if resp.Version != "0.2.0" {
			t.Errorf("Version = %q, want %q", resp.Version, "0.2.0")
		}
	})

	t.Run("agents response", func(t *testing.T) {
		input := `{"type":"agents","agents":[{"id":"a1","name":"test","state":"running","capabilities":["think"],"parent":null,"children":[],"thoughtCount":5}]}`
		msg, _ := ParseServerMessage([]byte(input))
		var resp AgentsResponse
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		if len(resp.Agents) != 1 {
			t.Fatalf("len(Agents) = %d, want 1", len(resp.Agents))
		}
		a := resp.Agents[0]
		if a.ID != "a1" {
			t.Errorf("ID = %q, want %q", a.ID, "a1")
		}
		if a.Name != "test" {
			t.Errorf("Name = %q, want %q", a.Name, "test")
		}
		if a.State != "running" {
			t.Errorf("State = %q, want %q", a.State, "running")
		}
		if len(a.Capabilities) != 1 || a.Capabilities[0] != "think" {
			t.Errorf("Capabilities = %v, want [think]", a.Capabilities)
		}
		if a.Parent != nil {
			t.Errorf("Parent = %v, want nil", a.Parent)
		}
		if a.ThoughtCount != 5 {
			t.Errorf("ThoughtCount = %d, want 5", a.ThoughtCount)
		}
	})

	t.Run("thought with decision fields", func(t *testing.T) {
		input := `{"type":"thought_added","agentId":"a1","thought":{"id":"t1","timestamp":"2026-01-01","type":"decision","confidence":0.9,"content":"choose X","provenance":null,"alternatives":[{"option":"X","score":0.9},{"option":"Y","score":0.3}],"chosen":"X","rationale":"better fit"}}`
		msg, _ := ParseServerMessage([]byte(input))
		var resp ThoughtAddedResponse
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		th := resp.Thought
		if th.Type != "decision" {
			t.Errorf("Type = %q, want decision", th.Type)
		}
		if len(th.Alternatives) != 2 {
			t.Fatalf("len(Alternatives) = %d, want 2", len(th.Alternatives))
		}
		if th.Alternatives[0].Option != "X" {
			t.Errorf("Alternatives[0].Option = %q, want X", th.Alternatives[0].Option)
		}
		if th.Chosen != "X" {
			t.Errorf("Chosen = %q, want X", th.Chosen)
		}
	})

	t.Run("system info response", func(t *testing.T) {
		input := `{"type":"system_info","version":"0.1.0","health":"ok","agentCount":3,"connectionCount":2}`
		msg, _ := ParseServerMessage([]byte(input))
		var resp SystemInfoResponse
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		if resp.Version != "0.1.0" {
			t.Errorf("Version = %q", resp.Version)
		}
		if resp.AgentCount != 3 {
			t.Errorf("AgentCount = %d", resp.AgentCount)
		}
		if resp.ConnectionCount != 2 {
			t.Errorf("ConnectionCount = %d", resp.ConnectionCount)
		}
	})

	t.Run("error response", func(t *testing.T) {
		input := `{"type":"error","code":"invalid_agent","message":"agent not found","requestId":"r5"}`
		msg, _ := ParseServerMessage([]byte(input))
		var resp ErrorResponse
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		if resp.Code != "invalid_agent" {
			t.Errorf("Code = %q", resp.Code)
		}
		if resp.Message != "agent not found" {
			t.Errorf("Message = %q", resp.Message)
		}
		if resp.RequestID != "r5" {
			t.Errorf("RequestID = %q", resp.RequestID)
		}
	})

	t.Run("event push", func(t *testing.T) {
		input := `{"type":"event","event":{"id":"e1","type":"agent-created","source":"system","agentId":"a1","data":{"name":"test"},"timestamp":"2026-01-01"}}`
		msg, _ := ParseServerMessage([]byte(input))
		var resp EventPush
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		if resp.Event.ID != "e1" {
			t.Errorf("Event.ID = %q", resp.Event.ID)
		}
		if resp.Event.Type != "agent-created" {
			t.Errorf("Event.Type = %q", resp.Event.Type)
		}
		if resp.Event.Data["name"] != "test" {
			t.Errorf("Event.Data[name] = %q", resp.Event.Data["name"])
		}
	})

	t.Run("persistent agent fields", func(t *testing.T) {
		input := `{"type":"agent","agent":{"id":"a1","name":"dual","state":"running","capabilities":[],"parent":null,"children":["c1"],"thoughtCount":10,"persistent":true,"version":3,"lineageHash":"abc"}}`
		msg, _ := ParseServerMessage([]byte(input))
		var resp AgentResponse
		if err := msg.As(&resp); err != nil {
			t.Fatal(err)
		}
		a := resp.Agent
		if a.Persistent == nil || !*a.Persistent {
			t.Error("Persistent should be true")
		}
		if len(a.Children) != 1 || a.Children[0] != "c1" {
			t.Errorf("Children = %v", a.Children)
		}
	})
}

func TestClientMessageSerialization(t *testing.T) {
	tests := []struct {
		name string
		msg  any
		want map[string]any
	}{
		{
			name: "ping",
			msg:  PingMsg{Type: "ping"},
			want: map[string]any{"type": "ping"},
		},
		{
			name: "create_agent",
			msg:  CreateAgentMsg{Type: "create_agent", Name: "test", Capabilities: []string{"think", "act"}},
			want: map[string]any{"type": "create_agent", "name": "test"},
		},
		{
			name: "subscribe",
			msg:  SubscribeMsg{Type: "subscribe", Channel: "agents", RequestID: "r1"},
			want: map[string]any{"type": "subscribe", "channel": "agents", "requestId": "r1"},
		},
		{
			name: "agent_action",
			msg:  AgentActionMsg{Type: "agent_action", AgentID: "a1", Action: "start"},
			want: map[string]any{"type": "agent_action", "agentId": "a1", "action": "start"},
		},
		{
			name: "set_stream_format",
			msg:  SetStreamFormatMsg{Type: "set_stream_format", Format: "json"},
			want: map[string]any{"type": "set_stream_format", "format": "json"},
		},
		{
			name: "get_thoughts",
			msg:  GetThoughtsMsg{Type: "get_thoughts", AgentID: "a1", Limit: 50},
			want: map[string]any{"type": "get_thoughts", "agentId": "a1", "limit": float64(50)},
		},
		{
			name: "chat_prompt",
			msg:  ChatPromptMsg{Type: "chat_prompt", AgentID: "a1", Text: "hello"},
			want: map[string]any{"type": "chat_prompt", "agentId": "a1", "text": "hello"},
		},
		{
			name: "inject_thought",
			msg:  InjectThoughtMsg{Type: "inject_thought", AgentID: "a1", Content: "test", ThoughtType: "observation"},
			want: map[string]any{"type": "inject_thought", "agentId": "a1", "content": "test", "thoughtType": "observation"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := json.Marshal(tt.msg)
			if err != nil {
				t.Fatalf("Marshal error: %v", err)
			}
			var got map[string]any
			if err := json.Unmarshal(data, &got); err != nil {
				t.Fatalf("Unmarshal error: %v", err)
			}
			for k, v := range tt.want {
				if got[k] != v {
					t.Errorf("field %q = %v, want %v", k, got[k], v)
				}
			}
		})
	}
}

func TestOmitEmptyFields(t *testing.T) {
	// requestId should be omitted when empty
	msg := PingMsg{Type: "ping"}
	data, _ := json.Marshal(msg)
	var m map[string]any
	json.Unmarshal(data, &m)
	if _, ok := m["requestId"]; ok {
		t.Error("requestId should be omitted when empty")
	}

	// But present when set
	msg2 := PingMsg{Type: "ping", RequestID: "r1"}
	data2, _ := json.Marshal(msg2)
	json.Unmarshal(data2, &m)
	if m["requestId"] != "r1" {
		t.Errorf("requestId = %v, want r1", m["requestId"])
	}
}

func TestAgentDataNullParent(t *testing.T) {
	input := `{"id":"a1","name":"test","state":"idle","capabilities":[],"parent":null,"children":[],"thoughtCount":0}`
	var a AgentData
	if err := json.Unmarshal([]byte(input), &a); err != nil {
		t.Fatal(err)
	}
	if a.Parent != nil {
		t.Errorf("Parent should be nil for null JSON")
	}

	input2 := `{"id":"a1","name":"test","state":"idle","capabilities":[],"parent":"p1","children":[],"thoughtCount":0}`
	var a2 AgentData
	if err := json.Unmarshal([]byte(input2), &a2); err != nil {
		t.Fatal(err)
	}
	if a2.Parent == nil || *a2.Parent != "p1" {
		t.Errorf("Parent should be 'p1', got %v", a2.Parent)
	}
}
