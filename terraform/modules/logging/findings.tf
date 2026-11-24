# ---- Findings notifications: EventBridge -> KMS-encrypted SNS in security (3.6.1, 3.14.3) ----

resource "aws_sns_topic" "findings" {
  for_each          = local.regions
  provider          = aws.security
  region            = each.value
  name              = "${var.name_prefix}-security-findings"
  kms_master_key_id = var.kms_key_arns.security
}

data "aws_iam_policy_document" "findings_topic" {
  for_each = local.regions
  provider = aws.security

  statement {
    sid       = "EventBridgePublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.findings[each.value].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_ids["security"]]
    }
  }

  # Trail alarms live in management and notify cross-account.
  statement {
    sid       = "ManagementAlarmsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.findings[each.value].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.mgmt_id, var.account_ids["log_archive"]]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:Publish", "sns:Subscribe"]
    resources = [aws_sns_topic.findings[each.value].arn]
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

resource "aws_sns_topic_policy" "findings" {
  for_each = local.regions
  provider = aws.security
  region   = each.value
  arn      = aws_sns_topic.findings[each.value].arn
  policy   = data.aws_iam_policy_document.findings_topic[each.value].json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = {
    for p in setproduct(local.regions, var.notification_emails) : "${p[0]}/${p[1]}" => { region = p[0], email = p[1] }
  }
  provider  = aws.security
  region    = each.value.region
  topic_arn = aws_sns_topic.findings[each.value.region].arn
  protocol  = "email"
  endpoint  = each.value.email
}

locals {
  finding_rules = {
    guardduty = {
      description = "GuardDuty findings."
      pattern = {
        source        = ["aws.guardduty"]
        "detail-type" = ["GuardDuty Finding"]
      }
    }
    inspector = {
      description = "Inspector findings."
      pattern = {
        source        = ["aws.inspector2"]
        "detail-type" = ["Inspector2 Finding"]
      }
    }
    securityhub = {
      description = "Security Hub findings that are active, new and high or critical; GuardDuty and Inspector have their own rules."
      pattern = {
        source        = ["aws.securityhub"]
        "detail-type" = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            ProductName = [{ "anything-but" = ["GuardDuty", "Inspector"] }]
            RecordState = ["ACTIVE"]
            Workflow    = { Status = ["NEW"] }
            Severity    = { Label = ["HIGH", "CRITICAL"] }
          }
        }
      }
    }
  }

  finding_rule_regions = {
    for p in setproduct(keys(local.finding_rules), local.regions) : "${p[1]}/${p[0]}" => { rule = p[0], region = p[1] }
  }
}

resource "aws_cloudwatch_event_rule" "findings" {
  for_each      = local.finding_rule_regions
  provider      = aws.security
  region        = each.value.region
  name          = "${var.name_prefix}-${each.value.rule}-findings"
  description   = local.finding_rules[each.value.rule].description
  event_pattern = jsonencode(local.finding_rules[each.value.rule].pattern)
}

resource "aws_cloudwatch_event_target" "findings" {
  for_each  = local.finding_rule_regions
  provider  = aws.security
  region    = each.value.region
  rule      = aws_cloudwatch_event_rule.findings[each.key].name
  target_id = "sns"
  arn       = aws_sns_topic.findings[each.value.region].arn
}
