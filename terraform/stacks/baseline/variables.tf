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
  description = "Regions the enclave may use. Defaults to the home region only; more than one needs multi_region_data_protection (KMS keys, EBS default encryption and backups are home-region only)."
  type        = list(string)
  default     = ["us-east-1"]

  validation {
    condition     = contains(var.allowed_regions, var.home_region)
    error_message = "home_region must be one of allowed_regions."
  }
}

variable "multi_region_data_protection" {
  description = "Set true only once KMS, EBS default encryption and backups cover every region in allowed_regions. Today they cover home_region only, so allowed_regions beyond it fails a precondition."
  type        = bool
  default     = false
}

variable "use_fips_endpoint" {
  type    = bool
  default = true
}

variable "account_ids" {
  description = "Output account_ids from stacks/org: management, log_archive, security, workload, grc."
  type        = map(string)
}

variable "assume_role_name" {
  description = "Role created in each member account by AWS Organizations."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "organization_id" {
  description = "Output organization_id from stacks/org."
  type        = string
}

variable "tags" {
  description = "Default tags. owner, environment and data-classification are required: the tag SCP denies creates of EC2, EBS, RDS, Lambda, DynamoDB, ECS, Secrets Manager, SNS, SQS and EFS without them."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["owner", "environment", "data-classification"] : contains(keys(var.tags), k)])
    error_message = "tags must include owner, environment and data-classification."
  }
}
