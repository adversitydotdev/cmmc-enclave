# One account's AWS Config: recorder and delivery channel in every in-scope region.
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_service_linked_role" "config" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "config.amazonaws.com"
}

locals {
  role_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
}

resource "aws_config_configuration_recorder" "this" {
  for_each = var.regions
  region   = each.value
  name     = "${var.name_prefix}-recorder"
  role_arn = local.role_arn
  #checkov:skip=CKV2_AWS_48:All supported types are recorded; global types only in the home region to avoid duplicate IAM records.

  recording_group {
    all_supported                 = true
    include_global_resource_types = each.value == var.home_region
  }

  depends_on = [aws_iam_service_linked_role.config]
}

resource "aws_config_delivery_channel" "this" {
  for_each       = var.regions
  region         = each.value
  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = var.bucket_name
  s3_kms_key_arn = var.kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  for_each   = var.regions
  region     = each.value
  name       = aws_config_configuration_recorder.this[each.value].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# Alarm on Config delivery failures (3.3.4): history or snapshot delivery to the
# archive bucket failed. Message types end in DeliveryFailed (for example
# ConfigurationSnapshotDeliveryFailed). The target is the security account's SNS
# topic; its policy allows these rules by source ARN.
resource "aws_cloudwatch_event_rule" "config_delivery_failed" {
  for_each    = var.regions
  region      = each.value
  name        = "${var.name_prefix}-config-delivery-failed"
  description = "AWS Config failed to deliver configuration history or a snapshot."
  event_pattern = jsonencode({
    source        = ["aws.config"]
    "detail-type" = ["Config Configuration History Delivery Status", "Config Configuration Snapshot Delivery Status"]
    detail        = { messageType = [{ suffix = "DeliveryFailed" }] }
  })
}

resource "aws_cloudwatch_event_target" "config_delivery_failed" {
  for_each  = var.regions
  region    = each.value
  rule      = aws_cloudwatch_event_rule.config_delivery_failed[each.value].name
  target_id = "security-findings-sns"
  arn       = var.findings_topic_arns[each.value]
}
