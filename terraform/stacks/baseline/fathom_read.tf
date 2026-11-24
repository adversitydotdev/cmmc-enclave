# Fathom read access (#32): one read-only role per account, each trusting only the Fathom
# ECS task role in grc. Paste each role_arn into a Fathom aws_role connection.
# ITAR: Fathom reaches GovCloud accounts through IAM Roles Anywhere (decision #7), not built.

variable "fathom_read_task_role_pattern" {
  description = "Name pattern of the Fathom ECS task role in grc. Default matches the CloudFormation-generated <stack>-TaskRole-<suffix> for stack \"fathom\"."
  type        = string
  default     = "fathom-TaskRole-*"
}

variable "fathom_read_external_ids" {
  description = "ExternalId per account key (management, log_archive, security, workload, grc), copied from the Fathom connection once it exists. Missing or empty: no ExternalId condition on that role."
  type        = map(list(string))
  default     = {}
}

module "fathom_read_management" {
  source    = "../../modules/fathom_read_role"
  providers = { aws = aws.management }

  name_prefix            = var.name_prefix
  tier                   = var.tier
  tags                   = var.tags
  grc_account_id         = var.account_ids["grc"]
  task_role_name_pattern = var.fathom_read_task_role_pattern
  external_ids           = lookup(var.fathom_read_external_ids, "management", [])
}

module "fathom_read_log_archive" {
  source    = "../../modules/fathom_read_role"
  providers = { aws = aws.log_archive }

  name_prefix            = var.name_prefix
  tier                   = var.tier
  tags                   = var.tags
  grc_account_id         = var.account_ids["grc"]
  task_role_name_pattern = var.fathom_read_task_role_pattern
  external_ids           = lookup(var.fathom_read_external_ids, "log_archive", [])
}

module "fathom_read_security" {
  source    = "../../modules/fathom_read_role"
  providers = { aws = aws.security }

  name_prefix            = var.name_prefix
  tier                   = var.tier
  tags                   = var.tags
  grc_account_id         = var.account_ids["grc"]
  task_role_name_pattern = var.fathom_read_task_role_pattern
  external_ids           = lookup(var.fathom_read_external_ids, "security", [])
}

module "fathom_read_workload" {
  source    = "../../modules/fathom_read_role"
  providers = { aws = aws.workload }

  name_prefix            = var.name_prefix
  tier                   = var.tier
  tags                   = var.tags
  grc_account_id         = var.account_ids["grc"]
  task_role_name_pattern = var.fathom_read_task_role_pattern
  external_ids           = lookup(var.fathom_read_external_ids, "workload", [])
}

module "fathom_read_grc" {
  source    = "../../modules/fathom_read_role"
  providers = { aws = aws.grc }

  name_prefix            = var.name_prefix
  tier                   = var.tier
  tags                   = var.tags
  grc_account_id         = var.account_ids["grc"]
  task_role_name_pattern = var.fathom_read_task_role_pattern
  external_ids           = lookup(var.fathom_read_external_ids, "grc", [])
}

output "fathom_read_role_arns" {
  description = "Role ARN per account, for the Fathom aws_role connections."
  value = {
    management  = module.fathom_read_management.role_arn
    log_archive = module.fathom_read_log_archive.role_arn
    security    = module.fathom_read_security.role_arn
    workload    = module.fathom_read_workload.role_arn
    grc         = module.fathom_read_grc.role_arn
  }
}
