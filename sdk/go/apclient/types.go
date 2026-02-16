// Package apclient provides a Go client for the Autopoiesis Control API.
//
// It wraps the REST API and SSE event stream, making it easy for external
// agent systems (like PicoClaw) to interact with a running Autopoiesis instance.
package apclient

// Agent represents a cognitive agent in Autopoiesis.
type Agent struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	State        string   `json:"state"`
	Capabilities []string `json:"capabilities"`
	Parent       string   `json:"parent,omitempty"`
	Children     []string `json:"children"`
	ThoughtCount int      `json:"thought_count"`
}

// Snapshot represents a point-in-time capture of agent cognitive state.
type Snapshot struct {
	ID         string      `json:"id"`
	Timestamp  float64     `json:"timestamp"`
	Parent     string      `json:"parent,omitempty"`
	Hash       string      `json:"hash"`
	Metadata   interface{} `json:"metadata,omitempty"`
	AgentState string      `json:"agent_state,omitempty"`
}

// Branch represents a named branch in the snapshot DAG.
type Branch struct {
	Name    string  `json:"name"`
	Head    string  `json:"head,omitempty"`
	Created float64 `json:"created"`
}

// Thought represents a unit of agent cognition.
type Thought struct {
	ID         string  `json:"id"`
	Type       string  `json:"type"`
	Content    string  `json:"content"`
	Confidence float64 `json:"confidence"`
	Timestamp  float64 `json:"timestamp"`
}

// Capability represents an agent capability.
type Capability struct {
	Name        string           `json:"name"`
	Description string           `json:"description"`
	Parameters  []CapabilityParam `json:"parameters"`
}

// CapabilityParam describes a capability parameter.
type CapabilityParam struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

// PendingRequest represents a human-in-the-loop input request.
type PendingRequest struct {
	ID        string   `json:"id"`
	Prompt    string   `json:"prompt"`
	Context   string   `json:"context,omitempty"`
	Options   []string `json:"options"`
	Status    string   `json:"status"`
	Default   string   `json:"default,omitempty"`
	CreatedAt float64  `json:"created_at"`
}

// SystemInfo represents the Autopoiesis system status.
type SystemInfo struct {
	Version         string `json:"version"`
	Platform        string `json:"platform"`
	AgentCount      int    `json:"agent_count"`
	RunningAgents   int    `json:"running_agents"`
	BranchCount     int    `json:"branch_count"`
	PendingRequests int    `json:"pending_requests"`
	SnapshotStore   string `json:"snapshot_store"`
}

// CycleResult represents the result of a cognitive cycle.
type CycleResult struct {
	AgentID string `json:"agent_id"`
	State   string `json:"state"`
	Result  string `json:"result,omitempty"`
}

// DiffResult represents the diff between two snapshots.
type DiffResult struct {
	From string `json:"from"`
	To   string `json:"to"`
	Diff string `json:"diff"`
}

// Event represents a real-time event from the SSE stream.
type Event struct {
	Type string `json:"type"`
	Data string `json:"data"`
}

// APIError represents an error response from the API.
type APIError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func (e *APIError) String() string {
	if e.Message != "" {
		return e.Message
	}
	return e.Error
}
