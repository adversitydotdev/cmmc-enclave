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

# tflint-ignore: terraform_unused_declarations
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

variable "account_ids" {
  description = "Account IDs by key: management, log_archive, security, workload, grc."
  type        = map(string)
}

variable "group_members" {
  description = "Map of group name to list of Identity Center user names (SCIM-provisioned from Google Workspace). Keys must be a subset of the four managed groups."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for g in keys(var.group_members) : contains(["enclave-admins", "enclave-auditors", "fathom-operators", "logging-admins"], g)])
    error_message = "group_members keys must be enclave-admins, enclave-auditors, fathom-operators, or logging-admins."
  }
}

variable "break_glass_user_name" {
  description = "IAM user name for the break-glass user in management."
  type        = string
  default     = "break-glass"
}

variable "session_duration" {
  description = "Permission set session duration (ISO 8601)."
  type        = string
  default     = "PT1H"
}

variable "password_min_length" {
  description = "IAM password policy minimum length."
  type        = number
  default     = 14
}

variable "password_reuse_prevention" {
  description = "IAM password policy reuse prevention count."
  type        = number
  default     = 24
}

variable "password_max_age" {
  description = "IAM password policy max age in days."
  type        = number
  default     = 90
}
