import boto3
import json
import os
import requests
from datetime import datetime, timezone, timedelta

# ── AWS Clients ──────────────────────────────────────────────────────
ec2_client = boto3.client('ec2',        region_name='us-east-1')
cw_client  = boto3.client('cloudwatch', region_name='us-east-1')
ses_client = boto3.client('ses',        region_name='us-east-1')

# ── Environment Variables ────────────────────────────────────────────
ALERT_EMAIL      = os.environ.get('ALERT_EMAIL')
GITHUB_TOKEN     = os.environ.get('GITHUB_TOKEN')
GITHUB_REPO      = os.environ.get('GITHUB_REPO')
DEVOPS_AGENT_URL = os.environ.get('DEVOPS_AGENT_URL',
                   'https://console.aws.amazon.com/devops-agent')


# ════════════════════════════════════════════════════════════════════
# MAIN HANDLER
# ════════════════════════════════════════════════════════════════════
def lambda_handler(event, context):
    print(f"Event: {json.dumps(event)}")

    try:
        # ── Extract alarm details ────────────────────────────────────
        alarm_name  = event['detail']['alarmName']
        alarm_state = event['detail']['state']['value']
        alarm_time  = event['detail']['state']['timestamp']
        reason      = event['detail']['state'].get('reason', 'N/A')
        instance_id = extract_instance_id(event)

        print(f"Alarm: {alarm_name} | State: {alarm_state} | Instance: {instance_id}")

        # Only process ALARM state
        if alarm_state != 'ALARM':
            print(f"State is {alarm_state} — skipping")
            return {'statusCode': 200, 'body': 'Not an ALARM state — skipped'}

        # ── Enrich context ───────────────────────────────────────────
        ec2_details    = get_ec2_details(instance_id)
        cpu_metrics    = get_cpu_metrics(instance_id)
        last_deploy    = get_last_github_deployment()
        investigation_prompt = build_investigation_prompt(
            alarm_name, alarm_time, instance_id,
            cpu_metrics, last_deploy
        )

        # ── Send Email ───────────────────────────────────────────────
        send_alert_email(
            alarm_name, alarm_time, reason,
            instance_id, ec2_details,
            cpu_metrics, last_deploy,
            investigation_prompt
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Alert email sent successfully',
                'alarm':   alarm_name,
                'instance': instance_id
            })
        }

    except Exception as e:
        print(f"Lambda error: {str(e)}")
        send_error_email(str(e))
        raise


# ════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ════════════════════════════════════════════════════════════════════

def extract_instance_id(event):
    """Extract EC2 instance ID from alarm event dimensions"""
    try:
        metrics = event['detail']['configuration']['metrics']
        for metric in metrics:
            dimensions = metric.get('metricStat', {}) \
                               .get('metric', {}) \
                               .get('dimensions', {})
            if 'InstanceId' in dimensions:
                return dimensions['InstanceId']
        return os.environ.get('DEFAULT_INSTANCE_ID', 'unknown')
    except Exception as e:
        print(f"Could not extract instance ID: {e}")
        return os.environ.get('DEFAULT_INSTANCE_ID', 'unknown')


def get_ec2_details(instance_id):
    """Fetch EC2 instance metadata"""
    try:
        if instance_id == 'unknown':
            return {}
        response = ec2_client.describe_instances(
            InstanceIds=[instance_id]
        )
        instance = response['Reservations'][0]['Instances'][0]

        # Get Name tag
        name = 'N/A'
        for tag in instance.get('Tags', []):
            if tag['Key'] == 'Name':
                name = tag['Value']

        return {
            'name':          name,
            'instance_type': instance.get('InstanceType', 'N/A'),
            'state':         instance['State']['Name'],
            'launch_time':   str(instance.get('LaunchTime', 'N/A')),
            'private_ip':    instance.get('PrivateIpAddress', 'N/A'),
            'public_ip':     instance.get('PublicIpAddress', 'N/A'),
            'region':        'us-east-1'
        }
    except Exception as e:
        print(f"Could not get EC2 details: {e}")
        return {
            'name': 'N/A', 'instance_type': 'N/A',
            'state': 'N/A', 'public_ip': 'N/A',
            'region': 'us-east-1'
        }


