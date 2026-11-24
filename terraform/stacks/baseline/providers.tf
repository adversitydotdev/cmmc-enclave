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
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias             = "log_archive"
  region            = var.home_region
  use_fips_endpoint = var.use_fips_endpoint
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
  assume_role {
    role_arn = local.role_arn["grc"]
  }
  default_tags {
    tags = var.tags
  }
}
