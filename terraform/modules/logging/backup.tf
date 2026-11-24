# ---- AWS Backup in workload with a cross-account copy to log_archive (3.8.9) ----

# Cross-account backup must be switched on from the management account.
resource "aws_backup_global_settings" "this" {
  provider = aws.management

  global_settings = {
    isCrossAccountBackupEnabled = "true"
  }
}

# Destination vault in log_archive, locked the same way.
resource "aws_backup_vault" "log_archive" {
  provider    = aws.log_archive
  region      = var.home_region
  name        = "${var.name_prefix}-backup-copy"
  kms_key_arn = var.kms_key_arns.backup_log_archive
}

data "aws_iam_policy_document" "log_archive_vault" {
  provider = aws.log_archive

  statement {
    sid       = "OrgAccountsCopyIn"
    actions   = ["backup:CopyIntoBackupVault"]
    resources = ["*"] # a vault policy applies only to its own vault
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

resource "aws_backup_vault_policy" "log_archive" {
  provider          = aws.log_archive
  region            = var.home_region
  backup_vault_name = aws_backup_vault.log_archive.name
  policy            = data.aws_iam_policy_document.log_archive_vault.json
}

resource "aws_backup_vault_lock_configuration" "log_archive" {
  provider            = aws.log_archive
  region              = var.home_region
  backup_vault_name   = aws_backup_vault.log_archive.name
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  changeable_for_days = var.backup_vault_lock_changeable_for_days
}

# Workload vault: governance mode unless backup_vault_lock_changeable_for_days is set.
resource "aws_backup_vault" "workload" {
  provider    = aws.workload
  region      = var.home_region
  name        = "${var.name_prefix}-backup"
  kms_key_arn = var.kms_key_arns.workload
}

resource "aws_backup_vault_lock_configuration" "workload" {
  provider            = aws.workload
  region              = var.home_region
  backup_vault_name   = aws_backup_vault.workload.name
  min_retention_days  = var.backup_vault_lock_min_retention_days
  max_retention_days  = var.backup_vault_lock_max_retention_days
  changeable_for_days = var.backup_vault_lock_changeable_for_days
}

data "aws_iam_policy_document" "backup_assume" {
  provider = aws.workload

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_ids["workload"]]
    }
  }
}

resource "aws_iam_role" "backup" {
  provider           = aws.workload
  name               = "${var.name_prefix}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset(["AWSBackupServiceRolePolicyForBackup", "AWSBackupServiceRolePolicyForRestores"])
  provider = aws.workload
  role     = aws_iam_role.backup.name

  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/${each.value}"
}

resource "aws_backup_plan" "workload" {
  provider = aws.workload
  region   = var.home_region
  name     = "${var.name_prefix}-daily"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.workload.name
    schedule          = "cron(0 5 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.log_archive.arn

      lifecycle {
        delete_after = var.backup_retention_days
      }
    }
  }

  depends_on = [
    aws_backup_vault_lock_configuration.workload,
    aws_backup_vault_policy.log_archive,
    aws_backup_global_settings.this,
  ]
}

resource "aws_backup_selection" "workload" {
  provider     = aws.workload
  region       = var.home_region
  name         = "tagged"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.workload.id

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_selection_tag.key
    value = var.backup_selection_tag.value
  }
}

# Vaults, plan and the log_archive copy exist in the home region only, and
# their CMKs are regional. Refuse a wider allowlist so CUI cannot land in a
# region with no backup (3.8.9).
resource "terraform_data" "backup_single_region_guard" {
  lifecycle {
    precondition {
      condition     = length(var.allowed_regions) == 1 || var.multi_region_data_protection
      error_message = "allowed_regions has more than one region but AWS Backup vaults and plans cover the home region only. Narrow allowed_regions to the home region."
    }
  }
}
