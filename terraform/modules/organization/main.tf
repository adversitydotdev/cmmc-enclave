locals {
  account_keys = ["log_archive", "security", "workload", "grc"]

  account_ou = {
    log_archive = "security"
    security    = "security"
    workload    = "workloads"
    grc         = "grc"
  }

  # Org roles: log_archive and security share the Security OU.
  ou_names = {
    security  = "Security"
    workloads = "Workloads"
    grc       = "GRC"
  }

  org = var.create_organization ? aws_organizations_organization.this[0] : data.aws_organizations_organization.existing[0]

  organization_id      = local.org.id
  organization_root_id = local.org.roots[0].id
  management_account   = local.org.master_account_id

  accounts_to_create = toset([for k in local.account_keys : k if !contains(keys(var.existing_account_ids), k)])

  account_ids = merge(
    { management = local.management_account },
    { for k in local.account_keys : k => contains(keys(var.existing_account_ids), k) ? var.existing_account_ids[k] : aws_organizations_account.member[k].id }
  )

  delegated_admins = merge(
    { for s in var.delegated_admin_services : "security/${s}" => { account = "security", service = s } },
    { for s in var.log_archive_delegated_admin_services : "log_archive/${s}" => { account = "log_archive", service = s } },
  )
}

# Fresh org. 3.1.1: all features so SCPs and trusted access work.
resource "aws_organizations_organization" "this" {
  provider = aws.management
  count    = var.create_organization ? 1 : 0

  feature_set                   = "ALL"
  aws_service_access_principals = var.service_access_principals
  enabled_policy_types          = var.enabled_policy_types
}

data "aws_organizations_organization" "existing" {
  provider = aws.management
  count    = var.create_organization ? 0 : 1
}

check "existing_org_ready" {
  assert {
    condition = var.create_organization || (
      data.aws_organizations_organization.existing[0].feature_set == "ALL" &&
      alltrue([for t in var.enabled_policy_types : contains(data.aws_organizations_organization.existing[0].enabled_policy_types, t)]) &&
      alltrue([for p in var.service_access_principals : contains(data.aws_organizations_organization.existing[0].aws_service_access_principals, p)])
    )
    error_message = "Existing organization lacks all features, an enabled policy type, or trusted access for a service in service_access_principals. Enable them out of band or import the org."
  }
}

resource "aws_organizations_organizational_unit" "this" {
  provider = aws.management
  for_each = local.ou_names

  name      = each.value
  parent_id = local.organization_root_id
  tags      = var.tags
}

resource "aws_organizations_account" "member" {
  provider = aws.management
  for_each = local.accounts_to_create

  name                       = "${var.name_prefix}-${replace(each.value, "_", "-")}"
  email                      = var.account_emails[each.value]
  parent_id                  = aws_organizations_organizational_unit.this[local.account_ou[each.value]].id
  role_name                  = var.account_role_name
  iam_user_access_to_billing = "DENY"
  close_on_deletion          = false
  tags                       = var.tags

  lifecycle {
    prevent_destroy = true
    # AWS sets these at creation; changing them forces replacement.
    ignore_changes = [role_name, iam_user_access_to_billing]
  }
}

# Centralized root access: no root credentials in member accounts (3.1.5, 3.1.6).
resource "aws_iam_organizations_features" "root_access" {
  provider = aws.management
  count    = var.enable_root_access_management ? 1 : 0

  enabled_features = ["RootCredentialsManagement", "RootSessions"]

  depends_on = [aws_organizations_organization.this]
}

resource "aws_organizations_delegated_administrator" "this" {
  provider = aws.management
  for_each = local.delegated_admins

  account_id        = local.account_ids[each.value.account]
  service_principal = each.value.service

  depends_on = [aws_organizations_organization.this]
}

# Tag policy: required keys (CM-8 inventory, 3.4.1).
resource "aws_organizations_policy" "tags" {
  provider = aws.management

  name        = "${var.name_prefix}-required-tags"
  description = "Required tag keys and data classification values."
  type        = "TAG_POLICY"
  tags        = var.tags

  content = jsonencode({
    tags = {
      for k in var.required_tag_keys : k => merge(
        {
          tag_key      = { "@@assign" = k }
          enforced_for = { "@@assign" = ["ec2:instance", "ec2:volume", "rds:db"] }
        },
        k == "data-classification" ? { tag_value = { "@@assign" = var.data_classification_values } } : {}
      )
    }
  })
}

resource "aws_organizations_policy_attachment" "tags" {
  provider = aws.management

  policy_id = aws_organizations_policy.tags.id
  target_id = local.organization_root_id
}
