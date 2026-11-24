# ---- Conformance pack template bucket in management (3.4.1, 3.14.6; issue #53) ----
# template_body is capped at 51,200 bytes. template_s3_uri is not, but the
# bucket name must start with "awsconfigconforms" and be readable by the
# AWSServiceRoleForConfigConforms role in every org account.
# The vendored file under templates/ stays the source of truth.

locals {
  conformance_bucket   = "awsconfigconforms-${var.name_prefix}-${local.mgmt_id}"
  conformance_key      = "cmmc-2.0-level-2.yaml"
  conformance_template = "${path.module}/templates/cmmc-2.0-level-2.yaml"
  conformance_roles    = "arn:${local.partition}:iam::*:role/aws-service-role/config-conforms.${data.aws_partition.current.dns_suffix}/AWSServiceRoleForConfigConforms"
}

data "aws_iam_policy_document" "conformance_key" {
  #checkov:skip=CKV_AWS_109:key policy root delegation required by KMS
  #checkov:skip=CKV_AWS_111:key policy root delegation required by KMS
  #checkov:skip=CKV_AWS_356:key policy Resource must be "*" (applies to the key itself)
  provider = aws.management

  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.mgmt_id}:root"]
    }
  }

  # S3 calls KMS as the reader, so the Config Conforms role needs Decrypt.
  statement {
    sid       = "ConfigConformsDecryptTemplate"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.conformance_roles]
    }
  }
}

resource "aws_kms_key" "conformance" {
  provider                = aws.management
  region                  = var.home_region
  description             = "Conformance pack template bucket"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.conformance_key.json
}

resource "aws_kms_alias" "conformance" {
  provider      = aws.management
  region        = var.home_region
  name          = "alias/${var.name_prefix}-conformance-templates"
  target_key_id = aws_kms_key.conformance.key_id
}

resource "aws_s3_bucket" "conformance" {
  provider      = aws.management
  region        = var.home_region
  bucket        = local.conformance_bucket
  force_destroy = false
  #checkov:skip=CKV_AWS_18:Holds one public vendored template; there is nothing to audit beyond CloudTrail management events.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for a template that is rebuilt from the repo.
  #checkov:skip=CKV2_AWS_62:Event notifications are not needed.
}

resource "aws_s3_bucket_versioning" "conformance" {
  provider = aws.management
  region   = var.home_region
  bucket   = aws_s3_bucket.conformance.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "conformance" {
  provider = aws.management
  region   = var.home_region
  bucket   = aws_s3_bucket.conformance.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.conformance.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "conformance" {
  provider                = aws.management
  region                  = var.home_region
  bucket                  = aws_s3_bucket.conformance.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "conformance" {
  provider = aws.management
  region   = var.home_region
  bucket   = aws_s3_bucket.conformance.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "conformance" {
  provider = aws.management
  region   = var.home_region
  bucket   = aws_s3_bucket.conformance.id

  rule {
    id     = "housekeeping"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.conformance]
}

data "aws_iam_policy_document" "conformance_bucket" {
  provider = aws.management

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.conformance.arn, "${aws_s3_bucket.conformance.arn}/*"]
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

  statement {
    sid       = "DenyTlsBelow12"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.conformance.arn, "${aws_s3_bucket.conformance.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  # AWS docs, "Prerequisites for Organization Conformance Packs with S3 templates":
  # the Conformance service-linked role in each member account reads the template.
  statement {
    sid       = "ConfigConformsRead"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
    resources = [aws_s3_bucket.conformance.arn, "${aws_s3_bucket.conformance.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.conformance_roles]
    }
  }
}

resource "aws_s3_bucket_policy" "conformance" {
  provider = aws.management
  region   = var.home_region
  bucket   = aws_s3_bucket.conformance.id
  policy   = data.aws_iam_policy_document.conformance_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.conformance]
}

resource "aws_s3_object" "conformance_template" {
  provider    = aws.management
  region      = var.home_region
  bucket      = aws_s3_bucket.conformance.id
  key         = local.conformance_key
  source      = local.conformance_template
  source_hash = filemd5(local.conformance_template)
  kms_key_id  = aws_kms_key.conformance.arn

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.conformance, aws_s3_bucket_policy.conformance]
}
