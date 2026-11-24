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

# Auth: service account with domain-wide delegation, impersonating a super admin
# (role management is super-admin only). Supply the key outside the repo:
#   GOOGLEWORKSPACE_CREDENTIALS=/path/to/key.json  (or var.credentials)
# In the Admin console grant the service account's client ID exactly these scopes.
provider "googleworkspace" {
  credentials             = var.credentials
  customer_id             = var.customer_id
  impersonated_user_email = var.impersonated_user_email

  oauth_scopes = [
    "https://www.googleapis.com/auth/admin.directory.orgunit",
    "https://www.googleapis.com/auth/admin.directory.user",
    "https://www.googleapis.com/auth/admin.directory.group",
    "https://www.googleapis.com/auth/admin.directory.rolemanagement",
  ]
}
