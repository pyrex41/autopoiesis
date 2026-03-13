// Fetch benchmark data and render charts
fetch('/api/benchmarks')
  .then(r => r.json())
  .then(data => {
    renderThroughputChart(data);
    renderLatencyChart(data);
    renderTable(data);
  });

function renderThroughputChart(data) {
  const ctx = document.getElementById('throughputChart');
  const sorted = [...data].sort((a, b) => b.requestsPerSec - a.requestsPerSec);

  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: sorted.map(d => d.name),
      datasets: [{
        label: 'Requests/second',
        data: sorted.map(d => d.requestsPerSec),
        backgroundColor: sorted.map(d =>
          d.highlight ? '#00d4aa' : '#444'
        ),
        borderColor: sorted.map(d =>
          d.highlight ? '#00ffcc' : '#666'
        ),
        borderWidth: 1
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        title: {
          display: true,
          text: 'Throughput Comparison (higher is better)',
          color: '#e0e0e0',
          font: { size: 16 }
        },
        legend: { display: false }
      },
      scales: {
        x: {
          grid: { color: '#333' },
          ticks: {
            color: '#888',
            callback: function(value) {
              return value.toLocaleString();
            }
          }
        },
        y: {
          grid: { color: '#333' },
          ticks: { color: '#e0e0e0' }
        }
      }
    }
  });
}

function renderLatencyChart(data) {
  const ctx = document.getElementById('latencyChart');
  const sorted = [...data].sort((a, b) => a.latencyAvgMs - b.latencyAvgMs);

  new Chart(ctx, {
    type: 'bar',
    data: {
      labels: sorted.map(d => d.name),
      datasets: [{
        label: 'Average Latency (ms)',
        data: sorted.map(d => d.latencyAvgMs),
        backgroundColor: sorted.map(d =>
          d.highlight ? '#00d4aa' : '#444'
        ),
        borderColor: sorted.map(d =>
          d.highlight ? '#00ffcc' : '#666'
        ),
        borderWidth: 1
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: true,
      plugins: {
        title: {
          display: true,
          text: 'Latency Comparison (lower is better)',
          color: '#e0e0e0',
          font: { size: 16 }
        },
        legend: { display: false }
      },
      scales: {
        x: {
          grid: { color: '#333' },
          ticks: {
            color: '#888',
            callback: function(value) {
              return value + 'ms';
            }
          }
        },
        y: {
          grid: { color: '#333' },
          ticks: { color: '#e0e0e0' }
        }
      }
    }
  });
}

function renderTable(data) {
  const tbody = document.getElementById('benchmarkTableBody');
  const sorted = [...data].sort((a, b) => b.requestsPerSec - a.requestsPerSec);

  tbody.innerHTML = sorted.map(d => `
    <tr class="${d.highlight ? 'highlight' : ''}">
      <td>${d.name}</td>
      <td>${d.language}</td>
      <td>${d.requestsPerSec.toLocaleString()}</td>
      <td>${d.latencyAvgMs}ms</td>
      <td>${d.latencyMaxMs}ms</td>
    </tr>
  `).join('');
}
