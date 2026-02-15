// apcli is a command-line interface for the Autopoiesis Control API.
//
// It is designed to be used as a PicoClaw Skill via the exec tool,
// or as a standalone CLI for interacting with Autopoiesis instances.
//
// Usage:
//
//	apcli [flags] <command> [args...]
//
// Commands:
//
//	system         Show system info
//	agents         List agents
//	create-agent   Create a new agent
//	get-agent      Get agent details
//	start-agent    Start an agent
//	pause-agent    Pause an agent
//	resume-agent   Resume an agent
//	stop-agent     Stop an agent
//	cycle          Run a cognitive cycle
//	thoughts       Get agent thoughts
//	capabilities   List agent capabilities
//	snapshot       Take a snapshot
//	snapshots      List snapshots
//	diff           Diff two snapshots
//	branches       List branches
//	create-branch  Create a branch
//	checkout       Checkout a branch
//	pending        List pending requests
//	respond        Respond to a pending request
//	events         Show recent events
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/pyrex41/autopoiesis/sdk/go/apclient"
)

var (
	baseURL = flag.String("url", envOr("AP_URL", "http://localhost:8080"), "Autopoiesis API URL")
	apiKey  = flag.String("key", envOr("AP_KEY", ""), "API key")
	output  = flag.String("output", "json", "Output format: json or text")
)

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	flag.Parse()
	args := flag.Args()
	if len(args) == 0 {
		printUsage()
		os.Exit(1)
	}

	client := apclient.NewClient(*baseURL, *apiKey)
	cmd := args[0]
	cmdArgs := args[1:]

	var err error
	switch cmd {
	case "system":
		err = cmdSystem(client)
	case "agents":
		err = cmdListAgents(client)
	case "create-agent":
		err = cmdCreateAgent(client, cmdArgs)
	case "get-agent":
		err = cmdGetAgent(client, cmdArgs)
	case "start-agent":
		err = cmdAgentAction(client, cmdArgs, "start")
	case "pause-agent":
		err = cmdAgentAction(client, cmdArgs, "pause")
	case "resume-agent":
		err = cmdAgentAction(client, cmdArgs, "resume")
	case "stop-agent":
		err = cmdAgentAction(client, cmdArgs, "stop")
	case "cycle":
		err = cmdCycle(client, cmdArgs)
	case "thoughts":
		err = cmdThoughts(client, cmdArgs)
	case "capabilities":
		err = cmdCapabilities(client, cmdArgs)
	case "snapshot":
		err = cmdSnapshot(client, cmdArgs)
	case "snapshots":
		err = cmdListSnapshots(client)
	case "diff":
		err = cmdDiff(client, cmdArgs)
	case "branches":
		err = cmdListBranches(client)
	case "create-branch":
		err = cmdCreateBranch(client, cmdArgs)
	case "checkout":
		err = cmdCheckout(client, cmdArgs)
	case "pending":
		err = cmdPending(client)
	case "respond":
		err = cmdRespond(client, cmdArgs)
	case "events":
		err = cmdEvents(client)
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", cmd)
		printUsage()
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func printJSON(v interface{}) {
	data, _ := json.MarshalIndent(v, "", "  ")
	fmt.Println(string(data))
}

func printUsage() {
	fmt.Fprintln(os.Stderr, `apcli - Autopoiesis Control API CLI

Usage: apcli [flags] <command> [args...]

Flags:
  -url    Autopoiesis API URL (default: $AP_URL or http://localhost:8080)
  -key    API key (default: $AP_KEY)
  -output Output format: json or text (default: json)

Commands:
  system                           Show system info
  agents                           List all agents
  create-agent <name>              Create a new agent
  get-agent <id>                   Get agent details
  start-agent <id>                 Start an agent
  pause-agent <id>                 Pause an agent
  resume-agent <id>                Resume an agent
  stop-agent <id>                  Stop an agent
  cycle <agent-id> [stimulus]      Run cognitive cycle
  thoughts <agent-id> [limit]      Get recent thoughts
  capabilities <agent-id>          List capabilities
  snapshot <agent-id>              Take a snapshot
  snapshots                        List all snapshots
  diff <snap-a> <snap-b>           Diff two snapshots
  branches                         List branches
  create-branch <name> [from-snap] Create a branch
  checkout <branch-name>           Switch to a branch
  pending                          List pending requests
  respond <request-id> <response>  Respond to a request
  events                           Show recent events`)
}

// --- Command Implementations ---

func cmdSystem(c *apclient.Client) error {
	info, err := c.SystemInfo()
	if err != nil {
		return err
	}
	printJSON(info)
	return nil
}

func cmdListAgents(c *apclient.Client) error {
	agents, err := c.ListAgents()
	if err != nil {
		return err
	}
	printJSON(agents)
	return nil
}

func cmdCreateAgent(c *apclient.Client, args []string) error {
	name := "unnamed"
	if len(args) > 0 {
		name = args[0]
	}
	agent, err := c.CreateAgent(name)
	if err != nil {
		return err
	}
	printJSON(agent)
	return nil
}

func cmdGetAgent(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: get-agent <id>")
	}
	agent, err := c.GetAgent(args[0])
	if err != nil {
		return err
	}
	printJSON(agent)
	return nil
}

