package tui

import (
	"strings"
	"testing"
)

func TestAgentStateColor(t *testing.T) {
	states := []string{"running", "paused", "stopped", "initialized", "idle", "unknown"}
	for _, s := range states {
		c := AgentStateColor(s)
		if c == "" {
			t.Errorf("AgentStateColor(%q) returned empty", s)
		}
	}
}

func TestAgentStateBullet(t *testing.T) {
	bullet := AgentStateBullet("running")
	if !strings.Contains(bullet, "●") {
		t.Errorf("bullet should contain ●, got %q", bullet)
	}
}

func TestThoughtBadge(t *testing.T) {
	tests := []struct {
		thoughtType string
		wantIcon    string
	}{
		{"observation", "obs"},
		{"decision", "dec"},
		{"action", "act"},
		{"reflection", "ref"},
		{"unknown", "???"},
	}

	for _, tt := range tests {
		badge := ThoughtBadge(tt.thoughtType)
		if !strings.Contains(badge, tt.wantIcon) {
			t.Errorf("ThoughtBadge(%q) = %q, should contain %q", tt.thoughtType, badge, tt.wantIcon)
		}
	}
}
