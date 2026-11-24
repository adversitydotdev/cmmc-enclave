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
  description = "Default tags. owner, environment and data-classification are required: the tag SCP denies EC2, EBS and RDS creates without them."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["owner", "environment", "data-classification"] : contains(keys(var.tags), k)])
    error_message = "tags must include owner, environment and data-classification."
  }
}
