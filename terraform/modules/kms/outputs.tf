output "kms_key_arns" {
  description = "Key ARNs: logs, security, workload_data, grc, backup_workload, backup_log_archive."
  value = {
    logs               = aws_kms_key.logs.arn
    security           = aws_kms_key.security.arn
    workload_data      = aws_kms_key.workload_data.arn
    grc                = aws_kms_key.grc.arn
    backup_workload    = aws_kms_key.backup_workload.arn
    backup_log_archive = aws_kms_key.backup_log_archive.arn
  }
}

output "tls_policy_name" {
  description = "ALB listener ssl_policy (TLS 1.2+, FIPS)."
  value       = var.tls_policy_name
}

output "s3_tls_deny_statement_json" {
  description = "JSON array of two bucket policy Deny statements (SecureTransport=false, s3:TlsVersion<1.2). Replace {{bucket_arn}} with the bucket ARN."
  value       = jsonencode(local.s3_tls_deny_statements)
}

output "services_without_fips_endpoint" {
  description = "Services in this baseline with no FIPS endpoint in the active tier."
  value       = local.services_without_fips_endpoint
}

output "fips_endpoint_reference" {
  description = "Full FIPS endpoint map."
  value       = local.fips_services
}
