# ── Lambda IAM Role ──────────────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "devops-agent-alert-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# ── Lambda IAM Policy ─────────────────────────────────────────────────
resource "aws_iam_role_policy" "lambda_policy" {
  name = "devops-agent-alert-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # CloudWatch Logs — Lambda execution logs
      {
        Sid    = "LambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },

      # EC2 — describe instances for enrichment
      {
        Sid    = "EC2Read"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },

      # CloudWatch — get metrics for enrichment
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      },

      # SES — send alert emails
      {
        Sid    = "SESEmail"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Package Lambda function ───────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.root}/lambda/autoalert"
  output_path = "${path.root}/lambda/autoalert/lambda_function.zip"
}

# ── Lambda Function ───────────────────────────────────────────────────
resource "aws_lambda_function" "auto_alert" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "devops-agent-auto-alert"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ALERT_EMAIL          = var.alert_email
      GITHUB_TOKEN         = var.github_token
      GITHUB_REPO          = var.github_repo
      DEVOPS_AGENT_URL     = var.devops_agent_url
      DEFAULT_INSTANCE_ID  = var.instance_id
    }
  }

  tags = {
    Purpose = "DevOps Agent Auto-Alert"
    POC     = "true"
  }
}

# ── CloudWatch Log Group for Lambda ──────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/devops-agent-auto-alert"
  retention_in_days = 14
}
