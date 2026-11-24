variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "regions" {
  description = "Regions to record in."
  type        = set(string)
}

variable "home_region" {
  description = "Region that records global resource types (IAM etc.)."
  type        = string
}

variable "bucket_name" {
  description = "Log archive bucket receiving Config history and snapshots."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used by the delivery channel for the archive bucket."
  type        = string
}

variable "create_service_linked_role" {
  description = "Create the AWSServiceRoleForConfig service-linked role. Set false if it already exists in the account."
  type        = bool
  default     = true
}

variable "findings_topic_arns" {
  description = "Security findings SNS topic ARN by region. Config delivery failures in this account are published there."
  type        = map(string)
}
