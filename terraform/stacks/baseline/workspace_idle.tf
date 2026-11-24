variable "workspace_idle_mode" {
  description = "report lists idle Workspace users in the log archive; suspend also suspends them. Suspend is deliberate: it needs the write scope delegated to the idle service account."
  type        = string
  default     = "report"
}

variable "workspace_idle_days" {
  description = "Days without login (creation time for never-logged-in users) before a Workspace user counts as idle."
  type        = number
  default     = 90
}

variable "workspace_idle_exclude_emails" {
  description = "Primary emails the idle check never suspends (break-glass, service accounts). Super admins are always excluded."
  type        = list(string)
  default     = []
}

variable "workspace_idle_exclude_org_units" {
  description = "Org unit paths (with sub-OUs) the idle check never suspends, for example [\"/Service Accounts\"]."
  type        = list(string)
  default     = []
}

# Runs in log_archive (bucket and logs key live there). Build the package first:
#   collectors/workspace_idle/build.sh
# Findings topic access for log_archive alarms is already in place (workspace_audit.tf).
module "workspace_idle" {
  source = "../../modules/workspace_idle"

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
  mode                    = var.workspace_idle_mode
  idle_days               = var.workspace_idle_days
  exclude_emails          = var.workspace_idle_exclude_emails
  exclude_org_units       = var.workspace_idle_exclude_org_units
}

output "workspace_idle_secret_arn" {
  description = "Set the idle service account's Google key JSON here by hand."
  value       = module.workspace_idle.service_account_secret_arn
}

output "workspace_idle_delegated_scope" {
  description = "The single Directory API scope to delegate to the idle service account for the configured mode."
  value       = module.workspace_idle.delegated_scope
}
