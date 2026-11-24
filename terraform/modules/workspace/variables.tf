variable "domain" {
  description = "Primary Workspace domain; group addresses are <group>@<domain>."
  type        = string
}

variable "cui_ou_name" {
  description = "Name of the CUI org unit under the root."
  type        = string
  default     = "CUI"
}

variable "non_cui_ou_name" {
  description = "Name of the non-CUI org unit under the root."
  type        = string
  default     = "Non-CUI"
}

variable "group_members" {
  description = "Group name to member emails. Keys must be the four AWS access-level groups. Membership is authoritative per group."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for g in keys(var.group_members) : contains(["enclave-admins", "enclave-auditors", "fathom-operators", "logging-admins"], g)])
    error_message = "group_members keys must be enclave-admins, enclave-auditors, fathom-operators, or logging-admins."
  }
}

variable "users" {
  description = <<-EOT
    Users to create, keyed by primary email. Default is none: most companies already
    have Workspace users, and managing them from Terraform risks resetting live
    accounts. Manage users here only for new accounts or to enforce suspension
    (3.5.6, 3.9.2) from code. ou is "cui" or "non_cui".
  EOT
  type = map(object({
    given_name  = string
    family_name = string
    ou          = string
    suspended   = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for u in values(var.users) : contains(["cui", "non_cui"], u.ou)])
    error_message = "users[*].ou must be cui or non_cui."
  }
}

variable "privilege_overrides" {
  description = <<-EOT
    Replace the privilege names of a built-in role (user_admin, help_desk,
    audit_viewer). Names are Admin SDK privilege names and must each exist exactly
    once in data.googleworkspace_privileges or plan fails. audit_viewer defaults to
    empty (role skipped) because the exact Audit and investigation View name must
    be read from your tenant: see the audit_privilege_candidates output.
  EOT
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.privilege_overrides) : contains(["user_admin", "help_desk", "audit_viewer"], k)])
    error_message = "privilege_overrides keys must be user_admin, help_desk, or audit_viewer."
  }
}

variable "role_assignments" {
  description = <<-EOT
    Admin role assignments, keyed by any label. role is user_admin, help_desk or
    audit_viewer. assignee_type is user or group; assignee is the email.
    scope_type is CUSTOMER or ORG_UNIT; with ORG_UNIT set ou to cui or non_cui
    (every privilege in the role must be OU-scopable or plan fails). Prefer groups (3.1.4).
  EOT
  type = map(object({
    role          = string
    assignee_type = string
    assignee      = string
    scope_type    = optional(string, "CUSTOMER")
    ou            = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.role_assignments) : contains(["user_admin", "help_desk", "audit_viewer"], a.role) && contains(["user", "group"], a.assignee_type) && contains(["CUSTOMER", "ORG_UNIT"], a.scope_type)])
    error_message = "role must be user_admin, help_desk or audit_viewer; assignee_type user or group; scope_type CUSTOMER or ORG_UNIT."
  }

  validation {
    condition     = alltrue([for a in values(var.role_assignments) : a.scope_type == "CUSTOMER" || contains(["cui", "non_cui"], coalesce(a.ou, "none"))])
    error_message = "ORG_UNIT scope requires ou = cui or non_cui."
  }
}
