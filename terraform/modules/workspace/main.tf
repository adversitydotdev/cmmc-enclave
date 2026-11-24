# Org units (3.1.1, 3.4.6): CUI and non-CUI under the root.
resource "googleworkspace_org_unit" "cui" {
  name                 = var.cui_ou_name
  description          = "Users who handle CUI; only FedRAMP-authorized services are enabled here."
  parent_org_unit_path = "/"
}

resource "googleworkspace_org_unit" "non_cui" {
  name                 = var.non_cui_ou_name
  description          = "Users who never handle CUI."
  parent_org_unit_path = "/"
}

locals {
  ou_id = {
    cui     = googleworkspace_org_unit.cui.org_unit_id
    non_cui = googleworkspace_org_unit.non_cui.org_unit_id
  }
  ou_path = {
    cui     = googleworkspace_org_unit.cui.org_unit_path
    non_cui = googleworkspace_org_unit.non_cui.org_unit_path
  }

  # Names match the Identity Center groups in modules/identity.
  groups = {
    enclave-admins   = "Administrators of the workload and grc accounts."
    enclave-auditors = "Read-only auditors across all accounts."
    fathom-operators = "Operators of the Fathom GRC platform in grc."
    logging-admins   = "Manage log resources in log_archive and security (3.3.9)."
  }
  group_email = { for k in keys(local.groups) : k => "${k}@${var.domain}" }
}

# Groups scope the AWS SAML app and SCIM auto-provisioning (3.1.1, 3.1.4).
resource "googleworkspace_group" "this" {
  for_each    = local.groups
  email       = local.group_email[each.key]
  name        = each.key
  description = each.value
}

resource "googleworkspace_group_members" "this" {
  for_each = var.group_members
  group_id = googleworkspace_group.this[each.key].id

  dynamic "members" {
    for_each = toset(each.value)
    content {
      email = members.value
      role  = "MEMBER"
    }
  }
}

# Users: none by default (see the variable description).
resource "random_password" "user" {
  for_each = var.users
  length   = 32
  special  = true
}

resource "googleworkspace_user" "this" {
  for_each      = var.users
  primary_email = each.key
  password      = random_password.user[each.key].result
  org_unit_path = local.ou_path[each.value.ou]
  suspended     = each.value.suspended

  # 3.5.9. Google ignores this when sign-in goes through the SAML IdP.
  change_password_at_next_login = true

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  lifecycle {
    ignore_changes = [password, change_password_at_next_login]
  }
}

# Admin roles (3.1.2, 3.1.4, 3.1.5, 3.1.7, 3.1.15, 3.3.8, 3.3.9, 3.4.5, 3.13.3).
data "googleworkspace_privileges" "all" {}

locals {
  # privilege_name is not unique across services (APP_ADMIN); group into lists.
  priv_index = { for p in data.googleworkspace_privileges.all.items : p.privilege_name => p... }

  # Names below come from Google's Directory API "Manage roles" guide.
  role_defs = {
    user_admin = {
      name        = "User administrator (least privilege)"
      description = "Create, update, move and suspend users and read OUs; no group, security or billing rights."
      privilege_names = [
        "USERS_RETRIEVE", "USERS_CREATE", "USERS_UPDATE", "USERS_MOVE",
        "USERS_SUSPEND", "USERS_ALIAS", "ORGANIZATION_UNITS_RETRIEVE",
      ]
    }
    help_desk = {
      name        = "Help desk (least privilege)"
      description = "Read users and OUs, reset passwords and force a password change; nothing else."
      privilege_names = [
        "USERS_RETRIEVE", "ORGANIZATION_UNITS_RETRIEVE",
        "USERS_RESET_PASSWORD", "USERS_FORCE_PASSWORD_CHANGE",
      ]
    }
    audit_viewer = {
      name            = "Audit and investigation viewer"
      description     = "View-only access to audit and investigation data (3.3.8, 3.3.9)."
      privilege_names = []
    }
  }

  roles = {
    for k, r in local.role_defs : k => merge(r, { privilege_names = lookup(var.privilege_overrides, k, r.privilege_names) })
  }
  active_roles = { for k, r in local.roles : k => r if length(r.privilege_names) > 0 }
}

resource "googleworkspace_role" "this" {
  for_each    = local.active_roles
  name        = each.value.name
  description = each.value.description

  dynamic "privileges" {
    for_each = toset(each.value.privilege_names)
    content {
      service_id     = local.priv_index[privileges.value][0].service_id
      privilege_name = privileges.value
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for n in each.value.privilege_names : length(lookup(local.priv_index, n, [])) == 1])
      error_message = "Every privilege name must exist exactly once in data.googleworkspace_privileges (role ${each.key})."
    }
  }
}

# Assignees not managed here are looked up by email.
data "googleworkspace_user" "ext" {
  for_each = toset([
    for a in var.role_assignments : a.assignee
    if a.assignee_type == "user" && !contains(keys(var.users), a.assignee)
  ])
  primary_email = each.value
}

data "googleworkspace_group" "ext" {
  for_each = toset([
    for a in var.role_assignments : a.assignee
    if a.assignee_type == "group" && !contains(values(local.group_email), a.assignee)
  ])
  email = each.value
}

locals {
  assignee_id = {
    for k, a in var.role_assignments : k => (
      a.assignee_type == "user"
      ? (contains(keys(var.users), a.assignee) ? googleworkspace_user.this[a.assignee].id : data.googleworkspace_user.ext[a.assignee].id)
      : (contains(values(local.group_email), a.assignee)
        ? googleworkspace_group.this[split("@", a.assignee)[0]].id
      : data.googleworkspace_group.ext[a.assignee].id)
    )
  }
}

# 3.1.4, 3.1.5, 3.4.5.
resource "googleworkspace_role_assignment" "this" {
  for_each    = var.role_assignments
  role_id     = googleworkspace_role.this[each.value.role].id
  assigned_to = local.assignee_id[each.key]
  scope_type  = each.value.scope_type
  org_unit_id = each.value.scope_type == "ORG_UNIT" ? local.ou_id[each.value.ou] : null

  lifecycle {
    precondition {
      condition = each.value.scope_type == "CUSTOMER" || alltrue([
        for n in local.active_roles[each.value.role].privilege_names : local.priv_index[n][0].is_org_unit_scopable
      ])
      error_message = "ORG_UNIT scope needs every privilege in the role to be OU-scopable (assignment ${each.key})."
    }
  }
}
