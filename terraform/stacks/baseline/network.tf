variable "flow_log_bucket_arn" {
  description = "Log archive bucket ARN for VPC flow logs. Output of the logging module."
  type        = string
}

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
  flow_log_bucket_arn = var.flow_log_bucket_arn
}

module "network_grc" {
  source = "../../modules/network"
  providers = {
    aws = aws.grc
  }

  name_prefix     = var.name_prefix
  tier            = var.tier
  allowed_regions = var.allowed_regions
  tags            = var.tags

  name                  = "grc"
  vpc_cidr              = var.grc_vpc_cidr
  az_count              = 1
  enable_public_subnets = true
  enable_nat_gateway    = true
  flow_log_bucket_arn   = var.flow_log_bucket_arn
}
