terraform {
  required_version = ">= 1.17.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.74"
      configuration_aliases = [aws.log_archive]
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}
