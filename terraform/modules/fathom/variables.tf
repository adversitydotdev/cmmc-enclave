variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

variable "tier" {
  description = "Impact tier: standard (commercial AWS) or itar (AWS GovCloud). itar is refused until Fathom's template is partition-aware."
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

variable "fathom_ref" {
  description = "Full 40-character Fathom commit SHA the CloudFormation template is fetched at. Never a branch or tag."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.fathom_ref))
    error_message = "fathom_ref must be a full 40-character lowercase commit SHA."
  }
}

variable "template_sha256" {
  description = "Expected sha256 (hex) of deploy/aws/template.yaml at fathom_ref. Plan fails if the fetched body differs."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.template_sha256))
    error_message = "template_sha256 must be 64 lowercase hex characters."
  }
}

variable "stack_name" {
  description = "CloudFormation stack name. Fathom uses it as the SSM prefix (/fathom/<name>), the log group path and the ECS cluster name. Changing it replaces the stack."
  type        = string
  default     = "fathom"
}

variable "kms_key_arn" {
  description = "grc CMK (kms module output kms_key_arns[\"grc\"]). Encrypts the database password parameter."
  type        = string
}

variable "flow_log_bucket_arn" {
  description = "Log archive bucket ARN for VPC flow logs (log_archive_bucket_arn from the logging module)."
  type        = string
}

variable "flow_log_prefix" {
  description = "Key prefix inside the flow log bucket."
  type        = string
  default     = "vpc-flow-logs/grc"
}

variable "enable_services" {
  description = "EnableServices. Leave false for the first apply, push the API and web images to the ECR repositories in the outputs, then set true."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN in this region for domain_name (the ALB listener). Required when enable_services is true."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "DomainName: SES identity, and the ALB alias record when hosted_zone_id is set. Empty skips mail."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone for domain_name. Empty means DNS (SES DKIM, ALB alias) is done by hand."
  type        = string
  default     = ""
}

variable "public_url" {
  description = "PublicUrl: stable https origin users reach Fathom at, such as https://grc.example.com."
  type        = string
  default     = ""
}

variable "task_size" {
  description = "TaskSize: small, medium, large, xlarge or 2xlarge."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large", "xlarge", "2xlarge"], var.task_size)
    error_message = "task_size must be small, medium, large, xlarge or 2xlarge."
  }
}

variable "database_instance_class" {
  description = "DatabaseInstanceClass: db.t4g.micro, db.t4g.small, db.t4g.medium or db.t4g.large."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = contains(["db.t4g.micro", "db.t4g.small", "db.t4g.medium", "db.t4g.large"], var.database_instance_class)
    error_message = "database_instance_class must be a db.t4g size the template allows."
  }
}

variable "api_image_tag" {
  description = "ApiImageTag in the API ECR repository."
  type        = string
  default     = "latest"
}

variable "web_image_tag" {
  description = "WebImageTag in the web ECR repository."
  type        = string
  default     = "latest"
}

variable "notification_arns" {
  description = "SNS topic ARNs (same region, policy allowing cloudformation.amazonaws.com to publish) that get stack events. Empty disables notifications."
  type        = list(string)
  default     = []
}

variable "database_password_version" {
  description = "SSM version of the database password parameter, passed as DatabasePasswordVersion. Starts at 1. Each bump rewrites the parameter with a new random password (one SSM version per bump), so the two stay equal."
  type        = number
  default     = 1

  validation {
    condition     = var.database_password_version >= 1 && floor(var.database_password_version) == var.database_password_version
    error_message = "database_password_version must be a positive integer."
  }
}

variable "oidc_provider_name" {
  description = "Provider key in Fathom's OIDC config; part of the callback path /v1/auth/oidc/<name>/callback."
  type        = string
  default     = "google"
}

variable "oidc_issuer" {
  description = "OIDC issuer. Google Workspace: https://accounts.google.com. Empty leaves sign-in off."
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OAuth client ID of the Google Cloud web client (created by hand)."
  type        = string
  default     = ""
}

variable "oidc_client_secret_parameter" {
  description = "Name of the SSM SecureString in grc holding the OAuth client secret (created by hand), e.g. /fathom/oidc/client-secret."
  type        = string
  default     = ""
}

variable "oidc_redirect_uri" {
  description = "Override for the callback URL. Empty derives it from public_url."
  type        = string
  default     = ""
}

variable "bootstrap_admin_emails" {
  description = "Workspace accounts made Fathom administrators on first sign-in."
  type        = list(string)
  default     = []
}

variable "disable_api_token_minting" {
  description = "Refuse API token minting for people so sign-in is IdP-only (3.5.3 rides on Workspace 2SV). Agents and services can still mint."
  type        = bool
  default     = true
}
