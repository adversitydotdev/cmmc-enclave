locals {
  partition = data.aws_partition.current.partition

  # Exemption for pipeline/admin roles. Empty list means no exemption.
  exempt_condition = length(var.exempt_principal_arn_patterns) > 0 ? {
    ArnNotLike = { "aws:PrincipalArn" = var.exempt_principal_arn_patterns }
  } : {}

  scp_limit = 5120

  # 3.13.x / 3.1.1: region allowlist. Global services are excluded via NotAction.
  scp_region = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyOutsideAllowedRegions"
      Effect    = "Deny"
      NotAction = var.global_service_actions
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
      }
    }]
  }

  # Every action here supports aws:RequestTag (Service Authorization Reference,
  # checked 2026-11-23). One statement per key keeps the SCP small.
  tag_resources = {
    "ec2:RunInstances"            = "arn:${local.partition}:ec2:*:*:instance/*"
    "ec2:CreateVolume"            = "arn:${local.partition}:ec2:*:*:volume/*"
    "rds:CreateDBInstance"        = "arn:${local.partition}:rds:*:*:db:*"
    "lambda:CreateFunction"       = "arn:${local.partition}:lambda:*:*:function:*"
    "dynamodb:CreateTable"        = "arn:${local.partition}:dynamodb:*:*:table/*"
    "ecs:CreateCluster"           = "arn:${local.partition}:ecs:*:*:cluster/*"
    "secretsmanager:CreateSecret" = "arn:${local.partition}:secretsmanager:*:*:secret:*"
    "sns:CreateTopic"             = "arn:${local.partition}:sns:*:*:*"
    "sqs:CreateQueue"             = "arn:${local.partition}:sqs:*:*:*"
  }

  # EFS CreateFileSystem supports aws:RequestTag but has no resource type, so
  # it only matches Resource "*".
  tag_actions_any_resource = ["elasticfilesystem:CreateFileSystem"]

  tag_statements = var.enforce_required_tags ? flatten([
    for key in var.required_tag_keys : [
      {
        Sid       = "RequireTag${replace(title(replace(key, "-", " ")), " ", "")}"
        Effect    = "Deny"
        Action    = keys(local.tag_resources)
        Resource  = tolist(values(local.tag_resources))
        Condition = { Null = { "aws:RequestTag/${key}" = "true" } }
      },
      {
        Sid       = "RequireTag${replace(title(replace(key, "-", " ")), " ", "")}Efs"
        Effect    = "Deny"
        Action    = tolist(local.tag_actions_any_resource)
        Resource  = ["*"]
        Condition = { Null = { "aws:RequestTag/${key}" = "true" } }
      },
    ]
  ]) : []

  # Baseline: leave org, root user, access keys, required tags.
  # SCPs never apply to the management account, so the access-key deny is
  # automatically "outside management".
  scp_baseline = {
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "DenyLeaveOrganization"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      },
      {
        Sid      = "DenyRootUser" # 3.1.5, 3.1.6
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = { "aws:PrincipalArn" = "arn:${local.partition}:iam::*:root" }
        }
      },
      {
        Sid      = "DenyIamUserAccessKeys" # 3.5.x: no long-term keys
        Effect   = "Deny"
        Action   = "iam:CreateAccessKey"
        Resource = "*"
      },
    ], local.tag_statements)
  }

  protected_service_actions = {
    cloudtrail = [
      "cloudtrail:DeleteTrail", "cloudtrail:StopLogging", "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors", "cloudtrail:PutInsightSelectors",
      "cloudtrail:DeleteEventDataStore", "cloudtrail:StopEventDataStoreIngestion",
      "cloudtrail:RemoveTags", "cloudtrail:AddTags",
    ]
    config = [
      "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder",
      "config:PutConfigurationRecorder", "config:DeleteDeliveryChannel",
      "config:PutDeliveryChannel", "config:DeleteConfigRule", "config:DeleteConformancePack",
      "config:DeleteOrganizationConfigRule", "config:DeleteOrganizationConformancePack",
      "config:DeleteConfigurationAggregator", "config:DeleteAggregationAuthorization",
      "config:DeleteRetentionConfiguration", "config:DeleteRemediationConfiguration",
    ]
    guardduty = [
      "guardduty:DeleteDetector", "guardduty:UpdateDetector",
      "guardduty:DisassociateFromMasterAccount", "guardduty:DisassociateFromAdministratorAccount",
      "guardduty:DisassociateMembers", "guardduty:DeleteMembers", "guardduty:StopMonitoringMembers",
      "guardduty:DeletePublishingDestination", "guardduty:UpdatePublishingDestination",
    ]
    securityhub = [
      "securityhub:DisableSecurityHub", "securityhub:DisassociateFromAdministratorAccount",
      "securityhub:DisassociateFromMasterAccount", "securityhub:DisassociateMembers",
      "securityhub:DeleteMembers", "securityhub:BatchDisableStandards",
      "securityhub:UpdateStandardsControl", "securityhub:DeleteActionTarget",
      "securityhub:DisableImportFindingsForProduct",
    ]
    other = [
      "inspector2:Disable", "inspector2:DisassociateMember",
      "access-analyzer:DeleteAnalyzer",
    ]
  }

  scp_protect_services = {
    Version = "2012-10-17"
    Statement = [merge({
      Sid      = "ProtectSecurityServices" # 3.3.1, 3.3.8, 3.14.6
      Effect   = "Deny"
      Action   = flatten(values(local.protected_service_actions))
      Resource = "*"
    }, length(local.exempt_condition) > 0 ? { Condition = local.exempt_condition } : {})]
  }

  log_bucket_arns = flatten([
    for p in var.log_archive_bucket_name_patterns : [
      "arn:${local.partition}:s3:::${p}",
      "arn:${local.partition}:s3:::${p}/*",
    ]
  ])

  kms_alias_arns = [for p in var.protected_kms_alias_patterns : "arn:${local.partition}:kms:*:*:alias/${p}"]

  scp_protect_logs = {
    Version = "2012-10-17"
    Statement = [
      merge({
        Sid    = "ProtectLogArchiveBucket" # 3.3.8: audit log integrity
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:PutBucketObjectLockConfiguration", "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration", "s3:PutEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock", "s3:PutBucketAcl", "s3:DeleteObjectVersion",
          "s3:BypassGovernanceRetention", "s3:PutObjectRetention", "s3:PutObjectLegalHold",
          "s3:PutReplicationConfiguration",
        ]
        Resource = local.log_bucket_arns
      }, length(local.exempt_condition) > 0 ? { Condition = local.exempt_condition } : {}),
      {
        Sid    = "ProtectLoggingKmsKeys" # 3.13.10, 3.3.8
        Effect = "Deny"
        Action = [
          "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
          "kms:DisableKeyRotation", "kms:DeleteImportedKeyMaterial",
        ]
        Resource = "*"
        Condition = merge({
          StringEquals = { "aws:ResourceTag/${var.protected_kms_tag.key}" = var.protected_kms_tag.values }
        }, local.exempt_condition)
      },
      merge({
        Sid      = "ProtectLoggingKmsAliases"
        Effect   = "Deny"
        Action   = ["kms:DeleteAlias", "kms:UpdateAlias"]
        Resource = local.kms_alias_arns
      }, length(local.exempt_condition) > 0 ? { Condition = local.exempt_condition } : {}),
    ]
  }

  scps = {
    region           = { name = "region-allowlist", description = "Deny actions outside allowed regions.", doc = local.scp_region }
    baseline         = { name = "org-baseline", description = "Deny leaving org, root user, IAM access keys, untagged resources.", doc = local.scp_baseline }
    protect_services = { name = "protect-security-services", description = "Protect CloudTrail, Config, GuardDuty, Security Hub.", doc = local.scp_protect_services }
    protect_logs     = { name = "protect-log-archive-and-kms", description = "Protect log archive buckets, Object Lock and logging KMS keys.", doc = local.scp_protect_logs }
  }

  scp_json = { for k, v in local.scps : k => jsonencode(v.doc) }
}

# Max 5 SCPs per target including FullAWSAccess, so four custom SCPs at root.
resource "aws_organizations_policy" "scp" {
  provider = aws.management
  for_each = local.scps

  name        = "${var.name_prefix}-${each.value.name}"
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  content     = local.scp_json[each.key]
  tags        = var.tags

  lifecycle {
    precondition {
      condition     = length(local.scp_json[each.key]) <= local.scp_limit
      error_message = "SCP ${each.key} exceeds the 5,120 character limit; split it."
    }
    precondition {
      condition = alltrue([
        for r in var.allowed_regions : var.tier == "itar" ? startswith(r, "us-gov-") : !startswith(r, "us-gov-")
      ])
      error_message = "allowed_regions does not match tier (itar needs us-gov-*, standard must not use them)."
    }
  }
}

resource "aws_organizations_policy_attachment" "scp" {
  provider = aws.management
  for_each = local.scps

  policy_id = aws_organizations_policy.scp[each.key].id
  target_id = local.organization_root_id
}
