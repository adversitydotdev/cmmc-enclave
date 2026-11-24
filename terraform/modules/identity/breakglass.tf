# Break-glass: no login profile and no access keys here. Password and FIDO keys are set by hand.
resource "aws_iam_user" "break_glass" {
  #checkov:skip=CKV_AWS_273:Break-glass is deliberately an IAM user (SCOPE D2); MFA-gated and alarmed.
  provider      = aws.management
  name          = var.break_glass_user_name
  force_destroy = false
}

resource "aws_iam_group" "break_glass" {
  provider = aws.management
  name     = "${var.name_prefix}-break-glass"
}

resource "aws_iam_user_group_membership" "break_glass" {
  provider = aws.management
  user     = aws_iam_user.break_glass.name
  groups   = [aws_iam_group.break_glass.name]
}

# Full admin, usable only with MFA (see the deny below).
resource "aws_iam_group_policy_attachment" "break_glass_admin" {
  #checkov:skip=CKV_AWS_274:Break-glass needs AdministratorAccess; gated by MFA and alarmed on use.
  provider   = aws.management
  group      = aws_iam_group.break_glass.name
  policy_arn = local.policy_arn["AdministratorAccess"]
}

data "aws_iam_policy_document" "break_glass_mfa" {
  # 3.5.3: deny everything except MFA self-enrollment and password change when no MFA.
  statement {
    sid    = "DenyAllWithoutMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "iam:GetUser",
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
      "sts:GetSessionToken",
    ]
    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_group_policy" "break_glass_mfa" {
  provider = aws.management
  name     = "require-mfa"
  group    = aws_iam_group.break_glass.name
  policy   = data.aws_iam_policy_document.break_glass_mfa.json
}

# 3.5.7, 3.5.8, 3.5.9; Config rule iam-password-policy.
resource "aws_iam_account_password_policy" "this" {
  provider                       = aws.management
  minimum_password_length        = var.password_min_length
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  password_reuse_prevention      = var.password_reuse_prevention
  max_password_age               = var.password_max_age
  allow_users_to_change_password = true
  hard_expiry                    = false
}
