variable "fathom_oidc_issuer" {
  description = "Set to https://accounts.google.com to sign in through Google Workspace."
  type        = string
  default     = "https://accounts.google.com"
}

variable "fathom_oidc_client_id" {
  description = "Google OAuth web client ID (created by hand; runbook #29)."
  type        = string
  default     = ""
}

variable "fathom_oidc_client_secret_parameter" {
  description = "SSM SecureString in grc holding the OAuth client secret."
  type        = string
  default     = "/fathom/oidc/client-secret"
}

variable "fathom_bootstrap_admin_emails" {
  description = "Workspace accounts that become Fathom administrators on first sign-in."
  type        = list(string)
  default     = []
}

variable "fathom_ref" {
  description = "Fathom commit SHA for deploy/aws/template.yaml."
  type        = string
  default     = "7db744e6bfadc90003202f15829357d26d6b65bb"
}

variable "fathom_template_sha256" {
  description = "sha256 of the template at fathom_ref."
  type        = string
  default     = "482085d875250b65a3eaa7e033b68b0afab43c61ec069acdfb96b686d64b0c25"
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

  oidc_issuer                  = var.fathom_oidc_issuer
  oidc_client_id               = var.fathom_oidc_client_id
  oidc_client_secret_parameter = var.fathom_oidc_client_secret_parameter
  bootstrap_admin_emails       = var.fathom_bootstrap_admin_emails

  seed_bundle_uri = try(module.fathom_seed[0].bundle_uri, "") # fathom_seed.tf
}

output "fathom_vpc_id" {
  description = "VPC created by the Fathom CloudFormation stack."
  value       = module.fathom.vpc_id
}
