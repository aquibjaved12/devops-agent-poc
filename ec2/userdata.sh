#!/bin/bash
yum update -y

# Install NodeJS properly
curl -sL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent

# Create app directory
mkdir -p /app
cd /app

# Create Node.js app
cat <<'APPEOF' > /app/app.js
const http = require('http');

const server = http.createServer((req, res) => {
  console.log("Request received:", req.url);

  if (req.url === "/") {
    res.end("App is running fine");
  }

  else if (req.url === "/error") {
    console.error("Simulated error triggered");
    res.statusCode = 500;
    res.end("Simulated application error");
    return;
  }

  else if (req.url === "/cpu") {
    console.log("CPU spike triggered");
    const start = Date.now();
    while (Date.now() - start < 10000) {}
    res.end("CPU spike completed");
  }

  else if (req.url === "/slow") {
    console.log("Slow response triggered");
    setTimeout(() => {
      res.end("Slow response done");
    }, 10000);
  }

  else {
    res.end("OK");
  }
});

server.listen(3000, () => {
  console.log("Server started on port 3000");
});
APPEOF

# Run app in background
nohup node /app/app.js > /var/log/app.log 2>&1 &

# -------------------------------------------------------------
# AL2023: Export journald to /var/log/messages
# (AL2023 removed /var/log/messages - we recreate via journald)
# -------------------------------------------------------------
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald

cat <<'EOF' > /etc/systemd/system/journal-to-messages.service
[Unit]
Description=Export journald to /var/log/messages
After=systemd-journald.service

[Service]
ExecStart=/bin/bash -c 'journalctl -f -o short >> /var/log/messages 2>&1'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable journal-to-messages
systemctl start journal-to-messages

# Give journal time to start writing before CW Agent reads it
sleep 10

# -------------------------------------------------------------
# CloudWatch Agent Config
# Covers:
#   - /var/log/messages -> OS-level logs (journald export)
#   - /var/log/app.log  -> Node.js application logs
#   - procstat (node)   -> Per-process CPU & memory metrics
#   - cpu/mem/disk      -> System metrics
# NOTE: Using tee + CWEOF delimiter to avoid heredoc conflicts
# -------------------------------------------------------------
tee /opt/aws/amazon-cloudwatch-agent/bin/config.json > /dev/null <<'CWEOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "namespace": "DevOpsAgent/EC2",
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system",
          "cpu_usage_iowait"
        ],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_available_percent"
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": [
          "used_percent",
          "inodes_free"
        ],
        "metrics_collection_interval": 60,
        "resources": ["/"]
      },
      "procstat": [
        {
          "pattern": "node",
          "measurement": [
            "cpu_usage",
            "memory_rss",
            "pid_count"
          ],
          "metrics_collection_interval": 60
        }
      ]
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "devops-agent-os-logs",
            "log_stream_name": "{instance_id}/messages",
            "timezone": "UTC",
            "retention_in_days": 30
          },
          {
            "file_path": "/var/log/app.log",
            "log_group_name": "devops-agent-app-logs",
            "log_stream_name": "{instance_id}/app",
            "timezone": "UTC",
            "retention_in_days": 30
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}/default",
    "force_flush_interval": 15
  }
}
CWEOF

# Validate JSON before starting agent
python3 -m json.tool /opt/aws/amazon-cloudwatch-agent/bin/config.json \
  && echo "CloudWatch Agent config JSON is valid" \
  || echo "CloudWatch Agent config JSON is INVALID - check config"

# Start CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json \
  -s

# Verify agent started
sleep 5
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

# ── Enable SSM Agent ─────────────────────────────────────────
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent