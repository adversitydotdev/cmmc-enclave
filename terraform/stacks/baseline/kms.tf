module "kms" {
  source = "../../modules/kms"
  providers = {
    aws             = aws.management
    aws.log_archive = aws.log_archive
    aws.security    = aws.security
    aws.workload    = aws.workload
    aws.grc         = aws.grc
  }

  name_prefix     = var.name_prefix
  tier            = var.tier
  allowed_regions = var.allowed_regions
  tags            = var.tags
  organization_id = var.organization_id
  account_ids     = var.account_ids
}
