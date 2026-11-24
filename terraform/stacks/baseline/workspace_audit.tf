variable "workspace_admin_email" {
  description = "Workspace admin the audit collector's service account impersonates (domain-wide delegation)."
  type        = string
}

variable "workspace_audit_applications" {
  description = "Reports API applications the collector pulls."
  type        = list(string)
  default     = ["admin", "login", "drive", "token", "saml", "user_accounts", "groups", "mobile", "access_transparency"]
}

# Runs in log_archive (bucket and logs key live there). Build the package first:
#   collectors/workspace_audit/build.sh
# Cross-module changes this needs (not applied here), see the issue #30 report:
#   - findings topic policy (modules/logging/findings.tf): allow cloudwatch.amazonaws.com from log_archive
#   - security key policy (modules/kms/main.tf, FindingsSNS): allow cloudwatch from log_archive
module "workspace_audit" {
  source = "../../modules/workspace_audit"

  providers = {
    aws.log_archive = aws.log_archive
  }

  name_prefix             = var.name_prefix
  tags                    = var.tags
  log_archive_bucket_name = module.logging.log_archive_bucket_name
  log_archive_bucket_arn  = module.logging.log_archive_bucket_arn
  kms_key_arn             = module.kms.kms_key_arns["logs"]
  alarm_topic_arn         = module.logging.findings_sns_topic_arn
  admin_user_email        = var.workspace_admin_email
  applications            = var.workspace_audit_applications
}

output "workspace_audit_secret_arn" {
  description = "Set the Google service account key JSON here by hand."
  value       = module.workspace_audit.service_account_secret_arn
}
