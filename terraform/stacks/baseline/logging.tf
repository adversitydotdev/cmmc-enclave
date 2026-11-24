variable "organization_root_id" {
  description = "Organization root ID (r-xxxx), from the organization module in stacks/org."
  type        = string
}

variable "enclave_bucket_arns" {
  description = "Enclave S3 bucket ARNs that get CloudTrail data events."
  type        = list(string)
  default     = []
}

variable "notification_emails" {
  description = "Emails subscribed to the security findings topics."
  type        = list(string)
  default     = []
}

module "logging" {
  source = "../../modules/logging"

  providers = {
    aws.management  = aws.management
    aws.log_archive = aws.log_archive
    aws.security    = aws.security
    aws.workload    = aws.workload
    aws.grc         = aws.grc
  }

  name_prefix          = var.name_prefix
  tier                 = var.tier
  allowed_regions      = var.allowed_regions
  tags                 = var.tags
  home_region          = var.home_region
  account_ids          = var.account_ids
  organization_id      = var.organization_id
  organization_root_id = var.organization_root_id
  kms_key_arns = {
    log_archive        = module.kms.kms_key_arns["logs"]
    management         = module.kms.kms_key_arns["logs"] # cross-account: the logs key grants CloudWatch Logs in every account
    security           = module.kms.kms_key_arns["security"]
    workload           = module.kms.kms_key_arns["backup_workload"]
    backup_log_archive = module.kms.kms_key_arns["backup_log_archive"]
  }
  enclave_bucket_arns   = var.enclave_bucket_arns
  notification_emails   = var.notification_emails
  break_glass_user_name = var.break_glass_user_name
}

output "log_archive_bucket_arn" {
  value = module.logging.log_archive_bucket_arn
}

output "log_archive_bucket_name" {
  value = module.logging.log_archive_bucket_name
}

output "cloudtrail_arn" {
  value = module.logging.cloudtrail_arn
}

output "findings_sns_topic_arn" {
  value = module.logging.findings_sns_topic_arn
}

output "athena_workgroup_name" {
  value = module.logging.athena_workgroup_name
}

output "backup_vault_arns" {
  value = module.logging.backup_vault_arns
}
