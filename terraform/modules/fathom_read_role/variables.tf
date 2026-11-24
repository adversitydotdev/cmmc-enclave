variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

variable "tier" {
  description = "Impact tier: standard (commercial AWS) or itar (AWS GovCloud). itar is refused: the trust is a same-partition role trust, and the GovCloud path is IAM Roles Anywhere (decision #7, not built)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "itar"], var.tier)
    error_message = "tier must be standard or itar."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "grc_account_id" {
  description = "Account that runs Fathom (stacks/org account_ids[\"grc\"]). Only roles in this account can assume the read role."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.grc_account_id))
    error_message = "grc_account_id must be a 12-digit account ID."
  }
}

variable "task_role_name_pattern" {
  description = "IAM role name (wildcards allowed) of the Fathom ECS task role in grc. The template names no role, so CloudFormation generates <stack name>-TaskRole-<suffix>. When the template outputs the task role ARN (fathom#13) this becomes an exact name."
  type        = string
  default     = "fathom-TaskRole-*"
}

variable "external_ids" {
  description = "ExternalIds Fathom generates per aws_role connection. Empty: no sts:ExternalId condition (Fathom creates the value with the connection, so add it on a second apply). Several values let one role serve more than one connection."
  type        = list(string)
  default     = []
}

variable "role_name" {
  description = "Role name. Empty uses <name_prefix>-fathom-read."
  type        = string
  default     = ""
}
