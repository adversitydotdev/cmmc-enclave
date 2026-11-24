variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

# tflint-ignore: terraform_unused_declarations
variable "tier" {
  description = "Impact tier: standard (commercial AWS) or itar (AWS GovCloud)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "itar"], var.tier)
    error_message = "tier must be standard or itar."
  }
}

variable "allowed_regions" {
  description = "Regions the enclave may use. Standard: us-east-1, us-east-2, us-west-2. ITAR: us-gov-west-1, us-gov-east-1."
  type        = list(string)
}

# tflint-ignore: terraform_unused_declarations
variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "home_region" {
  description = "Region holding the org trail, log archive bucket, Config aggregator and Security Hub aggregation. Must be in allowed_regions."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = contains(var.allowed_regions, var.home_region)
    error_message = "home_region must be one of allowed_regions."
  }
}

variable "account_ids" {
  description = "Account IDs by key: management, log_archive, security, workload, grc."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["management", "log_archive", "security", "workload", "grc"] : contains(keys(var.account_ids), k)])
    error_message = "account_ids needs management, log_archive, security, workload and grc."
  }
}

variable "organization_id" {
  description = "AWS Organizations ID (o-xxxx)."
  type        = string
}

variable "organization_root_id" {
  description = "Organization root ID (r-xxxx), the Security Hub central configuration target."
  type        = string
}

variable "kms_key_arns" {
  description = "CMK ARNs by account: log_archive (archive bucket, trail, Config, Athena, Glue, log_archive backup vault), security (SNS topics), management (trail log group), workload (backup vault). Key policies must allow the consuming services."
  type = object({
    log_archive        = string
    security           = string
    management         = string
    workload           = string
    backup_log_archive = string
  })
}

variable "object_lock_retention_days" {
  description = "Compliance-mode Object Lock default retention on the log archive bucket (3.3.8)."
  type        = number
  default     = 365

  validation {
    condition     = var.object_lock_retention_days >= 1
    error_message = "object_lock_retention_days must be at least 1."
  }
}

variable "enclave_bucket_arns" {
  description = "Enclave S3 bucket ARNs that get CloudTrail data events, in addition to the archive bucket."
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "Retention for the trail's CloudWatch log group."
  type        = number
  default     = 365
}

variable "break_glass_user_name" {
  description = "IAM user name of the break-glass user in the management account; any use raises an alarm."
  type        = string
  default     = "break-glass"
}

variable "notification_emails" {
  description = "Email endpoints subscribed to the findings topics. Each must confirm."
  type        = list(string)
  default     = []
}

variable "securityhub_standard_ids" {
  description = "Security Hub standard identifiers (path after standards/) enabled org-wide by the central configuration policy. NIST SP 800-171 Rev 2 is nist-800-171/v/2.0.0."
  type        = list(string)
  default     = ["nist-800-171/v/2.0.0"]
}

variable "guardduty_features" {
  description = "GuardDuty protection plans auto-enabled for all org accounts."
  type        = list(string)
  default     = ["S3_DATA_EVENTS", "EBS_MALWARE_PROTECTION", "RDS_LOGIN_EVENTS", "LAMBDA_NETWORK_LOGS"]
}

variable "create_config_service_linked_roles" {
  description = "Create the Config service-linked role in each account. Set false where it already exists."
  type        = bool
  default     = true
}

variable "backup_vault_lock_min_retention_days" {
  description = "Vault Lock minimum retention. Keep at or above the CMMC pack's 35 days (backup-plan-min-frequency-and-min-retention-check)."
  type        = number
  default     = 35
}

variable "backup_vault_lock_max_retention_days" {
  description = "Vault Lock maximum retention."
  type        = number
  default     = 3650
}

variable "backup_vault_lock_changeable_for_days" {
  description = "null keeps Vault Lock in governance mode. 3 to 36500 switches to compliance mode after that many days; irreversible."
  type        = number
  default     = null
}

variable "backup_retention_days" {
  description = "Retention of recovery points in the workload vault and the log_archive copy. Must be within the Vault Lock bounds."
  type        = number
  default     = 90
}

variable "backup_selection_tag" {
  description = "Resources carrying this tag key and value are backed up."
  type = object({
    key   = string
    value = string
  })
  default = {
    key   = "backup"
    value = "true"
  }
}

variable "multi_region_data_protection" {
  description = "Acknowledge that AWS Backup vaults and plans covers home_region only. Leave false: with more than one allowed region the backup precondition fails until the module loops over regions (KMS keys are regional, so that also needs multi-region keys or a key per region)."
  type        = bool
  default     = false
}

variable "required_tag_keys" {
  description = "Tag keys the required-tags Config rule checks (max 6). Keep in step with the organization module."
  type        = list(string)
  default     = ["owner", "environment", "data-classification"]

  validation {
    condition     = length(var.required_tag_keys) >= 1 && length(var.required_tag_keys) <= 6
    error_message = "required_tag_keys takes 1 to 6 keys (the managed rule has tag1Key..tag6Key)."
  }
}
