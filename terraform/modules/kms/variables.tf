variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

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

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "organization_id" {
  description = "AWS Organization ID (o-xxxx). Used in aws:SourceOrgID and aws:PrincipalOrgID conditions."
  type        = string
}

variable "account_ids" {
  description = "Account IDs by role: management, log_archive, security, workload, grc."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["management", "log_archive", "security", "workload", "grc"] : contains(keys(var.account_ids), k)])
    error_message = "account_ids must contain management, log_archive, security, workload, grc."
  }
}

variable "deletion_window_in_days" {
  description = "KMS key deletion waiting period (7-30). 30 per OGRL CR-02."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be 7-30."
  }
}

variable "tls_policy_name" {
  description = "ALB TLS 1.2+ FIPS security policy. 2023-04 is in commercial and GovCloud; ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09 is newer (verify GovCloud availability before switching)."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-FIPS-2023-04"

  validation {
    condition     = can(regex("^ELBSecurityPolicy-TLS13-1-2-.*FIPS", var.tls_policy_name))
    error_message = "Use a TLS 1.2 minimum FIPS policy (ELBSecurityPolicy-TLS13-1-2-*FIPS*)."
  }
}

variable "enable_ebs_default_encryption" {
  description = "Turn on EBS encryption by default (home region only): workload_data key in workload, grc key in grc."
  type        = bool
  default     = true
}
