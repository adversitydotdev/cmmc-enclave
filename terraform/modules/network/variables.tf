variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "enclave"
}

variable "tier" {
  description = "Impact tier: standard (commercial AWS) or itar (AWS GovCloud)."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "itar"], var.tier)
    error_message = "tier must be standard or itar."
  }
}

variable "allowed_regions" {
  description = "Regions the enclave may use. Standard: us-east-1, us-east-2, us-west-2. ITAR: us-gov-west-1, us-gov-east-1."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every taggable resource."
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "Short name of this VPC (for example workload or grc). Used in resource names."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC IPv4 CIDR. Must be /20 or larger (subnets are carved as /4 splits)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be a valid CIDR no smaller than /20."
  }
}

variable "az_count" {
  description = "Number of AZs to span (one private subnet, and one public subnet if enabled, per AZ). Each interface endpoint is billed per AZ (SCOPE section 13)."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be between 1 and 6."
  }
}

variable "interface_endpoint_services" {
  description = "Interface endpoint service suffixes (com.amazonaws.<region>.<suffix>). Each costs per AZ-hour."
  type        = list(string)
  default     = ["sts", "ssm", "ssmmessages", "ec2messages", "kms", "logs", "ecr.api", "ecr.dkr", "secretsmanager"]
}

variable "gateway_endpoint_services" {
  description = "Gateway endpoint services (free), attached to the private route table."
  type        = list(string)
  default     = ["s3", "dynamodb"]
}

variable "enable_public_subnets" {
  description = "Create public subnets, an internet gateway and a public route table (ALB only). Leave false for the workload VPC: it then has no internet gateway at all."
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Create one NAT gateway (first public subnet) and route private 0.0.0.0/0 to it. Requires enable_public_subnets."
  type        = bool
  default     = false
}

variable "flow_log_bucket_arn" {
  description = "ARN of the log archive S3 bucket for VPC flow logs (its policy must allow delivery.logs.amazonaws.com)."
  type        = string
}

variable "flow_log_prefix" {
  description = "Key prefix inside the flow log bucket. Defaults to vpc-flow-logs/<name>."
  type        = string
  default     = null
}

variable "enable_reachability_check" {
  description = "Create an aws_ec2_network_insights_path from the internet gateway to the first interface endpoint ENI. No effect without an internet gateway. Run the analysis in CI (see main.tf)."
  type        = bool
  default     = false
}
