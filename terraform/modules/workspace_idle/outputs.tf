output "function_name" {
  description = "Idle-account Lambda function name."
  value       = aws_lambda_function.idle.function_name
}

output "function_arn" {
  description = "Idle-account Lambda ARN."
  value       = aws_lambda_function.idle.arn
}

output "role_arn" {
  description = "Execution role."
  value       = aws_iam_role.idle.arn
}

output "service_account_secret_arn" {
  description = "Secrets Manager secret for the Google service account key JSON. Created empty; set by hand."
  value       = aws_secretsmanager_secret.service_account.arn
}

output "s3_prefix" {
  description = "Archive prefix the reports are written under."
  value       = local.prefix
}

output "delegated_scope" {
  description = "The one Directory API scope to delegate to this service account in the Admin console for the configured mode."
  value       = local.scopes[var.mode]
}

output "alarm_names" {
  description = "Alarm names."
  value = [
    aws_cloudwatch_metric_alarm.errors.alarm_name,
    aws_cloudwatch_metric_alarm.no_success.alarm_name,
  ]
}
