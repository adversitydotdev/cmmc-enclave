output "function_name" {
  description = "Collector Lambda function name."
  value       = aws_lambda_function.collector.function_name
}

output "function_arn" {
  description = "Collector Lambda ARN."
  value       = aws_lambda_function.collector.arn
}

output "role_arn" {
  description = "Collector execution role."
  value       = aws_iam_role.collector.arn
}

output "service_account_secret_arn" {
  description = "Secrets Manager secret for the Google service account key JSON. Created empty; set by hand."
  value       = aws_secretsmanager_secret.service_account.arn
}

output "state_table_name" {
  description = "DynamoDB table with the per-application cursors."
  value       = aws_dynamodb_table.state.name
}

output "s3_prefix" {
  description = "Archive prefix the collector writes under."
  value       = local.prefix
}

output "alarm_names" {
  description = "Collector alarm names."
  value = [
    aws_cloudwatch_metric_alarm.errors.alarm_name,
    aws_cloudwatch_metric_alarm.no_success.alarm_name,
    aws_cloudwatch_metric_alarm.no_objects.alarm_name,
  ]
}
