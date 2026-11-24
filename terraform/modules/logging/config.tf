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
  findings_topic_arns        = local.findings_topic_arns
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
  findings_topic_arns        = local.findings_topic_arns
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
  findings_topic_arns        = local.findings_topic_arns
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
  findings_topic_arns        = local.findings_topic_arns
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
  findings_topic_arns        = local.findings_topic_arns
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
# The vendored template is read from S3 (conformance_bucket.tf) because
# template_body is capped at 51,200 bytes. No delivery bucket: Config keeps
# the evaluation results itself.
resource "aws_config_organization_conformance_pack" "cmmc_l2" {
  provider        = aws.management
  region          = var.home_region
  name            = "${var.name_prefix}-cmmc-2-0-level-2"
  template_s3_uri = "s3://${aws_s3_bucket.conformance.id}/${aws_s3_object.conformance_template.key}"

  depends_on = [
    module.config_management,
    module.config_log_archive,
    module.config_security,
    module.config_workload,
    module.config_grc,
    aws_s3_bucket_policy.conformance,
    aws_s3_object.conformance_template,
  ]
}

# Not in the CMMC pack: untagged resources show as non-compliant (3.4.1, ogrl-am-01).
# The tag SCP blocks creates for the services that support aws:RequestTag; this
# rule covers the rest, including resources created before the SCP.
resource "aws_config_organization_managed_rule" "required_tags" {
  provider        = aws.management
  region          = var.home_region
  name            = "${var.name_prefix}-required-tags"
  rule_identifier = "REQUIRED_TAGS"

  input_parameters = jsonencode({
    for i, k in var.required_tag_keys : "tag${i + 1}Key" => k
  })

  depends_on = [
    module.config_management,
    module.config_log_archive,
    module.config_security,
    module.config_workload,
    module.config_grc,
  ]
}
