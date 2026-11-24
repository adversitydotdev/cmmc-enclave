
locals {
  partition   = data.aws_partition.current.partition
  mgmt_id     = var.account_ids["management"]
  regions     = toset(var.allowed_regions)
  other_regs  = toset([for r in var.allowed_regions : r if r != var.home_region])
  trail_name  = "${var.name_prefix}-org-trail"
  archive     = "${var.name_prefix}-log-archive-${var.account_ids["log_archive"]}"
  access_logs = "${var.name_prefix}-log-archive-access-${var.account_ids["log_archive"]}"
  results     = "${var.name_prefix}-athena-results-${var.account_ids["log_archive"]}"
  trail_arn   = "arn:${local.partition}:cloudtrail:${var.home_region}:${local.mgmt_id}:trail/${local.trail_name}"
  archive_arn = "arn:${local.partition}:s3:::${local.archive}"
  all_ids     = values(var.account_ids)
}

# ---- Log archive bucket (3.3.1, 3.3.8, 3.3.9) ----

resource "aws_s3_bucket" "archive" {
  provider            = aws.log_archive
  bucket              = local.archive
  object_lock_enabled = true
  force_destroy       = false
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required; Object Lock plus versioning protect the archive and region is fixed per tier.
  #checkov:skip=CKV2_AWS_62:Event notifications are not needed on the archive.
}

resource "aws_s3_bucket_versioning" "archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.archive.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.archive]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.archive.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arns.log_archive
    }
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  provider                = aws.log_archive
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.archive.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_logging" "archive" {
  provider      = aws.log_archive
  bucket        = aws_s3_bucket.archive.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "archive/"
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.archive.id

  rule {
    id     = "housekeeping"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.object_lock_retention_days + 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.archive]
}

data "aws_iam_policy_document" "archive" {
  provider = aws.log_archive

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.archive.arn,
      "${aws_s3_bucket.archive.arn}/*",
    ]
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
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.archive.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid     = "CloudTrailWrite"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.archive.arn}/AWSLogs/${local.mgmt_id}/*",
      "${aws_s3_bucket.archive.arn}/AWSLogs/${var.organization_id}/*",
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    sid       = "ConfigBucketCheck"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.archive.arn]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.all_ids
    }
  }

  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = [for id in local.all_ids : "${aws_s3_bucket.archive.arn}/AWSLogs/${id}/Config/*"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.all_ids
    }
  }
}

resource "aws_s3_bucket_policy" "archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.archive.id
  policy   = data.aws_iam_policy_document.archive.json

  depends_on = [aws_s3_bucket_public_access_block.archive]
}

# ---- Auxiliary buckets: access logs and Athena results ----

locals {
  aux_buckets = {
    access_logs = {
      name = local.access_logs
      sse  = "AES256" # S3 server access log delivery cannot write to SSE-KMS buckets
      days = null
    }
    athena_results = {
      name = local.results
      sse  = "aws:kms"
      days = 90
    }
  }
}

resource "aws_s3_bucket" "access_logs" {
  provider      = aws.log_archive
  bucket        = local.access_logs
  force_destroy = false
  #checkov:skip=CKV_AWS_18:This is the access log target; logging it to itself would loop.
  #checkov:skip=CKV_AWS_145:S3 server access log delivery does not support SSE-KMS target buckets.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for access logs.
  #checkov:skip=CKV2_AWS_62:Event notifications are not needed on the access log bucket.
}

resource "aws_s3_bucket" "athena_results" {
  provider      = aws.log_archive
  bucket        = local.results
  force_destroy = false
  #checkov:skip=CKV_AWS_144:Cross-region replication is not required for query results.
  #checkov:skip=CKV2_AWS_62:Event notifications are not needed on the results bucket.
}

locals {
  aux_ids = {
    access_logs    = aws_s3_bucket.access_logs.id
    athena_results = aws_s3_bucket.athena_results.id
  }
}

resource "aws_s3_bucket_versioning" "aux" {
  for_each = local.aux_ids
  provider = aws.log_archive
  bucket   = each.value

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aux" {
  for_each = local.aux_ids
  provider = aws.log_archive
  bucket   = each.value

  rule {
    bucket_key_enabled = local.aux_buckets[each.key].sse == "aws:kms"
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.aux_buckets[each.key].sse
      kms_master_key_id = local.aux_buckets[each.key].sse == "aws:kms" ? var.kms_key_arns.log_archive : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "aux" {
  for_each                = local.aux_ids
  provider                = aws.log_archive
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "aux" {
  for_each = local.aux_ids
  provider = aws.log_archive
  bucket   = each.value

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "aux" {
  for_each = local.aux_ids
  provider = aws.log_archive
  bucket   = each.value

  rule {
    id     = "housekeeping"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    dynamic "expiration" {
      for_each = local.aux_buckets[each.key].days == null ? [] : [local.aux_buckets[each.key].days]
      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.aux]
}

resource "aws_s3_bucket_logging" "athena_results" {
  provider      = aws.log_archive
  bucket        = aws_s3_bucket.athena_results.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "athena-results/"
}

data "aws_iam_policy_document" "access_logs" {
  provider = aws.log_archive

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
    ]
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
    sid       = "S3ServerAccessLogs"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_ids["log_archive"]]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.archive.arn, aws_s3_bucket.athena_results.arn]
    }
  }
}

data "aws_iam_policy_document" "athena_results" {
  provider = aws.log_archive

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.athena_results.arn,
      "${aws_s3_bucket.athena_results.arn}/*",
    ]
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

resource "aws_s3_bucket_policy" "access_logs" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.access_logs.id
  policy   = data.aws_iam_policy_document.access_logs.json

  depends_on = [aws_s3_bucket_public_access_block.aux]
}

resource "aws_s3_bucket_policy" "athena_results" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.athena_results.id
  policy   = data.aws_iam_policy_document.athena_results.json

  depends_on = [aws_s3_bucket_public_access_block.aux]
}
