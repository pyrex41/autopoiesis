package ws

import (
	"testing"
	"time"
)

func TestBackoff(t *testing.T) {
	tests := []struct {
		attempt int
		want    time.Duration
	}{
		{1, 1 * time.Second},
		{2, 2 * time.Second},
		{3, 4 * time.Second},
		{4, 8 * time.Second},
		{5, 16 * time.Second},
		{6, 30 * time.Second}, // capped
		{10, 30 * time.Second},
	}

	for _, tt := range tests {
		got := backoff(tt.attempt)
		if got != tt.want {
			t.Errorf("backoff(%d) = %v, want %v", tt.attempt, got, tt.want)
		}
	}
}

func TestNewClient(t *testing.T) {
	c := NewClient("ws://localhost:9080/ws")
	if c.url != "ws://localhost:9080/ws" {
		t.Errorf("url = %q", c.url)
	}
	if c.State() != Disconnected {
		t.Errorf("initial state = %v, want Disconnected", c.State())
	}
	if c.Incoming == nil {
		t.Error("Incoming channel is nil")
	}
	if c.StateChange == nil {
		t.Error("StateChange channel is nil")
	}
}

func TestSendWhenDisconnected(t *testing.T) {
	c := NewClient("ws://localhost:9999/ws")
	err := c.Send(PingMsg{Type: "ping"})
	if err == nil {
		t.Error("Send on disconnected client should error")
	}
}

func TestStartStop(t *testing.T) {
	// Use a bogus URL that won't connect
	c := NewClient("ws://127.0.0.1:1/ws")
	c.Start()

	// Give it a moment to attempt connection
	time.Sleep(100 * time.Millisecond)

	// Should be in connecting state
	state := c.State()
	if state != Connecting && state != Disconnected {
		t.Errorf("state = %v, want Connecting or Disconnected", state)
	}

	// Stop should not hang
	done := make(chan struct{})
	go func() {
		c.Stop()
		close(done)
	}()

	select {
	case <-done:
		// OK
	case <-time.After(5 * time.Second):
		t.Fatal("Stop() timed out")
	}
}
