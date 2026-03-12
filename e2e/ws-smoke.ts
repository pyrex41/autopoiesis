// ws-smoke.ts — WebSocket smoke test using bun
// Usage: WS_URL=ws://localhost:14401/ws bun run e2e/ws-smoke.ts

const WS_URL = process.env.WS_URL || "ws://localhost:14401/ws";
const TIMEOUT_MS = parseInt(process.env.TIMEOUT || "30") * 1000;

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const NC = "\x1b[0m";

const pass = (msg: string) => console.log(`${GREEN}✓ ${msg}${NC}`);
const fail = (msg: string) => {
  console.log(`${RED}✗ ${msg}${NC}`);
};
const info = (msg: string) => console.log(`${YELLOW}→ ${msg}${NC}`);

info(`Connecting to ${WS_URL} ...`);

const ws = new WebSocket(WS_URL);
const agentId = `smoke-test-${Date.now()}`;
let step = 0;
let passed = 0;
let failed = 0;

function done(success: boolean) {
  ws.close();
  console.log("");
  if (success) {
    console.log(`${GREEN}All WebSocket smoke tests passed! (${passed}/${passed + failed})${NC}`);
  } else {
    console.log(`${RED}WebSocket smoke tests FAILED (${passed} passed, ${failed} failed)${NC}`);
  }
  process.exit(success ? 0 : 1);
}

const timer = setTimeout(() => {
  fail(`Timed out at step ${step} after ${TIMEOUT_MS / 1000}s`);
  failed++;
  done(false);
}, TIMEOUT_MS);

ws.onopen = () => {
  pass("WebSocket connected");
  passed++;
  step = 1;
  ws.send(JSON.stringify({ type: "subscribe", channel: "agents" }));
};

ws.onerror = (e: Event) => {
  fail(`WebSocket error: ${e}`);
  failed++;
  done(false);
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
      // Welcome message
      if (msg.type) {
        info(`Received: ${msg.type}`);
      }
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
          done(false);
          return;
        }
        step = 4;
        info("Stopping chat session");
        ws.send(JSON.stringify({ type: "stop_chat", agentId }));
      } else if (msg.type === "error" || msg.type === "chat_error") {
        fail(`Chat error: ${JSON.stringify(msg)}`);
        failed++;
        done(false);
        return;
      }
      break;

    case 4:
      if (msg.type === "chat_stopped") {
        pass("Chat session stopped");
        passed++;
        clearTimeout(timer);
        done(true);
      }
      break;
  }
};
