variable "fathom_ref" {
  description = "Fathom commit SHA for deploy/aws/template.yaml."
  type        = string
  default     = "cbda9a45d4feed947d64b3b7796d1ddf4dd4d90c"
}

variable "fathom_template_sha256" {
  description = "sha256 of the template at fathom_ref."
  type        = string
  default     = "56f388de23538f9dbf4d50bb746f10b85aefe414ef4897a35eb7c2ab99e0c9e3"
}

variable "fathom_enable_services" {
  description = "Start the Fathom tasks and ALB. Set true after the images are pushed and the certificate is issued."
  type        = bool
  default     = false
}

variable "fathom_certificate_arn" {
  description = "ACM certificate ARN (grc account, home region) for the Fathom domain."
  type        = string
  default     = ""
}

variable "fathom_domain_name" {
  description = "Fathom domain name (SES identity, ALB alias)."
  type        = string
  default     = ""
}

variable "fathom_hosted_zone_id" {
  description = "Route 53 hosted zone for fathom_domain_name. Empty: DNS by hand."
  type        = string
  default     = ""
}

variable "fathom_public_url" {
  description = "Fathom public origin, such as https://grc.example.com."
  type        = string
  default     = ""
}

variable "fathom_task_size" {
  description = "Fathom API task size: small, medium, large, xlarge or 2xlarge."
  type        = string
  default     = "small"
}

variable "fathom_database_instance_class" {
  description = "Fathom RDS instance class (db.t4g.*)."
  type        = string
  default     = "db.t4g.micro"
}

module "fathom" {
  source = "../../modules/fathom"
  providers = {
    aws = aws.grc
  }

  name_prefix     = var.name_prefix
  tier            = var.tier
  allowed_regions = var.allowed_regions
  tags            = var.tags

  fathom_ref              = var.fathom_ref
  template_sha256         = var.fathom_template_sha256
  kms_key_arn             = module.kms.kms_key_arns["grc"]
  flow_log_bucket_arn     = module.logging.log_archive_bucket_arn
  enable_services         = var.fathom_enable_services
  certificate_arn         = var.fathom_certificate_arn
  domain_name             = var.fathom_domain_name
  hosted_zone_id          = var.fathom_hosted_zone_id
  public_url              = var.fathom_public_url
  task_size               = var.fathom_task_size
  database_instance_class = var.fathom_database_instance_class
}

output "fathom_vpc_id" {
  description = "VPC created by the Fathom CloudFormation stack."
  value       = module.fathom.vpc_id
}
