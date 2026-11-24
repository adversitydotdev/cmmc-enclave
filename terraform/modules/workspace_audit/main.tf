# Workspace audit collector (issue #30): Reports API -> log archive bucket.
# Runs in log_archive so the bucket write is same-account (no cross-account bucket or key policy).
# Everything is created with provider aws.log_archive.

# ARNs come in as inputs, so no partition handling is needed (works in aws-us-gov).
locals {
  name        = "${var.name_prefix}-workspace-audit"
  prefix      = "workspace-audit"
  source_dir  = coalesce(var.source_dir, "${path.module}/../../../collectors/workspace_audit/build")
  log_group   = "/aws/lambda/${local.name}"
  metric_ns   = "WorkspaceAudit" # EMF namespace emitted by the handler
  alarm_hours = var.no_objects_alarm_hours
}

# ---- Package ----
# archive_file zips the build/ directory made by collectors/workspace_audit/build.sh
# (code plus arm64 wheels). It is read at plan time, so `terraform validate` works
# offline without the directory; run build.sh before plan/apply.
data "archive_file" "collector" {
  type        = "zip"
  source_dir  = local.source_dir
  output_path = "${path.module}/.build/${local.name}.zip"
}

# ---- Google service account key: created empty, value set by hand (runbook) ----
resource "aws_secretsmanager_secret" "service_account" {
  provider                = aws.log_archive
  name                    = "${local.name}/google-service-account-key"
  description             = "Google service account key JSON (domain-wide delegation, admin.reports.audit.readonly). Set by hand."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 30
  tags                    = var.tags
  #checkov:skip=CKV2_AWS_57:The key is a Google-issued JSON key rotated by hand (runbook); Secrets Manager cannot rotate it.
}

# ---- Cursor state (one item per application) ----
# DynamoDB over SSM: the item also carries the seen-event keys for the overlap window,
# which outgrow SSM's 8 KB parameter limit; DynamoDB allows 400 KB and consistent reads.
resource "aws_dynamodb_table" "state" {
  provider                    = aws.log_archive
  name                        = "${local.name}-state"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "application"
  deletion_protection_enabled = true
  tags                        = var.tags

  attribute {
    name = "application"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }
}

# ---- Logs (3.3.1) ----
resource "aws_cloudwatch_log_group" "collector" {
  provider          = aws.log_archive
  name              = local.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

# ---- IAM: least privilege (3.1.5) ----
data "aws_iam_policy_document" "assume" {
  provider = aws.log_archive

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "collector" {
  provider           = aws.log_archive
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "collector" {
  provider = aws.log_archive

  statement {
    sid       = "ArchiveWrite"
    actions   = ["s3:PutObject"]
    resources = ["${var.log_archive_bucket_arn}/${local.prefix}/*"]
  }

  statement {
    sid       = "LogsKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"] # Decrypt: secret and state table
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "ReadServiceAccountKey"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.service_account.arn]
  }

  statement {
    sid       = "Cursor"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.state.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.collector.arn}:*"]
  }
}

resource "aws_iam_role_policy" "collector" {
  provider = aws.log_archive
  name     = "collector"
  role     = aws_iam_role.collector.id
  policy   = data.aws_iam_policy_document.collector.json
}

# ---- Function ----
resource "aws_lambda_function" "collector" {
  provider         = aws.log_archive
  function_name    = local.name
  role             = aws_iam_role.collector.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.collector.output_path
  source_code_hash = data.archive_file.collector.output_base64sha256
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds
  kms_key_arn      = var.kms_key_arn
  tags             = var.tags

  # One run at a time: the cursor update is read-modify-write.
  reserved_concurrent_executions = 1

  environment {
    variables = {
      APPLICATIONS           = join(",", var.applications)
      ADMIN_USER             = var.admin_user_email
      SECRET_ARN             = aws_secretsmanager_secret.service_account.arn
      BUCKET                 = var.log_archive_bucket_name
      KMS_KEY_ARN            = var.kms_key_arn
      STATE_TABLE            = aws_dynamodb_table.state.name
      OVERLAP_HOURS          = tostring(var.overlap_hours)
      OVERLAP_HOURS_BY_APP   = jsonencode(var.overlap_hours_by_app)
      INITIAL_LOOKBACK_HOURS = tostring(var.initial_lookback_hours)
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.collector.name
  }

  depends_on = [aws_iam_role_policy.collector]

  #checkov:skip=CKV_AWS_117:Not in a VPC on purpose; it needs internet egress to Google and the enclave has no NAT in log_archive. It holds no CUI.
  #checkov:skip=CKV_AWS_116:No DLQ; scheduled runs are idempotent (next run re-reads the overlap) and failures page through the Errors alarm.
  #checkov:skip=CKV_AWS_272:Code signing is not set up for this repo; the zip is built from reviewed source in CI.
  #checkov:skip=CKV_AWS_50:X-Ray is not used; EMF metrics, logs and alarms cover this job.
}

# ---- Schedule ----
resource "aws_cloudwatch_event_rule" "schedule" {
  provider            = aws.log_archive
  name                = local.name
  description         = "Run the Workspace audit collector."
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  provider = aws.log_archive
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_lambda_function.collector.arn

  retry_policy {
    maximum_retry_attempts = 0 # the next scheduled run covers a miss
  }
}

resource "aws_lambda_permission" "schedule" {
  provider      = aws.log_archive
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# ---- Alarms to the findings topic (3.3.4) ----
# Alarm actions publish cross-account to the topic in security; its policy and key policy
# must allow cloudwatch.amazonaws.com from this account (see stack file note).

resource "aws_cloudwatch_metric_alarm" "errors" {
  provider            = aws.log_archive
  alarm_name          = "${local.name}-errors"
  alarm_description   = "Workspace audit collector invocation failed (3.3.4)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.collector.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  tags                = var.tags
}

# The handler emits Success=1 only after every readable application was archived.
# One 15 minute period: a 10 minute schedule always lands at least one run inside it.
# Missing data breaches, so a dead schedule or a disabled function alarms too.
resource "aws_cloudwatch_metric_alarm" "no_success" {
  provider            = aws.log_archive
  alarm_name          = "${local.name}-no-success-15m"
  alarm_description   = "No successful Workspace audit collection in 15 minutes (3.3.4)."
  namespace           = local.metric_ns
  metric_name         = "Success"
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  tags                = var.tags
}

# Objects the collector wrote (counted after each PutObject returns). Used instead of S3
# request metrics: those need a filter on the logging module's bucket, and this one needs
# no cross-module change. Runs that succeed but find no events (a stuck cursor, revoked
# delegation that still returns empty) alarm here; no_objects_alarm_hours tunes it for
# quiet tenants.
resource "aws_cloudwatch_metric_alarm" "no_objects" {
  provider            = aws.log_archive
  alarm_name          = "${local.name}-no-new-objects"
  alarm_description   = "No new objects under ${local.prefix}/ for ${local.alarm_hours} hours (3.3.4)."
  namespace           = local.metric_ns
  metric_name         = "ObjectsWritten"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = local.alarm_hours
  datapoints_to_alarm = local.alarm_hours
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  tags                = var.tags
}
