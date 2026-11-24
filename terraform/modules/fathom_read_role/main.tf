# Read-only role that Fathom assumes through its aws_role connection (RFC 0005 section 5).
# fathom-aws 0.3.0 asks for SecurityAudit plus iam:GenerateCredentialReport. Fathom's task
# role may only assume roles tagged ogrl-integration=true (deploy/aws/template.yaml TaskRole).

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
  role_name = var.role_name != "" ? var.role_name : "${var.name_prefix}-fathom-read"

  # Fathom runs in the commercial grc account (decision #7), so the trusted principal is a
  # commercial ARN, which only a commercial role can match.
  trusted_partition = "aws"
}

data "aws_iam_policy_document" "trust" {
  # The account root delegates to the condition: only the Fathom task role matches, so no
  # other principal in grc (including the ECS execution role) can assume this role. 3.1.1
  statement {
    sid     = "FathomTaskRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.trusted_partition}:iam::${var.grc_account_id}:root"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:${local.trusted_partition}:iam::${var.grc_account_id}:role/${var.task_role_name_pattern}"]
    }
    dynamic "condition" {
      for_each = length(var.external_ids) > 0 ? [1] : []
      content {
        test     = "StringEquals"
        variable = "sts:ExternalId"
        values   = var.external_ids
      }
    }
  }
}

resource "aws_iam_role" "fathom_read" {
  name                 = local.role_name
  description          = "Read-only access for Fathom (fathom-aws). Trusts only the Fathom ECS task role in grc."
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600 # Fathom requests 3600 s

  # The Fathom task role's sts:AssumeRole is conditioned on this tag.
  tags = merge(var.tags, { "ogrl-integration" = "true" })

  lifecycle {
    precondition {
      condition     = var.tier == "standard" && local.partition == local.trusted_partition
      error_message = "Fathom runs in a commercial account, so a ${local.partition} role cannot trust it. For ITAR use IAM Roles Anywhere (decision #7), which is not built."
    }
  }
}

resource "aws_iam_role_policy_attachment" "security_audit" {
  role       = aws_iam_role.fathom_read.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/SecurityAudit"
}

# Beyond SecurityAudit. All metadata, no data-plane reads.
data "aws_iam_policy_document" "extra" {
  #checkov:skip=CKV_AWS_356:iam:GenerateCredentialReport has no resource-level permissions and the Config describe/get calls are account-wide reads
  statement {
    sid       = "CredentialReport"
    actions   = ["iam:GenerateCredentialReport"] # fathom-aws iam-users resource
    resources = ["*"]                            # account-level action, no resource-level permissions
  }

  # fathom-aws 0.3.0 has no Config service in its manifest, so nothing reads these yet.
  # They let a Config query source work once one exists: compliance of the organization
  # conformance pack (logging module) in each account.
  statement {
    sid = "ConformancePackCompliance"
    actions = [
      "config:DescribeConformancePacks",
      "config:DescribeConformancePackStatus",
      "config:DescribeConformancePackCompliance",
      "config:GetConformancePackComplianceSummary",
      "config:GetConformancePackComplianceDetails",
    ]
    resources = ["*"] # these calls take no resource, or the pack name is not known to Terraform
  }
}

resource "aws_iam_role_policy" "extra" {
  name   = "fathom-extra-read"
  role   = aws_iam_role.fathom_read.id
  policy = data.aws_iam_policy_document.extra.json
}
