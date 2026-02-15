package apclient

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client is an Autopoiesis Control API client.
type Client struct {
	BaseURL    string
	APIKey     string
	HTTPClient *http.Client
}

// NewClient creates a new Autopoiesis API client.
func NewClient(baseURL string, apiKey string) *Client {
	return &Client{
		BaseURL: baseURL,
		APIKey:  apiKey,
		HTTPClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// request performs an HTTP request and decodes the JSON response.
func (c *Client) request(method, path string, body interface{}, result interface{}) error {
	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, c.BaseURL+path, reqBody)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		req.Header.Set("X-API-Key", c.APIKey)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		var apiErr APIError
		if json.Unmarshal(respBody, &apiErr) == nil && apiErr.Message != "" {
			return fmt.Errorf("API error (%d): %s", resp.StatusCode, apiErr.Message)
		}
		return fmt.Errorf("API error (%d): %s", resp.StatusCode, string(respBody))
	}

	if result != nil {
		if err := json.Unmarshal(respBody, result); err != nil {
			return fmt.Errorf("decode response: %w", err)
		}
	}
	return nil
}

// --- System ---

// SystemInfo returns the Autopoiesis system status.
func (c *Client) SystemInfo() (*SystemInfo, error) {
	var info SystemInfo
	err := c.request("GET", "/api/system", nil, &info)
	return &info, err
}

// --- Agents ---

// ListAgents returns all registered agents.
func (c *Client) ListAgents() ([]Agent, error) {
	var agents []Agent
	err := c.request("GET", "/api/agents", nil, &agents)
	return agents, err
}

// CreateAgent creates a new agent with the given name.
func (c *Client) CreateAgent(name string) (*Agent, error) {
	var agent Agent
	err := c.request("POST", "/api/agents", map[string]string{"name": name}, &agent)
	return &agent, err
}

// GetAgent returns the agent with the given ID.
func (c *Client) GetAgent(id string) (*Agent, error) {
	var agent Agent
	err := c.request("GET", "/api/agents/"+id, nil, &agent)
	return &agent, err
}

// StartAgent starts the agent's cognitive loop.
func (c *Client) StartAgent(id string) (*Agent, error) {
	var agent Agent
	err := c.request("POST", "/api/agents/"+id+"/start", nil, &agent)
	return &agent, err
}

// PauseAgent pauses a running agent.
func (c *Client) PauseAgent(id string) (*Agent, error) {
	var agent Agent
	err := c.request("POST", "/api/agents/"+id+"/pause", nil, &agent)
	return &agent, err
}

// ResumeAgent resumes a paused agent.
func (c *Client) ResumeAgent(id string) (*Agent, error) {
	var agent Agent
	err := c.request("POST", "/api/agents/"+id+"/resume", nil, &agent)
	return &agent, err
}

// StopAgent stops an agent.
func (c *Client) StopAgent(id string) (*Agent, error) {
	var agent Agent
	err := c.request("POST", "/api/agents/"+id+"/stop", nil, &agent)
	return &agent, err
}

// DeleteAgent stops and removes an agent.
func (c *Client) DeleteAgent(id string) error {
	return c.request("DELETE", "/api/agents/"+id, nil, nil)
}

// --- Cognitive Operations ---

// CognitiveCycle runs one perceive-reason-decide-act-reflect cycle.
func (c *Client) CognitiveCycle(agentID string, environment interface{}) (*CycleResult, error) {
	var result CycleResult
	body := map[string]interface{}{"environment": environment}
	err := c.request("POST", "/api/agents/"+agentID+"/cycle", body, &result)
	return &result, err
}

// GetThoughts returns recent thoughts from an agent.
func (c *Client) GetThoughts(agentID string, limit int) ([]Thought, error) {
	var thoughts []Thought
	path := fmt.Sprintf("/api/agents/%s/thoughts?limit=%d", agentID, limit)
	err := c.request("GET", path, nil, &thoughts)
	return thoughts, err
}

// ListCapabilities returns an agent's capabilities.
func (c *Client) ListCapabilities(agentID string) ([]Capability, error) {
	var caps []Capability
	err := c.request("GET", "/api/agents/"+agentID+"/capabilities", nil, &caps)
	return caps, err
}

// InvokeCapability invokes a capability on an agent.
func (c *Client) InvokeCapability(agentID, capability string, args map[string]interface{}) (map[string]interface{}, error) {
	var result map[string]interface{}
	body := map[string]interface{}{
		"capability": capability,
		"arguments":  args,
	}
	err := c.request("POST", "/api/agents/"+agentID+"/invoke", body, &result)
	return result, err
}

// --- Snapshots ---

// TakeSnapshot captures the current cognitive state of an agent.
func (c *Client) TakeSnapshot(agentID string, parent string, metadata map[string]interface{}) (*Snapshot, error) {
	var snap Snapshot
	body := map[string]interface{}{
		"parent":   parent,
		"metadata": metadata,
	}
	err := c.request("POST", "/api/agents/"+agentID+"/snapshot", body, &snap)
	return &snap, err
}

// ListSnapshots returns all snapshots.
func (c *Client) ListSnapshots() ([]Snapshot, error) {
	var snaps []Snapshot
	err := c.request("GET", "/api/snapshots", nil, &snaps)
	return snaps, err
}

// GetSnapshot returns a snapshot by ID.
func (c *Client) GetSnapshot(id string) (*Snapshot, error) {
	var snap Snapshot
	err := c.request("GET", "/api/snapshots/"+id, nil, &snap)
	return &snap, err
}

// DiffSnapshots computes the diff between two snapshots.
func (c *Client) DiffSnapshots(fromID, toID string) (*DiffResult, error) {
	var diff DiffResult
	err := c.request("GET", "/api/snapshots/"+fromID+"/diff/"+toID, nil, &diff)
	return &diff, err
}

// --- Branches ---

// ListBranches returns all cognitive branches.
func (c *Client) ListBranches() ([]Branch, error) {
	var branches []Branch
	err := c.request("GET", "/api/branches", nil, &branches)
	return branches, err
}

// CreateBranch creates a new branch.
func (c *Client) CreateBranch(name, fromSnapshot string) (*Branch, error) {
	var branch Branch
	body := map[string]string{"name": name, "from_snapshot": fromSnapshot}
	err := c.request("POST", "/api/branches", body, &branch)
	return &branch, err
}

// CheckoutBranch switches to a branch.
func (c *Client) CheckoutBranch(name string) (*Branch, error) {
	var branch Branch
	err := c.request("POST", "/api/branches/"+name+"/checkout", nil, &branch)
	return &branch, err
}

// --- Human-in-the-Loop ---

// ListPending returns all pending human input requests.
func (c *Client) ListPending() ([]PendingRequest, error) {
	var reqs []PendingRequest
	err := c.request("GET", "/api/pending", nil, &reqs)
	return reqs, err
}

// Respond provides a response to a pending request.
func (c *Client) Respond(requestID, response string) error {
	body := map[string]string{"response": response}
	return c.request("POST", "/api/pending/"+requestID+"/respond", body, nil)
}

// CancelRequest cancels a pending request.
func (c *Client) CancelRequest(requestID, reason string) error {
	body := map[string]string{"reason": reason}
	return c.request("POST", "/api/pending/"+requestID+"/cancel", body, nil)
}

// --- Events ---

// GetEventHistory returns recent events as JSON.
func (c *Client) GetEventHistory(limit int) ([]map[string]interface{}, error) {
	var events []map[string]interface{}
	path := fmt.Sprintf("/api/events?limit=%d", limit)
	err := c.request("GET", path, nil, &events)
	return events, err
}
