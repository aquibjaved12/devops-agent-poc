# ── EventBridge Rule — fires when CPU alarm → ALARM ──────────────────
resource "aws_cloudwatch_event_rule" "cpu_alarm_trigger" {
  name        = "devops-agent-cpu-alarm-trigger"
  description = "Triggers Lambda when high-cpu-alarm transitions to ALARM"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = ["high-cpu-alarm"]
      state = {
        value = ["ALARM"]
      }
    }
  })

  tags = {
    Purpose = "DevOps Agent Auto-Alert"
    POC     = "true"
  }
}

# ── EventBridge Target — invoke Lambda ───────────────────────────────
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cpu_alarm_trigger.name
  target_id = "DevOpsAgentAutoAlert"
  arn       = var.lambda_function_arn
}

# ── Permission — allow EventBridge to invoke Lambda ───────────────────
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cpu_alarm_trigger.arn
}
