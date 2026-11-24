output "organization_id" {
  description = "AWS Organization ID."
  value       = local.organization_id
}

output "organization_root_id" {
  description = "ID of the organization root."
  value       = local.organization_root_id
}

output "account_ids" {
  description = "Account IDs keyed management, log_archive, security, workload, grc."
  value       = local.account_ids
}

output "ou_ids" {
  description = "OU IDs keyed security, workloads, grc."
  value       = { for k, v in aws_organizations_organizational_unit.this : k => v.id }
}

output "scp_ids" {
  description = "SCP policy IDs by name."
  value       = { for k, v in aws_organizations_policy.scp : k => v.id }
}

output "scp_sizes" {
  description = "Character length of each SCP (limit 5,120)."
  value       = { for k, v in local.scp_json : k => length(v) }
}
