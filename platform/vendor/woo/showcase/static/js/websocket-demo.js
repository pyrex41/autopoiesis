let ws = null;
let messageCount = 0;
let latencies = [];
let pendingPings = new Map();

const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const connectBtn = document.getElementById('connectBtn');
const disconnectBtn = document.getElementById('disconnectBtn');
const messageInput = document.getElementById('messageInput');
const sendBtn = document.getElementById('sendBtn');
const log = document.getElementById('log');
const latencyDisplay = document.getElementById('latency');
const messageCountDisplay = document.getElementById('messageCount');
const avgLatencyDisplay = document.getElementById('avgLatency');
const pingTestBtn = document.getElementById('pingTestBtn');
const pingResults = document.getElementById('pingResults');

function connect() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${protocol}//${location.host}/ws/echo`);

  ws.onopen = () => {
    statusDot.className = 'status-dot connected';
    statusText.textContent = 'Connected';
    connectBtn.disabled = true;
    disconnectBtn.disabled = false;
    messageInput.disabled = false;
    sendBtn.disabled = false;
    pingTestBtn.disabled = false;
    addLog('Connected to Woo WebSocket server', 'system');
  };

  ws.onmessage = (event) => {
    const now = performance.now();
    const data = event.data;

    // Check if this is a ping response
    if (pendingPings.has(data)) {
      const sent = pendingPings.get(data);
      const latency = (now - sent).toFixed(2);
      pendingPings.delete(data);

      latencies.push(parseFloat(latency));
      latencyDisplay.textContent = latency;

      // Update average
      const avg = (latencies.reduce((a, b) => a + b, 0) / latencies.length).toFixed(2);
      avgLatencyDisplay.textContent = avg;

      addLog(`← Echo: "${data}" (${latency}ms)`, 'received');
    } else {
      addLog(`← Received: "${data}"`, 'received');
    }
  };

  ws.onclose = () => {
    statusDot.className = 'status-dot';
    statusText.textContent = 'Disconnected';
    connectBtn.disabled = false;
    disconnectBtn.disabled = true;
    messageInput.disabled = true;
    sendBtn.disabled = true;
    pingTestBtn.disabled = true;
    addLog('Disconnected', 'system');
  };

  ws.onerror = (error) => {
    addLog('Error occurred', 'error');
  };
}

function disconnect() {
  if (ws) {
    ws.close();
  }
}

function send() {
  const message = messageInput.value.trim();
  if (message && ws && ws.readyState === WebSocket.OPEN) {
    pendingPings.set(message, performance.now());
    ws.send(message);
    messageCount++;
    messageCountDisplay.textContent = messageCount;
    addLog(`→ Sent: "${message}"`, 'sent');
    messageInput.value = '';
  }
}

function addLog(text, type) {
  const entry = document.createElement('div');
  entry.className = `log-entry log-${type}`;
  entry.textContent = `[${new Date().toLocaleTimeString()}] ${text}`;
  log.insertBefore(entry, log.firstChild);

  // Keep only last 50 entries
  while (log.children.length > 50) {
    log.removeChild(log.lastChild);
  }
}

async function runPingTest() {
  pingTestBtn.disabled = true;
  pingResults.innerHTML = 'Running test...';

  const testLatencies = [];
  const testCount = 100;

  for (let i = 0; i < testCount; i++) {
    const msg = `ping-${i}-${Date.now()}`;
    const start = performance.now();

    await new Promise(resolve => {
      const handler = (event) => {
        if (event.data === msg) {
          ws.removeEventListener('message', handler);
          testLatencies.push(performance.now() - start);
          resolve();
        }
      };
      ws.addEventListener('message', handler);
      ws.send(msg);
    });
  }

  const min = Math.min(...testLatencies).toFixed(2);
  const max = Math.max(...testLatencies).toFixed(2);
  const avg = (testLatencies.reduce((a, b) => a + b, 0) / testLatencies.length).toFixed(2);
  const p99 = testLatencies.sort((a, b) => a - b)[Math.floor(testLatencies.length * 0.99)].toFixed(2);

  pingResults.innerHTML = `
    <div class="test-results">
      <div><strong>Messages:</strong> ${testCount}</div>
      <div><strong>Min:</strong> ${min}ms</div>
      <div><strong>Avg:</strong> ${avg}ms</div>
      <div><strong>Max:</strong> ${max}ms</div>
      <div><strong>P99:</strong> ${p99}ms</div>
    </div>
  `;

  pingTestBtn.disabled = false;
}

// Event listeners
connectBtn.addEventListener('click', connect);
disconnectBtn.addEventListener('click', disconnect);
sendBtn.addEventListener('click', send);
messageInput.addEventListener('keypress', (e) => {
  if (e.key === 'Enter') send();
});
pingTestBtn.addEventListener('click', runPingTest);
