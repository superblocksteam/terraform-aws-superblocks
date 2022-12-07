locals {
  agent_domain = "${var.record_name}.${var.zone_name}"
}

data "aws_route53_zone" "superblocks" {
  name = var.zone_name
}

resource "aws_route53_record" "superblocks" {
  zone_id = data.aws_route53_zone.superblocks.zone_id
  name    = local.agent_domain
  type    = "A"

  alias {
    name                   = var.alias_name
    zone_id                = var.alias_zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "superblocks" {
  domain_name       = local.agent_domain
  validation_method = "DNS"
}

resource "aws_route53_record" "validation_record" {
  allow_overwrite = true
  name            = tolist(aws_acm_certificate.superblocks.domain_validation_options)[0].resource_record_name
  records         = [tolist(aws_acm_certificate.superblocks.domain_validation_options)[0].resource_record_value]
  type            = tolist(aws_acm_certificate.superblocks.domain_validation_options)[0].resource_record_type
  zone_id         = data.aws_route53_zone.superblocks.zone_id
  ttl             = 60
}

resource "aws_acm_certificate_validation" "superblocks" {
  certificate_arn         = aws_acm_certificate.superblocks.arn
  validation_record_fqdns = [aws_route53_record.validation_record.fqdn]
}
