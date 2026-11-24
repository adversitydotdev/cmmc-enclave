output "log_archive_bucket_arn" {
  description = "ARN of the Object Lock log archive bucket."
  value       = aws_s3_bucket.archive.arn
}

output "log_archive_bucket_name" {
  description = "Name of the Object Lock log archive bucket."
  value       = aws_s3_bucket.archive.id
}

output "cloudtrail_arn" {
  description = "ARN of the org trail."
  value       = aws_cloudtrail.org.arn
}

output "findings_sns_topic_arn" {
  description = "Findings topic in security, home region."
  value       = aws_sns_topic.findings[var.home_region].arn
}

output "findings_sns_topic_arns" {
  description = "Findings topics in security by region."
  value       = { for r, t in aws_sns_topic.findings : r => t.arn }
}

output "athena_workgroup_name" {
  description = "Athena workgroup for audit review, in log_archive."
  value       = aws_athena_workgroup.audit.name
}

output "backup_vault_arns" {
  description = "Backup vault ARNs: workload (source) and log_archive (copy)."
  value = {
    workload    = aws_backup_vault.workload.arn
    log_archive = aws_backup_vault.log_archive.arn
  }
}
