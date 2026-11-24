variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "log_archive_bucket_name" {
  description = "Object Lock log archive bucket (module.logging.log_archive_bucket_name)."
  type        = string
}

variable "log_archive_bucket_arn" {
  description = "ARN of the log archive bucket (module.logging.log_archive_bucket_arn)."
  type        = string
}

variable "kms_key_arn" {
  description = "Logs CMK in log_archive (module.kms.kms_key_arns[\"logs\"]): bucket SSE-KMS, log group, secret."
  type        = string
}

variable "alarm_topic_arn" {
  description = "Findings SNS topic in the security account, same region (module.logging.findings_sns_topic_arn). Its policy must allow cloudwatch.amazonaws.com from this account (already done for the audit collector)."
  type        = string
}

variable "admin_user_email" {
  description = "Workspace admin the service account impersonates (domain-wide delegation)."
  type        = string
}

variable "mode" {
  description = "report only lists idle users; suspend also suspends them. Suspend needs the write scope delegated to this module's service account (runbook)."
  type        = string
  default     = "report"

  validation {
    condition     = contains(["report", "suspend"], var.mode)
    error_message = "mode must be report or suspend."
  }
}

variable "idle_days" {
  description = "Suspend (or report) users whose last login, or creation time if they never logged in, is older than this many days."
  type        = number
  default     = 90

  validation {
    condition     = var.idle_days >= 1
    error_message = "idle_days must be at least 1."
  }
}

variable "exclude_emails" {
  description = "Primary emails never suspended (break-glass, service accounts). Super admins are always excluded."
  type        = list(string)
  default     = []
}

variable "exclude_org_units" {
  description = "Org unit paths never suspended, including their sub-OUs (for example /Service Accounts)."
  type        = list(string)
  default     = []
}

variable "schedule_expression" {
  description = "EventBridge schedule. Daily keeps the 24 hour disable window of the inactivity policy."
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "log_retention_days" {
  description = "Retention of the function's CloudWatch log group."
  type        = number
  default     = 365
}

variable "lambda_memory_mb" {
  description = "Lambda memory."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. One PATCH per idle user, so allow for a large first run."
  type        = number
  default     = 600
}

variable "source_dir" {
  description = "Directory produced by collectors/workspace_idle/build.sh (code plus arm64 dependencies). Must exist at plan time. Default: the repo's collectors/workspace_idle/build."
  type        = string
  default     = null
}
