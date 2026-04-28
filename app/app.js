// Version: 1.1 — deployed via GitHub Actions + SSM + S3
const http = require('http');
const os   = require('os');

//  Deployment metadata (injected via CI/CD environment variables) 
const APP_VERSION    = process.env.APP_VERSION    || 'v1.0.0';
const DEPLOYED_BY    = process.env.DEPLOYED_BY    || 'manual';
const DEPLOYED_AT    = process.env.DEPLOYED_AT    || new Date().toISOString();
const GIT_COMMIT     = process.env.GIT_COMMIT     || 'local';
const ENVIRONMENT    = process.env.ENVIRONMENT    || 'dev';

// In-memory state 
const stats = {
  cpu:   { count: 0, lastTriggered: null },
  error: { count: 0, lastTriggered: null },
  slow:  { count: 0, lastTriggered: null },
  total: 0,
  startTime: new Date().toISOString()
};

const recentLogs = [];

function addLog(level, message) {
  const entry = {
    time: new Date().toISOString(),
    level,
    message
  };
  recentLogs.unshift(entry);
  if (recentLogs.length > 20) recentLogs.pop();

  if (level === 'ERROR') {
    console.error(`[${entry.time}] [${level}] ${message}`);
  } else {
    console.log(`[${entry.time}] [${level}] ${message}`);
  }
}

