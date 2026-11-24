# Idle Workspace account suspension (issue #51, 3.5.6): Directory API -> suspend or report.
# Runs in log_archive next to the audit collector so the report write is same-account.
# Everything is created with provider aws.log_archive.

# ARNs come in as inputs, so no partition handling is needed (works in aws-us-gov).
locals {
  name       = "${var.name_prefix}-workspace-idle"
  prefix     = "workspace-idle"
  source_dir = coalesce(var.source_dir, "${path.module}/../../../collectors/workspace_idle/build")
  log_group  = "/aws/lambda/${local.name}"
  metric_ns  = "WorkspaceIdle" # EMF namespace emitted by the handler
  scopes = {
    report  = "https://www.googleapis.com/auth/admin.directory.user.readonly"
    suspend = "https://www.googleapis.com/auth/admin.directory.user"
  }
}

# ---- Package ----
# archive_file zips the build/ directory made by collectors/workspace_idle/build.sh.
# Read at plan time, so `terraform validate` works offline without it; build before plan/apply.
data "archive_file" "idle" {
  type        = "zip"
  source_dir  = local.source_dir
  output_path = "${path.module}/.build/${local.name}.zip"
}

# ---- Google service account key: created empty, value set by hand (runbook) ----
# Own secret, not the audit collector's: the audit key's delegated scope is read-only audit logs,
# and this one may hold a user-write scope in suspend mode. Separate service accounts keep the
# two delegations (and a leaked key's reach) apart, and each role reads only its own secret.
resource "aws_secretsmanager_secret" "service_account" {
  provider                = aws.log_archive
  name                    = "${local.name}/google-service-account-key"
  description             = "Google service account key JSON (domain-wide delegation, ${local.scopes[var.mode]}). Set by hand."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 30
  tags                    = var.tags
  #checkov:skip=CKV2_AWS_57:The key is a Google-issued JSON key rotated by hand (runbook); Secrets Manager cannot rotate it.
}

# ---- Logs (3.3.1) ----
resource "aws_cloudwatch_log_group" "idle" {
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

resource "aws_iam_role" "idle" {
  provider           = aws.log_archive
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "idle" {
  provider = aws.log_archive

  statement {
    sid       = "ArchiveWrite"
    actions   = ["s3:PutObject"]
    resources = ["${var.log_archive_bucket_arn}/${local.prefix}/*"]
  }

  statement {
    sid       = "LogsKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"] # Decrypt: the secret
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "ReadServiceAccountKey"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.service_account.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.idle.arn}:*"]
  }
}

resource "aws_iam_role_policy" "idle" {
  provider = aws.log_archive
  name     = "idle"
  role     = aws_iam_role.idle.id
  policy   = data.aws_iam_policy_document.idle.json
}

# ---- Function ----
resource "aws_lambda_function" "idle" {
  provider         = aws.log_archive
  function_name    = local.name
  role             = aws_iam_role.idle.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.idle.output_path
  source_code_hash = data.archive_file.idle.output_base64sha256
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds
  kms_key_arn      = var.kms_key_arn
  tags             = var.tags

  # One run at a time: two overlapping runs would double-suspend and double-report.
  reserved_concurrent_executions = 1

  environment {
    variables = {
      MODE           = var.mode
      IDLE_DAYS      = tostring(var.idle_days)
      EXCLUDE_EMAILS = join(",", var.exclude_emails)
      EXCLUDE_OUS    = join(",", var.exclude_org_units)
      ADMIN_USER     = var.admin_user_email
      SECRET_ARN     = aws_secretsmanager_secret.service_account.arn
      BUCKET         = var.log_archive_bucket_name
      KMS_KEY_ARN    = var.kms_key_arn
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.idle.name
  }

  depends_on = [aws_iam_role_policy.idle]

  #checkov:skip=CKV_AWS_117:Not in a VPC on purpose; it needs internet egress to Google and the enclave has no NAT in log_archive. It holds no CUI.
  #checkov:skip=CKV_AWS_116:No DLQ; the schedule is daily and idempotent (suspending is a no-op the second time) and failures alarm through Errors.
  #checkov:skip=CKV_AWS_272:Code signing is not set up for this repo; the zip is built from reviewed source in CI.
  #checkov:skip=CKV_AWS_50:X-Ray is not used; EMF metrics, logs and alarms cover this job.
}

# ---- Schedule ----
resource "aws_cloudwatch_event_rule" "schedule" {
  provider            = aws.log_archive
  name                = local.name
  description         = "Run the idle Workspace account check."
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  provider = aws.log_archive
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_lambda_function.idle.arn

  retry_policy {
    maximum_retry_attempts = 0 # the next daily run covers a miss
  }
}

resource "aws_lambda_permission" "schedule" {
  provider      = aws.log_archive
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.idle.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# ---- Alarms to the findings topic (3.3.4) ----
# Alarm actions publish cross-account to the topic in security; its policy and key policy
# already allow cloudwatch.amazonaws.com from log_archive (audit collector, #30).

resource "aws_cloudwatch_metric_alarm" "errors" {
  provider            = aws.log_archive
  alarm_name          = "${local.name}-errors"
  alarm_description   = "Idle Workspace account run failed (3.5.6)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.idle.function_name }
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

# The handler emits Success=1 only after the report is archived and every suspension worked.
# 26 hourly periods: a daily schedule always lands one run inside the window, with slack.
# Missing data breaches, so a dead schedule or a disabled function alarms too.
resource "aws_cloudwatch_metric_alarm" "no_success" {
  provider            = aws.log_archive
  alarm_name          = "${local.name}-no-success-26h"
  alarm_description   = "No successful idle Workspace account run in 26 hours (3.5.6)."
  namespace           = local.metric_ns
  metric_name         = "Success"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 26
  datapoints_to_alarm = 26
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
  tags                = var.tags
}
