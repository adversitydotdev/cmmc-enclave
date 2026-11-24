data "aws_ssoadmin_instances" "this" {
  provider = aws.management
}

locals {
  partition         = data.aws_partition.current.partition
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  policy_arn        = { for n in ["AdministratorAccess", "ReadOnlyAccess", "SecurityAudit"] : n => "arn:${local.partition}:iam::aws:policy/${n}" }

  groups = {
    enclave-admins   = "Administrators of the workload and grc accounts."
    enclave-auditors = "Read-only auditors across all accounts."
    fathom-operators = "Operators of the Fathom GRC platform in grc."
    logging-admins   = "Manage log resources in log_archive and security (3.3.9)."
  }

  # group -> permission set -> accounts
  assignments = {
    enclave-admins   = { Admin = ["workload", "grc"] }
    enclave-auditors = { Auditor = ["management", "log_archive", "security", "workload", "grc"] }
    fathom-operators = { FathomOperator = ["grc"] }
    logging-admins   = { LoggingAdmin = ["log_archive", "security"] }
  }

  assignment_list = flatten([
    for g, ps in local.assignments : [
      for p, accts in ps : [
        for a in accts : { group = g, ps = p, account = a }
      ]
    ]
  ])

  member_pairs = flatten([
    for g, users in var.group_members : [for u in users : { group = g, user = u }]
  ])
  member_users = toset([for m in local.member_pairs : m.user])
}

# Groups are Terraform-managed; SCIM syncs users only.
resource "aws_identitystore_group" "this" {
  provider          = aws.management
  for_each          = local.groups
  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value
}

data "aws_identitystore_user" "this" {
  provider          = aws.management
  for_each          = local.member_users
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = each.key
    }
  }
}

resource "aws_identitystore_group_membership" "this" {
  provider          = aws.management
  for_each          = { for m in local.member_pairs : "${m.group}/${m.user}" => m }
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = data.aws_identitystore_user.this[each.value.user].user_id
}

# ---- Permission sets (3.1.5 least privilege, 3.1.11 session termination) ----

resource "aws_ssoadmin_permission_set" "this" {
  provider         = aws.management
  for_each         = toset(["Admin", "Auditor", "FathomOperator", "LoggingAdmin"])
  name             = each.key
  instance_arn     = local.sso_instance_arn
  session_duration = var.session_duration
  description      = "${each.key} (${var.name_prefix})"
}

# Admin is scoped by assignment: workload and grc only, never management.
resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  provider           = aws.management
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["Admin"].arn
  managed_policy_arn = local.policy_arn["AdministratorAccess"]
}

resource "aws_ssoadmin_managed_policy_attachment" "auditor" {
  provider           = aws.management
  for_each           = toset(["ReadOnlyAccess", "SecurityAudit"])
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["Auditor"].arn
  managed_policy_arn = local.policy_arn[each.key]
}

resource "aws_ssoadmin_managed_policy_attachment" "fathom" {
  provider           = aws.management
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["FathomOperator"].arn
  managed_policy_arn = local.policy_arn["ReadOnlyAccess"]
}

data "aws_iam_policy_document" "fathom" {
  #checkov:skip=CKV_AWS_111:Operate actions on ECS in the dedicated grc account; ARNs unknown at this layer.
  #checkov:skip=CKV_AWS_356:Same.
  statement {
    sid = "OperateFathomService"
    actions = [
      "ecs:UpdateService",
      "ecs:StopTask",
      "ecs:RunTask",
      "ecs:ExecuteCommand",
      "ssm:StartSession",
    ]
    resources = ["*"] # ECS task and service ARNs are not known here; account is dedicated to Fathom.
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "fathom" {
  provider           = aws.management
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["FathomOperator"].arn
  inline_policy      = data.aws_iam_policy_document.fathom.json
}

data "aws_iam_policy_document" "logging_admin" {
  #checkov:skip=CKV_AWS_108:Read of logs is the role purpose; explicit deny blocks deletion and Object Lock changes.
  #checkov:skip=CKV_AWS_111:Log management write access; bounded by the explicit deny statement.
  #checkov:skip=CKV_AWS_356:Log resource names differ per account.
  statement {
    sid = "ManageLogResources"
    actions = [
      "logs:*",
      "cloudwatch:*",
      "cloudtrail:Describe*",
      "cloudtrail:Get*",
      "cloudtrail:List*",
      "cloudtrail:LookupEvents",
      "cloudtrail:StartLogging",
      "config:Describe*",
      "config:Get*",
      "config:List*",
      "s3:Get*",
      "s3:List*",
      "kms:Describe*",
      "kms:List*",
      "kms:Get*",
      "kms:Decrypt",
      "sns:Get*",
      "sns:List*",
    ]
    resources = ["*"] # Resource names vary per account; the deny below bounds the risk.
  }

  # 3.3.8 / 3.3.9: no deletion of audit records and no Object Lock changes.
  statement {
    sid    = "DenyObjectLockAndDeletion"
    effect = "Deny"
    actions = [
      "s3:BypassGovernanceRetention",
      "s3:PutObjectRetention",
      "s3:PutObjectLegalHold",
      "s3:PutBucketObjectLockConfiguration",
      "s3:PutBucketVersioning",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:DeleteBucket",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "logs:DeleteLogGroup",
      "logs:DeleteLogStream",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "cloudtrail:DeleteTrail",
      "cloudtrail:StopLogging",
      "cloudtrail:UpdateTrail",
    ]
    resources = ["*"]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "logging_admin" {
  provider           = aws.management
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["LoggingAdmin"].arn
  inline_policy      = data.aws_iam_policy_document.logging_admin.json
}

resource "aws_ssoadmin_account_assignment" "this" {
  provider           = aws.management
  for_each           = { for a in local.assignment_list : "${a.group}/${a.ps}/${a.account}" => a }
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps].arn
  principal_id       = aws_identitystore_group.this[each.value.group].group_id
  principal_type     = "GROUP"
  target_id          = var.account_ids[each.value.account]
  target_type        = "AWS_ACCOUNT"

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.admin,
    aws_ssoadmin_managed_policy_attachment.auditor,
    aws_ssoadmin_managed_policy_attachment.fathom,
    aws_ssoadmin_permission_set_inline_policy.fathom,
    aws_ssoadmin_permission_set_inline_policy.logging_admin,
  ]
}
