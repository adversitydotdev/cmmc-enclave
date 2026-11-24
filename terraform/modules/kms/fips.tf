# FIPS endpoint reference for services this baseline uses.
# Source: https://aws.amazon.com/compliance/fips/ (checked 2026-11-23).
# Verified against botocore endpoints.json 1.44.10 (2026-11-23) for us-east-1 and us-gov-west-1.
# GovCloud endpoints are FIPS-validated by default even where the hostname has no "-fips" label.
locals {
  fips_services = {
    s3                   = { commercial = true, govcloud = true, note = "s3-fips" }
    cloudtrail           = { commercial = true, govcloud = true, note = "" }
    config               = { commercial = true, govcloud = true, note = "" }
    cloudwatch           = { commercial = true, govcloud = true, note = "monitoring-fips" }
    logs                 = { commercial = true, govcloud = true, note = "" }
    sns                  = { commercial = true, govcloud = true, note = "" }
    sqs                  = { commercial = true, govcloud = true, note = "" }
    ec2                  = { commercial = true, govcloud = true, note = "" }
    rds                  = { commercial = true, govcloud = true, note = "" }
    backup               = { commercial = false, govcloud = false, note = "no FIPS endpoint; providers pin the standard endpoint" }
    ecs                  = { commercial = true, govcloud = true, note = "Fargate uses the ECS endpoint" }
    ecr                  = { commercial = true, govcloud = true, note = "" }
    guardduty            = { commercial = true, govcloud = true, note = "" }
    inspector2           = { commercial = true, govcloud = true, note = "" }
    events               = { commercial = true, govcloud = true, note = "EventBridge" }
    macie2               = { commercial = true, govcloud = false, note = "no GovCloud FIPS endpoint listed" }
    kms                  = { commercial = true, govcloud = true, note = "" }
    elasticloadbalancing = { commercial = true, govcloud = true, note = "" }
    sts                  = { commercial = true, govcloud = true, note = "" }
    ssm                  = { commercial = true, govcloud = true, note = "" }
    secretsmanager       = { commercial = true, govcloud = true, note = "" }
    securityhub          = { commercial = true, govcloud = true, note = "" }
    organizations        = { commercial = true, govcloud = true, note = "global FIPS endpoint" }
    iam                  = { commercial = true, govcloud = true, note = "global FIPS endpoint" }
    access-analyzer      = { commercial = true, govcloud = true, note = "" }
    sso                  = { commercial = false, govcloud = true, note = "IAM Identity Center admin API; providers pin the standard endpoint in commercial" }
    identitystore        = { commercial = false, govcloud = true, note = "providers pin the standard endpoint in commercial" }
    athena               = { commercial = true, govcloud = true, note = "" }
    glue                 = { commercial = true, govcloud = true, note = "" }
  }

  # Services lacking a FIPS endpoint in the active tier.
  services_without_fips_endpoint = sort([
    for name, s in local.fips_services : name
    if !(var.tier == "itar" ? s.govcloud : s.commercial)
  ])

  # S3 bucket policy statements. Replace {{bucket_arn}} with the bucket ARN.
  s3_tls_deny_statements = [
    {
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["{{bucket_arn}}", "{{bucket_arn}}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    },
    {
      Sid       = "DenyTlsBelow12"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["{{bucket_arn}}", "{{bucket_arn}}/*"]
      Condition = { NumericLessThan = { "s3:TlsVersion" = "1.2" } }
    },
  ]
}

# EBS default encryption and the CMKs are configured in the provider's region
# only. Looping needs a key per region (or multi-region keys) per account, so
# refuse a wider allowlist rather than leave other regions unencrypted by default.
resource "terraform_data" "single_region_guard" {
  lifecycle {
    precondition {
      condition     = length(var.allowed_regions) == 1 || var.multi_region_data_protection
      error_message = "allowed_regions has more than one region but KMS keys and EBS default encryption are home-region only. Narrow allowed_regions to the home region (3.13.16)."
    }
  }
}
