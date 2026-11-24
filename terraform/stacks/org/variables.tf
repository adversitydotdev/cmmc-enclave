variable "name_prefix" {
  type    = string
  default = "enclave"
}

variable "tier" {
  type    = string
  default = "standard"
}

variable "home_region" {
  type    = string
  default = "us-east-1"
}

variable "allowed_regions" {
  type    = list(string)
  default = ["us-east-1", "us-east-2", "us-west-2"]
}

variable "use_fips_endpoint" {
  description = "Force FIPS endpoints (3.13.11). Some services have no FIPS endpoint; see modules/kms."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
