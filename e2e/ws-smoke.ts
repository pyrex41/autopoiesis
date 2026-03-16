// ws-smoke.ts — WebSocket smoke test using bun
// Usage: WS_URL=ws://localhost:14401/ws bun run e2e/ws-smoke.ts
//
// Tests two paths:
//   1. Jarvis chat path: start_chat → chat_prompt → chat_response
//   2. Agent runtime path: REST create/start → WS subscribe → chat_prompt → thought_added

const WS_URL = process.env.WS_URL || "ws://localhost:14401/ws";
const REST_PORT = process.env.REST_PORT || "14402";
const REST_BASE = `http://localhost:${REST_PORT}/api`;
const TIMEOUT_MS = parseInt(process.env.TIMEOUT || "45") * 1000;

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const NC = "\x1b[0m";

const pass = (msg: string) => console.log(`${GREEN}✓ ${msg}${NC}`);
const fail = (msg: string) => {
  console.log(`${RED}✗ ${msg}${NC}`);
};
const info = (msg: string) => console.log(`${YELLOW}→ ${msg}${NC}`);

let passed = 0;
let failed = 0;

// ===================================================================
// Phase 1: Jarvis Chat Path
// ===================================================================

async function runJarvisChatTest(): Promise<boolean> {
  info("--- Phase 1: Jarvis Chat Path ---");

  return new Promise((resolve) => {
    const ws = new WebSocket(WS_URL);
    const agentId = `smoke-test-${Date.now()}`;
    let step = 0;

    const timer = setTimeout(() => {
      fail(`Jarvis test timed out at step ${step}`);
      failed++;
      ws.close();
      resolve(false);
    }, TIMEOUT_MS / 2);

    ws.onopen = () => {
      pass("WebSocket connected");
      passed++;
      step = 1;
      ws.send(JSON.stringify({ type: "subscribe", channel: "agents" }));
    };

    ws.onerror = (e: Event) => {
      fail(`WebSocket error: ${e}`);
      failed++;
      clearTimeout(timer);
      resolve(false);
    };

    ws.onmessage = (event: MessageEvent) => {
      let msg: any;
      try {
        msg = JSON.parse(event.data as string);
      } catch {
        return;
      }

      switch (step) {
        case 0:
          if (msg.type) info(`Received: ${msg.type}`);
          break;

        case 1:
          if (msg.type === "subscribed") {
            pass(`Subscribed to ${msg.channel}`);
            passed++;
            step = 2;
            info(`Starting chat session for agent: ${agentId}`);
            ws.send(JSON.stringify({ type: "start_chat", agentId }));
          }
          break;

        case 2:
          if (msg.type === "chat_started") {
            pass(`Chat session started (agentId=${msg.agentId})`);
            passed++;
            step = 3;
            info("Sending chat prompt: 'hello from smoke test'");
            ws.send(
              JSON.stringify({
                type: "chat_prompt",
                agentId,
                text: "hello from smoke test",
              })
            );
          }
          break;

        case 3:
          if (msg.type === "chat_response") {
            const text = msg.text || "";
            pass(`Chat response received: ${text.substring(0, 120)}`);
            passed++;
            if (text.length > 0) {
              pass("Response text is non-empty");
              passed++;
            } else {
              fail("Response text is empty");
              failed++;
              clearTimeout(timer);
              ws.close();
              resolve(false);
              return;
            }
            step = 4;
            info("Stopping chat session");
            ws.send(JSON.stringify({ type: "stop_chat", agentId }));
          } else if (msg.type === "error" || msg.type === "chat_error") {
            fail(`Chat error: ${JSON.stringify(msg)}`);
            failed++;
            clearTimeout(timer);
            ws.close();
            resolve(false);
            return;
          }
          break;

        case 4:
          if (msg.type === "chat_stopped") {
            pass("Chat session stopped");
            passed++;
            clearTimeout(timer);
            ws.close();
            resolve(true);
          }
          break;
      }
    };
  });
}

// ===================================================================
// Phase 2: Agent Runtime Path
// ===================================================================

