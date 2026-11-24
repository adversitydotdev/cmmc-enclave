terraform {
  required_version = ">= 1.17.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.74"
      configuration_aliases = [aws.management]
    }
  }
}

data "aws_partition" "current" {
  provider = aws.management
}
