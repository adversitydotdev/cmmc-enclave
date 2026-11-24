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
  description = "Logs CMK in log_archive (module.kms.kms_key_arns[\"logs\"]): bucket SSE-KMS, log group, secret, state table."
  type        = string
}

variable "alarm_topic_arn" {
  description = "Findings SNS topic in the security account, same region (module.logging.findings_sns_topic_arn). Its policy must allow cloudwatch.amazonaws.com from this account."
  type        = string
}

variable "admin_user_email" {
  description = "Workspace admin the service account impersonates (domain-wide delegation)."
  type        = string
}

variable "applications" {
  description = "Reports API applications to collect. Unavailable ones are skipped with a warning at run time."
  type        = list(string)
  default     = ["admin", "login", "drive", "token", "saml", "user_accounts", "groups", "mobile", "access_transparency"]
}

variable "schedule_expression" {
  description = "EventBridge schedule for the collector."
  type        = string
  default     = "rate(10 minutes)"
}

variable "overlap_hours" {
  description = "Hours before the cursor each run re-reads to catch events Google reports late (documented data delay: up to a few hours, longer for some applications)."
  type        = number
  default     = 6
}

variable "overlap_hours_by_app" {
  description = "Per-application override of overlap_hours."
  type        = map(number)
  default     = {}
}

variable "initial_lookback_hours" {
  description = "How far back the first run of an application reads."
  type        = number
  default     = 24
}

variable "no_objects_alarm_hours" {
  description = "Alarm when no object has been archived for this many hours (1 to 24). Raise it if the tenant is quiet overnight."
  type        = number
  default     = 6

  validation {
    condition     = var.no_objects_alarm_hours >= 1 && var.no_objects_alarm_hours <= 24
    error_message = "no_objects_alarm_hours must be 1 to 24."
  }
}

variable "log_retention_days" {
  description = "Retention of the collector's CloudWatch log group."
  type        = number
  default     = 365
}

variable "lambda_memory_mb" {
  description = "Lambda memory."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. Must be shorter than the schedule interval."
  type        = number
  default     = 300
}

variable "source_dir" {
  description = "Directory produced by collectors/workspace_audit/build.sh (code plus arm64 dependencies). Must exist at plan time. Default: the repo's collectors/workspace_audit/build."
  type        = string
  default     = null
}