//  HTML Dashboard 
function getHTML() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>DevOps Agent POC</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Segoe UI', Arial, sans-serif;
      background: #0f1117;
      color: #e2e8f0;
      min-height: 100vh;
      padding: 24px;
    }

    .header {
      background: linear-gradient(135deg, #1a1f2e, #232f3e);
      border: 1px solid #ff9900;
      border-radius: 12px;
      padding: 24px 32px;
      margin-bottom: 24px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .header h1 {
      font-size: 24px;
      font-weight: 700;
      color: #ff9900;
    }

    .header p {
      font-size: 13px;
      color: #94a3b8;
      margin-top: 4px;
    }

    .badge {
      background: #1e3a5f;
      border: 1px solid #3b82f6;
      border-radius: 8px;
      padding: 8px 16px;
      text-align: right;
    }

    .badge .version {
      font-size: 20px;
      font-weight: 700;
      color: #60a5fa;
    }

    .badge .meta {
      font-size: 11px;
      color: #64748b;
      margin-top: 2px;
    }

    .grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 20px;
      margin-bottom: 24px;
    }

    .card {
      background: #1a1f2e;
      border: 1px solid #2d3748;
      border-radius: 12px;
      padding: 24px;
    }

    .card h2 {
      font-size: 14px;
      font-weight: 600;
      color: #94a3b8;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin-bottom: 16px;
      border-bottom: 1px solid #2d3748;
      padding-bottom: 8px;
    }

    /* Trigger Buttons */
    .btn-grid {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .btn {
      padding: 14px 20px;
      border: none;
      border-radius: 8px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: all 0.2s;
      display: flex;
      align-items: center;
      gap: 10px;
    }

    .btn:hover { transform: translateY(-2px); opacity: 0.9; }
    .btn:active { transform: translateY(0); }
    .btn:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }

    .btn-cpu   { background: #dc2626; color: #fff; }
    .btn-error { background: #d97706; color: #fff; }
    .btn-slow  { background: #7c3aed; color: #fff; }
    .btn-reset { background: #1e3a5f; color: #60a5fa; border: 1px solid #3b82f6; }

    /* Status */
    .status-box {
      background: #0f1117;
      border: 1px solid #2d3748;
      border-radius: 8px;
      padding: 14px;
      margin-top: 14px;
      font-size: 13px;
      min-height: 50px;
    }

    .status-ok    { color: #34d399; }
    .status-error { color: #f87171; }
    .status-warn  { color: #fbbf24; }
    .status-info  { color: #60a5fa; }

    /* Stats */
    .stat-grid {
      display: grid;
      grid-template-columns: 1fr 1fr 1fr;
      gap: 10px;
    }

    .stat-item {
      background: #0f1117;
      border: 1px solid #2d3748;
      border-radius: 8px;
      padding: 12px;
      text-align: center;
    }

    .stat-value {
      font-size: 28px;
      font-weight: 700;
      color: #ff9900;
    }

    .stat-label {
      font-size: 11px;
      color: #64748b;
      margin-top: 4px;
    }

    /* Deployment Info */
    .deploy-table {
      width: 100%;
      font-size: 13px;
      border-collapse: collapse;
    }

    .deploy-table td {
      padding: 8px 10px;
      border-bottom: 1px solid #2d3748;
    }

    .deploy-table td:first-child {
      color: #64748b;
      width: 40%;
    }

    .deploy-table td:last-child {
      color: #e2e8f0;
      font-weight: 600;
      font-family: monospace;
    }

    /* Logs */
    .log-container {
      background: #0a0d14;
      border: 1px solid #2d3748;
      border-radius: 8px;
      padding: 12px;
      height: 220px;
      overflow-y: auto;
      font-family: 'Courier New', monospace;
      font-size: 12px;
    }

    .log-entry { padding: 2px 0; line-height: 1.5; }
    .log-INFO  { color: #60a5fa; }
    .log-WARN  { color: #fbbf24; }
    .log-ERROR { color: #f87171; }

    .spinner {
      display: inline-block;
      width: 14px; height: 14px;
      border: 2px solid #fff;
      border-top-color: transparent;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      vertical-align: middle;
    }

    @keyframes spin { to { transform: rotate(360deg); } }

    .full-width { grid-column: 1 / -1; }

    .env-tag {
      display: inline-block;
      background: #064e3b;
      color: #34d399;
      border: 1px solid #34d399;
      border-radius: 4px;
      padding: 2px 8px;
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      margin-left: 8px;
      vertical-align: middle;
    }
  </style>
</head>
<body>

  <!-- Header -->
  <div class="header">
    <div>
      <h1>🚀 DevOps Agent POC - Demo <span class="env-tag">${ENVIRONMENT}</span></h1>
      <p>Live incident simulation dashboard — AWS DevOps Agent integration demo</p>
      <p style="margin-top:6px; font-size:12px; color:#64748b;">
        Instance: <strong style="color:#94a3b8">${os.hostname()}</strong> &nbsp;|&nbsp;
        Uptime: <span id="uptime">calculating...</span>
      </p>
    </div>
    <div class="badge">
      <div class="version">${APP_VERSION}</div>
      <div class="meta">by ${DEPLOYED_BY}</div>
      <div class="meta">${DEPLOYED_AT.replace('T',' ').substring(0,19)} UTC</div>
      <div class="meta" style="color:#475569">commit: ${GIT_COMMIT.substring(0,7)}</div>
    </div>
  </div>

  <div class="grid">

    <!-- Trigger Panel -->
    <div class="card">
      <h2>⚡ Incident Triggers</h2>
      <div class="btn-grid">
        <button class="btn btn-cpu"   onclick="trigger('/cpu',   this)" id="btn-cpu">
          🔥 Trigger CPU Spike <small style="opacity:0.8">(120s sustained loop)</small>
        </button>
        <button class="btn btn-error" onclick="trigger('/error', this)" id="btn-error">
          ❌ Trigger Error <small style="opacity:0.8">(HTTP 500)</small>
        </button>
        <button class="btn btn-slow"  onclick="trigger('/slow',  this)" id="btn-slow">
          🐢 Trigger Slow Response <small style="opacity:0.8">(10s delay)</small>
        </button>
        <button class="btn" style="background:#7f1d1d; color:#fff;"
                onclick="trigger('/crash', this)" id="btn-crash">
          💥 Simulate Deployment Bug <small style="opacity:0.8">(crashes app)</small>
        </button>
      </div>
      <div class="status-box" id="status">
        <span class="status-ok">✅ System healthy — ready to trigger incidents</span>
      </div>
    </div>

    <!-- Deployment Info -->
    <div class="card">
      <h2>🚢 Deployment Info</h2>
      <table class="deploy-table">
        <tr><td>Version</td>    <td>${APP_VERSION}</td></tr>
        <tr><td>Environment</td><td>${ENVIRONMENT}</td></tr>
        <tr><td>Deployed By</td><td>${DEPLOYED_BY}</td></tr>
        <tr><td>Deployed At</td><td>${DEPLOYED_AT.replace('T',' ').substring(0,19)}</td></tr>
        <tr><td>Git Commit</td> <td>${GIT_COMMIT.substring(0,12)}</td></tr>
        <tr><td>Hostname</td>   <td>${os.hostname()}</td></tr>
        <tr><td>Node.js</td>    <td>${process.version}</td></tr>
        <tr><td>Platform</td>   <td>${os.platform()} ${os.arch()}</td></tr>
      </table>
    </div>

    <!-- Stats -->
    <div class="card">
      <h2>📊 Request Stats</h2>
      <div class="stat-grid" id="stats">
        <div class="stat-item">
          <div class="stat-value" id="stat-cpu">0</div>
          <div class="stat-label">CPU Spikes</div>
        </div>
        <div class="stat-item">
          <div class="stat-value" id="stat-error">0</div>
          <div class="stat-label">Errors</div>
        </div>
        <div class="stat-item">
          <div class="stat-value" id="stat-slow">0</div>
          <div class="stat-label">Slow Reqs</div>
        </div>
      </div>
      <div style="margin-top:14px; font-size:12px; color:#64748b; text-align:center;">
        Total requests: <strong id="stat-total" style="color:#e2e8f0">0</strong>
        &nbsp;|&nbsp; Server started: <strong style="color:#e2e8f0">${stats.startTime.replace('T',' ').substring(0,19)}</strong>
      </div>
    </div>

    <!-- Live Logs -->
    <div class="card">
      <h2>📋 Live Logs <span id="log-badge" style="font-size:11px; color:#34d399; text-transform:none; font-weight:400">● streaming</span></h2>
      <div class="log-container" id="logs">
        <div class="log-entry log-INFO">[INFO] Server started — waiting for requests...</div>
      </div>
    </div>

  </div>

  <script>
    // ── Trigger incident endpoints ──────────────────────────────
    function trigger(path, btn) {
      const statusEl = document.getElementById('status');
      const labels = { '/cpu': 'CPU Spike', '/error': 'Error', '/slow': 'Slow Response' };
      const label  = labels[path];

      // Disable button + show spinner
      btn.disabled = true;
      btn.innerHTML = btn.innerHTML.replace(/^[^\s]+/, '<span class="spinner"></span>');
      statusEl.innerHTML = '<span class="status-warn">⏳ Triggering ' + label + '...</span>';

      fetch(path)
        .then(res => {
          const ok = res.ok;
          return res.text().then(text => ({ ok, text, status: res.status }));
        })
        .then(({ ok, text, status }) => {
          if (ok) {
            statusEl.innerHTML = '<span class="status-ok">✅ ' + label + ' completed: ' + text + '</span>';
          } else {
            statusEl.innerHTML = '<span class="status-error">❌ ' + label + ' — HTTP ' + status + ': ' + text + '</span>';
          }
          refreshStats();
          refreshLogs();
        })
        .catch(err => {
          statusEl.innerHTML = '<span class="status-error">⚠️ Request failed: ' + err.message + '</span>';
        })
        .finally(() => {
          btn.disabled = false;
          const icons = {
            '/cpu':   '🔥',
            '/error': '❌',
            '/slow':  '🐢',
            '/crash': '💥'
          };
          const smallText = {
            '/cpu':   '(120s sustained loop)',
            '/error': '(HTTP 500)',
            '/slow':  '(10s delay)',
            '/crash': '(crashes app)'
          };
          const names = {
            '/cpu':   'Trigger CPU Spike',
            '/error': 'Trigger Error',
            '/slow':  'Trigger Slow Response',
            '/crash': 'Simulate Deployment Bug'
          };
          btn.innerHTML = icons[path] + ' ' + names[path] + ' <small style="opacity:0.8">' + smallText[path] + '</small>';
        });
      }

    // ── Fetch and update stats ───────────────────────────────────
    function refreshStats() {
      fetch('/stats')
        .then(r => r.json())
        .then(data => {
          document.getElementById('stat-cpu').textContent   = data.cpu.count;
          document.getElementById('stat-error').textContent = data.error.count;
          document.getElementById('stat-slow').textContent  = data.slow.count;
          document.getElementById('stat-total').textContent = data.total;
        })
        .catch(() => {});
    }

    // ── Fetch and update logs ────────────────────────────────────
    function refreshLogs() {
      fetch('/logs')
        .then(r => r.json())
        .then(logs => {
          const container = document.getElementById('logs');
          container.innerHTML = logs.map(l =>
            '<div class="log-entry log-' + l.level + '">' +
            '<span style="color:#475569">' + l.time.replace('T',' ').substring(0,19) + '</span> ' +
            '<span>[' + l.level + ']</span> ' + l.message +
            '</div>'
          ).join('');
        })
        .catch(() => {});
    }

    // ── Uptime counter ───────────────────────────────────────────
    const serverStart = new Date('${stats.startTime}');
    function updateUptime() {
      const diff = Math.floor((Date.now() - serverStart) / 1000);
      const h = Math.floor(diff / 3600);
      const m = Math.floor((diff % 3600) / 60);
      const s = diff % 60;
      document.getElementById('uptime').textContent =
        (h > 0 ? h + 'h ' : '') + (m > 0 ? m + 'm ' : '') + s + 's';
    }

    // ── Auto-refresh every 5 seconds ─────────────────────────────
    setInterval(refreshStats, 5000);
    setInterval(refreshLogs,  5000);
    setInterval(updateUptime, 1000);

    // Initial load
    refreshStats();
    refreshLogs();
    updateUptime();
  </script>
</body>
</html>`;
}

//  HTTP Server 
const server = http.createServer((req, res) => {
  stats.total++;
  addLog('INFO', `Request: ${req.method} ${req.url}`);

  //  Dashboard UI 
  if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(getHTML());
  }

  // ── Stats API ──
  else if (req.url === '/stats') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(stats));
  }

  // ── Logs API ──
  else if (req.url === '/logs') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(recentLogs));
  }

  // ── Health check ──
  else if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status:    'healthy',
      version:   APP_VERSION,
      commit:    GIT_COMMIT,
      uptime:    process.uptime(),
      timestamp: new Date().toISOString()
    }));
  }

  // ── CPU spike ──
    else if (req.url === '/cpu') {
    stats.cpu.count++;
    stats.cpu.lastTriggered = new Date().toISOString();
    addLog('WARN', `CPU spike triggered — running high CPU load for 120s (trigger #${stats.cpu.count})`);

    // Run 120s of sustained CPU load — enough for CloudWatch to capture clearly
    const duration = 120000; // 120 seconds
    const start = Date.now();

    // Use setInterval to keep event loop alive + maintain sustained CPU
    let elapsed = 0;
    const interval = setInterval(() => {
      elapsed = Date.now() - start;

      // Burn CPU in each interval tick
      const burn = Date.now();
      while (Date.now() - burn < 900) {} // burn 900ms per tick

      addLog('WARN', `CPU burning — ${Math.floor(elapsed / 1000)}s / 120s elapsed`);

      if (elapsed >= duration) {
        clearInterval(interval);
        addLog('WARN', `CPU spike #${stats.cpu.count} completed — 120s sustained load done`);
      }
    }, 1000); // tick every second

    // Respond immediately so browser doesn't hang
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(`CPU spike #${stats.cpu.count} started — 120s sustained load running in background`);
  }

  // ── Error simulation ──
  else if (req.url === '/error') {
    stats.error.count++;
    stats.error.lastTriggered = new Date().toISOString();
    addLog('ERROR', `Simulated error triggered (error #${stats.error.count})`);

    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end(`Simulated error #${stats.error.count} generated`);
  }

  // Add a new buggy endpoint that causes errors
  else if (req.url === "/bug") {
    stats.error.count++;
    addLog('ERROR', `Bug endpoint hit — simulating post-deployment error (build #${stats.error.count})`);
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end(`Post-deployment bug detected — error #${stats.error.count}`);
  }

  // ── Slow response simulation ──
  else if (req.url === '/slow') {
    stats.slow.count++;
    stats.slow.lastTriggered = new Date().toISOString();
    addLog('WARN', `Slow response triggered — waiting 10s (request #${stats.slow.count})`);

    setTimeout(() => {
      addLog('INFO', 'Slow response completed — 10s delay done');
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(`Slow response #${stats.slow.count} done (10s delay)`);
    }, 10000);
  }

  // ── Crash simulation ──
  else if (req.url === '/crash') {
    stats.error.count++;
    stats.error.lastTriggered = new Date().toISOString();

    // Log multiple ERROR lines per click — ensures metric filter catches them
    addLog('ERROR', `💥 DEPLOYMENT BUG: Uncaught exception (error #${stats.error.count})`);
    addLog('ERROR', `TypeError: Cannot read properties of undefined (reading 'data')`);
    addLog('ERROR', `  at processRequest (/app/app.js:45:12)`);
    addLog('ERROR', `  at Server.<anonymous> (/app/app.js:12:3)`);
    addLog('ERROR', `Stack trace: deployment introduced breaking change in feature branch`);

    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end(`Deployment bug #${stats.error.count} — fatal error logged!`);
  }

  // ── 404 ──
  else {
    addLog('WARN', `404 — route not found: ${req.url}`);
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  }
});

server.listen(3000, () => {
  addLog('INFO', `Server started on port 3000 | version=${APP_VERSION} | env=${ENVIRONMENT} | commit=${GIT_COMMIT}`);
});
