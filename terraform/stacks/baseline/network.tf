variable "workload_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "grc_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

module "network_workload" {
  source = "../../modules/network"
  providers = {
    aws = aws.workload
  }

  name_prefix     = var.name_prefix
  tier            = var.tier
  allowed_regions = var.allowed_regions
  tags            = var.tags

  name                = "workload"
  vpc_cidr            = var.workload_vpc_cidr
  az_count            = 2
  flow_log_bucket_arn = module.logging.log_archive_bucket_arn
}
