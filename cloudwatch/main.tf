resource "aws_cloudwatch_log_group" "app_logs" {
  name              = var.log_group_name
  retention_in_days = var.retention_days
}

# NEW: OS-level logs from /var/log/messages     
resource "aws_cloudwatch_log_group" "os_logs" {
  name              = var.os_log_group_name
  retention_in_days = var.retention_days
}



resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "high-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "EC2 CPU utilization exceeded 30% threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }
}


# NEW: Node.js process CPU alarm (procstat) 
resource "aws_cloudwatch_metric_alarm" "node_process_cpu_alarm" {
  alarm_name          = "high-node-process-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "procstat_cpu_usage"
  namespace           = "DevOpsAgent/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "Node.js process CPU exceeded 20% - approaching t3.micro baseline"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId   = var.instance_id
    process_name = "node"
  }
}

# ── NEW: App Error Log Metric Filter ─────────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "error_filter" {
  name           = "app-error-count"
  pattern        = "ERROR"
  log_group_name = var.log_group_name

  metric_transformation {
    name      = "AppErrorCount"
    namespace = "DevOpsAgent/EC2"
    value     = "1"
    unit      = "Count"
  }
}

# ── NEW: Error Rate Alarm ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  alarm_name          = "high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "AppErrorCount"
  namespace           = "DevOpsAgent/EC2"
  period              = 60
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "App error rate exceeded 3 errors per minute"
  treat_missing_data  = "notBreaching"
}