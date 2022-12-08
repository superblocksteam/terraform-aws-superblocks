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

  lifecycle {
    create_before_destroy = true
  }
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
