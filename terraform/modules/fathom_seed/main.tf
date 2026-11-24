# Stages the rendered enclave bundle in grc and lets the Fathom task role read it, so Fathom
# restores it into an empty database at first boot (FATHOM_SEED_BUNDLE_URI, fathom
# operations/seed.py). The bundle holds no CUI: org objects and policy text.

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  key = "fathom/seed/bundle.tar.gz"
}

resource "aws_s3_bucket" "seed" {
  #checkov:skip=CKV_AWS_144:A rebuildable copy of repository files; cross-region replication adds nothing
  #checkov:skip=CKV2_AWS_62:No consumers need event notifications for seed uploads
  #checkov:skip=CKV_AWS_18:Reads and writes of this bucket are in the org CloudTrail; S3 access logs add no signal
  bucket        = "${var.name_prefix}-fathom-seed-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = var.tags

  lifecycle {
    precondition {
      condition     = contains(var.allowed_regions, data.aws_region.current.region)
      error_message = "Region is not in allowed_regions."
    }
    precondition {
      condition     = var.tier == "standard"
      error_message = "Fathom deploys to commercial accounts only for now (see the fathom module)."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "seed" {
  bucket                  = aws_s3_bucket.seed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "seed" {
  bucket = aws_s3_bucket.seed.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "seed" {
  bucket = aws_s3_bucket.seed.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "seed" {
  bucket = aws_s3_bucket.seed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn # 3.13.16
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "seed" {
  bucket = aws_s3_bucket.seed.id
  rule {
    id     = "expire-old-seed-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.seed.arn, "${aws_s3_bucket.seed.arn}/*"]
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
    sid       = "DenyOldTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.seed.arn, "${aws_s3_bucket.seed.arn}/*"]
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
}

resource "aws_s3_bucket_policy" "seed" {
  bucket = aws_s3_bucket.seed.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.seed]
}

resource "aws_s3_object" "bundle" {
  bucket                 = aws_s3_bucket.seed.id
  key                    = local.key
  source                 = var.bundle_path
  source_hash            = filesha256(var.bundle_path)
  content_type           = "application/gzip"
  server_side_encryption = "aws:kms"
  kms_key_id             = var.kms_key_arn
  tags                   = merge(var.tags, { "ogrl-library-ref" = var.ogrl_library_ref })

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.seed]
}

# The template's TaskRole is unnamed and has no output (fathom#13), so find it by name once
# the stack exists. The inline policy is the task role's only access to this bucket.
resource "terraform_data" "stack" {
  input = var.fathom_stack_id
}

data "aws_iam_roles" "task" {
  name_regex = var.task_role_name_regex

  depends_on = [terraform_data.stack]
}

data "aws_iam_policy_document" "task_read" {
  statement {
    sid       = "ReadSeedBundle"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.seed.arn}/${local.key}"]
  }

  # The bucket key makes the encryption context the bucket ARN; the object ARN covers a
  # bucket without one.
  statement {
    sid       = "DecryptSeedBundle"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [aws_s3_bucket.seed.arn, "${aws_s3_bucket.seed.arn}/*"]
    }
  }
}

resource "aws_iam_role_policy" "task_read" {
  name   = "fathom-seed-read"
  role   = one(data.aws_iam_roles.task.names)
  policy = data.aws_iam_policy_document.task_read.json

  lifecycle {
    precondition {
      condition     = length(data.aws_iam_roles.task.names) == 1
      error_message = "Expected exactly one role matching task_role_name_regex in grc, found ${length(data.aws_iam_roles.task.names)}."
    }
  }
}
