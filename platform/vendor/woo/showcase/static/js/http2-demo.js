const resourceCount = document.getElementById('resourceCount');
const delayMs = document.getElementById('delayMs');
const runTest = document.getElementById('runTest');
const http1Waterfall = document.getElementById('http1Waterfall');
const http2Waterfall = document.getElementById('http2Waterfall');
const http1Time = document.getElementById('http1Time');
const http2Time = document.getElementById('http2Time');

runTest.addEventListener('click', async () => {
  const count = parseInt(resourceCount.value);
  const delay = parseInt(delayMs.value);

  runTest.disabled = true;
  runTest.textContent = 'Running...';
  http1Waterfall.innerHTML = '';
  http2Waterfall.innerHTML = '';
  http1Time.textContent = '--';
  http2Time.textContent = '--';

  // Simulate HTTP/1.1 (max 6 concurrent)
  const http1Result = await simulateHttp1(count, delay);
  http1Time.textContent = `${http1Result.total.toFixed(0)}ms`;

  // Simulate HTTP/2 (all concurrent)
  const http2Result = await simulateHttp2(count, delay);
  http2Time.textContent = `${http2Result.total.toFixed(0)}ms`;

  runTest.disabled = false;
  runTest.textContent = 'Run Comparison';
});

async function simulateHttp1(count, delay) {
  const maxConcurrent = 6;
  const results = [];
  const startTime = performance.now();
  const maxTime = Math.ceil(count / maxConcurrent) * (delay + 100);

  for (let i = 0; i < count; i += maxConcurrent) {
    const batch = [];
    const batchStart = performance.now() - startTime;

    for (let j = 0; j < maxConcurrent && i + j < count; j++) {
      const id = i + j;
      batch.push(fetchResource(id, delay).then(time => {
        results.push({ id, start: batchStart, duration: time });
        renderBar(http1Waterfall, id, batchStart, time, maxTime);
      }));
    }

    await Promise.all(batch);
  }

  return { total: performance.now() - startTime, results };
}

async function simulateHttp2(count, delay) {
  const results = [];
  const startTime = performance.now();
  const maxTime = delay + 200;

  const promises = [];
  for (let i = 0; i < count; i++) {
    const id = i;
    promises.push(fetchResource(id, delay).then(time => {
      results.push({ id, start: 0, duration: time });
      renderBar(http2Waterfall, id, 0, time, maxTime);
    }));
  }

  await Promise.all(promises);
  return { total: performance.now() - startTime, results };
}

async function fetchResource(id, delay) {
  const start = performance.now();
  await fetch(`/api/resource/${id}?delay=${delay}`);
  return performance.now() - start;
}

function renderBar(container, id, start, duration, maxTime) {
  const bar = document.createElement('div');
  bar.className = 'waterfall-bar';
  bar.style.marginLeft = `${(start / maxTime) * 100}%`;
  bar.style.width = `${Math.max((duration / maxTime) * 100, 1)}%`;
  bar.title = `Resource ${id}: ${duration.toFixed(0)}ms`;
  container.appendChild(bar);
}
