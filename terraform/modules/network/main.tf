# Enclave VPC module. Instantiated twice from stacks/baseline/network.tf.
#
#   workload (no internet path at all)        grc (Fathom)
#   +-----------------------------------+     +------------------------------------------+
#   | VPC 10.10.0.0/16   no IGW, no NAT |     | VPC 10.20.0.0/16                         |
#   |                                   |     |   Internet                               |
#   |  private subnets (x az_count)     |     |      |                                   |
#   |   - no 0.0.0.0/0 route            |     |    [IGW]                                 |
#   |   - interface endpoints (443)     |     |      |                                   |
#   |   - S3 + DynamoDB gateway eps     |     |  public subnets: ALB only                |
#   |                                   |     |      |            [NAT] (1, first AZ)    |
#   |  AWS APIs <--PrivateLink--        |     |  private subnets: Fargate tasks, RDS     |
#   +-----------------------------------+     |   - 0.0.0.0/0 -> NAT                     |
#                                             |   - same interface + gateway endpoints   |
#   Both: closed default SG, endpoint SG       +------------------------------------------+
#   allows 443 from the VPC CIDR only, no auto-assign public IPs, flow logs (ALL,
#   parquet, hourly partitions) to the log archive bucket, default NACLs.

data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only names are sliced to az_count; subnets are created once and not re-derived
  state = "available"
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  has_igw    = var.enable_public_subnets
  has_nat    = var.enable_nat_gateway
  partition  = var.tier == "itar" ? "aws-us-gov" : "aws"
  svc_prefix = "com.amazonaws.${data.aws_region.current.region}"
  name       = "${var.name_prefix}-${var.name}"

  # Private in the lower half, public in the upper half of the VPC range.
  private_cidrs = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_cidrs  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  flow_log_prefix = coalesce(var.flow_log_prefix, "vpc-flow-logs/${var.name}")
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for interface endpoint private DNS

  tags = merge(var.tags, { Name = local.name })

  lifecycle {
    precondition {
      condition     = data.aws_partition.current.partition == local.partition
      error_message = "Provider partition does not match var.tier."
    }
    precondition {
      condition     = contains(var.allowed_regions, data.aws_region.current.region)
      error_message = "Region is not in allowed_regions."
    }
    precondition {
      condition     = !var.enable_nat_gateway || var.enable_public_subnets
      error_message = "enable_nat_gateway requires enable_public_subnets."
    }
  }
}

# 3.13.6 default SG has no rules.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-default-closed" })
}

# The default route table stays empty so nothing inherits a route by accident.
resource "aws_default_route_table" "this" {
  default_route_table_id = aws_vpc.this.default_route_table_id
  tags                   = merge(var.tags, { Name = "${local.name}-default-empty" })
}

# 3.13.5 private subnets; no auto-assigned public IPs.
resource "aws_subnet" "private" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = local.private_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${local.name}-private-${local.azs[count.index]}", Tier = "private" })
}

resource "aws_subnet" "public" {
  count                   = local.has_igw ? length(local.azs) : 0
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${local.name}-public-${local.azs[count.index]}", Tier = "public" })
}

resource "aws_internet_gateway" "this" {
  count  = local.has_igw ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = local.name })
}

resource "aws_route_table" "public" {
  count  = local.has_igw ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-public" })
}

resource "aws_route" "public_internet" {
  count                  = local.has_igw ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = local.has_igw ? length(local.azs) : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count  = local.has_nat ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${local.name}-nat" })
}

resource "aws_nat_gateway" "this" {
  count         = local.has_nat ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(var.tags, { Name = local.name })

  depends_on = [aws_internet_gateway.this]
}

# One private route table. Only route besides local is the NAT default (grc).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${local.name}-private" })
}

resource "aws_route" "private_nat" {
  count                  = local.has_nat ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count          = length(local.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# 3.13.1, 3.13.6: AWS API traffic stays on the AWS network. No egress rules needed.
resource "aws_security_group" "endpoints" {
  name_prefix = "${local.name}-vpce-"
  description = "Interface endpoints: HTTPS from the VPC CIDR only"
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${local.name}-vpce" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from VPC"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "${local.svc_prefix}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${local.name}-${each.value}" })
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = toset(var.gateway_endpoint_services)

  vpc_id            = aws_vpc.this.id
  service_name      = "${local.svc_prefix}.${each.value}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${local.name}-${each.value}" })
}

# 3.3.1, 3.14.6 flow logs, all traffic, to the log archive bucket.
resource "aws_flow_log" "this" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = "${var.flow_log_bucket_arn}/${local.flow_log_prefix}"

  destination_options {
    file_format                = "parquet"
    per_hour_partition         = true
    hive_compatible_partitions = false
  }

  tags = merge(var.tags, { Name = local.name })
}

# Reachability proof (#25). Off by default. Needs an IGW, so it is meaningful
# for grc only: IGW -> a private endpoint ENI must have no path. The workload
# VPC has no IGW resource at all (enable_public_subnets = false); CI should also
# assert that with `aws ec2 describe-internet-gateways` filtered by VPC.
# CI: after apply, run
#   aws ec2 start-network-insights-analysis --network-insights-path-id <id>
# and assert NetworkPathFound == false.
resource "aws_ec2_network_insights_path" "igw_to_private" {
  count = var.enable_reachability_check && local.has_igw ? 1 : 0

  source           = aws_internet_gateway.this[0].id
  destination      = tolist(aws_vpc_endpoint.interface[var.interface_endpoint_services[0]].network_interface_ids)[0]
  protocol         = "tcp"
  destination_port = 443

  tags = merge(var.tags, { Name = "${local.name}-igw-to-private" })
}
