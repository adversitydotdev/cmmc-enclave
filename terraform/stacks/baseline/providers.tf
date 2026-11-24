terraform {
  required_version = ">= 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.74"
    }
  }
}

locals {
  partition = var.tier == "itar" ? "aws-us-gov" : "aws"
  role_arn  = { for k, id in var.account_ids : k => "arn:${local.partition}:iam::${id}:role/${var.assume_role_name}" }
}

provider "aws" {
  alias             = "management"
  region            = var.home_region
  use_fips_endpoint = var.use_fips_endpoint
  endpoints {
    backup        = local.nonfips_endpoints.backup
    ssoadmin      = local.nonfips_endpoints.ssoadmin
    identitystore = local.nonfips_endpoints.identitystore
  }
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias             = "log_archive"
  region            = var.home_region
  use_fips_endpoint = var.use_fips_endpoint
  endpoints {
    backup        = local.nonfips_endpoints.backup
    ssoadmin      = local.nonfips_endpoints.ssoadmin
    identitystore = local.nonfips_endpoints.identitystore
  }
  assume_role {
    role_arn = local.role_arn["log_archive"]
  }
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias             = "security"
  region            = var.home_region
  use_fips_endpoint = var.use_fips_endpoint
  endpoints {
    backup        = local.nonfips_endpoints.backup
    ssoadmin      = local.nonfips_endpoints.ssoadmin
    identitystore = local.nonfips_endpoints.identitystore
  }
  assume_role {
    role_arn = local.role_arn["security"]
  }
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias             = "workload"
  region            = var.home_region
  use_fips_endpoint = var.use_fips_endpoint
  endpoints {
    backup        = local.nonfips_endpoints.backup
    ssoadmin      = local.nonfips_endpoints.ssoadmin
    identitystore = local.nonfips_endpoints.identitystore
  }
  assume_role {
    role_arn = local.role_arn["workload"]
  }
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias             = "grc"
  region            = var.home_region
  use_fips_endpoint = var.use_fips_endpoint
  endpoints {
    backup        = local.nonfips_endpoints.backup
    ssoadmin      = local.nonfips_endpoints.ssoadmin
    identitystore = local.nonfips_endpoints.identitystore
  }
  assume_role {
    role_arn = local.role_arn["grc"]
  }
  default_tags {
    tags = var.tags
  }
}

# FIPS endpoint gaps (botocore endpoints.json 1.44.10, checked 2026-11-23): with
# use_fips_endpoint on, the SDK would call hostnames that don't exist. Pin these
# services to their standard regional endpoints. Commercial: backup, sso-admin,
# identitystore. GovCloud: backup only (its other endpoints are FIPS by default).
locals {
  nonfips_endpoints = {
    backup        = "https://backup.${var.home_region}.amazonaws.com"
    ssoadmin      = var.tier == "standard" ? "https://sso.${var.home_region}.amazonaws.com" : null
    identitystore = var.tier == "standard" ? "https://identitystore.${var.home_region}.amazonaws.com" : null
  }
}
