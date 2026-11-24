variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

variable "tier" {
  description = "Impact tier: standard (commercial AWS) or itar (AWS GovCloud). Fathom runs commercial only for now."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "itar"], var.tier)
    error_message = "tier must be standard or itar."
  }
}

variable "allowed_regions" {
  description = "Regions the enclave may use. The bucket is created in the provider's region, which must be one of them."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "grc CMK (kms module output kms_key_arns[\"grc\"]). Encrypts the seed bucket."
  type        = string
}

variable "bundle_path" {
  description = <<-EOT
    Local path of the seed artifact built by scripts/package-fathom-seed from the wizard's
    rendered ogrl/ directory (a .tar.gz holding bundle.yaml, the org objects, and the policy
    and procedure document bodies). Contract: the wizard output feeds the script, the script
    output feeds this variable. The artifact must have been built with --library-ref set to
    ogrl_library_ref.
  EOT
  type        = string
}

variable "ogrl_library_ref" {
  description = "Full ogrl-library commit the artifact pins (the manifest's library.commit). Same value CI lints against (OGRL_LIBRARY_REF in .github/workflows/ogrl.yml). Recorded as an object tag and an output so a mismatch with the artifact is visible; Fathom itself pins whatever the artifact names."
  type        = string
  default     = "5c0987730e2af897d0071cd3826f1c3c4faf8926"

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.ogrl_library_ref))
    error_message = "ogrl_library_ref must be a full 40-character lowercase commit SHA."
  }
}

variable "fathom_stack_id" {
  description = "ID of the Fathom CloudFormation stack (module fathom output stack_id). Orders the task role lookup after the stack exists."
  type        = string
}

variable "task_role_name_regex" {
  description = "Regex for the Fathom ECS task role name in this account. CloudFormation generates <stack>-TaskRole-<suffix> because the template names no role (fathom#13). Exactly one role must match."
  type        = string
  default     = "^fathom-TaskRole-"
}