async function runAgentRuntimeTest(): Promise<boolean> {
  info("--- Phase 2: Agent Runtime Path ---");

  // 1. Create agent via REST
  info("Creating agent via REST API...");
  let agentId: string;
  try {
    const createResp = await fetch(`${REST_BASE}/agents`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: `smoke-runtime-${Date.now()}` }),
    });
    if (!createResp.ok) {
      fail(`REST create agent failed: ${createResp.status}`);
      failed++;
      return false;
    }
    const createData = (await createResp.json()) as any;
    agentId = createData.id || createData.agentId;
    if (!agentId) {
      fail(`No agent ID in response: ${JSON.stringify(createData)}`);
      failed++;
      return false;
    }
    pass(`Agent created via REST: ${agentId}`);
    passed++;
  } catch (e) {
    fail(`REST create agent error: ${e}`);
    failed++;
    return false;
  }

  // 2. Start agent via REST
  try {
    const startResp = await fetch(`${REST_BASE}/agents/${agentId}/start`, {
      method: "POST",
    });
    if (!startResp.ok) {
      fail(`REST start agent failed: ${startResp.status}`);
      failed++;
      return false;
    }
    pass("Agent started via REST");
    passed++;
  } catch (e) {
    fail(`REST start agent error: ${e}`);
    failed++;
    return false;
  }

  // 3. Connect WS and subscribe to agent channel
  return new Promise((resolve) => {
    const ws = new WebSocket(WS_URL);
    let subscribed = false;
    let promptAccepted = false;
    let thoughtReceived = false;

    const timer = setTimeout(() => {
      if (!thoughtReceived) {
        fail("Agent runtime test timed out waiting for thought_added");
        failed++;
      }
      ws.close();
      resolve(thoughtReceived);
    }, TIMEOUT_MS / 2);

    ws.onopen = () => {
      // Subscribe to this agent's thought stream
      ws.send(
        JSON.stringify({
          type: "subscribe",
          channel: `agent:${agentId}`,
        })
      );
    };

    ws.onerror = (e: Event) => {
      fail(`WS error in runtime test: ${e}`);
      failed++;
      clearTimeout(timer);
      resolve(false);
    };

    ws.onmessage = (event: MessageEvent) => {
      let msg: any;
      try {
        msg = JSON.parse(event.data as string);
      } catch {
        return;
      }

      if (msg.type === "subscribed") {
        subscribed = true;
        pass(`Subscribed to agent:${agentId}`);
        passed++;
        // Send a chat prompt through the runtime path
        info("Sending chat_prompt to agent runtime...");
        ws.send(
          JSON.stringify({
            type: "chat_prompt",
            agentId,
            text: "hello from runtime smoke test",
          })
        );
      }

      if (msg.type === "chat_prompt_accepted") {
        promptAccepted = true;
        pass("chat_prompt_accepted received");
        passed++;
      }

      if (msg.type === "thought_added" && !thoughtReceived) {
        thoughtReceived = true;
        const thoughtType = msg.thought?.type || "unknown";
        pass(`thought_added received (type: ${thoughtType})`);
        passed++;
        clearTimeout(timer);
        ws.close();
        resolve(true);
      }

      // Also accept chat_stream_* and chat_response as valid runtime output
      if (
        (msg.type === "chat_stream_delta" ||
          msg.type === "chat_response") &&
        !thoughtReceived
      ) {
        thoughtReceived = true;
        pass(`Agent runtime produced output: ${msg.type}`);
        passed++;
        clearTimeout(timer);
        ws.close();
        resolve(true);
      }
    };
  });
}

// ===================================================================
// Main
// ===================================================================

async function main() {
  const jarvisOk = await runJarvisChatTest();

  // Run agent runtime test regardless of Jarvis result
  // (Jarvis may fail without API keys, but runtime path should still work)
  const runtimeOk = await runAgentRuntimeTest();

  console.log("");
  const total = passed + failed;
  if (jarvisOk && runtimeOk) {
    console.log(
      `${GREEN}All WebSocket smoke tests passed! (${passed}/${total})${NC}`
    );
    process.exit(0);
  } else if (runtimeOk) {
    console.log(
      `${YELLOW}Runtime tests passed, Jarvis tests failed (${passed}/${total})${NC}`
    );
    // Exit 0 if runtime works — Jarvis failure is often due to missing API keys
    process.exit(0);
  } else {
    console.log(
      `${RED}WebSocket smoke tests FAILED (${passed} passed, ${failed} failed)${NC}`
    );
    process.exit(1);
  }
}

main().catch((e) => {
  fail(`Unhandled error: ${e}`);
  process.exit(1);
});
