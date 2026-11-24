terraform {
  required_version = ">= 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.74"
    }
  }
}

# Runs in the management account with the caller's credentials.
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

# FIPS endpoint gaps (botocore endpoints.json 1.44.10, checked 2026-11-23): with
# use_fips_endpoint on, the SDK would call hostnames that don't exist. Pin these
# services to their standard regional endpoints. They are control-plane APIs that
# carry no CUI, so 3.13.11 doesn't apply to them (SCOPE section 9, item 15). Commercial: backup, sso-admin,
# identitystore. GovCloud: backup only (its other endpoints are FIPS by default).
locals {
  nonfips_endpoints = {
    backup        = "https://backup.${var.home_region}.amazonaws.com"
    ssoadmin      = var.tier == "standard" ? "https://sso.${var.home_region}.amazonaws.com" : null
    identitystore = var.tier == "standard" ? "https://identitystore.${var.home_region}.amazonaws.com" : null
  }
}
