# Fathom is deployed with its own CloudFormation template (deploy/aws/template.yaml),
# pinned to one commit and checked against a recorded sha256. This module only adds
# what the template has no option for: the database password parameter, and VPC flow
# logs on the VPC the stack creates. Gaps in the template are tracked upstream, not
# worked around here.

data "aws_region" "current" {}

locals {
  template_url = "https://raw.githubusercontent.com/adversitydotdev/fathom/${var.fathom_ref}/deploy/aws/template.yaml"
  bool         = { true = "true", false = "false" }
}

# The template is over the 51,200-byte template_body limit (fathom#24), so it is staged in S3 below.
data "http" "template" {
  url = local.template_url

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Could not fetch the Fathom template at fathom_ref (HTTP ${self.status_code})."
    }
    postcondition {
      condition     = sha256(self.response_body) == var.template_sha256
      error_message = "Fathom template sha256 does not match template_sha256. Review the diff at fathom_ref, then update the variable."
    }
  }
}

# The template reads this with {{resolve:ssm-secure}} and has no way to create it.
# Ephemeral + write-only keeps the password out of Terraform state and plan output.
# RDS rejects slash, at-sign, quote and space, so the special set is restricted.
ephemeral "random_password" "database" {
  length           = 32
  special          = true
  override_special = "-_.~!#%^*+="
}

resource "aws_ssm_parameter" "database_password" {
  name             = "/fathom/${var.stack_name}/database/password"
  description      = "Fathom RDS master password. Read by CloudFormation and the ECS execution role."
  type             = "SecureString"
  key_id           = var.kms_key_arn # 3.13.16
  value_wo         = ephemeral.random_password.database.result
  value_wo_version = var.database_password_version
  tier             = "Standard"
}

# CloudFormation caps inline template bodies at 51,200 bytes and Fathom's template
# is larger, so it is staged in a private bucket in grc and deployed by URL.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "templates" {
  #checkov:skip=CKV_AWS_144:Holds only a copy of a public template; cross-region replication adds nothing
  #checkov:skip=CKV2_AWS_62:No consumers need event notifications for template uploads
  #checkov:skip=CKV_AWS_18:Access to a public template copy needs no access logging; writes are in the org CloudTrail
  bucket        = "${var.name_prefix}-fathom-cfn-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "templates" {
  bucket                  = aws_s3_bucket.templates.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "templates" {
  bucket = aws_s3_bucket.templates.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "templates" {
  bucket = aws_s3_bucket.templates.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "templates" {
  bucket = aws_s3_bucket.templates.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "templates" {
  bucket = aws_s3_bucket.templates.id
  rule {
    id     = "expire-old-template-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "templates" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.templates.arn, "${aws_s3_bucket.templates.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "templates" {
  bucket = aws_s3_bucket.templates.id
  policy = data.aws_iam_policy_document.templates.json
}

resource "aws_s3_object" "template" {
  bucket                 = aws_s3_bucket.templates.id
  key                    = "fathom/${var.fathom_ref}/template.yaml"
  content                = data.http.template.response_body
  content_type           = "application/x-yaml"
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  tags                   = var.tags

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.templates]
}

resource "aws_cloudformation_stack" "fathom" {
  #checkov:skip=CKV_AWS_124:Topic is optional (notification_arns); stack changes are in the org CloudTrail, and the findings topic lives in another account
  name         = var.stack_name
  template_url = "https://${aws_s3_bucket.templates.bucket_regional_domain_name}/${aws_s3_object.template.key}"
  capabilities = ["CAPABILITY_IAM"] # template roles are unnamed

  parameters = merge({
    EnableServices          = local.bool[var.enable_services]
    EnableNatGateway        = "true" # SCOPE section 5: tasks are private, egress through the one NAT
    EnableLoadBalancer      = "true" # the ALB is the only inbound path
    CertificateArn          = var.certificate_arn
    DeletionProtection      = "true"
    TaskSize                = var.task_size
    DatabaseInstanceClass   = var.database_instance_class
    DatabasePasswordVersion = tostring(var.database_password_version)
    DomainName              = var.domain_name
    HostedZoneId            = var.hosted_zone_id
    PublicUrl               = var.public_url
    ApiImageTag             = var.api_image_tag
    WebImageTag             = var.web_image_tag

    # Sign-in through Google Workspace (fathom#22); empty issuer leaves OIDC off.
    OidcProviderName          = var.oidc_provider_name
    OidcIssuer                = var.oidc_issuer
    OidcClientId              = var.oidc_client_id
    OidcClientSecretParameter = var.oidc_client_secret_parameter
    OidcRedirectUri           = var.oidc_redirect_uri
    BootstrapAdminEmails      = join(",", var.bootstrap_admin_emails)
    DisableApiTokenMinting    = local.bool[var.disable_api_token_minting]
    }, var.seed_bundle_uri == "" ? {} : {
    SeedBundleUri = var.seed_bundle_uri # first-boot restore of the enclave bundle (#32)
  })

  notification_arns = var.notification_arns
  tags              = var.tags

  depends_on = [aws_ssm_parameter.database_password]

  lifecycle {
    precondition {
      condition     = var.tier == "standard"
      error_message = "Fathom's template hardcodes arn:aws and has no FIPS or partition options, so it cannot deploy to GovCloud yet (see the gap issues in the report)."
    }
    precondition {
      condition     = contains(var.allowed_regions, data.aws_region.current.region)
      error_message = "Region is not in allowed_regions."
    }
    precondition {
      condition     = var.oidc_issuer == "" || (var.oidc_client_id != "" && var.oidc_client_secret_parameter != "" && length(var.bootstrap_admin_emails) > 0)
      error_message = "OIDC needs oidc_client_id, oidc_client_secret_parameter, and at least one bootstrap_admin_emails entry (otherwise nobody is an administrator, fathom#23)."
    }
    precondition {
      condition     = !var.enable_services || var.certificate_arn != ""
      error_message = "certificate_arn is required when enable_services is true."
    }
  }
}

# The template has no VpcId output, so find the VPC by the tag CloudFormation puts on it.
data "aws_vpc" "fathom" {
  tags = {
    "aws:cloudformation:stack-name" = aws_cloudformation_stack.fathom.name
  }
}

# 3.3.1, 3.14.6 flow logs, all traffic, to the log archive bucket.
resource "aws_flow_log" "fathom" {
  vpc_id               = data.aws_vpc.fathom.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${var.flow_log_bucket_arn}/${var.flow_log_prefix}"

  destination_options {
    file_format                = "parquet"
    per_hour_partition         = true
    hive_compatible_partitions = false
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-fathom" })
}
