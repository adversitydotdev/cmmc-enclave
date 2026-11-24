locals {
  partition    = data.aws_partition.current.partition
  dns_suffix   = data.aws_partition.current.dns_suffix
  acct         = var.account_ids
  all_accounts = values(var.account_ids)

  root_arn = { for k, id in var.account_ids : k => "arn:${local.partition}:iam::${id}:root" }

  # Regional service principals, e.g. logs.us-east-1.amazonaws.com.
  logs_principals   = [for r in var.allowed_regions : "logs.${r}.${local.dns_suffix}"]
  backup_via_values = [for r in var.allowed_regions : "backup.${r}.${local.dns_suffix}"]

  log_group_arns = [for id in local.all_accounts : "arn:${local.partition}:logs:*:${id}:log-group:*"]
}

# Each policy: root delegation (AWS requires it, otherwise the key is unmanageable and IAM
# policies can't grant access), service grants with confused-deputy conditions, and an
# org-perimeter deny for non-service principals (3.1.3, 3.13.16).

# ---- logs (log_archive) ----
data "aws_iam_policy_document" "logs" {
  statement {
    sid     = "EnableIAMPolicies"
    actions = ["kms:*"] #checkov:skip=CKV_AWS_111:root delegation statement required by KMS
    #checkov:skip=CKV_AWS_109:key policy root delegation required by KMS
    #checkov:skip=CKV_AWS_356:key policy Resource must be "*" (applies to the key itself)
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.root_arn["log_archive"]]
    }
  }

  # Organization trail in management account (3.3.1).
  statement {
    sid       = "CloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct["management"]]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:*:${local.acct["management"]}:trail/*"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:${local.partition}:cloudtrail:*:${local.acct["management"]}:trail/*"]
    }
  }

  statement {
    sid       = "ConfigDelivery"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["config.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.all_accounts
    }
  }

  statement {
    sid       = "S3ArchiveBucket"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["s3.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct["log_archive"]]
    }
  }

  statement {
    sid       = "CloudWatchLogsGroups"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = local.logs_principals
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.all_accounts
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = local.log_group_arns
    }
  }

  statement {
    sid       = "SNSTopics"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sns.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [var.organization_id]
    }
  }

  statement {
    sid       = "AlarmsAndRulesToSNS"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.${local.dns_suffix}", "events.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct["log_archive"]]
    }
  }

  # Security account reads archived logs (3.3.5). Its IAM policies must also allow.
  statement {
    sid       = "SecurityAccountRead"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.root_arn["security"]]
    }
  }

  statement {
    sid       = "DenyOutsideOrg"
    effect    = "Deny"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
}

# ---- security ----
data "aws_iam_policy_document" "security" {
  statement {
    sid     = "EnableIAMPolicies"
    actions = ["kms:*"] #checkov:skip=CKV_AWS_111:root delegation statement required by KMS
    #checkov:skip=CKV_AWS_109:key policy root delegation required by KMS
    #checkov:skip=CKV_AWS_356:key policy Resource must be "*" (applies to the key itself)
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.root_arn["security"]]
    }
  }

  statement {
    sid       = "FindingsSNS"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["sns.${local.dns_suffix}", "cloudwatch.${local.dns_suffix}", "events.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct["security"]]
    }
  }

  statement {
    sid       = "DenyOutsideOrg"
    effect    = "Deny"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
}

# ---- workload_data, grc, backup keys: root delegation plus perimeter deny ----
# S3, EBS, RDS, SSM and Backup use the caller's IAM permissions, so no service
# principal statements are needed. Grants made on behalf of callers are covered by the root delegation.
data "aws_iam_policy_document" "perimeter_only" {
  for_each = {
    workload_data      = "workload"
    grc                = "grc"
    backup_workload    = "workload"
    backup_log_archive = "log_archive"
  }

  statement {
    sid     = "EnableIAMPolicies"
    actions = ["kms:*"] #checkov:skip=CKV_AWS_111:root delegation statement required by KMS
    #checkov:skip=CKV_AWS_109:key policy root delegation required by KMS
    #checkov:skip=CKV_AWS_356:key policy Resource must be "*" (applies to the key itself)
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.root_arn[each.value]]
    }
  }

  # Workload account copies backups into the log_archive vault (3.8.9).
  dynamic "statement" {
    for_each = each.key == "backup_log_archive" ? [1] : []
    content {
      sid       = "WorkloadBackupCopy"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = [local.root_arn["workload"]]
      }
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = local.backup_via_values
      }
    }
  }

  statement {
    sid       = "DenyOutsideOrg"
    effect    = "Deny"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }
}

resource "aws_kms_key" "logs" {
  provider                = aws.log_archive
  description             = "${var.name_prefix} logs: CloudTrail, Config, S3 archive, CloudWatch Logs, SNS"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.logs.json
  tags                    = merge(var.tags, { DataClass = "logs", "enclave:protected" = "logging" })
}

resource "aws_kms_alias" "logs" {
  provider      = aws.log_archive
  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

resource "aws_kms_key" "security" {
  provider                = aws.security
  description             = "${var.name_prefix} security: findings SNS"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.security.json
  tags                    = merge(var.tags, { DataClass = "security", "enclave:protected" = "logging" })
}

resource "aws_kms_alias" "security" {
  provider      = aws.security
  name          = "alias/${var.name_prefix}-security"
  target_key_id = aws_kms_key.security.key_id
}

resource "aws_kms_key" "workload_data" {
  provider                = aws.workload
  description             = "${var.name_prefix} workload data: CUI at rest (S3, EBS, RDS, Backup)"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.perimeter_only["workload_data"].json
  tags                    = merge(var.tags, { DataClass = "cui" })
}

resource "aws_kms_alias" "workload_data" {
  provider      = aws.workload
  name          = "alias/${var.name_prefix}-workload-data"
  target_key_id = aws_kms_key.workload_data.key_id
}

resource "aws_kms_key" "grc" {
  provider                = aws.grc
  description             = "${var.name_prefix} grc: Fathom S3, RDS, SSM"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.perimeter_only["grc"].json
  tags                    = merge(var.tags, { DataClass = "grc" })
}

resource "aws_kms_alias" "grc" {
  provider      = aws.grc
  name          = "alias/${var.name_prefix}-grc"
  target_key_id = aws_kms_key.grc.key_id
}

resource "aws_kms_key" "backup_workload" {
  provider                = aws.workload
  description             = "${var.name_prefix} backup vault key (workload)"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.perimeter_only["backup_workload"].json
  tags                    = merge(var.tags, { DataClass = "backup" })
}

resource "aws_kms_alias" "backup_workload" {
  provider      = aws.workload
  name          = "alias/${var.name_prefix}-backup"
  target_key_id = aws_kms_key.backup_workload.key_id
}

resource "aws_kms_key" "backup_log_archive" {
  provider                = aws.log_archive
  description             = "${var.name_prefix} backup vault key (log_archive)"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.perimeter_only["backup_log_archive"].json
  tags                    = merge(var.tags, { DataClass = "backup" })
}

resource "aws_kms_alias" "backup_log_archive" {
  provider      = aws.log_archive
  name          = "alias/${var.name_prefix}-backup"
  target_key_id = aws_kms_key.backup_log_archive.key_id
}

# EBS encryption by default, home region of each provider (3.13.16, Config ec2-ebs-encryption-by-default).
resource "aws_ebs_encryption_by_default" "workload" {
  count    = var.enable_ebs_default_encryption ? 1 : 0
  provider = aws.workload
  enabled  = true
}

resource "aws_ebs_default_kms_key" "workload" {
  count      = var.enable_ebs_default_encryption ? 1 : 0
  provider   = aws.workload
  key_arn    = aws_kms_key.workload_data.arn
  depends_on = [aws_ebs_encryption_by_default.workload]
}

resource "aws_ebs_encryption_by_default" "grc" {
  count    = var.enable_ebs_default_encryption ? 1 : 0
  provider = aws.grc
  enabled  = true
}

resource "aws_ebs_default_kms_key" "grc" {
  count      = var.enable_ebs_default_encryption ? 1 : 0
  provider   = aws.grc
  key_arn    = aws_kms_key.grc.arn
  depends_on = [aws_ebs_encryption_by_default.grc]
}
