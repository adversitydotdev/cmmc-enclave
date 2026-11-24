variable "name_prefix" {
  type    = string
  default = "enclave"
}

variable "tier" {
  type    = string
  default = "standard"
}

variable "home_region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_regions" {
  type    = list(string)
  default = ["us-east-1", "us-east-2", "us-west-2"]
}

variable "use_fips_endpoint" {
  description = "Force FIPS endpoints (3.13.11). Some services have no FIPS endpoint; see modules/kms."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Default tags. owner, environment and data-classification are required: the tag SCP denies EC2, EBS and RDS creates without them."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["owner", "environment", "data-classification"] : contains(keys(var.tags), k)])
    error_message = "tags must include owner, environment and data-classification."
  }
}
