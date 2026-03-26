package ws

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"sync"
	"time"

	"nhooyr.io/websocket"
)

// ConnState represents the WebSocket connection state.
type ConnState int

const (
	Disconnected ConnState = iota
	Connecting
	Connected
)

// Client manages a WebSocket connection with automatic reconnection.
type Client struct {
	url string

	mu    sync.Mutex
	conn  *websocket.Conn
	state ConnState

	// Incoming is where parsed server messages arrive.
	Incoming chan ServerMessage
	// StateChange signals connection state changes.
	StateChange chan ConnState

	ctx    context.Context
	cancel context.CancelFunc
	done   chan struct{}
}

// NewClient creates a new WebSocket client for the given URL.
func NewClient(url string) *Client {
	ctx, cancel := context.WithCancel(context.Background())
	return &Client{
		url:         url,
		Incoming:    make(chan ServerMessage, 64),
		StateChange: make(chan ConnState, 8),
		ctx:         ctx,
		cancel:      cancel,
		done:        make(chan struct{}),
	}
}

// Start begins the connection loop in a background goroutine.
func (c *Client) Start() {
	go c.connectLoop()
}

// Stop gracefully shuts down the client.
func (c *Client) Stop() {
	c.cancel()
	<-c.done
}

// Send marshals and sends a message over the WebSocket.
func (c *Client) Send(msg any) error {
	c.mu.Lock()
	conn := c.conn
	c.mu.Unlock()

	if conn == nil {
		return fmt.Errorf("not connected")
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("marshal: %w", err)
	}

	ctx, cancel := context.WithTimeout(c.ctx, 5*time.Second)
	defer cancel()

	return conn.Write(ctx, websocket.MessageText, data)
}

// State returns the current connection state.
func (c *Client) State() ConnState {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.state
}

func (c *Client) setState(s ConnState) {
	c.mu.Lock()
	c.state = s
	c.mu.Unlock()
	select {
	case c.StateChange <- s:
	default:
	}
}

func (c *Client) connectLoop() {
	defer close(c.done)

	attempt := 0
	for {
		if c.ctx.Err() != nil {
			return
		}

		c.setState(Connecting)

		conn, err := c.dial()
		if err != nil {
			attempt++
			delay := backoff(attempt)
			log.Printf("ws: connect failed (attempt %d): %v, retry in %v", attempt, err, delay)

			select {
			case <-time.After(delay):
				continue
			case <-c.ctx.Done():
				c.setState(Disconnected)
				return
			}
		}

		c.mu.Lock()
		c.conn = conn
		c.mu.Unlock()
		c.setState(Connected)
		attempt = 0

		c.readLoop(conn)

		c.mu.Lock()
		c.conn = nil
		c.mu.Unlock()
		c.setState(Disconnected)

		// Brief pause before reconnect
		select {
		case <-time.After(500 * time.Millisecond):
		case <-c.ctx.Done():
			return
		}
	}
}

func (c *Client) dial() (*websocket.Conn, error) {
	ctx, cancel := context.WithTimeout(c.ctx, 10*time.Second)
	defer cancel()

	conn, _, err := websocket.Dial(ctx, c.url, nil)
	if err != nil {
		return nil, err
	}

	// Allow large messages (e.g., full agent thought streams)
	conn.SetReadLimit(1 << 20) // 1MB

	return conn, nil
}

func (c *Client) readLoop(conn *websocket.Conn) {
	for {
		_, data, err := conn.Read(c.ctx)
		if err != nil {
			if c.ctx.Err() == nil {
				log.Printf("ws: read error: %v", err)
			}
			conn.Close(websocket.StatusNormalClosure, "")
			return
		}

		msg, err := ParseServerMessage(data)
		if err != nil {
			log.Printf("ws: parse error: %v", err)
			continue
		}

		select {
		case c.Incoming <- msg:
		case <-c.ctx.Done():
			conn.Close(websocket.StatusNormalClosure, "")
			return
		}
	}
}

func backoff(attempt int) time.Duration {
	// Exponential backoff: 1s, 2s, 4s, 8s, max 30s
	d := time.Duration(math.Pow(2, float64(attempt-1))) * time.Second
	if d > 30*time.Second {
		d = 30 * time.Second
	}
	return d
}
