variable "create_organization" {
  description = "true creates the organization; false reads an existing one."
  type        = bool
  default     = true
}

variable "account_emails" {
  description = "Root emails for log_archive, security, workload, grc."
  type        = map(string)
}

variable "existing_account_ids" {
  description = "Already existing member accounts (same keys as account_emails)."
  type        = map(string)
  default     = {}
}

variable "exempt_principal_arn_patterns" {
  description = "ARN patterns of pipeline/admin roles exempt from the protective SCPs."
  type        = list(string)
  default     = ["arn:*:iam::*:role/OrganizationAccountAccessRole", "arn:*:iam::*:role/enclave-pipeline*"]
}

variable "log_archive_bucket_name_patterns" {
  description = "Bucket name patterns of the log archive buckets (from the logging module)."
  type        = list(string)
  default     = ["enclave-log-archive*"]
}

variable "service_access_principals" {
  description = "Trusted access principals. Trim for GovCloud if a service is unavailable."
  type        = list(string)
  default = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "malware-protection.guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
    "inspector2.amazonaws.com",
    "backup.amazonaws.com",
    "account.amazonaws.com",
    "iam.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
  ]
}

module "organization" {
  source = "../../modules/organization"

  providers = {
    aws.management = aws.management
  }

  name_prefix                      = var.name_prefix
  tier                             = var.tier
  allowed_regions                  = var.allowed_regions
  tags                             = var.tags
  create_organization              = var.create_organization
  account_emails                   = var.account_emails
  existing_account_ids             = var.existing_account_ids
  exempt_principal_arn_patterns    = var.exempt_principal_arn_patterns
  log_archive_bucket_name_patterns = var.log_archive_bucket_name_patterns
  service_access_principals        = var.service_access_principals
}

output "organization_id" {
  value = module.organization.organization_id
}

output "organization_root_id" {
  value = module.organization.organization_root_id
}

output "account_ids" {
  value = module.organization.account_ids
}

output "ou_ids" {
  value = module.organization.ou_ids
}
