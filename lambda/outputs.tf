output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.auto_alert.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.auto_alert.function_name
}

output "lambda_role_arn" {
  description = "Lambda IAM role ARN"
  value       = aws_iam_role.lambda_role.arn
}
