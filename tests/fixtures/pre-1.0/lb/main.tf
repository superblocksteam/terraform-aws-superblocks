# The pre-1.3.2 load balancer: one target group named `superblocks`, and a
# listener that references the certificate. The listener is what makes this
# fixture worth having -- it is the reference that stops the certificate from
# being destroyed independently, which is what turns a rename into the
# `Error: Cycle:` in issue #17.

variable "name_prefix" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

resource "aws_lb" "superblocks" {
  name               = "${var.name_prefix}-lb"
  internal           = true
  load_balancer_type = "application"
  subnets            = var.subnet_ids
}

# Renamed to `http` in v1.3.2 when the gRPC target group was added.
resource "aws_lb_target_group" "superblocks" {
  name        = "${var.name_prefix}-target-group"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "superblocks" {
  load_balancer_arn = aws_lb.superblocks.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.superblocks.arn
  }
}

output "target_group_arn" {
  value = aws_lb_target_group.superblocks.arn
}
