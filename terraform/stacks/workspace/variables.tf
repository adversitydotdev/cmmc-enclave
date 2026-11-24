variable "customer_id" {
  description = "Workspace customer ID (Admin console, Account settings)."
  type        = string
}

variable "impersonated_user_email" {
  description = "Super admin the service account impersonates (required for roles)."
  type        = string
}

variable "credentials" {
  description = "Service account key JSON contents or path. Null reads GOOGLEWORKSPACE_CREDENTIALS from the environment."
  type        = string
  default     = null
  sensitive   = true
}

variable "domain" {
  description = "Primary Workspace domain."
  type        = string
}

variable "cui_ou_name" {
  description = "Name of the CUI org unit."
  type        = string
  default     = "CUI"
}

variable "non_cui_ou_name" {
  description = "Name of the non-CUI org unit."
  type        = string
  default     = "Non-CUI"
}

variable "group_members" {
  description = "Group name to member emails (the four AWS access-level groups)."
  type        = map(list(string))
  default     = {}
}

variable "users" {
  description = "Users to manage, keyed by primary email. Default none; existing users stay as they are."
  type = map(object({
    given_name  = string
    family_name = string
    ou          = string
    suspended   = optional(bool, false)
  }))
  default = {}
}

variable "privilege_overrides" {
  description = "Replace privilege names of user_admin, help_desk or audit_viewer. Set audit_viewer from the audit_privilege_candidates output."
  type        = map(list(string))
  default     = {}
}

variable "role_assignments" {
  description = "Admin role assignments; see the module variable for the shape."
  type = map(object({
    role          = string
    assignee_type = string
    assignee      = string
    scope_type    = optional(string, "CUSTOMER")
    ou            = optional(string)
  }))
  default = {}
}
