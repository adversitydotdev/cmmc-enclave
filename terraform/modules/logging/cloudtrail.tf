# ---- Org trail (3.3.1, 3.3.2, 3.3.8) ----

resource "aws_cloudwatch_log_group" "trail" {
  provider          = aws.management
  region            = var.home_region
  name              = "/aws/cloudtrail/${local.trail_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.kms_key_arns.management
}

data "aws_iam_policy_document" "trail_assume" {
  provider = aws.management

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.mgmt_id]
    }
  }
}

data "aws_iam_policy_document" "trail_logs" {
  provider = aws.management

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:log-stream:*"]
  }
}

resource "aws_iam_role" "trail_logs" {
  provider           = aws.management
  name               = "${var.name_prefix}-cloudtrail-to-logs"
  assume_role_policy = data.aws_iam_policy_document.trail_assume.json
}

resource "aws_iam_role_policy" "trail_logs" {
  provider = aws.management
  name     = "deliver-to-log-group"
  role     = aws_iam_role.trail_logs.id
  policy   = data.aws_iam_policy_document.trail_logs.json
}

resource "aws_cloudtrail" "org" {
  provider = aws.management
  region   = var.home_region
  name     = local.trail_name
  #checkov:skip=CKV_AWS_252:Notifications come from CloudWatch alarms and EventBridge to the security topic, not trail SNS (SNS must be in the management account).
  s3_bucket_name                = aws_s3_bucket.archive.id
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arns.log_archive
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_logs.arn

  # Management events, all read/write.
  advanced_event_selector {
    name = "Management events"
    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  # S3 data events on the archive and enclave buckets (3.3.1, 3.3.9).
  advanced_event_selector {
    name = "S3 data events on archive and enclave buckets"
    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
    field_selector {
      field       = "resources.ARN"
      starts_with = [for arn in concat([local.archive_arn], var.enclave_bucket_arns) : "${arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.archive, aws_iam_role_policy.trail_logs]
}

# ---- Metric filters and alarms on the trail (3.3.4, 3.1.7, 3.3.8, 3.14.6) ----

locals {
  trail_filters = {
    root-use = {
      pattern     = "{ $.userIdentity.type = \"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != \"AwsServiceEvent\" }"
      description = "Root account use."
    }
    break-glass-use = {
      pattern     = "{ $.userIdentity.type = \"IAMUser\" && $.userIdentity.userName = \"${var.break_glass_user_name}\" }"
      description = "Break-glass IAM user activity."
    }
    cloudtrail-changes = {
      pattern     = "{ ($.eventSource = cloudtrail.amazonaws.com) && (($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ($.eventName = StartLogging) || ($.eventName = StopLogging) || ($.eventName = PutEventSelectors) || ($.eventName = PutInsightSelectors)) }"
      description = "CloudTrail configuration changes."
    }
    config-changes = {
      pattern     = "{ ($.eventSource = config.amazonaws.com) && (($.eventName = StopConfigurationRecorder) || ($.eventName = DeleteConfigurationRecorder) || ($.eventName = PutConfigurationRecorder) || ($.eventName = DeleteDeliveryChannel) || ($.eventName = PutDeliveryChannel) || ($.eventName = DeleteConfigurationAggregator) || ($.eventName = DeleteOrganizationConformancePack) || ($.eventName = DeleteOrganizationConfigRule)) }"
      description = "AWS Config configuration changes."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "trail" {
  for_each       = local.trail_filters
  provider       = aws.management
  region         = var.home_region
  name           = "${var.name_prefix}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = each.value.pattern

  metric_transformation {
    name          = each.key
    namespace     = "${var.name_prefix}/CloudTrail"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "trail" {
  for_each            = local.trail_filters
  provider            = aws.management
  region              = var.home_region
  alarm_name          = "${var.name_prefix}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "${var.name_prefix}/CloudTrail"
  metric_name         = each.key
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.findings[var.home_region].arn]

  depends_on = [aws_cloudwatch_log_metric_filter.trail]
}

# CloudTrail has no delivery failure metric. If no events reach the log group
# in an hour the trail or its delivery is broken (3.3.4).
resource "aws_cloudwatch_metric_alarm" "trail_delivery" {
  provider            = aws.management
  region              = var.home_region
  alarm_name          = "${var.name_prefix}-cloudtrail-delivery-stalled"
  alarm_description   = "No CloudTrail events reached CloudWatch Logs in the last hour: audit logging process failure."
  namespace           = "AWS/Logs"
  metric_name         = "IncomingLogEvents"
  dimensions          = { LogGroupName = aws_cloudwatch_log_group.trail.name }
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.findings[var.home_region].arn]
}
