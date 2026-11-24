# ---- GuardDuty org-wide, security as delegated admin (3.14.6, 3.14.7) ----

resource "aws_guardduty_organization_admin_account" "this" {
  for_each         = local.regions
  provider         = aws.management
  region           = each.value
  admin_account_id = var.account_ids["security"]
}

resource "aws_guardduty_detector" "security" {
  for_each                     = local.regions
  provider                     = aws.security
  region                       = each.value
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  depends_on = [aws_guardduty_organization_admin_account.this]
}

resource "aws_guardduty_organization_configuration" "this" {
  for_each                         = local.regions
  provider                         = aws.security
  region                           = each.value
  detector_id                      = aws_guardduty_detector.security[each.value].id
  auto_enable_organization_members = "ALL"
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each = {
    for p in setproduct(local.regions, var.guardduty_features) : "${p[0]}/${p[1]}" => { region = p[0], feature = p[1] }
  }
  provider    = aws.security
  region      = each.value.region
  detector_id = aws_guardduty_detector.security[each.value.region].id
  name        = each.value.feature
  auto_enable = "ALL"

  depends_on = [aws_guardduty_organization_configuration.this]
}

# ---- Security Hub org-wide with central configuration (3.14.6, 3.11.2, 3.12.4) ----

resource "aws_securityhub_organization_admin_account" "this" {
  for_each         = local.regions
  provider         = aws.management
  region           = each.value
  admin_account_id = var.account_ids["security"]
}

resource "aws_securityhub_account" "security" {
  for_each                  = local.regions
  provider                  = aws.security
  region                    = each.value
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"

  depends_on = [aws_securityhub_organization_admin_account.this]
}

resource "aws_securityhub_finding_aggregator" "this" {
  provider          = aws.security
  region            = var.home_region
  linking_mode      = "SPECIFIED_REGIONS"
  specified_regions = tolist(local.other_regs)

  depends_on = [aws_securityhub_account.security]
}

# Central configuration needs the aggregator first. Accounts and standards
# come from the policy below, so per-account auto-enable stays off.
resource "aws_securityhub_organization_configuration" "this" {
  provider              = aws.security
  region                = var.home_region
  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.this]
}

resource "aws_securityhub_configuration_policy" "baseline" {
  provider = aws.security
  region   = var.home_region
  name     = "${var.name_prefix}-baseline"

  configuration_policy {
    service_enabled       = true
    enabled_standard_arns = [for s in var.securityhub_standard_ids : "arn:${local.partition}:securityhub:${var.home_region}::standards/${s}"]

    security_controls_configuration {
      disabled_control_identifiers = []
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

resource "aws_securityhub_configuration_policy_association" "root" {
  provider  = aws.security
  region    = var.home_region
  target_id = var.organization_root_id
  policy_id = aws_securityhub_configuration_policy.baseline.id
}

# ---- Inspector (ECR and Lambda) org-wide (3.11.2, 3.14.5) ----

resource "aws_inspector2_delegated_admin_account" "this" {
  for_each   = local.regions
  provider   = aws.management
  region     = each.value
  account_id = var.account_ids["security"]
}

resource "aws_inspector2_organization_configuration" "this" {
  for_each = local.regions
  provider = aws.security
  region   = each.value

  auto_enable {
    ec2         = false
    ecr         = true
    lambda      = true
    lambda_code = false
  }

  depends_on = [aws_inspector2_delegated_admin_account.this]
}

# Auto-enable only covers new accounts; enable existing ones explicitly.
resource "aws_inspector2_enabler" "this" {
  for_each       = local.regions
  provider       = aws.security
  region         = each.value
  account_ids    = local.all_ids
  resource_types = ["ECR", "LAMBDA"]

  depends_on = [aws_inspector2_organization_configuration.this]
}
