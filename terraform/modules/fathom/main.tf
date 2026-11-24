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

# 46,364 bytes at the pinned SHA, under the 51,200 byte template_body limit, so no S3 upload.
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

resource "aws_cloudformation_stack" "fathom" {
  #checkov:skip=CKV_AWS_124:Topic is optional (notification_arns); stack changes are in the org CloudTrail, and the findings topic lives in another account
  name          = var.stack_name
  template_body = data.http.template.response_body
  capabilities  = ["CAPABILITY_IAM"] # template roles are unnamed

  parameters = {
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
  }

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
