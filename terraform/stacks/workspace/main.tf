module "workspace" {
  source = "../../modules/workspace"

  domain              = var.domain
  cui_ou_name         = var.cui_ou_name
  non_cui_ou_name     = var.non_cui_ou_name
  group_members       = var.group_members
  users               = var.users
  privilege_overrides = var.privilege_overrides
  role_assignments    = var.role_assignments
}

output "group_emails" {
  description = "Scope the AWS SAML app and auto-provisioning to these groups."
  value       = module.workspace.group_emails
}

output "audit_privilege_candidates" {
  description = "Privilege names to choose from for the audit_viewer role."
  value       = module.workspace.audit_privilege_candidates
}