def get_cpu_metrics(instance_id):
    """Fetch last 10 minutes of CPU utilization"""
    try:
        end_time   = datetime.now(timezone.utc)
        start_time = end_time - timedelta(minutes=10)

        response = cw_client.get_metric_statistics(
            Namespace  = 'AWS/EC2',
            MetricName = 'CPUUtilization',
            Dimensions = [{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime  = start_time,
            EndTime    = end_time,
            Period     = 60,
            Statistics = ['Average', 'Maximum']
        )

        datapoints = sorted(
            response.get('Datapoints', []),
            key=lambda x: x['Timestamp']
        )

        if datapoints:
            latest = datapoints[-1]
            peak   = max(datapoints, key=lambda x: x['Maximum'])
            return {
                'average':        round(latest['Average'], 2),
                'maximum':        round(latest['Maximum'], 2),
                'peak':           round(peak['Maximum'], 2),
                'peak_time':      str(peak['Timestamp']),
                'datapoints':     len(datapoints),
                'threshold':      30
            }
        return {
            'average': 0, 'maximum': 0,
            'peak': 0, 'threshold': 30
        }
    except Exception as e:
        print(f"Could not get CPU metrics: {e}")
        return {
            'average': 0, 'maximum': 0,
            'peak': 0, 'threshold': 30
        }


def get_last_github_deployment():
    """Fetch last deployment from GitHub Actions"""
    try:
        if not GITHUB_TOKEN or not GITHUB_REPO:
            return {
                'commit':  'N/A',
                'message': 'GitHub token not configured',
                'author':  'N/A',
                'time':    'N/A',
                'run_url': 'N/A',
                'run_num': 'N/A'
            }

        headers = {
            'Authorization': f'token {GITHUB_TOKEN}',
            'Accept':        'application/vnd.github.v3+json'
        }

        # Get latest workflow run
        url = f'https://api.github.com/repos/{GITHUB_REPO}/actions/runs'
        response = requests.get(
            url,
            headers=headers,
            params={'status': 'completed', 'per_page': 1},
            timeout=10
        )

        if response.status_code == 200:
            runs = response.json().get('workflow_runs', [])
            if runs:
                run = runs[0]
                # Get commit details
                commit_sha = run.get('head_sha', 'N/A')
                commit_msg = run.get('head_commit', {}).get('message', 'N/A')
                author     = run.get('head_commit', {}).get(
                    'author', {}
                ).get('name', 'N/A')

                return {
                    'commit':  commit_sha[:7],
                    'full_sha': commit_sha,
                    'message': commit_msg.split('\n')[0],
                    'author':  author,
                    'time':    run.get('updated_at', 'N/A'),
                    'run_url': run.get('html_url', 'N/A'),
                    'run_num': str(run.get('run_number', 'N/A')),
                    'status':  run.get('conclusion', 'N/A')
                }

        return {
            'commit': 'N/A', 'message': 'Could not fetch',
            'author': 'N/A', 'time': 'N/A',
            'run_url': 'N/A', 'run_num': 'N/A'
        }

    except Exception as e:
        print(f"Could not get GitHub deployment: {e}")
        return {
            'commit': 'N/A', 'message': f'Error: {str(e)}',
            'author': 'N/A', 'time': 'N/A',
            'run_url': 'N/A', 'run_num': 'N/A'
        }


def build_investigation_prompt(alarm_name, alarm_time,
                                instance_id, cpu_metrics,
                                last_deploy):
    """Build ready-to-paste DevOps Agent investigation prompt"""
    return (
        f"Investigate high CPU alarm '{alarm_name}' on EC2 instance "
        f"{instance_id} triggered at {alarm_time}. "
        f"CPU utilization reached {cpu_metrics.get('average')}% average "
        f"and {cpu_metrics.get('maximum')}% maximum against a "
        f"{cpu_metrics.get('threshold')}% threshold. "
        f"Last deployment was commit {last_deploy.get('commit')} "
        f"('{last_deploy.get('message')}') by {last_deploy.get('author')} "
        f"at {last_deploy.get('time')} via GitHub Actions "
        f"run #{last_deploy.get('run_num')}. "
        f"Please identify the root cause, impacted processes, "
        f"and correlation with recent deployments."
    )


def send_alert_email(alarm_name, alarm_time, reason,
                     instance_id, ec2_details,
                     cpu_metrics, last_deploy,
                     investigation_prompt):
    """Send rich HTML alert email via SES"""

    subject = (
        f"🔴 [AUTO-ALERT] High CPU — "
        f"{instance_id} — Investigation Required"
    )

    # ── Plain text version ───────────────────────────────────────────
    text_body = f"""
HIGH CPU ALERT — AWS DevOps Agent POC
======================================

ALARM DETAILS
  Alarm Name : {alarm_name}
  State      : ALARM
  Time       : {alarm_time}
  Reason     : {reason}

EC2 DETAILS
  Instance ID   : {instance_id}
  Instance Name : {ec2_details.get('name', 'N/A')}
  Instance Type : {ec2_details.get('instance_type', 'N/A')}
  Region        : {ec2_details.get('region', 'N/A')}
  Public IP     : {ec2_details.get('public_ip', 'N/A')}
  State         : {ec2_details.get('state', 'N/A')}

CPU METRICS (Last 10 min)
  Average   : {cpu_metrics.get('average')}%
  Maximum   : {cpu_metrics.get('maximum')}%
  Peak      : {cpu_metrics.get('peak')}%
  Threshold : {cpu_metrics.get('threshold')}%

LAST GITHUB DEPLOYMENT
  Commit  : {last_deploy.get('commit')}
  Message : {last_deploy.get('message')}
  Author  : {last_deploy.get('author')}
  Time    : {last_deploy.get('time')}
  Run #   : {last_deploy.get('run_num')}
  URL     : {last_deploy.get('run_url')}

INVESTIGATION PROMPT (copy-paste to DevOps Agent):
{investigation_prompt}

Open DevOps Agent: {DEVOPS_AGENT_URL}

---
Auto-generated by AWS Lambda + EventBridge
DevOps Agent POC — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
"""

    # ── HTML version ─────────────────────────────────────────────────
    html_body = f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <style>
    body {{
      font-family: 'Segoe UI', Arial, sans-serif;
      background: #f1f5f9;
      margin: 0; padding: 20px;
      color: #1e293b;
    }}
    .container {{
      max-width: 700px;
      margin: 0 auto;
      background: #ffffff;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 4px 20px rgba(0,0,0,0.1);
    }}
    .header {{
      background: linear-gradient(135deg, #232f3e, #1a1f2e);
      padding: 28px 32px;
      border-top: 5px solid #ff0000;
    }}
    .header h1 {{
      color: #ffffff;
      margin: 0;
      font-size: 22px;
    }}
    .header p {{
      color: #94a3b8;
      margin: 6px 0 0;
      font-size: 13px;
    }}
    .alert-badge {{
      display: inline-block;
      background: #dc2626;
      color: white;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 700;
      margin-bottom: 10px;
    }}
    .body {{ padding: 28px 32px; }}
    .section {{
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 18px 20px;
      margin-bottom: 16px;
    }}
    .section h2 {{
      font-size: 13px;
      font-weight: 700;
      color: #64748b;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      margin: 0 0 12px;
      padding-bottom: 8px;
      border-bottom: 1px solid #e2e8f0;
    }}
    .grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
    }}
    .field {{ margin: 4px 0; font-size: 13px; }}
    .label {{
      color: #64748b;
      font-weight: 500;
    }}
    .value {{
      color: #1e293b;
      font-weight: 600;
    }}
    .value.red   {{ color: #dc2626; }}
    .value.green {{ color: #16a34a; }}
    .value.blue  {{ color: #2563eb; }}
    .metric-row {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 0;
      border-bottom: 1px solid #f1f5f9;
    }}
    .metric-row:last-child {{ border: none; }}
    .metric-value {{
      font-size: 24px;
      font-weight: 700;
      color: #dc2626;
    }}
    .prompt-box {{
      background: #0f172a;
      border-radius: 8px;
      padding: 16px 20px;
      margin-top: 8px;
    }}
    .prompt-box p {{
      color: #ffffff;
      font-family: 'Courier New', monospace;
      font-size: 13px;
      line-height: 1.8;
      margin: 0;
      white-space: pre-wrap;
      word-break: break-word;
    }}
    .cta-button {{
      display: block;
      background: #ff9900;
      color: #000000 !important;
      text-decoration: none;
      padding: 14px 28px;
      border-radius: 8px;
      font-weight: 700;
      font-size: 15px;
      text-align: center;
      margin: 20px 0 8px;
    }}
    .footer {{
      background: #f8fafc;
      padding: 16px 32px;
      border-top: 1px solid #e2e8f0;
      font-size: 11px;
      color: #94a3b8;
      text-align: center;
    }}
    .tag {{
      display: inline-block;
      background: #fef3c7;
      color: #92400e;
      border: 1px solid #fcd34d;
      border-radius: 4px;
      padding: 2px 8px;
      font-size: 11px;
      font-weight: 600;
    }}
  </style>
</head>
<body>
<div class="container">

  <!-- Header -->
  <div class="header">
    <div class="alert-badge">🔴 ALARM</div>
    <h1>High CPU Alert — Auto-Enriched</h1>
    <p>
      Auto-generated by AWS Lambda + EventBridge •
      {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
    </p>
  </div>

  <div class="body">

    <!-- Alarm Details -->
    <div class="section">
      <h2>🚨 Alarm Details</h2>
      <div class="grid">
        <div class="field">
          <span class="label">Alarm Name: </span>
          <span class="value red">{alarm_name}</span>
        </div>
        <div class="field">
          <span class="label">State: </span>
          <span class="value red">● ALARM</span>
        </div>
        <div class="field">
          <span class="label">Triggered At: </span>
          <span class="value">{alarm_time}</span>
        </div>
        <div class="field">
          <span class="label">Threshold: </span>
          <span class="value">{cpu_metrics.get('threshold')}% CPU</span>
        </div>
      </div>
    </div>

    <!-- EC2 Details -->
    <div class="section">
      <h2>🖥️ EC2 Instance Details</h2>
      <div class="grid">
        <div class="field">
          <span class="label">Instance ID: </span>
          <span class="value blue">{instance_id}</span>
        </div>
        <div class="field">
          <span class="label">Type: </span>
          <span class="value">{ec2_details.get('instance_type', 'N/A')}</span>
        </div>
        <div class="field">
          <span class="label">Region: </span>
          <span class="value">{ec2_details.get('region', 'N/A')}</span>
        </div>
        <div class="field">
          <span class="label">Public IP: </span>
          <span class="value">{ec2_details.get('public_ip', 'N/A')}</span>
        </div>
        <div class="field">
          <span class="label">State: </span>
          <span class="value green">{ec2_details.get('state', 'N/A')}</span>
        </div>
        <div class="field">
          <span class="label">Name: </span>
          <span class="value">{ec2_details.get('name', 'N/A')}</span>
        </div>
      </div>
    </div>

    <!-- CPU Metrics -->
    <div class="section">
      <h2>📊 CPU Metrics — Last 10 Minutes</h2>
      <div class="metric-row">
        <span class="label">Average CPU</span>
        <span class="metric-value">{cpu_metrics.get('average')}%</span>
      </div>
      <div class="metric-row">
        <span class="label">Maximum CPU</span>
        <span class="metric-value">{cpu_metrics.get('maximum')}%</span>
      </div>
      <div class="metric-row">
        <span class="label">Peak CPU</span>
        <span class="metric-value">{cpu_metrics.get('peak')}%</span>
      </div>
      <div class="metric-row">
        <span class="label">Threshold</span>
        <span style="font-weight:600; color:#64748b;">
          {cpu_metrics.get('threshold')}%
        </span>
      </div>
    </div>

    <!-- Last Deployment -->
    <div class="section">
      <h2>🚀 Last GitHub Deployment</h2>
      <div class="grid">
        <div class="field">
          <span class="label">Commit: </span>
          <span class="value blue">{last_deploy.get('commit')}</span>
        </div>
        <div class="field">
          <span class="label">Run #: </span>
          <span class="value">{last_deploy.get('run_num')}</span>
        </div>
        <div class="field">
          <span class="label">Author: </span>
          <span class="value">{last_deploy.get('author')}</span>
        </div>
        <div class="field">
          <span class="label">Status: </span>
          <span class="value green">{last_deploy.get('status', 'N/A')}</span>
        </div>
      </div>
      <div class="field" style="margin-top:10px;">
        <span class="label">Message: </span>
        <span class="value">{last_deploy.get('message')}</span>
      </div>
      <div class="field" style="margin-top:6px;">
        <span class="label">Deployed At: </span>
        <span class="value">{last_deploy.get('time')}</span>
      </div>
      <div style="margin-top:10px;">
        <a href="{last_deploy.get('run_url')}"
           style="color:#2563eb; font-size:13px;">
          → View GitHub Actions Run
        </a>
      </div>
    </div>

    <!-- Investigation Prompt -->
    <div class="section">
      <h2>🤖 Ready-to-Use Investigation Prompt</h2>
      <p style="font-size:13px; color:#64748b; margin:0 0 10px;">
        👇 Copy the text below and paste it into AWS DevOps Agent:
      </p>
      <div class="prompt-box">
        <p>{investigation_prompt}</p>
      </div>
    </div>

    <!-- Steps to Investigate -->
    <div class="section" style="background:#f0fdf4; border:1px solid #bbf7d0;">
      <h2 style="color:#15803d;">📋 Steps to Start Investigation</h2>
      <div style="font-size:13px; color:#1e293b; line-height:2;">
        <div>
          <strong>Step 1:</strong>
          Open AWS DevOps Agent Web App
        </div>
        <div>
          <strong>Step 2:</strong>
          Click "Start Investigation"
        </div>
        <div>
          <strong>Step 3:</strong>
          Copy the prompt above and paste it
        </div>
        <div>
          <strong>Step 4:</strong>
          Wait ~3 minutes for RCA ✅
        </div>
      </div>
    </div>

  </div>

  <!-- Footer -->
  <div class="footer">
    <span class="tag">AUTO-GENERATED</span>
    &nbsp; AWS Lambda + EventBridge + SES &nbsp;|&nbsp;
    DevOps Agent POC &nbsp;|&nbsp;
    {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
  </div>

</div>
</body>
</html>
"""

    # ── Send via SES ─────────────────────────────────────────────────
    ses_client.send_email(
        Source      = ALERT_EMAIL,
        Destination = {'ToAddresses': [ALERT_EMAIL]},
        Message     = {
            'Subject': {
                'Data':    subject,
                'Charset': 'UTF-8'
            },
            'Body': {
                'Text': {
                    'Data':    text_body,
                    'Charset': 'UTF-8'
                },
                'Html': {
                    'Data':    html_body,
                    'Charset': 'UTF-8'
                }
            }
        }
    )
    print(f"Alert email sent to {ALERT_EMAIL}")


def send_error_email(error_msg):
    """Send error notification if Lambda fails"""
    try:
        ses_client.send_email(
            Source      = ALERT_EMAIL,
            Destination = {'ToAddresses': [ALERT_EMAIL]},
            Message     = {
                'Subject': {
                    'Data': '⚠️ DevOps Agent Alert Lambda Error',
                    'Charset': 'UTF-8'
                },
                'Body': {
                    'Text': {
                        'Data': (
                            f"Lambda function failed:\n\n{error_msg}\n\n"
                            f"Please check CloudWatch logs for details."
                        ),
                        'Charset': 'UTF-8'
                    }
                }
            }
        )
    except Exception as e:
        print(f"Could not send error email: {e}")
