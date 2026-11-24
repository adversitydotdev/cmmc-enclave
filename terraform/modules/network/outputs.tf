output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "endpoint_security_group_id" {
  value = aws_security_group.endpoints.id
}

output "nat_gateway_id" {
  description = "Null when no NAT gateway."
  value       = one(aws_nat_gateway.this[*].id)
}
