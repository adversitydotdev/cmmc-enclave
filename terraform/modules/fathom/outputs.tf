output "vpc_id" {
  description = "VPC created by the Fathom stack (looked up by stack tag)."
  value       = data.aws_vpc.fathom.id
}

output "stack_id" {
  description = "CloudFormation stack ID."
  value       = aws_cloudformation_stack.fathom.id
}

output "stack_outputs" {
  description = "All CloudFormation outputs: BucketName, ApiRepositoryUri, WebRepositoryUri, ConfigurationPrefix, DatabaseEndpoint, LoadBalancerDnsName, ..."
  value       = aws_cloudformation_stack.fathom.outputs
}

output "api_repository_uri" {
  description = "Push the API image here before enabling services."
  value       = aws_cloudformation_stack.fathom.outputs["ApiRepositoryUri"]
}

output "web_repository_uri" {
  description = "Push the web image here before enabling services."
  value       = aws_cloudformation_stack.fathom.outputs["WebRepositoryUri"]
}

output "load_balancer_dns_name" {
  description = "ALB DNS name once services are enabled. Point domain_name at it when no hosted zone is set."
  value       = try(aws_cloudformation_stack.fathom.outputs["LoadBalancerDnsName"], null)
}

output "template_ref" {
  description = "Fathom commit the template was fetched at, and its sha256."
  value       = { ref = var.fathom_ref, sha256 = var.template_sha256 }
}
