output "identity_store_id" {
  description = "Identity Store ID of the Identity Center instance."
  value       = local.identity_store_id
}

output "sso_instance_arn" {
  description = "Identity Center instance ARN."
  value       = local.sso_instance_arn
}

output "group_ids" {
  description = "Group name to Identity Store group ID."
  value       = { for k, g in aws_identitystore_group.this : k => g.group_id }
}

output "permission_set_arns" {
  description = "Permission set name to ARN."
  value       = { for k, p in aws_ssoadmin_permission_set.this : k => p.arn }
}

output "break_glass_user_arn" {
  description = "Break-glass user ARN, for the logging module to alarm on use."
  value       = aws_iam_user.break_glass.arn
}
