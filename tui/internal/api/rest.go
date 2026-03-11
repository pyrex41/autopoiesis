package api

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client provides REST API access as a fallback to WebSocket.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates a REST API client.
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// GetHealth checks the server health endpoint.
func (c *Client) GetHealth() (map[string]any, error) {
	return c.getJSON("/health")
}

// GetMetrics fetches server metrics.
func (c *Client) GetMetrics() (map[string]any, error) {
	return c.getJSON("/metrics")
}

func (c *Client) getJSON(path string) (map[string]any, error) {
	resp, err := c.httpClient.Get(c.baseURL + path)
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", path, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body))
	}

	var result map[string]any
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("unmarshal: %w", err)
	}
	return result, nil
}
