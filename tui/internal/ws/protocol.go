package ws

import "encoding/json"

// Envelope is the base message structure for all WS messages.
type Envelope struct {
	Type      string `json:"type"`
	RequestID string `json:"requestId,omitempty"`
}

// --- Client → Server Messages ---

type PingMsg struct {
	Type      string `json:"type"`
	RequestID string `json:"requestId,omitempty"`
}

type SystemInfoMsg struct {
	Type      string `json:"type"`
	RequestID string `json:"requestId,omitempty"`
}

type SetStreamFormatMsg struct {
	Type      string `json:"type"`
	Format    string `json:"format"`
	RequestID string `json:"requestId,omitempty"`
}

type SubscribeMsg struct {
	Type      string `json:"type"`
	Channel   string `json:"channel"`
	RequestID string `json:"requestId,omitempty"`
}

type UnsubscribeMsg struct {
	Type      string `json:"type"`
	Channel   string `json:"channel"`
	RequestID string `json:"requestId,omitempty"`
}

type ListAgentsMsg struct {
	Type      string `json:"type"`
	RequestID string `json:"requestId,omitempty"`
}

type GetAgentMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	RequestID string `json:"requestId,omitempty"`
}

type CreateAgentMsg struct {
	Type         string   `json:"type"`
	Name         string   `json:"name,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
	RequestID    string   `json:"requestId,omitempty"`
}

type AgentActionMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	Action    string `json:"action"`
	RequestID string `json:"requestId,omitempty"`
}

type StepAgentMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	RequestID string `json:"requestId,omitempty"`
}

type GetThoughtsMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	Limit     int    `json:"limit,omitempty"`
	RequestID string `json:"requestId,omitempty"`
}

type InjectThoughtMsg struct {
	Type        string `json:"type"`
	AgentID     string `json:"agentId"`
	Content     string `json:"content"`
	ThoughtType string `json:"thoughtType,omitempty"`
	RequestID   string `json:"requestId,omitempty"`
}

type GetEventsMsg struct {
	Type      string `json:"type"`
	Limit     int    `json:"limit,omitempty"`
	EventType string `json:"eventType,omitempty"`
	AgentID   string `json:"agentId,omitempty"`
	RequestID string `json:"requestId,omitempty"`
}

type StartChatMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	RequestID string `json:"requestId,omitempty"`
}

type ChatPromptMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	Text      string `json:"text"`
	RequestID string `json:"requestId,omitempty"`
}

type StopChatMsg struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	RequestID string `json:"requestId,omitempty"`
}

// --- Server → Client Data Structures ---

type AgentData struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	State        string   `json:"state"`
	Capabilities []string `json:"capabilities"`
	Parent       *string  `json:"parent"`
	Children     []string `json:"children"`
	ThoughtCount int      `json:"thoughtCount"`
	// Persistent agent fields (optional)
	Persistent  *bool  `json:"persistent,omitempty"`
	Version     any    `json:"version,omitempty"`
	LineageHash any    `json:"lineageHash,omitempty"`
	ParentRoot  any    `json:"parentRoot,omitempty"`
}

type ThoughtData struct {
	ID         string  `json:"id"`
	Timestamp  any     `json:"timestamp"`
	Type       string  `json:"type"`
	Confidence any     `json:"confidence"`
	Content    string  `json:"content"`
	Provenance *string `json:"provenance"`
	// Decision fields
	Alternatives []Alternative `json:"alternatives,omitempty"`
	Chosen       string        `json:"chosen,omitempty"`
	Rationale    any           `json:"rationale,omitempty"`
	// Action fields
	Capability *string `json:"capability,omitempty"`
	Result     string  `json:"result,omitempty"`
	// Observation fields
	Source *string `json:"source,omitempty"`
	Raw    string  `json:"raw,omitempty"`
	// Reflection fields
	Target  *string `json:"target,omitempty"`
	Insight *string `json:"insight,omitempty"`
}

type Alternative struct {
	Option string `json:"option"`
	Score  any    `json:"score"`
}

type EventData struct {
	ID        string            `json:"id"`
	Type      string            `json:"type"`
	Source    string            `json:"source"`
	AgentID   any               `json:"agentId"`
	Data      map[string]string `json:"data"`
	Timestamp any               `json:"timestamp"`
}

type SnapshotData struct {
	ID        string  `json:"id"`
	Timestamp any     `json:"timestamp"`
	Parent    any     `json:"parent"`
	Hash      string  `json:"hash"`
	Metadata  *string `json:"metadata"`
}

// --- Server Response Types ---

type ConnectedResponse struct {
	Type         string `json:"type"`
	ConnectionID string `json:"connectionId"`
	Version      string `json:"version"`
}

type SystemInfoResponse struct {
	Type            string `json:"type"`
	Version         string `json:"version"`
	Health          string `json:"health"`
	AgentCount      int    `json:"agentCount"`
	ConnectionCount int    `json:"connectionCount"`
	RequestID       string `json:"requestId,omitempty"`
}

type AgentsResponse struct {
	Type      string      `json:"type"`
	Agents    []AgentData `json:"agents"`
	RequestID string      `json:"requestId,omitempty"`
}

type AgentResponse struct {
	Type      string    `json:"type"`
	Agent     AgentData `json:"agent"`
	RequestID string    `json:"requestId,omitempty"`
}

type AgentCreatedResponse struct {
	Type      string    `json:"type"`
	Agent     AgentData `json:"agent"`
	RequestID string    `json:"requestId,omitempty"`
}

type AgentStateChangedResponse struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	State     string `json:"state"`
	RequestID string `json:"requestId,omitempty"`
}

type ThoughtsResponse struct {
	Type      string        `json:"type"`
	AgentID   string        `json:"agentId"`
	Thoughts  []ThoughtData `json:"thoughts"`
	Total     int           `json:"total"`
	RequestID string        `json:"requestId,omitempty"`
}

type ThoughtAddedResponse struct {
	Type      string      `json:"type"`
	AgentID   string      `json:"agentId"`
	Thought   ThoughtData `json:"thought"`
	RequestID string      `json:"requestId,omitempty"`
}

type EventsResponse struct {
	Type      string      `json:"type"`
	Events    []EventData `json:"events"`
	Count     int         `json:"count"`
	RequestID string      `json:"requestId,omitempty"`
}

type EventPush struct {
	Type  string    `json:"type"`
	Event EventData `json:"event"`
}

type ChatStartedResponse struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	SessionID string `json:"sessionId"`
	RequestID string `json:"requestId,omitempty"`
}

type ChatResponse struct {
	Type      string `json:"type"`
	AgentID   string `json:"agentId"`
	Text      string `json:"text"`
	SessionID string `json:"sessionId"`
	RequestID string `json:"requestId,omitempty"`
}

type ErrorResponse struct {
	Type      string `json:"type"`
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"requestId,omitempty"`
}

// ServerMessage is a parsed server message with its raw JSON.
type ServerMessage struct {
	Envelope
	Raw json.RawMessage
}

// ParseServerMessage extracts the type envelope and keeps raw JSON for further parsing.
func ParseServerMessage(data []byte) (ServerMessage, error) {
	var msg ServerMessage
	msg.Raw = json.RawMessage(data)
	err := json.Unmarshal(data, &msg.Envelope)
	return msg, err
}

// As unmarshals the raw message into a specific type.
func (m ServerMessage) As(v any) error {
	return json.Unmarshal(m.Raw, v)
}
