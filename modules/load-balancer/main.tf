resource "aws_lb" "superblocks" {
  name_prefix        = substr(var.name_prefix, 0, 6)
  internal           = var.internal
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = var.create_sg ? concat([module.loadbalancer_security_group[0].security_group_id], var.security_group_ids) : var.security_group_ids
  tags               = var.tags
}

resource "aws_lb_target_group" "superblocks" {
  name_prefix = substr(var.name_prefix, 0, 6)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  tags        = var.tags
  health_check {
    path = "/health"
  }

  lifecycle {
    create_before_destroy = true
  }
}


data "aws_route53_zone" "superblocks" {
  count = var.create_dns ? 1 : 0
  name  = var.zone_name
}

resource "aws_route53_record" "superblocks" {
  count   = var.create_dns ? 1 : 0
  zone_id = data.aws_route53_zone.superblocks[0].zone_id
  name    = var.record_name
  type    = "CNAME"
  ttl     = var.dns_ttl

  records = [
    aws_lb.superblocks.dns_name
  ]
}

resource "aws_lb_listener" "superblocks" {
  load_balancer_arn = aws_lb.superblocks.arn
  port              = var.listener_port
  protocol          = var.listener_protocol
  ssl_policy        = var.certificate_arn != null ? "ELBSecurityPolicy-2016-08" : null
  certificate_arn   = var.certificate_arn != null ? var.certificate_arn : null
  tags              = var.tags

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.superblocks.arn
  }
}

module "loadbalancer_security_group" {
  count               = var.create_sg ? 1 : 0
  source              = "terraform-aws-modules/security-group/aws"
  version             = ">=5.0.0"
  name                = "${var.name_prefix}-lb-sg"
  vpc_id              = var.vpc_id
  ingress_with_cidr_blocks = var.sg_ingress_with_cidr_blocks
  egress_with_cidr_blocks = var.sg_egress_with_cidr_blocks
  tags                = var.tags
  use_name_prefix     = true
}
