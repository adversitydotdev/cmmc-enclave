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
  description = "Regions the enclave may use. Defaults to the home region only; the baseline stack refuses more than one region until multi_region_data_protection is set there."
  type        = list(string)
  default     = ["us-east-1"]

  validation {
    condition     = contains(var.allowed_regions, var.home_region)
    error_message = "home_region must be one of allowed_regions."
  }
}

variable "use_fips_endpoint" {
  description = "Force FIPS endpoints (3.13.11). Some services have no FIPS endpoint; see modules/kms."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Default tags. owner, environment and data-classification are required: the tag SCP denies creates of EC2, EBS, RDS, Lambda, DynamoDB, ECS, Secrets Manager, SNS, SQS and EFS without them."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["owner", "environment", "data-classification"] : contains(keys(var.tags), k)])
    error_message = "tags must include owner, environment and data-classification."
  }
}
