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
