# ---- AWS Config in every account and in-scope region (3.3.1, 3.4.1, 3.14.6) ----

module "config_management" {
  source                     = "./config_account"
  providers                  = { aws = aws.management }
  name_prefix                = var.name_prefix
  regions                    = local.regions
  home_region                = var.home_region
  bucket_name                = aws_s3_bucket.archive.id
  kms_key_arn                = var.kms_key_arns.log_archive
  create_service_linked_role = var.create_config_service_linked_roles
  depends_on                 = [aws_s3_bucket_policy.archive]
}

module "config_log_archive" {
  source                     = "./config_account"
  providers                  = { aws = aws.log_archive }
  name_prefix                = var.name_prefix
  regions                    = local.regions
  home_region                = var.home_region
  bucket_name                = aws_s3_bucket.archive.id
  kms_key_arn                = var.kms_key_arns.log_archive
  create_service_linked_role = var.create_config_service_linked_roles
  depends_on                 = [aws_s3_bucket_policy.archive]
}

module "config_security" {
  source                     = "./config_account"
  providers                  = { aws = aws.security }
  name_prefix                = var.name_prefix
  regions                    = local.regions
  home_region                = var.home_region
  bucket_name                = aws_s3_bucket.archive.id
  kms_key_arn                = var.kms_key_arns.log_archive
  create_service_linked_role = var.create_config_service_linked_roles
  depends_on                 = [aws_s3_bucket_policy.archive]
}

module "config_workload" {
  source                     = "./config_account"
  providers                  = { aws = aws.workload }
  name_prefix                = var.name_prefix
  regions                    = local.regions
  home_region                = var.home_region
  bucket_name                = aws_s3_bucket.archive.id
  kms_key_arn                = var.kms_key_arns.log_archive
  create_service_linked_role = var.create_config_service_linked_roles
  depends_on                 = [aws_s3_bucket_policy.archive]
}

module "config_grc" {
  source                     = "./config_account"
  providers                  = { aws = aws.grc }
  name_prefix                = var.name_prefix
  regions                    = local.regions
  home_region                = var.home_region
  bucket_name                = aws_s3_bucket.archive.id
  kms_key_arn                = var.kms_key_arns.log_archive
  create_service_linked_role = var.create_config_service_linked_roles
  depends_on                 = [aws_s3_bucket_policy.archive]
}

# Org aggregator in security. Needs trusted access for config.amazonaws.com
# in the org stack.
data "aws_iam_policy_document" "aggregator_assume" {
  provider = aws.security

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_ids["security"]]
    }
  }
}

resource "aws_iam_role" "aggregator" {
  provider           = aws.security
  name               = "${var.name_prefix}-config-aggregator"
  assume_role_policy = data.aws_iam_policy_document.aggregator_assume.json
}

resource "aws_iam_role_policy_attachment" "aggregator" {
  provider   = aws.security
  role       = aws_iam_role.aggregator.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security
  region   = var.home_region
  name     = "${var.name_prefix}-org"

  organization_aggregation_source {
    all_regions = false
    regions     = var.allowed_regions
    role_arn    = aws_iam_role.aggregator.arn
  }

  depends_on = [aws_iam_role_policy_attachment.aggregator]
}

# AWS's published CMMC 2.0 Level 2 pack, deployed org-wide from management.
# Needs trusted access for config-multiaccountsetup.amazonaws.com.
# No delivery bucket: Config keeps the evaluation results itself, and a
# pack bucket would have to be named awsconfigconforms*.
resource "aws_config_organization_conformance_pack" "cmmc_l2" {
  provider      = aws.management
  region        = var.home_region
  name          = "${var.name_prefix}-cmmc-2-0-level-2"
  template_body = file("${path.module}/templates/cmmc-2.0-level-2.yaml")

  depends_on = [
    module.config_management,
    module.config_log_archive,
    module.config_security,
    module.config_workload,
    module.config_grc,
  ]
}
