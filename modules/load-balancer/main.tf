resource "aws_lb" "superblocks" {
  name               = "${var.name_prefix}-lb"
  internal           = var.internal
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = var.security_group_ids
  tags               = var.tags
}

resource "aws_lb_target_group" "superblocks" {
  name        = "${var.name_prefix}-target-group"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  tags        = var.tags
  health_check {
    path                = "/health"
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