func cmdAgentAction(c *apclient.Client, args []string, action string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: %s-agent <id>", action)
	}
	var agent *apclient.Agent
	var err error
	switch action {
	case "start":
		agent, err = c.StartAgent(args[0])
	case "pause":
		agent, err = c.PauseAgent(args[0])
	case "resume":
		agent, err = c.ResumeAgent(args[0])
	case "stop":
		agent, err = c.StopAgent(args[0])
	}
	if err != nil {
		return err
	}
	printJSON(agent)
	return nil
}

func cmdCycle(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: cycle <agent-id> [stimulus]")
	}
	var env interface{}
	if len(args) > 1 {
		env = map[string]string{"stimulus": args[1]}
	}
	result, err := c.CognitiveCycle(args[0], env)
	if err != nil {
		return err
	}
	printJSON(result)
	return nil
}

func cmdThoughts(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: thoughts <agent-id> [limit]")
	}
	limit := 20
	if len(args) > 1 {
		fmt.Sscanf(args[1], "%d", &limit)
	}
	thoughts, err := c.GetThoughts(args[0], limit)
	if err != nil {
		return err
	}
	printJSON(thoughts)
	return nil
}

func cmdCapabilities(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: capabilities <agent-id>")
	}
	caps, err := c.ListCapabilities(args[0])
	if err != nil {
		return err
	}
	printJSON(caps)
	return nil
}

func cmdSnapshot(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: snapshot <agent-id>")
	}
	snap, err := c.TakeSnapshot(args[0], "", nil)
	if err != nil {
		return err
	}
	printJSON(snap)
	return nil
}

func cmdListSnapshots(c *apclient.Client) error {
	snaps, err := c.ListSnapshots()
	if err != nil {
		return err
	}
	printJSON(snaps)
	return nil
}

func cmdDiff(c *apclient.Client, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: diff <snap-a> <snap-b>")
	}
	diff, err := c.DiffSnapshots(args[0], args[1])
	if err != nil {
		return err
	}
	printJSON(diff)
	return nil
}

func cmdListBranches(c *apclient.Client) error {
	branches, err := c.ListBranches()
	if err != nil {
		return err
	}
	printJSON(branches)
	return nil
}

func cmdCreateBranch(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: create-branch <name> [from-snapshot]")
	}
	from := ""
	if len(args) > 1 {
		from = args[1]
	}
	branch, err := c.CreateBranch(args[0], from)
	if err != nil {
		return err
	}
	printJSON(branch)
	return nil
}

func cmdCheckout(c *apclient.Client, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("usage: checkout <branch-name>")
	}
	branch, err := c.CheckoutBranch(args[0])
	if err != nil {
		return err
	}
	printJSON(branch)
	return nil
}

func cmdPending(c *apclient.Client) error {
	reqs, err := c.ListPending()
	if err != nil {
		return err
	}
	printJSON(reqs)
	return nil
}

func cmdRespond(c *apclient.Client, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: respond <request-id> <response>")
	}
	return c.Respond(args[0], args[1])
}

func cmdEvents(c *apclient.Client) error {
	events, err := c.GetEventHistory(50)
	if err != nil {
		return err
	}
	printJSON(events)
	return nil
}
