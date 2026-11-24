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

  default_tags {
    tags = var.tags
  }
}
