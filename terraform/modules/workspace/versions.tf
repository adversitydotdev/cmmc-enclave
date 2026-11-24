terraform {
  required_version = ">= 1.17.0"

  required_providers {
    googleworkspace = {
      source  = "macadmins/googleworkspace"
      version = "1.5.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
