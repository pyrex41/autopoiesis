package ws

import (
	"encoding/json"
	"testing"
)

func TestPlistToMap(t *testing.T) {
	// Object format (passthrough)
	obj := `{"id":"a1","name":"test"}`
	m, err := plistToMap(json.RawMessage(obj))
	if err != nil {
		t.Fatal(err)
	}
	if m["id"] != "a1" {
		t.Errorf("id = %v", m["id"])
	}

	// Plist array format
	plist := `["id","a1","name","test","thoughtCount",5]`
	m, err = plistToMap(json.RawMessage(plist))
	if err != nil {
		t.Fatal(err)
	}
	if m["id"] != "a1" {
		t.Errorf("id = %v", m["id"])
	}
	if m["name"] != "test" {
		t.Errorf("name = %v", m["name"])
	}
	if m["thoughtCount"] != float64(5) {
		t.Errorf("thoughtCount = %v", m["thoughtCount"])
	}
}

func TestAgentDataUnmarshalPlist(t *testing.T) {
	plist := `["id","a1","name","smoketest","state","initialized","capabilities",[],"parent",null,"children",[],"thoughtCount",0]`
	var a AgentData
	if err := json.Unmarshal([]byte(plist), &a); err != nil {
		t.Fatal(err)
	}
	if a.ID != "a1" {
		t.Errorf("ID = %q", a.ID)
	}
	if a.Name != "smoketest" {
		t.Errorf("Name = %q", a.Name)
	}
	if a.State != "initialized" {
		t.Errorf("State = %q", a.State)
	}
	if a.ThoughtCount != 0 {
		t.Errorf("ThoughtCount = %d", a.ThoughtCount)
	}
	if a.Parent != nil {
		t.Errorf("Parent = %v, want nil", a.Parent)
	}
}

func TestAgentDataUnmarshalObject(t *testing.T) {
	obj := `{"id":"a2","name":"obj","state":"running","capabilities":["think"],"parent":null,"children":[],"thoughtCount":3}`
	var a AgentData
	if err := json.Unmarshal([]byte(obj), &a); err != nil {
		t.Fatal(err)
	}
	if a.ID != "a2" || a.Name != "obj" || a.State != "running" || a.ThoughtCount != 3 {
		t.Errorf("unexpected: %+v", a)
	}
}

func TestAgentsResponseWithPlist(t *testing.T) {
	// Real wire format from server
	wire := `{"type":"agents","agents":[["id","A0234D70","name","smoketest","state","initialized","capabilities",[],"parent",null,"children",[],"thoughtCount",0]]}`
	msg, _ := ParseServerMessage([]byte(wire))
	var resp AgentsResponse
	if err := msg.As(&resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Agents) != 1 {
		t.Fatalf("len = %d", len(resp.Agents))
	}
	if resp.Agents[0].ID != "A0234D70" {
		t.Errorf("ID = %q", resp.Agents[0].ID)
	}
	if resp.Agents[0].Name != "smoketest" {
		t.Errorf("Name = %q", resp.Agents[0].Name)
	}
}
