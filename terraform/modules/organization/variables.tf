variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

variable "tier" {
  description = "Impact tier: standard (commercial AWS) or itar (AWS GovCloud)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "itar"], var.tier)
    error_message = "tier must be standard or itar."
  }
}

variable "allowed_regions" {
  description = "Regions the enclave may use. Standard: us-east-1, us-east-2, us-west-2. ITAR: us-gov-west-1, us-gov-east-1."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "create_organization" {
  description = "true creates the AWS Organization. false reads an existing one (the caller must already have enabled all features, the policy types and trusted access; checks warn if not). To manage trusted access from Terraform on an existing org, import it into aws_organizations_organization.this and set this to true."
  type        = bool
  default     = true
}

variable "account_emails" {
  description = "Root email for each member account. Keys: log_archive, security, workload, grc. Must be unique and unused by any other AWS account."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["log_archive", "security", "workload", "grc"] : contains(keys(var.account_emails), k)])
    error_message = "account_emails needs keys log_archive, security, workload and grc."
  }
}

variable "existing_account_ids" {
  description = "Member accounts that already exist (keys log_archive, security, workload, grc). Listed accounts are not created or moved; place them in the right OU by hand or import them."
  type        = map(string)
  default     = {}
}

variable "account_role_name" {
  description = "Role AWS creates in each new member account for the management account to assume."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "service_access_principals" {
  description = "Services granted trusted access in the organization. Trim for GovCloud if a service is unavailable."
  type        = list(string)
  default = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "malware-protection.guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com",
    "inspector2.amazonaws.com",
    "backup.amazonaws.com",
    "account.amazonaws.com",
    "iam.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
  ]
}

variable "enabled_policy_types" {
  description = "Organization policy types to enable."
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY"]
}

variable "enable_root_access_management" {
  description = "Enable centralized root access (RootCredentialsManagement and RootSessions) so member-account root credentials can be removed (3.1.5, 3.1.6)."
  type        = bool
  default     = true
}

variable "delegated_admin_services" {
  description = "Service principals delegated to the security account."
  type        = list(string)
  default = [
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "inspector2.amazonaws.com",
    "access-analyzer.amazonaws.com",
  ]
}

variable "log_archive_delegated_admin_services" {
  description = "Service principals delegated to the log archive account. Empty by default: nothing in the baseline needs it."
  type        = list(string)
  default     = []
}

variable "exempt_principal_arn_patterns" {
  description = "ARN patterns (ArnLike, wildcards allowed) of pipeline/admin roles exempt from the protective SCPs. Empty means no exemption."
  type        = list(string)
  default     = []
}

variable "log_archive_bucket_name_patterns" {
  description = "Bucket name patterns (no ARN prefix) of the log archive buckets protected by SCP."
  type        = list(string)
  default     = ["enclave-log-archive*"]
}

variable "protected_kms_tag" {
  description = "Tag marking KMS keys used by logging. SCP denies disabling or deleting keys carrying it. The kms module must apply this tag."
  type = object({
    key    = string
    values = list(string)
  })
  default = {
    key    = "enclave:protected"
    values = ["logging"]
  }
}

variable "protected_kms_alias_patterns" {
  description = "KMS alias name patterns (without alias/) protected against delete and update."
  type        = list(string)
  default     = ["enclave-*"]
}

variable "enforce_required_tags" {
  description = "Deny creating EC2 instances, volumes, RDS instances, Lambda functions, DynamoDB tables, ECS clusters, secrets, SNS topics, SQS queues and EFS file systems without the required tag keys."
  type        = bool
  default     = true
}

variable "required_tag_keys" {
  description = "Tag keys required by the tag policy and the tag SCP."
  type        = list(string)
  default     = ["owner", "environment", "data-classification"]
}

variable "data_classification_values" {
  description = "Allowed values for the data-classification tag in the tag policy."
  type        = list(string)
  default     = ["cui", "fci", "public"]
}

variable "global_service_actions" {
  description = "Actions exempt from the region allowlist (global services with a single endpoint)."
  type        = list(string)
  default = [
    "account:*", "aws-portal:*", "billing:*", "budgets:*", "ce:*", "consolidatedbilling:*",
    "cur:*", "cloudfront:*", "directconnect:*", "freetier:*", "globalaccelerator:*",
    "health:*", "iam:*", "organizations:*", "payments:*", "pricing:*", "route53:*",
    "route53domains:*", "route53-recovery-cluster:*", "route53-recovery-control-config:*",
    "route53-recovery-readiness:*", "shield:*", "sts:*", "support:*", "tag:*",
    "trustedadvisor:*", "waf:*", "wafv2:*", "ec2:DescribeRegions", "s3:GetBucketLocation",
    "s3:ListAllMyBuckets", "sso:*", "sso-directory:*", "identitystore:*",
  ]
}
