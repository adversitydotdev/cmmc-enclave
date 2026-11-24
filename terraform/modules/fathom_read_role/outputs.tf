output "role_arn" {
  description = "Paste into the Fathom aws_role connection (IAM role ARN)."
  value       = aws_iam_role.fathom_read.arn
}

output "role_name" {
  description = "Role name."
  value       = aws_iam_role.fathom_read.name
}
