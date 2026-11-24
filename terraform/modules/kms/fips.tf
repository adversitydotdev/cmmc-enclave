# FIPS endpoint reference for services this baseline uses.
# Source: https://aws.amazon.com/compliance/fips/ (checked 2026-11-23).
# Entries with note "verify" were not on the page text read; confirm before relying on them.
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
    backup               = { commercial = true, govcloud = true, note = "" }
    ecs                  = { commercial = true, govcloud = true, note = "Fargate uses the ECS endpoint" }
    ecr                  = { commercial = true, govcloud = true, note = "" }
    guardduty            = { commercial = true, govcloud = true, note = "" }
    inspector2           = { commercial = true, govcloud = true, note = "" }
    events               = { commercial = true, govcloud = true, note = "EventBridge" }
    macie2               = { commercial = true, govcloud = false, note = "no GovCloud FIPS endpoint listed" }
    kms                  = { commercial = true, govcloud = true, note = "verify" }
    elasticloadbalancing = { commercial = true, govcloud = true, note = "verify" }
    sts                  = { commercial = true, govcloud = true, note = "verify" }
    ssm                  = { commercial = true, govcloud = true, note = "verify" }
    secretsmanager       = { commercial = true, govcloud = true, note = "verify" }
    securityhub          = { commercial = true, govcloud = true, note = "verify" }
    organizations        = { commercial = true, govcloud = true, note = "verify; global endpoint" }
    iam                  = { commercial = true, govcloud = true, note = "verify; global endpoint" }
    access-analyzer      = { commercial = true, govcloud = true, note = "verify" }
    sso                  = { commercial = false, govcloud = false, note = "IAM Identity Center; not confirmed, treated as no FIPS endpoint" }
    identitystore        = { commercial = false, govcloud = false, note = "not confirmed, treated as no FIPS endpoint" }
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
