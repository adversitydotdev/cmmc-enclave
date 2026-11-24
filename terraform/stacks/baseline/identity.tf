variable "group_members" {
  description = "Group name to list of Identity Center user names."
  type        = map(list(string))
  default     = {}
}

variable "break_glass_user_name" {
  description = "IAM user name for the break-glass user."
  type        = string
  default     = "break-glass"
}

module "identity" {
  source = "../../modules/identity"
  providers = {
    aws.management = aws.management
  }

  name_prefix           = var.name_prefix
  tier                  = var.tier
  allowed_regions       = var.allowed_regions
  tags                  = var.tags
  account_ids           = var.account_ids
  group_members         = var.group_members
  break_glass_user_name = var.break_glass_user_name
}

output "break_glass_user_arn" {
  value = module.identity.break_glass_user_arn
}
