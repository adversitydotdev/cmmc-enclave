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
