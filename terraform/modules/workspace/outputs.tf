output "org_unit_ids" {
  description = "OU key (cui, non_cui) to org unit ID."
  value       = local.ou_id
}

output "org_unit_paths" {
  description = "OU key (cui, non_cui) to org unit path."
  value       = local.ou_path
}

output "group_emails" {
  description = "Group name to email, for scoping the AWS SAML app and auto-provisioning."
  value       = { for k, g in googleworkspace_group.this : k => g.email }
}

output "group_ids" {
  description = "Group name to Workspace group ID."
  value       = { for k, g in googleworkspace_group.this : k => g.id }
}

output "role_ids" {
  description = "Built-in role key to role ID (audit_viewer absent until privilege names are set)."
  value       = { for k, r in googleworkspace_role.this : k => r.id }
}

output "audit_privilege_candidates" {
  description = "Privileges whose name suggests audit, investigation or reporting; choose the Audit and investigation View name for privilege_overrides.audit_viewer."
  value = [
    for p in data.googleworkspace_privileges.all.items : p.privilege_name
    if length(regexall("AUDIT|INVESTIGAT|REPORT", upper(p.privilege_name))) > 0
  ]
}
