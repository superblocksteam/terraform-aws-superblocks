output "certificate_arn" {
  value = aws_acm_certificate_validation.superblocks.certificate_arn
}

output "agent_domain" {
  value = local.agent_domain
}
